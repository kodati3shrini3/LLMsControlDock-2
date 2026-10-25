// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes holds the finished page.
	"bytes"
	// context lets a request be cancelled or given a deadline.
	"context"
	// embed lets the load page template be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// fmt builds formatted text.
	"fmt"
	// html/template builds HTML and escapes every inserted value.
	"html/template"
	// log prints messages to the terminal.
	"log"
	// net/http provides requests and status codes.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// time provides durations and pauses.
	"time"
) // end of imports

// loadTemplateText is the load page template, stored inside the executable at build time (requirements T3 and T4).
//
//go:embed web/load.html
var loadTemplateText string

// loadTimeout is how long the load request may take; loading a large model from disk can take minutes.
const loadTimeout = 5 * time.Minute

// loadVerifyWait is how long the monitor keeps asking whether the model is listed after the load request returned (a variable so tests can make it short).
var loadVerifyWait = 10 * time.Second

// defaultKeepText is Ollama's built-in time to keep a model loaded after its last use (from Ollama's FAQ); a server can be set to another value, which only the real countdown after loading shows.
const defaultKeepText = "5 minutes"

// tightFactor decides when free memory counts as "close": less than this many times the model's size.
const tightFactor = 1.25

// keepChoice is one entry of the "stay loaded for" list on the load page.
type keepChoice struct {
	// Value is what the form sends; an empty value means "use Ollama's own default".
	Value string
	// Label is what the person reads.
	Label string
} // end of keepChoice

// keepChoices is the fixed list the load page offers; nothing outside it is ever sent to Ollama.
var keepChoices = []keepChoice{
	// Ollama's own default time.
	{"", "Ollama's default (" + defaultKeepText + ")"},
	// Five minutes.
	{"5m", "5 minutes"},
	// Half an hour.
	{"30m", "30 minutes"},
	// One hour.
	{"1h", "1 hour"},
	// One day.
	{"24h", "24 hours"},
	// Never unload by itself: Ollama takes a negative number for this.
	{"-1", "Until I unload it (never unloads by itself)"},
} // end of keepChoices

// keepAliveValue turns the form's choice into the value sent to Ollama: nil means "send nothing", and ok is false for a choice that is not in the list.
func keepAliveValue(choice string) (value any, ok bool) {
	// Go through the fixed list.
	for _, c := range keepChoices {
		// Only an exact match counts.
		if c.Value != choice {
			// Next choice.
			continue
		} // end of the match check
		// The default: send nothing.
		if choice == "" {
			// No keep-alive field.
			return nil, true
		} // end of the default case
		// Never unload: a negative number.
		if choice == "-1" {
			// The number.
			return -1, true
		} // end of the forever case
		// A time such as 5m.
		return choice, true
	} // end of the loop
	// Not in the list.
	return nil, false
} // end of keepAliveValue

// loadModel asks Ollama to load one model now, without a prompt and without a keep-alive setting, so Ollama's own default time applies; it returns which request worked.
func loadModel(ctx context.Context, base *url.URL, name string, timeout time.Duration) (string, error) {
	// No keep-alive field.
	return loadModelKeep(ctx, base, name, nil, timeout)
} // end of loadModel

// loadModelKeep is loadModel with an optional keep-alive value (nil means none); it returns which request worked.
func loadModelKeep(ctx context.Context, base *url.URL, name string, keep any, timeout time.Duration) (string, error) {
	// The body of the generate request.
	body := map[string]any{"model": name}
	// The same for the embedding fallback, which also needs some input.
	embedBody := map[string]any{"model": name, "input": "load"}
	// Add the keep-alive value when there is one.
	if keep != nil {
		// To both bodies.
		body["keep_alive"], embedBody["keep_alive"] = keep, keep
	} // end of the keep-alive case
	// Chat and text models are loaded through /api/generate with no prompt (the documented way to preload).
	status, err := postJSON(ctx, base, "api/generate", timeout, body)
	// No answer at all.
	if err != nil {
		// Pass the safe error on.
		return "", err
	} // end of the send check
	// Status 200 means the model is loaded.
	if status == http.StatusOK {
		// Report which request worked.
		return "generate", nil
	} // end of the success case
	// Status 400 is what a model that cannot generate text (an embedding model, for example) answers; try the embedding request instead.
	if status == http.StatusBadRequest {
		// The one-word input is only there because an embedding request needs some input.
		status2, err2 := postJSON(ctx, base, "api/embed", timeout, embedBody)
		// No answer at all.
		if err2 != nil {
			// Pass the safe error on.
			return "", err2
		} // end of the second send check
		// Status 200 means the model is loaded.
		if status2 == http.StatusOK {
			// Report which request worked.
			return "embed", nil
		} // end of the second success case
		// Both requests were refused; report both numbers.
		return "", fmt.Errorf("Ollama refused both load requests (status %d and status %d)", status, status2)
	} // end of the 400 case
	// Any other status.
	return "", fmt.Errorf("Ollama answered the load request with status %d", status)
} // end of loadModel

