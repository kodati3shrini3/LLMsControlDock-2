// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes holds the finished page and the reply body.
	"bytes"
	// context lets a request be cancelled or given a deadline.
	"context"
	// embed lets the page templates be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// encoding/json reads Ollama's replies and builds the request body.
	"encoding/json"
	// errors builds fixed error messages.
	"errors"
	// fmt builds formatted text.
	"fmt"
	// html/template builds HTML and escapes every inserted value.
	"html/template"
	// io limits how much of a reply is read.
	"io"
	// log prints messages to the terminal.
	"log"
	// math checks that a number is whole.
	"math"
	// net/http provides requests and status codes.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// sort puts the preset sizes in order.
	"sort"
	// strconv turns numbers into text and back.
	"strconv"
	// strings trims and splits text.
	"strings"
	// sync makes sure two saves never run at the same time.
	"sync"
	// time provides durations.
	"time"
) // end of imports

// gearTemplateText is the settings page template, stored inside the executable at build time (requirements T3 and T4).
//
//go:embed web/gear.html
var gearTemplateText string

// tipsTemplateText holds the shared help-bubble templates, stored inside the executable at build time.
//
//go:embed web/tips.html
var tipsTemplateText string

// minContext is the smallest context size this monitor lets you save; Ollama itself sets no smallest value (a test on the real Ollama accepted 1).
const minContext int64 = 512

// maxShowReply caps how many bytes of an /api/show reply are read (16 MiB, far more than the real reply).
const maxShowReply = 16 * 1024 * 1024

// maxContextField is the longest text the context size field may hold.
const maxContextField = 40

// gearTimeout is how long one request to Ollama may take on the settings pages.
const gearTimeout = 2 * time.Minute

// showReply is the part of the /api/show reply that the settings page uses.
type showReply struct {
	// Parameters is the saved parameters as text, one "name value" pair per line.
	Parameters string `json:"parameters"`
	// ModelInfo holds the model's own facts; each value stays raw text until it is needed, so a long list inside it costs nothing.
	ModelInfo map[string]json.RawMessage `json:"model_info"`
} // end of showReply

// paramLine is one saved parameter, such as num_ctx with 8192.
type paramLine struct {
	// Name is the parameter name.
	Name string
	// Value is the value as Ollama prints it.
	Value string
} // end of paramLine

// parseParams splits the parameters text into name and value pairs; blank lines are skipped.
func parseParams(text string) []paramLine {
	// The result.
	var out []paramLine
	// Go through the lines.
	for _, line := range strings.Split(text, "\n") {
		// Remove spaces around the line.
		line = strings.TrimSpace(line)
		// A blank line holds nothing.
		if line == "" {
			// Next line.
			continue
		} // end of the blank check
		// The name is the first word; the value is everything after it.
		name, value, _ := strings.Cut(line, " ")
		// Add the pair, without the spaces Ollama uses to line up its columns.
		out = append(out, paramLine{Name: name, Value: strings.TrimSpace(value)})
	} // end of the line loop
	// Hand back the pairs.
	return out
} // end of parseParams

// savedContext reads the saved context size: text is what Ollama printed, present says a num_ctx line exists, and n is its value (0 when it is not a usable whole number).
func savedContext(lines []paramLine) (text string, n int64, present bool) {
	// The last num_ctx line wins, like in a Modelfile.
	for _, l := range lines {
		// Only the context size line counts.
		if l.Name != "num_ctx" {
			// Next line.
			continue
		} // end of the name check
		// Remember it.
		text, present, n = l.Value, true, 0
		// Ollama may print a big number in the form 1e+08, so read it as a decimal number first.
		f, err := strconv.ParseFloat(l.Value, 64)
		// Accept only a whole number in a sane range.
		if err == nil && f == math.Trunc(f) && f >= 1 && f <= 1e12 {
			// Keep it.
			n = int64(f)
		} // end of the number check
	} // end of the line loop
	// Hand back all three.
	return text, n, present
} // end of savedContext

// otherParams returns every saved parameter except num_ctx, as "name value" texts in the order Ollama gave them.
func otherParams(lines []paramLine) []string {
	// The result.
	var out []string
	// Go through the lines.
	for _, l := range lines {
		// The context size is handled separately.
		if l.Name != "num_ctx" {
			// Keep the rest as they are.
			out = append(out, l.Name+" "+l.Value)
		} // end of the name check
	} // end of the line loop
	// Hand back the list.
	return out
} // end of otherParams

// sameStrings says whether two lists hold the same texts in the same order.
func sameStrings(a, b []string) bool {
	// Different lengths cannot be the same.
	if len(a) != len(b) {
		// Not the same.
		return false
	} // end of the length check
	// Compare one by one.
	for i := range a {
		// A difference.
		if a[i] != b[i] {
			// Not the same.
			return false
		} // end of the compare
	} // end of the loop
	// All equal.
	return true
} // end of sameStrings

// modelMaxContext reads the largest context size the model supports from its own facts; the second result is false when it cannot be read.
func modelMaxContext(info map[string]json.RawMessage) (int64, bool) {
	// The model's architecture name, such as gemma3, tells which key holds the limit.
	var arch string
	// Read it when it is there.
	if raw, ok := info["general.architecture"]; ok {
		// A failure leaves arch empty.
		_ = json.Unmarshal(raw, &arch)
	} // end of the architecture read
	// readKey turns one key's value into a number.
	readKey := func(key string) (int64, bool) {
		// The key must exist.
		raw, ok := info[key]
		// Missing.
		if !ok {
			// Not found.
			return 0, false
		} // end of the exist check
		// Numbers in JSON arrive as decimal numbers.
		var f float64
		// A value that is not a number cannot be used.
		if err := json.Unmarshal(raw, &f); err != nil || f < 1 || f != math.Trunc(f) || f > 1e12 {
			// Not usable.
			return 0, false
		} // end of the number check
		// The whole number.
		return int64(f), true
	} // end of readKey
	// The normal case: architecture name plus .context_length.
	if arch != "" {
		// Try that key.
		if n, ok := readKey(arch + ".context_length"); ok {
			// Found it.
			return n, true
		} // end of the key check
	} // end of the architecture case
	// Otherwise accept a single key that ends in .context_length, and nothing when there are several different ones.
	var found int64
	// Count what is found.
	count := 0
	// Look at every key.
	for key := range info {
		// Only keys that end this way.
		if !strings.HasSuffix(key, ".context_length") {
			// Next key.
			continue
		} // end of the suffix check
		// Read it.
		if n, ok := readKey(key); ok {
			// Remember it and count it.
			found, count = n, count+1
		} // end of the read check
	} // end of the key loop
	// Exactly one usable key.
	if count == 1 {
		// Use it.
		return found, true
	} // end of the single case
	// Nothing certain.
	return 0, false
} // end of modelMaxContext

// contextPresets lists the sizes offered as suggestions: the usual powers of two inside the allowed range, plus the model's maximum.
func contextPresets(min, max int64) []int64 {
	// The usual sizes.
	base := []int64{2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576}
	// Keep the ones inside the range.
	var out []int64
	// Go through them.
	for _, v := range base {
		// Inside the range.
		if v >= min && v <= max {
			// Keep it.
			out = append(out, v)
		} // end of the range check
	} // end of the loop
	// The maximum is always offered, unless it is already there.
	if max >= min {
		// Look for it.
		has := false
		// Check each one.
		for _, v := range out {
			// A match.
			if v == max {
				// Already there.
				has = true
			} // end of the match check
		} // end of the loop
		// Add it when missing.
		if !has {
			// Add it.
			out = append(out, max)
		} // end of the add
	} // end of the maximum case
	// Smallest first.
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	// Hand back the list.
	return out
} // end of contextPresets