// waitUntilLoaded asks Ollama until the model appears in the loaded list, for a limited time, and returns its entry.
func waitUntilLoaded(ctx context.Context, base *url.URL, name string, timeout time.Duration) (loadedModel, bool, error) {
	// The moment to stop asking.
	deadline := time.Now().Add(loadVerifyWait)
	// Ask until the deadline.
	for {
		// Read the loaded list.
		list, err := fetchLoaded(ctx, base, timeout)
		// A failure to read means we cannot say.
		if err != nil {
			// Pass the safe error on.
			return loadedModel{}, false, err
		} // end of the read check
		// The model is in the list.
		if m, ok := findLoaded(list, name); ok {
			// Done: it is loaded.
			return m, true, nil
		} // end of the found check
		// Out of time: not listed.
		if time.Now().After(deadline) {
			// Report that it is not there.
			return loadedModel{}, false, nil
		} // end of the deadline check
		// Wait a little, or stop at once if the browser went away.
		select {
		// The browser closed the request.
		case <-ctx.Done():
			// Give up.
			return loadedModel{}, false, ctx.Err()
		// The pause is over.
		case <-time.After(unloadVerifyStep):
		} // end of the wait
	} // end of the loop
} // end of waitUntilLoaded

// findInstalled returns the installed model with the given name; the second result is false when it is not installed.
func findInstalled(list []installedModel, name string) (installedModel, bool) {
	// Look at every installed model.
	for _, m := range list {
		// A match by exact name.
		if m.Name == name {
			// Found it.
			return m, true
		} // end of the name check
	} // end of the loop
	// Not installed.
	return installedModel{}, false
} // end of findInstalled

// loadPage is everything the load page template can show.
type loadPage struct {
	// Kind says which version of the page to draw: confirm, alreadyloaded, notinstalled, done, stillnotloaded or error.
	Kind string
	// Model is the model name.
	Model string
	// NeedText is the memory the model needs at least, such as 3.3 GB.
	NeedText string
	// AvailText is the free memory now, such as 12.4 GB; empty when it is unknown.
	AvailText string
	// MemNote explains why the free memory is unknown.
	MemNote string
	// Level is "short" when free memory is below the model's size, "tight" when it is close, and empty otherwise.
	Level string
	// DefaultText is the default time the model stays loaded.
	DefaultText string
	// KeepOptions is the list of "stay loaded for" choices.
	KeepOptions []keepChoice
	// KeepTip is the help bubble of the keep-alive heading.
	KeepTip tipView
	// Remaining is the time left before Ollama unloads the model by itself (done page).
	Remaining string
	// Seconds is the same time in seconds, for the ticking timer; 0 means no ticking timer.
	Seconds int
	// Detail is the plain reason shown on the error page.
	Detail string
	// Theme is the saved theme choice, as on the main page.
	Theme string
	// Token is the page token for the forms on this page.
	Token string
} // end of loadPage

// memoryLevel compares free memory with the model's size and returns "short", "tight" or "".
func memoryLevel(avail, need int64) string {
	// Less free memory than the model's size.
	if avail < need {
		// Not enough.
		return "short"
	} // end of the short case
	// Free memory is below the model's size times the factor.
	if float64(avail) < float64(need)*tightFactor {
		// Close.
		return "tight"
	} // end of the tight case
	// Plenty.
	return ""
} // end of memoryLevel

// memoryFacts works out what the load page says about free memory: the free memory text, the reason when it is unknown, and the warning level.
func memoryFacts(u *url.URL, need int64) (avail, note, level string) {
	// Free memory is only meaningful when Ollama runs on this same computer.
	if !ollamaIsLocal(u) {
		// Say why it is not shown.
		return "", "Ollama runs on another computer, and this monitor can read only the memory of the computer it runs on", ""
	} // end of the remote case
	// Read this computer's free memory.
	n, err := availableMemoryFunc()
	// It could not be read.
	if err != nil {
		// Say why it is not shown.
		return "", err.Error(), ""
	} // end of the failure case
	// Show it and compare.
	return formatSize(n), "", memoryLevel(n, need)
} // end of memoryFacts