// validateContext checks what was typed; it returns the number and an empty text when all is well, or zero and the reason in plain words.
func validateContext(raw string, min, max int64) (int64, string) {
	// Spaces around the number do not matter.
	s := strings.TrimSpace(raw)
	// An empty value is never allowed: a saved value can be changed but not removed.
	if s == "" {
		// Say why.
		return 0, "The context size cannot be empty. A saved value can be changed, but not removed."
	} // end of the empty check
	// Only the digits 0 to 9: no signs, no decimals, no letters, no other scripts.
	for _, r := range s {
		// Anything else is refused.
		if r < '0' || r > '9' {
			// Say what is expected.
			return 0, "Use digits only, as a whole number such as 8192."
		} // end of the digit check
	} // end of the loop
	// A number with more than 12 digits is far outside any model.
	if len(s) > 12 {
		// Say so with the range.
		return 0, fmt.Sprintf("That number is too large. The model maximum is %d.", max)
	} // end of the length check
	// Read the number; it cannot fail now.
	n, err := strconv.ParseInt(s, 10, 64)
	// Defensive: treat a failure as a bad number.
	if err != nil {
		// Say what is expected.
		return 0, "Use digits only, as a whole number such as 8192."
	} // end of the parse check
	// Below the smallest allowed size.
	if n < min {
		// Say so.
		return 0, fmt.Sprintf("%d is too small. The smallest size allowed here is %d.", n, min)
	} // end of the small check
	// Above the model's maximum.
	if n > max {
		// Say so.
		return 0, fmt.Sprintf("%d is more than this model supports. The model maximum is %d.", n, max)
	} // end of the large check
	// All good.
	return n, ""
} // end of validateContext

// postForReply sends one JSON body and decodes the JSON reply into out (when out is not nil); it also returns the short error text Ollama may have sent; every error text is fixed and never contains the address.
func postForReply(ctx context.Context, base *url.URL, path string, timeout time.Duration, payload any, out any) (int, string, error) {
	// Turn the payload into JSON text.
	body, err := json.Marshal(payload)
	// A failure here is a bug in the program, not in Ollama.
	if err != nil {
		// Return a fixed message.
		return 0, "", errors.New("the request could not be built")
	} // end of the marshal check
	// Create the request; the context allows cancelling it from outside.
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base.JoinPath(path).String(), bytes.NewReader(body))
	// A failure here means the address could not form a request.
	if err != nil {
		// Return a fixed message.
		return 0, "", errors.New("the address could not be used to build a request")
	} // end of the request check
	// Tell Ollama the body is JSON.
	req.Header.Set("Content-Type", "application/json")
	// Send the request and wait for the reply.
	resp, err := (&http.Client{Timeout: timeout}).Do(req)
	// A failure here means no reply arrived at all.
	if err != nil {
		// Turn the technical error into a plain reason (reused from check.go).
		return 0, "", errors.New(explainError(err))
	} // end of the send check
	// Always close the reply body when this function ends.
	defer resp.Body.Close()
	// Read a limited amount of the reply.
	data, _ := io.ReadAll(io.LimitReader(resp.Body, maxShowReply))
	// A good reply is decoded into out.
	if resp.StatusCode == http.StatusOK {
		// Nothing to decode for some requests.
		if out == nil {
			// Done.
			return resp.StatusCode, "", nil
		} // end of the nothing case
		// Decode.
		if err := json.Unmarshal(data, out); err != nil {
			// Not the expected JSON.
			return resp.StatusCode, "", errors.New("the reply was not the expected JSON, so it does not look like Ollama")
		} // end of the decode check
		// Done.
		return resp.StatusCode, "", nil
	} // end of the good case
	// A refusal may carry a short error text.
	var e struct {
		// Error is Ollama's own short message.
		Error string `json:"error"`
	} // end of the error shape
	// Read it when possible.
	_ = json.Unmarshal(data, &e)
	// Keep it short; the page escapes it before showing it.
	msg := e.Error
	// Cut a long message.
	if len(msg) > 200 {
		// Keep the first 200 bytes.
		msg = msg[:200]
	} // end of the cut
	// Hand back the status and the text.
	return resp.StatusCode, msg, nil
} // end of postForReply

// fetchShow asks Ollama for one model's details; the status is 404 when Ollama does not know the model.
func fetchShow(ctx context.Context, base *url.URL, name string, timeout time.Duration) (showReply, int, error) {
	// A place for the reply.
	var reply showReply
	// Ask.
	status, _, err := postForReply(ctx, base, "api/show", timeout, map[string]any{"model": name}, &reply)
	// Hand everything back.
	return reply, status, err
} // end of fetchShow

// createWithContext saves a context size inside the model: Ollama rewrites the model's saved settings, keeping everything else (the model is created from itself, so no weights are fetched).
func createWithContext(ctx context.Context, base *url.URL, name string, n int64, timeout time.Duration) (int, string, error) {
	// The body Ollama expects; stream false makes it answer once, when finished.
	payload := map[string]any{"model": name, "from": name, "parameters": map[string]any{"num_ctx": n}, "stream": false}
	// Send it.
	return postForReply(ctx, base, "api/create", timeout, payload, nil)
} // end of createWithContext

// gearPage is everything the settings page template can show.
type gearPage struct {
	// Kind says which version of the page to draw: settings, review, done, nochange, loaded, notinstalled, mismatch or error.
	Kind string
	// Model is the model name.
	Model string
	// SavedText says what is saved now: the number, or a sentence when nothing is saved.
	SavedText string
	// Max is the model's largest context size; 0 when unknown.
	Max int64
	// Min is the smallest size this monitor allows.
	Min int64
	// Presets are the suggested sizes.
	Presets []int64
	// Others are the other saved parameters, shown and kept as they are.
	Others []string
	// CanSave is false when no safe limit is known, so saving is switched off.
	CanSave bool
	// Problem explains why the typed value was refused.
	Problem string
	// Typed is what was typed, shown again in the field.
	Typed string
	// NewValue is the size to be saved (review and done pages).
	NewValue int64
	// AfterText is what Ollama reports after the save.
	AfterText string
	// Detail is the plain reason shown on the error and mismatch pages.
	Detail string
	// AboveMax is true when the saved size is already above the model's maximum.
	AboveMax bool
	// Theme is the saved theme choice, as on the main page.
	Theme string
	// Token is the page token for the forms on this page.
	Token string
	// Tips holds the help bubbles by short name.
	Tips map[string]tipView
} // end of gearPage

// gearFacts is what the three handlers learn about one model before they act.
type gearFacts struct {
	// Page holds the figures for the page.
	Page gearPage
	// Lines are the saved parameters.
	Lines []paramLine
	// Current is the saved context size (0 when none or unusable).
	Current int64
	// Present says whether a num_ctx line exists.
	Present bool
} // end of gearFacts

// gearTipKeys maps the short names used in the template to the headings of the help texts.
var gearTipKeys = map[string]string{"ctx": "Context size", "max": "Model maximum", "min": "Smallest allowed", "saved": "Saved in the model", "other": "Other saved settings"}