// loadHandlers builds the two handlers: the first shows the memory warning (it changes nothing), the second does the load.
func loadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc) {
	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
	page := template.Must(template.New("load").Parse(loadTemplateText + tipsTemplateText))
	// The help bubble of the keep-alive heading never changes, so build it once.
	keepTip := makeTip("tip-keep", "Keep-alive time")
	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, status int, data loadPage) {
		// Add what every version of the page needs.
		data.Theme, data.Token, data.DefaultText = themeFromRequest(r), token, defaultKeepText
		// The choices and the bubble for the keep-alive row.
		data.KeepOptions, data.KeepTip = keepChoices, keepTip
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("load page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// A page with a ticking timer, and the warning page with its waiting message, may run the monitor's own script, and nothing else.
		if data.Seconds > 0 || data.Kind == "confirm" {
			// Replace the strict policy by the one that allows the script file.
			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
		} // end of the script policy
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the status line.
		w.WriteHeader(status)
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of show
	// check runs the checks both steps share: the model must be installed and not loaded yet; it returns the installed model, or false after the page was already shown.
	check := func(w http.ResponseWriter, r *http.Request, name string) (installedModel, bool) {
		// Read the installed models now, not what the page showed earlier.
		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return installedModel{}, false
		} // end of the installed read check
		// The model must exist.
		m, found := findInstalled(installed, name)
		// Not installed.
		if !found {
			// Say so.
			show(w, r, http.StatusOK, loadPage{Kind: "notinstalled", Model: name})
			// Stop here.
			return installedModel{}, false
		} // end of the installed check
		// Read the loaded models.
		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return installedModel{}, false
		} // end of the loaded read check
		// Already loaded: nothing to do.
		if _, ok := findLoaded(loaded, name); ok {
			// Say so.
			show(w, r, http.StatusOK, loadPage{Kind: "alreadyloaded", Model: name})
			// Stop here.
			return installedModel{}, false
		} // end of the loaded check
		// All good.
		return m, true
	} // end of check
	// ask is the first step: it shows the memory figures and the default time with a Yes and a Cancel button; it never loads anything.
	ask := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Run the model checks.
		m, ok := check(w, r, name)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the model checks
		// Start the page data with the memory the model needs at least: its size on disk (the real use is higher once the context memory is added).
		data := loadPage{Kind: "confirm", Model: name, NeedText: formatSize(m.Size)}
		// Fill in the memory figures.
		data.AvailText, data.MemNote, data.Level = memoryFacts(addr.URL, m.Size)
		// Show the page.
		show(w, r, http.StatusOK, data)
	} // end of ask
	// confirm is the second step: it checks again, loads, and then reads the real unload time from Ollama.
	confirm := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Only a choice from the fixed list is accepted; a missing choice means Ollama's default.
		keep, keepOK := keepAliveValue(r.PostFormValue("keep"))
		// Anything else is refused before any model is touched.
		if !keepOK {
			// Refuse.
			http.Error(w, "bad keep-alive choice", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the keep-alive check
		// Run the model checks again: things may have changed since the warning page.
		if _, ok := check(w, r, name); !ok {
			// A page was already shown.
			return
		} // end of the model checks
		// Ask Ollama to load it; this call returns when loading is finished, which can take a while.
		if _, err := loadModelKeep(r.Context(), addr.URL, name, keep, loadTimeout); err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the load check
		// Do not trust the 200 alone: ask until the model is in the loaded list.
		m, found, err := waitUntilLoaded(r.Context(), addr.URL, name, defaultCheckTimeout)
		// The list could not be read afterwards.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the verify check
		// Not listed: say so honestly.
		if !found {
			// Show that page.
			show(w, r, http.StatusOK, loadPage{Kind: "stillnotloaded", Model: name})
			// Stop here.
			return
		} // end of the not-listed case
		// Read the real unload time that Ollama reports for the loaded model.
		exp, expOK := m.expiresTime()
		// Show the result with the live timer.
		show(w, r, http.StatusOK, loadPage{Kind: "done", Model: name, Remaining: remainingText(time.Now(), exp, expOK), Seconds: remainingSeconds(time.Now(), exp, expOK)})
	} // end of confirm
	// Hand both back.
	return ask, confirm
} // end of loadHandlers

// readModelForm runs the checks the load forms share (same rules as the unload forms): origin, form, token and model name; ok is false when a refusal was already sent.
func readModelForm(w http.ResponseWriter, r *http.Request, token string) (string, bool) {
	// Never read more than 2 KB of form data; the real form is tiny.
	return readModelFormLimit(w, r, token, 2048)
} // end of readModelForm

// readModelFormLimit does the same checks with a chosen limit on the form size (the settings forms are larger).
func readModelFormLimit(w http.ResponseWriter, r *http.Request, token string, limit int64) (string, bool) {
	// Never read more than the limit.
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	// Only a form on this very page may send this request (requirement S2).
	if !sameOrigin(r) {
		// Refuse.
		http.Error(w, "request did not come from this page", http.StatusForbidden)
		// Stop here.
		return "", false
	} // end of the origin check
	// Read the form fields.
	if err := r.ParseForm(); err != nil {
		// A broken or too large form.
		http.Error(w, "bad form", http.StatusBadRequest)
		// Stop here.
		return "", false
	} // end of the form check
	// The token proves the form came from a page this monitor made.
	if !tokenValid(token, r.PostFormValue("token")) {
		// Refuse.
		http.Error(w, "bad token", http.StatusForbidden)
		// Stop here.
		return "", false
	} // end of the token check
	// The model name must be present and not absurdly long.
	name := r.PostFormValue("model")
	// Check the name.
	if name == "" || len(name) > maxModelNameLen {
		// Refuse.
		http.Error(w, "bad model name", http.StatusBadRequest)
		// Stop here.
		return "", false
	} // end of the name check
	// All checks passed.
	return name, true
} // end of readModelFormLimit