// gearHandlers builds the three handlers: the settings page (shows, changes nothing), the review page (checks the typed value and asks "are you sure?"), and the save (changes the model).
func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
	// Read the template once, together with the shared help-bubble templates; Must stops the program at start-up if it is broken, which a test would catch first.
	page := template.Must(template.New("gear").Parse(gearTemplateText + tipsTemplateText))
	// The help bubbles never change, so build them once.
	tips := map[string]tipView{}
	// One for each short name.
	for key, heading := range gearTipKeys {
		// Build it with an element name that is unique on the page.
		tips[key] = makeTip("tip-gear-"+key, heading)
	} // end of the tip loop
	// A lock so two saves never run at the same time (a double click on the Yes button, for example).
	var saveLock sync.Mutex
	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, status int, data gearPage) {
		// Add what every version of the page needs.
		data.Theme, data.Token, data.Tips, data.Min = themeFromRequest(r), token, tips, minContext
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("settings page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the status line.
		w.WriteHeader(status)
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of show
	// facts runs the checks all three steps share: the model must be installed, must not be loaded, and its details must be readable; ok is false after a page was already shown.
	facts := func(w http.ResponseWriter, r *http.Request, name string) (gearFacts, bool) {
		// Read the installed models now, not what the page showed earlier.
		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return gearFacts{}, false
		} // end of the installed read check
		// The model must exist.
		if _, found := findInstalled(installed, name); !found {
			// Say so.
			show(w, r, http.StatusOK, gearPage{Kind: "notinstalled", Model: name})
			// Stop here.
			return gearFacts{}, false
		} // end of the installed check
		// Read the loaded models.
		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return gearFacts{}, false
		} // end of the loaded read check
		// A loaded model keeps the size it was loaded with, so its settings are not changed here.
		if _, ok := findLoaded(loaded, name); ok {
			// Say so.
			show(w, r, http.StatusOK, gearPage{Kind: "loaded", Model: name})
			// Stop here.
			return gearFacts{}, false
		} // end of the loaded check
		// Read the model's details.
		info, status, err := fetchShow(r.Context(), addr.URL, name, gearTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return gearFacts{}, false
		} // end of the show read check
		// Ollama does not know the model.
		if status == http.StatusNotFound {
			// Say so.
			show(w, r, http.StatusOK, gearPage{Kind: "notinstalled", Model: name})
			// Stop here.
			return gearFacts{}, false
		} // end of the unknown check
		// Any other refusal.
		if status != http.StatusOK {
			// Say so.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: fmt.Sprintf("Ollama answered the details request with status %d", status)})
			// Stop here.
			return gearFacts{}, false
		} // end of the status check
		// Work out the figures.
		lines := parseParams(info.Parameters)
		// The saved context size.
		text, current, present := savedContext(lines)
		// The model maximum.
		max, maxOK := modelMaxContext(info.ModelInfo)
		// Start the page figures.
		p := gearPage{Model: name, Max: max, Others: otherParams(lines), CanSave: maxOK}
		// The words for the saved value.
		switch {
		// Nothing saved.
		case !present:
			// Say what that means.
			p.SavedText = "not saved in the model (Ollama chooses a size when the model loads)"
		// Saved but not usable.
		case current == 0:
			// Show it as it is.
			p.SavedText = text + " (not a usable size)"
		// A normal value.
		default:
			// Show the number.
			p.SavedText = strconv.FormatInt(current, 10)
		} // end of the saved text
		// Offer suggestions only when the limit is known.
		if maxOK {
			// The suggestions.
			p.Presets = contextPresets(minContext, max)
			// A saved value above the maximum deserves a note.
			p.AboveMax = current > max
		} // end of the preset case
		// Hand everything back.
		return gearFacts{Page: p, Lines: lines, Current: current, Present: present}, true
	} // end of facts
	// check runs the typed value through the rules; it shows the settings page again with the reason when it is refused, and returns false then.
	check := func(w http.ResponseWriter, r *http.Request, f gearFacts) (int64, bool) {
		// The typed text, cut to a sane length first.
		typed := r.PostFormValue("num_ctx")
		// An absurdly long text is refused at once.
		if len(typed) > maxContextField {
			// Cut it for display.
			typed = typed[:maxContextField]
		} // end of the length check
		// Without a known maximum nothing can be saved.
		if !f.Page.CanSave {
			// Show the settings page with the reason.
			p := f.Page
			// The reason.
			p.Kind, p.Problem, p.Typed = "settings", "Ollama does not report this model's maximum context size, so no safe limit can be checked and nothing can be saved.", typed
			// Show it.
			show(w, r, http.StatusOK, p)
			// Refused.
			return 0, false
		} // end of the limit check
		// Apply the rules.
		n, problem := validateContext(r.PostFormValue("num_ctx"), minContext, f.Page.Max)
		// A refusal.
		if problem != "" {
			// Show the settings page with the reason.
			p := f.Page
			// The reason and the typed text.
			p.Kind, p.Problem, p.Typed = "settings", problem, typed
			// Show it.
			show(w, r, http.StatusOK, p)
			// Refused.
			return 0, false
		} // end of the problem check
		// Accepted.
		return n, true
	} // end of check
	// settings is the first step: it shows the saved values and the form; it changes nothing.
	settings := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Run the model checks.
		f, ok := facts(w, r, name)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the model checks
		// Show the form; the field starts with the saved value when there is one.
		p := f.Page
		// The kind of page.
		p.Kind = "settings"
		// Pre-fill the field with the saved value.
		if f.Current > 0 {
			// The number.
			p.Typed = strconv.FormatInt(f.Current, 10)
		} // end of the pre-fill
		// Show it.
		show(w, r, http.StatusOK, p)
	} // end of settings
	// review is the second step: it checks the typed value and asks "are you sure?"; it changes nothing.
	review := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Run the model checks.
		f, ok := facts(w, r, name)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the model checks
		// Run the rules.
		n, ok := check(w, r, f)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the rule check
		// The same value as now: nothing to do.
		p := f.Page
		// The size under review.
		p.NewValue = n
		// Nothing changes.
		if f.Present && n == f.Current {
			// Say so.
			p.Kind = "nochange"
			// Show it.
			show(w, r, http.StatusOK, p)
			// Stop here.
			return
		} // end of the same-value case
		// Ask for the confirmation.
		p.Kind = "review"
		// Show it.
		show(w, r, http.StatusOK, p)
	} // end of review
	// save is the third step: it checks everything again, saves, and then asks Ollama what is saved now.
	save := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Only one save at a time.
		saveLock.Lock()
		// Release at the end.
		defer saveLock.Unlock()
		// Run the model checks again: things may have changed since the review page.
		f, ok := facts(w, r, name)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the model checks
		// Run the rules again.
		n, ok := check(w, r, f)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the rule check
		// The page figures for the result pages.
		p := f.Page
		// The size being saved.
		p.NewValue = n
		// The same value as now: nothing to do (a second click on Yes ends up here).
		if f.Present && n == f.Current {
			// Say so.
			p.Kind = "nochange"
			// Show it.
			show(w, r, http.StatusOK, p)
			// Stop here.
			return
		} // end of the same-value case
		// Save it inside the model.
		status, text, err := createWithContext(r.Context(), addr.URL, name, n, gearTimeout)
		// No answer at all.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the send check
		// Ollama refused.
		if status != http.StatusOK {
			// The reason, with Ollama's own words when it gave any.
			detail := fmt.Sprintf("Ollama refused the change (status %d).", status)
			// Add its message.
			if text != "" {
				// Append it; the page escapes it.
				detail += " Ollama said: " + text
			} // end of the message
			// Show it.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: detail})
			// Stop here.
			return
		} // end of the refusal check
		// Do not trust the success alone: ask Ollama what is saved now.
		after, status, err := fetchShow(r.Context(), addr.URL, name, gearTimeout)
		// The check could not be done.
		if err != nil || status != http.StatusOK {
			// Say exactly what is known.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: "Ollama accepted the change, but the check afterwards failed. Open the settings again to see what is saved."})
			// Stop here.
			return
		} // end of the check read
		// Read the saved values again.
		afterLines := parseParams(after.Parameters)
		// The saved context size now.
		afterText, afterN, afterPresent := savedContext(afterLines)
		// What Ollama reports, for the page.
		p.AfterText = afterText
		// The size must be the new one, and every other saved parameter must be exactly as before.
		if !afterPresent || afterN != n || !sameStrings(otherParams(f.Lines), otherParams(afterLines)) {
			// Say honestly that the result is not what was asked.
			p.Kind = "mismatch"
			// The detail.
			p.Detail = "Ollama accepted the change, but what it reports now is not what was expected. Open the settings again and check the values."
			// Show it.
			show(w, r, http.StatusOK, p)
			// Stop here.
			return
		} // end of the verify check
		// Everything checked out.
		p.Kind = "done"
		// Show it.
		show(w, r, http.StatusOK, p)
	} // end of save
	// Hand the three back.
	return settings, review, save
} // end of gearHandlers
