#!/usr/bin/env bash
# Script 34: gear icon and model settings page (context size saved inside the Ollama model) plus the keep-alive choice on the Load page; applied on the feature branch.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/gear-load-settings" ] || { echo "FAIL  not on feature/gear-load-settings"; exit 1; }
# Refuse when tracked files are already changed or new files other than scripts exist (a clean start keeps the commit clean).
if [ -n "$(git status --porcelain | grep -v '^?? scripts/' || true)" ]; then
  # Show what is in the way.
  echo "FAIL  the working tree is not clean:"; git status --short; exit 1
fi
# Refuse when the change was already applied.
[ ! -f gear.go ] || { echo "FAIL  gear.go already exists; this script was already applied"; exit 1; }
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/gear.go b/gear.go
new file mode 100644
index 0000000..d53aaf5
--- /dev/null
+++ b/gear.go
@@ -0,0 +1,761 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes holds the finished page and the reply body.
+	"bytes"
+	// context lets a request be cancelled or given a deadline.
+	"context"
+	// embed lets the page templates be stored inside the executable (the blank name means we only need its side effect).
+	_ "embed"
+	// encoding/json reads Ollama's replies and builds the request body.
+	"encoding/json"
+	// errors builds fixed error messages.
+	"errors"
+	// fmt builds formatted text.
+	"fmt"
+	// html/template builds HTML and escapes every inserted value.
+	"html/template"
+	// io limits how much of a reply is read.
+	"io"
+	// log prints messages to the terminal.
+	"log"
+	// math checks that a number is whole.
+	"math"
+	// net/http provides requests and status codes.
+	"net/http"
+	// net/url holds the parsed address type.
+	"net/url"
+	// sort puts the preset sizes in order.
+	"sort"
+	// strconv turns numbers into text and back.
+	"strconv"
+	// strings trims and splits text.
+	"strings"
+	// sync makes sure two saves never run at the same time.
+	"sync"
+	// time provides durations.
+	"time"
+) // end of imports
+
+// gearTemplateText is the settings page template, stored inside the executable at build time (requirements T3 and T4).
+//
+//go:embed web/gear.html
+var gearTemplateText string
+
+// tipsTemplateText holds the shared help-bubble templates, stored inside the executable at build time.
+//
+//go:embed web/tips.html
+var tipsTemplateText string
+
+// minContext is the smallest context size this monitor lets you save; Ollama itself sets no smallest value (a test on the real Ollama accepted 1).
+const minContext int64 = 512
+
+// maxShowReply caps how many bytes of an /api/show reply are read (16 MiB, far more than the real reply).
+const maxShowReply = 16 * 1024 * 1024
+
+// maxContextField is the longest text the context size field may hold.
+const maxContextField = 40
+
+// gearTimeout is how long one request to Ollama may take on the settings pages.
+const gearTimeout = 2 * time.Minute
+
+// showReply is the part of the /api/show reply that the settings page uses.
+type showReply struct {
+	// Parameters is the saved parameters as text, one "name value" pair per line.
+	Parameters string `json:"parameters"`
+	// ModelInfo holds the model's own facts; each value stays raw text until it is needed, so a long list inside it costs nothing.
+	ModelInfo map[string]json.RawMessage `json:"model_info"`
+} // end of showReply
+
+// paramLine is one saved parameter, such as num_ctx with 8192.
+type paramLine struct {
+	// Name is the parameter name.
+	Name string
+	// Value is the value as Ollama prints it.
+	Value string
+} // end of paramLine
+
+// parseParams splits the parameters text into name and value pairs; blank lines are skipped.
+func parseParams(text string) []paramLine {
+	// The result.
+	var out []paramLine
+	// Go through the lines.
+	for _, line := range strings.Split(text, "\n") {
+		// Remove spaces around the line.
+		line = strings.TrimSpace(line)
+		// A blank line holds nothing.
+		if line == "" {
+			// Next line.
+			continue
+		} // end of the blank check
+		// The name is the first word; the value is everything after it.
+		name, value, _ := strings.Cut(line, " ")
+		// Add the pair, without the spaces Ollama uses to line up its columns.
+		out = append(out, paramLine{Name: name, Value: strings.TrimSpace(value)})
+	} // end of the line loop
+	// Hand back the pairs.
+	return out
+} // end of parseParams
+
+// savedContext reads the saved context size: text is what Ollama printed, present says a num_ctx line exists, and n is its value (0 when it is not a usable whole number).
+func savedContext(lines []paramLine) (text string, n int64, present bool) {
+	// The last num_ctx line wins, like in a Modelfile.
+	for _, l := range lines {
+		// Only the context size line counts.
+		if l.Name != "num_ctx" {
+			// Next line.
+			continue
+		} // end of the name check
+		// Remember it.
+		text, present, n = l.Value, true, 0
+		// Ollama may print a big number in the form 1e+08, so read it as a decimal number first.
+		f, err := strconv.ParseFloat(l.Value, 64)
+		// Accept only a whole number in a sane range.
+		if err == nil && f == math.Trunc(f) && f >= 1 && f <= 1e12 {
+			// Keep it.
+			n = int64(f)
+		} // end of the number check
+	} // end of the line loop
+	// Hand back all three.
+	return text, n, present
+} // end of savedContext
+
+// otherParams returns every saved parameter except num_ctx, as "name value" texts in the order Ollama gave them.
+func otherParams(lines []paramLine) []string {
+	// The result.
+	var out []string
+	// Go through the lines.
+	for _, l := range lines {
+		// The context size is handled separately.
+		if l.Name != "num_ctx" {
+			// Keep the rest as they are.
+			out = append(out, l.Name+" "+l.Value)
+		} // end of the name check
+	} // end of the line loop
+	// Hand back the list.
+	return out
+} // end of otherParams
+
+// sameStrings says whether two lists hold the same texts in the same order.
+func sameStrings(a, b []string) bool {
+	// Different lengths cannot be the same.
+	if len(a) != len(b) {
+		// Not the same.
+		return false
+	} // end of the length check
+	// Compare one by one.
+	for i := range a {
+		// A difference.
+		if a[i] != b[i] {
+			// Not the same.
+			return false
+		} // end of the compare
+	} // end of the loop
+	// All equal.
+	return true
+} // end of sameStrings
+
+// modelMaxContext reads the largest context size the model supports from its own facts; the second result is false when it cannot be read.
+func modelMaxContext(info map[string]json.RawMessage) (int64, bool) {
+	// The model's architecture name, such as gemma3, tells which key holds the limit.
+	var arch string
+	// Read it when it is there.
+	if raw, ok := info["general.architecture"]; ok {
+		// A failure leaves arch empty.
+		_ = json.Unmarshal(raw, &arch)
+	} // end of the architecture read
+	// readKey turns one key's value into a number.
+	readKey := func(key string) (int64, bool) {
+		// The key must exist.
+		raw, ok := info[key]
+		// Missing.
+		if !ok {
+			// Not found.
+			return 0, false
+		} // end of the exist check
+		// Numbers in JSON arrive as decimal numbers.
+		var f float64
+		// A value that is not a number cannot be used.
+		if err := json.Unmarshal(raw, &f); err != nil || f < 1 || f != math.Trunc(f) || f > 1e12 {
+			// Not usable.
+			return 0, false
+		} // end of the number check
+		// The whole number.
+		return int64(f), true
+	} // end of readKey
+	// The normal case: architecture name plus .context_length.
+	if arch != "" {
+		// Try that key.
+		if n, ok := readKey(arch + ".context_length"); ok {
+			// Found it.
+			return n, true
+		} // end of the key check
+	} // end of the architecture case
+	// Otherwise accept a single key that ends in .context_length, and nothing when there are several different ones.
+	var found int64
+	// Count what is found.
+	count := 0
+	// Look at every key.
+	for key := range info {
+		// Only keys that end this way.
+		if !strings.HasSuffix(key, ".context_length") {
+			// Next key.
+			continue
+		} // end of the suffix check
+		// Read it.
+		if n, ok := readKey(key); ok {
+			// Remember it and count it.
+			found, count = n, count+1
+		} // end of the read check
+	} // end of the key loop
+	// Exactly one usable key.
+	if count == 1 {
+		// Use it.
+		return found, true
+	} // end of the single case
+	// Nothing certain.
+	return 0, false
+} // end of modelMaxContext
+
+// contextPresets lists the sizes offered as suggestions: the usual powers of two inside the allowed range, plus the model's maximum.
+func contextPresets(min, max int64) []int64 {
+	// The usual sizes.
+	base := []int64{2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576}
+	// Keep the ones inside the range.
+	var out []int64
+	// Go through them.
+	for _, v := range base {
+		// Inside the range.
+		if v >= min && v <= max {
+			// Keep it.
+			out = append(out, v)
+		} // end of the range check
+	} // end of the loop
+	// The maximum is always offered, unless it is already there.
+	if max >= min {
+		// Look for it.
+		has := false
+		// Check each one.
+		for _, v := range out {
+			// A match.
+			if v == max {
+				// Already there.
+				has = true
+			} // end of the match check
+		} // end of the loop
+		// Add it when missing.
+		if !has {
+			// Add it.
+			out = append(out, max)
+		} // end of the add
+	} // end of the maximum case
+	// Smallest first.
+	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
+	// Hand back the list.
+	return out
+} // end of contextPresets
+
+// validateContext checks what was typed; it returns the number and an empty text when all is well, or zero and the reason in plain words.
+func validateContext(raw string, min, max int64) (int64, string) {
+	// Spaces around the number do not matter.
+	s := strings.TrimSpace(raw)
+	// An empty value is never allowed: a saved value can be changed but not removed.
+	if s == "" {
+		// Say why.
+		return 0, "The context size cannot be empty. A saved value can be changed, but not removed."
+	} // end of the empty check
+	// Only the digits 0 to 9: no signs, no decimals, no letters, no other scripts.
+	for _, r := range s {
+		// Anything else is refused.
+		if r < '0' || r > '9' {
+			// Say what is expected.
+			return 0, "Use digits only, as a whole number such as 8192."
+		} // end of the digit check
+	} // end of the loop
+	// A number with more than 12 digits is far outside any model.
+	if len(s) > 12 {
+		// Say so with the range.
+		return 0, fmt.Sprintf("That number is too large. The model maximum is %d.", max)
+	} // end of the length check
+	// Read the number; it cannot fail now.
+	n, err := strconv.ParseInt(s, 10, 64)
+	// Defensive: treat a failure as a bad number.
+	if err != nil {
+		// Say what is expected.
+		return 0, "Use digits only, as a whole number such as 8192."
+	} // end of the parse check
+	// Below the smallest allowed size.
+	if n < min {
+		// Say so.
+		return 0, fmt.Sprintf("%d is too small. The smallest size allowed here is %d.", n, min)
+	} // end of the small check
+	// Above the model's maximum.
+	if n > max {
+		// Say so.
+		return 0, fmt.Sprintf("%d is more than this model supports. The model maximum is %d.", n, max)
+	} // end of the large check
+	// All good.
+	return n, ""
+} // end of validateContext
+
+// postForReply sends one JSON body and decodes the JSON reply into out (when out is not nil); it also returns the short error text Ollama may have sent; every error text is fixed and never contains the address.
+func postForReply(ctx context.Context, base *url.URL, path string, timeout time.Duration, payload any, out any) (int, string, error) {
+	// Turn the payload into JSON text.
+	body, err := json.Marshal(payload)
+	// A failure here is a bug in the program, not in Ollama.
+	if err != nil {
+		// Return a fixed message.
+		return 0, "", errors.New("the request could not be built")
+	} // end of the marshal check
+	// Create the request; the context allows cancelling it from outside.
+	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base.JoinPath(path).String(), bytes.NewReader(body))
+	// A failure here means the address could not form a request.
+	if err != nil {
+		// Return a fixed message.
+		return 0, "", errors.New("the address could not be used to build a request")
+	} // end of the request check
+	// Tell Ollama the body is JSON.
+	req.Header.Set("Content-Type", "application/json")
+	// Send the request and wait for the reply.
+	resp, err := (&http.Client{Timeout: timeout}).Do(req)
+	// A failure here means no reply arrived at all.
+	if err != nil {
+		// Turn the technical error into a plain reason (reused from check.go).
+		return 0, "", errors.New(explainError(err))
+	} // end of the send check
+	// Always close the reply body when this function ends.
+	defer resp.Body.Close()
+	// Read a limited amount of the reply.
+	data, _ := io.ReadAll(io.LimitReader(resp.Body, maxShowReply))
+	// A good reply is decoded into out.
+	if resp.StatusCode == http.StatusOK {
+		// Nothing to decode for some requests.
+		if out == nil {
+			// Done.
+			return resp.StatusCode, "", nil
+		} // end of the nothing case
+		// Decode.
+		if err := json.Unmarshal(data, out); err != nil {
+			// Not the expected JSON.
+			return resp.StatusCode, "", errors.New("the reply was not the expected JSON, so it does not look like Ollama")
+		} // end of the decode check
+		// Done.
+		return resp.StatusCode, "", nil
+	} // end of the good case
+	// A refusal may carry a short error text.
+	var e struct {
+		// Error is Ollama's own short message.
+		Error string `json:"error"`
+	} // end of the error shape
+	// Read it when possible.
+	_ = json.Unmarshal(data, &e)
+	// Keep it short; the page escapes it before showing it.
+	msg := e.Error
+	// Cut a long message.
+	if len(msg) > 200 {
+		// Keep the first 200 bytes.
+		msg = msg[:200]
+	} // end of the cut
+	// Hand back the status and the text.
+	return resp.StatusCode, msg, nil
+} // end of postForReply
+
+// fetchShow asks Ollama for one model's details; the status is 404 when Ollama does not know the model.
+func fetchShow(ctx context.Context, base *url.URL, name string, timeout time.Duration) (showReply, int, error) {
+	// A place for the reply.
+	var reply showReply
+	// Ask.
+	status, _, err := postForReply(ctx, base, "api/show", timeout, map[string]any{"model": name}, &reply)
+	// Hand everything back.
+	return reply, status, err
+} // end of fetchShow
+
+// createWithContext saves a context size inside the model: Ollama rewrites the model's saved settings, keeping everything else (the model is created from itself, so no weights are fetched).
+func createWithContext(ctx context.Context, base *url.URL, name string, n int64, timeout time.Duration) (int, string, error) {
+	// The body Ollama expects; stream false makes it answer once, when finished.
+	payload := map[string]any{"model": name, "from": name, "parameters": map[string]any{"num_ctx": n}, "stream": false}
+	// Send it.
+	return postForReply(ctx, base, "api/create", timeout, payload, nil)
+} // end of createWithContext
+
+// gearPage is everything the settings page template can show.
+type gearPage struct {
+	// Kind says which version of the page to draw: settings, review, done, nochange, loaded, notinstalled, mismatch or error.
+	Kind string
+	// Model is the model name.
+	Model string
+	// SavedText says what is saved now: the number, or a sentence when nothing is saved.
+	SavedText string
+	// Max is the model's largest context size; 0 when unknown.
+	Max int64
+	// Min is the smallest size this monitor allows.
+	Min int64
+	// Presets are the suggested sizes.
+	Presets []int64
+	// Others are the other saved parameters, shown and kept as they are.
+	Others []string
+	// CanSave is false when no safe limit is known, so saving is switched off.
+	CanSave bool
+	// Problem explains why the typed value was refused.
+	Problem string
+	// Typed is what was typed, shown again in the field.
+	Typed string
+	// NewValue is the size to be saved (review and done pages).
+	NewValue int64
+	// AfterText is what Ollama reports after the save.
+	AfterText string
+	// Detail is the plain reason shown on the error and mismatch pages.
+	Detail string
+	// AboveMax is true when the saved size is already above the model's maximum.
+	AboveMax bool
+	// Theme is the saved theme choice, as on the main page.
+	Theme string
+	// Token is the page token for the forms on this page.
+	Token string
+	// Tips holds the help bubbles by short name.
+	Tips map[string]tipView
+} // end of gearPage
+
+// gearFacts is what the three handlers learn about one model before they act.
+type gearFacts struct {
+	// Page holds the figures for the page.
+	Page gearPage
+	// Lines are the saved parameters.
+	Lines []paramLine
+	// Current is the saved context size (0 when none or unusable).
+	Current int64
+	// Present says whether a num_ctx line exists.
+	Present bool
+} // end of gearFacts
+
+// gearTipKeys maps the short names used in the template to the headings of the help texts.
+var gearTipKeys = map[string]string{"ctx": "Context size", "max": "Model maximum", "min": "Smallest allowed", "saved": "Saved in the model", "other": "Other saved settings"}
+
+// gearHandlers builds the three handlers: the settings page (shows, changes nothing), the review page (checks the typed value and asks "are you sure?"), and the save (changes the model).
+func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
+	// Read the template once, together with the shared help-bubble templates; Must stops the program at start-up if it is broken, which a test would catch first.
+	page := template.Must(template.New("gear").Parse(gearTemplateText + tipsTemplateText))
+	// The help bubbles never change, so build them once.
+	tips := map[string]tipView{}
+	// One for each short name.
+	for key, heading := range gearTipKeys {
+		// Build it with an element name that is unique on the page.
+		tips[key] = makeTip("tip-gear-"+key, heading)
+	} // end of the tip loop
+	// A lock so two saves never run at the same time (a double click on the Yes button, for example).
+	var saveLock sync.Mutex
+	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
+	show := func(w http.ResponseWriter, r *http.Request, status int, data gearPage) {
+		// Add what every version of the page needs.
+		data.Theme, data.Token, data.Tips, data.Min = themeFromRequest(r), token, tips, minContext
+		// Build the page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason for the person running the program.
+			log.Printf("settings page error: %v", err)
+			// Send a plain 500 without details.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the status line.
+		w.WriteHeader(status)
+		// Send the finished page.
+		w.Write(buf.Bytes())
+	} // end of show
+	// facts runs the checks all three steps share: the model must be installed, must not be loaded, and its details must be readable; ok is false after a page was already shown.
+	facts := func(w http.ResponseWriter, r *http.Request, name string) (gearFacts, bool) {
+		// Read the installed models now, not what the page showed earlier.
+		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return gearFacts{}, false
+		} // end of the installed read check
+		// The model must exist.
+		if _, found := findInstalled(installed, name); !found {
+			// Say so.
+			show(w, r, http.StatusOK, gearPage{Kind: "notinstalled", Model: name})
+			// Stop here.
+			return gearFacts{}, false
+		} // end of the installed check
+		// Read the loaded models.
+		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return gearFacts{}, false
+		} // end of the loaded read check
+		// A loaded model keeps the size it was loaded with, so its settings are not changed here.
+		if _, ok := findLoaded(loaded, name); ok {
+			// Say so.
+			show(w, r, http.StatusOK, gearPage{Kind: "loaded", Model: name})
+			// Stop here.
+			return gearFacts{}, false
+		} // end of the loaded check
+		// Read the model's details.
+		info, status, err := fetchShow(r.Context(), addr.URL, name, gearTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return gearFacts{}, false
+		} // end of the show read check
+		// Ollama does not know the model.
+		if status == http.StatusNotFound {
+			// Say so.
+			show(w, r, http.StatusOK, gearPage{Kind: "notinstalled", Model: name})
+			// Stop here.
+			return gearFacts{}, false
+		} // end of the unknown check
+		// Any other refusal.
+		if status != http.StatusOK {
+			// Say so.
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: fmt.Sprintf("Ollama answered the details request with status %d", status)})
+			// Stop here.
+			return gearFacts{}, false
+		} // end of the status check
+		// Work out the figures.
+		lines := parseParams(info.Parameters)
+		// The saved context size.
+		text, current, present := savedContext(lines)
+		// The model maximum.
+		max, maxOK := modelMaxContext(info.ModelInfo)
+		// Start the page figures.
+		p := gearPage{Model: name, Max: max, Others: otherParams(lines), CanSave: maxOK}
+		// The words for the saved value.
+		switch {
+		// Nothing saved.
+		case !present:
+			// Say what that means.
+			p.SavedText = "not saved in the model (Ollama chooses a size when the model loads)"
+		// Saved but not usable.
+		case current == 0:
+			// Show it as it is.
+			p.SavedText = text + " (not a usable size)"
+		// A normal value.
+		default:
+			// Show the number.
+			p.SavedText = strconv.FormatInt(current, 10)
+		} // end of the saved text
+		// Offer suggestions only when the limit is known.
+		if maxOK {
+			// The suggestions.
+			p.Presets = contextPresets(minContext, max)
+			// A saved value above the maximum deserves a note.
+			p.AboveMax = current > max
+		} // end of the preset case
+		// Hand everything back.
+		return gearFacts{Page: p, Lines: lines, Current: current, Present: present}, true
+	} // end of facts
+	// check runs the typed value through the rules; it shows the settings page again with the reason when it is refused, and returns false then.
+	check := func(w http.ResponseWriter, r *http.Request, f gearFacts) (int64, bool) {
+		// The typed text, cut to a sane length first.
+		typed := r.PostFormValue("num_ctx")
+		// An absurdly long text is refused at once.
+		if len(typed) > maxContextField {
+			// Cut it for display.
+			typed = typed[:maxContextField]
+		} // end of the length check
+		// Without a known maximum nothing can be saved.
+		if !f.Page.CanSave {
+			// Show the settings page with the reason.
+			p := f.Page
+			// The reason.
+			p.Kind, p.Problem, p.Typed = "settings", "Ollama does not report this model's maximum context size, so no safe limit can be checked and nothing can be saved.", typed
+			// Show it.
+			show(w, r, http.StatusOK, p)
+			// Refused.
+			return 0, false
+		} // end of the limit check
+		// Apply the rules.
+		n, problem := validateContext(r.PostFormValue("num_ctx"), minContext, f.Page.Max)
+		// A refusal.
+		if problem != "" {
+			// Show the settings page with the reason.
+			p := f.Page
+			// The reason and the typed text.
+			p.Kind, p.Problem, p.Typed = "settings", problem, typed
+			// Show it.
+			show(w, r, http.StatusOK, p)
+			// Refused.
+			return 0, false
+		} // end of the problem check
+		// Accepted.
+		return n, true
+	} // end of check
+	// settings is the first step: it shows the saved values and the form; it changes nothing.
+	settings := func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared form checks.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the form checks
+		// Run the model checks.
+		f, ok := facts(w, r, name)
+		// A page was already shown.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the model checks
+		// Show the form; the field starts with the saved value when there is one.
+		p := f.Page
+		// The kind of page.
+		p.Kind = "settings"
+		// Pre-fill the field with the saved value.
+		if f.Current > 0 {
+			// The number.
+			p.Typed = strconv.FormatInt(f.Current, 10)
+		} // end of the pre-fill
+		// Show it.
+		show(w, r, http.StatusOK, p)
+	} // end of settings
+	// review is the second step: it checks the typed value and asks "are you sure?"; it changes nothing.
+	review := func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared form checks.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the form checks
+		// Run the model checks.
+		f, ok := facts(w, r, name)
+		// A page was already shown.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the model checks
+		// Run the rules.
+		n, ok := check(w, r, f)
+		// A page was already shown.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the rule check
+		// The same value as now: nothing to do.
+		p := f.Page
+		// The size under review.
+		p.NewValue = n
+		// Nothing changes.
+		if f.Present && n == f.Current {
+			// Say so.
+			p.Kind = "nochange"
+			// Show it.
+			show(w, r, http.StatusOK, p)
+			// Stop here.
+			return
+		} // end of the same-value case
+		// Ask for the confirmation.
+		p.Kind = "review"
+		// Show it.
+		show(w, r, http.StatusOK, p)
+	} // end of review
+	// save is the third step: it checks everything again, saves, and then asks Ollama what is saved now.
+	save := func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared form checks.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the form checks
+		// Only one save at a time.
+		saveLock.Lock()
+		// Release at the end.
+		defer saveLock.Unlock()
+		// Run the model checks again: things may have changed since the review page.
+		f, ok := facts(w, r, name)
+		// A page was already shown.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the model checks
+		// Run the rules again.
+		n, ok := check(w, r, f)
+		// A page was already shown.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the rule check
+		// The page figures for the result pages.
+		p := f.Page
+		// The size being saved.
+		p.NewValue = n
+		// The same value as now: nothing to do (a second click on Yes ends up here).
+		if f.Present && n == f.Current {
+			// Say so.
+			p.Kind = "nochange"
+			// Show it.
+			show(w, r, http.StatusOK, p)
+			// Stop here.
+			return
+		} // end of the same-value case
+		// Save it inside the model.
+		status, text, err := createWithContext(r.Context(), addr.URL, name, n, gearTimeout)
+		// No answer at all.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return
+		} // end of the send check
+		// Ollama refused.
+		if status != http.StatusOK {
+			// The reason, with Ollama's own words when it gave any.
+			detail := fmt.Sprintf("Ollama refused the change (status %d).", status)
+			// Add its message.
+			if text != "" {
+				// Append it; the page escapes it.
+				detail += " Ollama said: " + text
+			} // end of the message
+			// Show it.
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: detail})
+			// Stop here.
+			return
+		} // end of the refusal check
+		// Do not trust the success alone: ask Ollama what is saved now.
+		after, status, err := fetchShow(r.Context(), addr.URL, name, gearTimeout)
+		// The check could not be done.
+		if err != nil || status != http.StatusOK {
+			// Say exactly what is known.
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: "Ollama accepted the change, but the check afterwards failed. Open the settings again to see what is saved."})
+			// Stop here.
+			return
+		} // end of the check read
+		// Read the saved values again.
+		afterLines := parseParams(after.Parameters)
+		// The saved context size now.
+		afterText, afterN, afterPresent := savedContext(afterLines)
+		// What Ollama reports, for the page.
+		p.AfterText = afterText
+		// The size must be the new one, and every other saved parameter must be exactly as before.
+		if !afterPresent || afterN != n || !sameStrings(otherParams(f.Lines), otherParams(afterLines)) {
+			// Say honestly that the result is not what was asked.
+			p.Kind = "mismatch"
+			// The detail.
+			p.Detail = "Ollama accepted the change, but what it reports now is not what was expected. Open the settings again and check the values."
+			// Show it.
+			show(w, r, http.StatusOK, p)
+			// Stop here.
+			return
+		} // end of the verify check
+		// Everything checked out.
+		p.Kind = "done"
+		// Show it.
+		show(w, r, http.StatusOK, p)
+	} // end of save
+	// Hand the three back.
+	return settings, review, save
+} // end of gearHandlers
diff --git a/gear_test.go b/gear_test.go
new file mode 100644
index 0000000..7581bd9
--- /dev/null
+++ b/gear_test.go
@@ -0,0 +1,972 @@
+// Package main tells Go that this test file belongs to the same program as gear.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// encoding/json reads the create request the fake receives.
+	"encoding/json"
+	// fmt builds text.
+	"fmt"
+	// io reads request bodies in the fake Ollama.
+	"io"
+	// net/http provides requests and status codes.
+	"net/http"
+	// net/url builds form data.
+	"net/url"
+	// regexp finds the token in the page.
+	"regexp"
+	// strings searches the page text.
+	"strings"
+	// sync protects the fake's records and runs the double-click test.
+	"sync"
+	// testing is Go's built-in test framework.
+	"testing"
+	// time makes the fake's create slow.
+	"time"
+) // end of imports
+
+// gearFake is a fake Ollama with two installed models and a saved-parameters text that /api/create changes like the real one did in the experiment (it replaces num_ctx and keeps every other line).
+type gearFake struct {
+	// mu protects every field below.
+	mu sync.Mutex
+	// params is the saved parameters text of every installed model (one shared text keeps the tests short).
+	params string
+	// modelInfo is the model_info JSON of every installed model.
+	modelInfo string
+	// loaded lists the names /api/ps reports.
+	loaded []string
+	// createStatus is the status /api/create answers (0 means 200).
+	createStatus int
+	// createMsg is the error text sent with a refusal.
+	createMsg string
+	// ignoreCreate makes /api/create answer 200 without changing anything.
+	ignoreCreate bool
+	// dropOthers makes /api/create answer 200 but also remove every other saved parameter.
+	dropOthers bool
+	// creates records every /api/create body.
+	creates []string
+	// calls records every other POST as "path body".
+	calls []string
+	// createDelay makes /api/create slow, with the fake's lock released meanwhile, so other requests can slip in (like real life).
+	createDelay time.Duration
+} // end of gearFake
+
+// newGearFake builds a fake whose model supports 131072 tokens and has one saved stop word.
+func newGearFake() *gearFake {
+	// The values.
+	return &gearFake{
+		// A stop word, formatted the way Ollama prints it (name, spaces, value).
+		params: "stop                           \"<end_of_turn>\"",
+		// The model's own facts: architecture and its limit, plus a long list that must not matter.
+		modelInfo: `{"general.architecture":"gemma3","gemma3.context_length":131072,"tokenizer.ggml.tokens":["a","b","c"]}`,
+	} // end of the values
+} // end of newGearFake
+
+// start runs the fake as a server and returns it.
+func (f *gearFake) start(t *testing.T) string {
+	// Mark this as a helper.
+	t.Helper()
+	// Start the server.
+	srv := fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
+		// One request at a time.
+		f.mu.Lock()
+		// Release when this request is done.
+		defer f.mu.Unlock()
+		// Read the body, if any.
+		b, _ := io.ReadAll(r.Body)
+		// Pick the reply by path.
+		switch r.URL.Path {
+		// The version check.
+		case "/api/version":
+			// A valid version.
+			w.Write([]byte(`{"version":"0.34.4"}`))
+		// The installed list: two models.
+		case "/api/tags":
+			// Two models.
+			w.Write([]byte(`{"models":[{"name":"alpha:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"embed:1b","size":2000000000,"details":{"family":"bert"},"capabilities":["embedding"]}]}`))
+		// The loaded list.
+		case "/api/ps":
+			// Build the list from the fake's state.
+			parts := []string{}
+			// Every loaded name.
+			for _, n := range f.loaded {
+				// One entry.
+				parts = append(parts, `{"name":"`+n+`","size":5,"expires_at":"2999-01-01T00:00:00Z"}`)
+			} // end of the loop
+			// Send the list.
+			w.Write([]byte(`{"models":[` + strings.Join(parts, ",") + `]}`))
+		// The details of one model.
+		case "/api/show":
+			// Read the name.
+			var req struct {
+				// Model is the asked name.
+				Model string `json:"model"`
+			} // end of the request shape
+			// Decode it.
+			_ = json.Unmarshal(b, &req)
+			// Only the two installed models are known.
+			if req.Model != "alpha:1b" && req.Model != "embed:1b" {
+				// Not found, like the real one.
+				w.WriteHeader(http.StatusNotFound)
+				// The error text.
+				w.Write([]byte(`{"error":"model not found"}`))
+				// Stop here.
+				return
+			} // end of the unknown check
+			// The reply, with the parameters as one string.
+			out, _ := json.Marshal(map[string]any{"parameters": f.params, "model_info": json.RawMessage(f.modelInfo)})
+			// Send it.
+			w.Write(out)
+		// The create request.
+		case "/api/create":
+			// Record it.
+			f.creates = append(f.creates, string(b))
+			// A slow create: let other requests in while it works.
+			if f.createDelay > 0 {
+				// Release the lock.
+				f.mu.Unlock()
+				// Work for a while.
+				time.Sleep(f.createDelay)
+				// Take the lock back, because the deferred unlock expects it.
+				f.mu.Lock()
+			} // end of the delay
+			// A refusal.
+			if f.createStatus != 0 {
+				// The status.
+				w.WriteHeader(f.createStatus)
+				// The error text.
+				w.Write([]byte(`{"error":` + fmt.Sprintf("%q", f.createMsg) + `}`))
+				// Stop here.
+				return
+			} // end of the refusal
+			// Accepted but without effect.
+			if f.ignoreCreate {
+				// Say success.
+				w.Write([]byte(`{"status":"success"}`))
+				// Stop here.
+				return
+			} // end of the ignore case
+			// Read the wanted size.
+			var req struct {
+				// Parameters holds the wanted values.
+				Parameters map[string]float64 `json:"parameters"`
+			} // end of the request shape
+			// Decode it.
+			_ = json.Unmarshal(b, &req)
+			// Keep the other lines (unless the test wants them dropped) and put the new size on top, like the real one did.
+			var lines []string
+			// The new size first.
+			lines = append(lines, fmt.Sprintf("num_ctx                        %d", int64(req.Parameters["num_ctx"])))
+			// Keep every other line.
+			if !f.dropOthers {
+				// Go through the old lines.
+				for _, l := range strings.Split(f.params, "\n") {
+					// Skip the old size line and blank lines.
+					if strings.TrimSpace(l) != "" && !strings.HasPrefix(strings.TrimSpace(l), "num_ctx") {
+						// Keep it.
+						lines = append(lines, l)
+					} // end of the skip check
+				} // end of the line loop
+			} // end of the keep case
+			// Store the new text.
+			f.params = strings.Join(lines, "\n")
+			// Say success.
+			w.Write([]byte(`{"status":"success"}`))
+		// Anything else is a load or unload request or unknown.
+		default:
+			// Record it.
+			f.calls = append(f.calls, r.URL.Path+" "+string(b))
+			// Accept.
+			w.Write([]byte(`{}`))
+		} // end of the switch
+	}) // end of the server
+	// Hand the address back.
+	return srv.URL
+} // end of start
+
+// createCount says how many create requests the fake has received.
+func (f *gearFake) createCount() int {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// The number.
+	return len(f.creates)
+} // end of createCount
+
+// setLoaded changes what /api/ps reports.
+func (f *gearFake) setLoaded(names ...string) {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// Store the list.
+	f.loaded = names
+} // end of setLoaded
+
+// gearRig builds a handler on top of the fake and finds the page token.
+func gearRig(t *testing.T, f *gearFake) themeRig {
+	// Mark this as a helper.
+	t.Helper()
+	// Start the fake.
+	h := handlerFor(t, f.start(t))
+	// Fetch the main page.
+	_, _, body := get(t, h, http.MethodGet, "/")
+	// Find the first hidden token field.
+	m := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)
+	// The page must carry a token.
+	if m == nil {
+		// Stop the test.
+		t.Fatalf("no token found in the page")
+	} // end of the token check
+	// Hand back the pair.
+	return themeRig{h: h, token: m[1]}
+} // end of gearRig
+
+// gearPost sends a form to one of the three settings routes as the page's own form would.
+func gearPost(t *testing.T, rig themeRig, path, model, size string) (int, string, http.Header) {
+	// Mark this as a helper.
+	t.Helper()
+	// Send it.
+	res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {model}, "num_ctx": {size}}, fromThisPage)
+	// Hand back status, body and headers.
+	return res.StatusCode, bodyOf(res), res.Header
+} // end of gearPost
+
+// TestParseParams checks the parameters text is split into names and values, the way Ollama prints it.
+func TestParseParams(t *testing.T) {
+	// The real format: the name, many spaces, the value; blank lines appear too.
+	got := parseParams("num_ctx                        8192\n\nstop                           \"<end_of_turn>\"\nstop   \"<eos>\"\n")
+	// The expected pairs.
+	want := []paramLine{{"num_ctx", "8192"}, {"stop", "\"<end_of_turn>\""}, {"stop", "\"<eos>\""}}
+	// Compare the length and each pair.
+	if len(got) != len(want) {
+		// Report the difference.
+		t.Fatalf("got %v", got)
+	} // end of the length check
+	// Go through the pairs.
+	for i := range want {
+		// A difference.
+		if got[i] != want[i] {
+			// Report it.
+			t.Errorf("pair %d = %v, want %v", i, got[i], want[i])
+		} // end of the compare
+	} // end of the loop
+	// An empty text gives nothing.
+	if n := len(parseParams("")); n != 0 {
+		// Report the problem.
+		t.Errorf("empty text gave %d pairs", n)
+	} // end of the empty check
+} // end of TestParseParams
+
+// TestSavedContext checks the saved size is read from every format Ollama was seen to print.
+func TestSavedContext(t *testing.T) {
+	// The cases: text, then the expected text, number and presence.
+	cases := []struct {
+		// name for the report.
+		name string
+		// in is the parameters text.
+		in string
+		// text is the expected value text.
+		text string
+		// n is the expected number.
+		n int64
+		// present is the expected presence.
+		present bool
+	}{
+		// Nothing saved.
+		{"none", "stop \"x\"", "", 0, false},
+		// A plain number.
+		{"plain", "num_ctx   8192", "8192", 8192, true},
+		// Ollama printed a big number like this in the experiment.
+		{"exponent", "num_ctx   1e+08", "1e+08", 100000000, true},
+		// Text instead of a number.
+		{"garbage", "num_ctx   lots", "lots", 0, true},
+		// A decimal is not a size.
+		{"decimal", "num_ctx   8192.5", "8192.5", 0, true},
+		// Zero is not a size.
+		{"zero", "num_ctx   0", "0", 0, true},
+		// The last line wins.
+		{"twice", "num_ctx 4096\nnum_ctx 8192", "8192", 8192, true},
+	} // end of the case table
+	// Go through the cases.
+	for _, c := range cases {
+		// Read it.
+		text, n, present := savedContext(parseParams(c.in))
+		// Compare.
+		if text != c.text || n != c.n || present != c.present {
+			// Report the difference.
+			t.Errorf("%s: got (%q, %d, %v), want (%q, %d, %v)", c.name, text, n, present, c.text, c.n, c.present)
+		} // end of the compare
+	} // end of the case loop
+} // end of TestSavedContext
+
+// TestModelMaxContext checks the model maximum is read from the architecture key, or from a single other key, and never guessed.
+func TestModelMaxContext(t *testing.T) {
+	// A helper that builds the map from JSON.
+	build := func(s string) map[string]json.RawMessage {
+		// Decode.
+		var m map[string]json.RawMessage
+		// A test bug if it fails.
+		if err := json.Unmarshal([]byte(s), &m); err != nil {
+			// Stop.
+			t.Fatalf("bad test json: %v", err)
+		} // end of the check
+		// Hand back.
+		return m
+	} // end of build
+	// The cases.
+	cases := []struct {
+		// name for the report.
+		name string
+		// in is the model_info JSON.
+		in string
+		// n is the expected number.
+		n int64
+		// ok is the expected success.
+		ok bool
+	}{
+		// The normal case.
+		{"architecture key", `{"general.architecture":"gemma3","gemma3.context_length":131072}`, 131072, true},
+		// No architecture, one key.
+		{"single key", `{"bert.context_length":512}`, 512, true},
+		// Two different keys and no architecture: do not guess.
+		{"two keys", `{"a.context_length":1000,"b.context_length":2000}`, 0, false},
+		// Nothing.
+		{"empty", `{}`, 0, false},
+		// Not a number.
+		{"text", `{"general.architecture":"x","x.context_length":"big"}`, 0, false},
+		// A decimal.
+		{"decimal", `{"general.architecture":"x","x.context_length":1.5}`, 0, false},
+		// Zero.
+		{"zero", `{"general.architecture":"x","x.context_length":0}`, 0, false},
+	} // end of the case table
+	// Go through the cases.
+	for _, c := range cases {
+		// Read it.
+		n, ok := modelMaxContext(build(c.in))
+		// Compare.
+		if n != c.n || ok != c.ok {
+			// Report the difference.
+			t.Errorf("%s: got (%d, %v), want (%d, %v)", c.name, n, ok, c.n, c.ok)
+		} // end of the compare
+	} // end of the case loop
+	// A missing map is the same as an empty one.
+	if _, ok := modelMaxContext(nil); ok {
+		// Report the problem.
+		t.Errorf("a missing model_info gave a maximum")
+	} // end of the nil check
+} // end of TestModelMaxContext
+
+// TestValidateContext checks every rule for the typed size, including the ones that keep a saved value from being emptied.
+func TestValidateContext(t *testing.T) {
+	// The cases: typed text and whether it is accepted.
+	cases := []struct {
+		// in is what was typed.
+		in string
+		// n is the expected number when accepted.
+		n int64
+		// ok says whether it is accepted.
+		ok bool
+	}{
+		// The smallest and the largest allowed values, and normal ones.
+		{"512", 512, true}, {"8192", 8192, true}, {"131072", 131072, true}, {"  8192  ", 8192, true}, {"0008192", 8192, true},
+		// Empty and blank: never allowed.
+		{"", 0, false}, {"   ", 0, false},
+		// Outside the range.
+		{"511", 0, false}, {"131073", 0, false}, {"0", 0, false},
+		// Not a plain whole number.
+		{"-8192", 0, false}, {"+8192", 0, false}, {"8192.0", 0, false}, {"8,192", 0, false}, {"1e4", 0, false}, {"0x2000", 0, false}, {"abc", 0, false}, {"８１９２", 0, false}, {"٨١٩٢", 0, false}, {"8 192", 0, false},
+		// Far too long.
+		{"99999999999999999999", 0, false}, {strings.Repeat("9", 400), 0, false},
+		// Markup.
+		{"<script>alert(1)</script>", 0, false},
+	} // end of the case table
+	// Go through the cases.
+	for _, c := range cases {
+		// Check it against a model that supports 131072.
+		n, problem := validateContext(c.in, minContext, 131072)
+		// Compare.
+		if (problem == "") != c.ok || n != c.n {
+			// Report the difference (the input is cut so a long one does not flood the report).
+			in := c.in
+			// Cut it.
+			if len(in) > 30 {
+				// Keep the start.
+				in = in[:30]
+			} // end of the cut
+			// Report.
+			t.Errorf("%q: got (%d, %q), want ok=%v n=%d", in, n, problem, c.ok, c.n)
+		} // end of the compare
+	} // end of the case loop
+} // end of TestValidateContext
+
+// TestContextPresets checks the suggestions stay inside the range, in order, and always include the maximum.
+func TestContextPresets(t *testing.T) {
+	// A model that supports 131072: the powers of two up to it.
+	got := contextPresets(512, 131072)
+	// The expected list.
+	want := []int64{2048, 4096, 8192, 16384, 32768, 65536, 131072}
+	// Compare.
+	if fmt.Sprint(got) != fmt.Sprint(want) {
+		// Report the difference.
+		t.Errorf("got %v, want %v", got, want)
+	} // end of the compare
+	// A model whose maximum is not a power of two: the maximum is added at the end.
+	got = contextPresets(512, 40960)
+	// The expected list.
+	want = []int64{2048, 4096, 8192, 16384, 32768, 40960}
+	// Compare.
+	if fmt.Sprint(got) != fmt.Sprint(want) {
+		// Report the difference.
+		t.Errorf("got %v, want %v", got, want)
+	} // end of the compare
+	// A small embedding model: only its maximum.
+	got = contextPresets(512, 512)
+	// Compare.
+	if fmt.Sprint(got) != "[512]" {
+		// Report the difference.
+		t.Errorf("got %v", got)
+	} // end of the compare
+} // end of TestContextPresets
+
+// TestGearShowsSettings checks the settings page: the facts, the form with its limits and suggestions, the help bubbles, no script, and nothing changed.
+func TestGearShowsSettings(t *testing.T) {
+	// A fake with no saved size.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Open the settings of the first model.
+	status, body, header := gearPost(t, rig, "/gear", "alpha:1b", "")
+	// It must load.
+	if status != http.StatusOK {
+		// Stop the test.
+		t.Fatalf("status %d", status)
+	} // end of the status check
+	// Everything the page must say.
+	for _, want := range []string{
+		// The heading names the model.
+		"Settings for <code>alpha:1b</code>",
+		// Nothing is saved yet.
+		"not saved in the model",
+		// The model's own limit.
+		"131072 tokens",
+		// The smallest allowed value.
+		"512 tokens",
+		// The other saved setting is shown, and escaped.
+		"stop &#34;&lt;end_of_turn&gt;&#34;",
+		// The form goes to the review step.
+		`action="/gear/review"`,
+		// The field has the limits and cannot be left empty.
+		`min="512" max="131072" step="1" required`,
+		// The suggestions.
+		`<option value="8192">`,
+		// The rule about removing.
+		"cannot be removed, only changed",
+		// The five help bubbles, each with the three standard parts.
+		`aria-describedby="tip-gear-ctx"`, `aria-describedby="tip-gear-max"`, `aria-describedby="tip-gear-min"`, `aria-describedby="tip-gear-saved"`, `aria-describedby="tip-gear-other"`,
+		"In plain words:", "Example:", "Helps you decide:",
+	} { // end of the list
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// No script and the strict policy.
+	if strings.Contains(body, "<script") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
+		// Report the problem.
+		t.Errorf("the settings page allows or contains a script")
+	} // end of the script check
+	// Opening the page changes nothing.
+	if f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("opening the page sent a create request")
+	} // end of the change check
+} // end of TestGearShowsSettings
+
+// TestGearPrefillsSavedValue checks the field starts with the saved size, so it is never blank.
+func TestGearPrefillsSavedValue(t *testing.T) {
+	// A fake with 4096 saved.
+	f := newGearFake()
+	// The saved text.
+	f.params = "num_ctx                        4096\n" + f.params
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Open the settings.
+	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
+	// The field value and the facts.
+	if !strings.Contains(body, `required value="4096"`) || !strings.Contains(body, "<td>4096</td>") {
+		// Report the gap.
+		t.Errorf("the saved value is not shown or pre-filled")
+	} // end of the check
+} // end of TestGearPrefillsSavedValue
+
+// TestGearRefusesLoadedModel checks a loaded model gets no form on any of the three steps, and nothing is saved.
+func TestGearRefusesLoadedModel(t *testing.T) {
+	// A fake with the model loaded.
+	f := newGearFake()
+	// Mark it loaded.
+	f.loaded = []string{"alpha:1b"}
+	// Build the rig.
+	rig := gearRig(t, f)
+	// All three steps.
+	for _, path := range []string{"/gear", "/gear/review", "/gear/save"} {
+		// Send a valid size.
+		status, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
+		// The page explains and offers no form.
+		if status != http.StatusOK || !strings.Contains(body, "Unload it first") || strings.Contains(body, `action="/gear/`) {
+			// Report the problem.
+			t.Errorf("%s: status %d, body %q", path, status, body)
+		} // end of the check
+	} // end of the loop
+	// Nothing was saved.
+	if f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("a loaded model was changed")
+	} // end of the change check
+} // end of TestGearRefusesLoadedModel
+
+// TestGearNotInstalled checks an unknown model name is refused politely and nothing is sent to Ollama.
+func TestGearNotInstalled(t *testing.T) {
+	// A fake.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// All three steps with a made-up name.
+	for _, path := range []string{"/gear", "/gear/review", "/gear/save"} {
+		// Send it.
+		_, body, _ := gearPost(t, rig, path, "ghost:1b", "8192")
+		// The page says so.
+		if !strings.Contains(body, "not installed") {
+			// Report the problem.
+			t.Errorf("%s: %q", path, body)
+		} // end of the check
+	} // end of the loop
+	// Nothing was saved.
+	if f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("an unknown model was changed")
+	} // end of the change check
+} // end of TestGearNotInstalled
+
+// TestGearRejectsBadValues checks every bad value is refused on the review step and on the save step, shown back escaped, and never reaches Ollama.
+func TestGearRejectsBadValues(t *testing.T) {
+	// A fake with 4096 saved, so "emptying" would mean losing something.
+	f := newGearFake()
+	// The saved text.
+	f.params = "num_ctx                        4096\n" + f.params
+	// Build the rig.
+	rig := gearRig(t, f)
+	// The bad values.
+	for _, bad := range []string{"", "   ", "abc", "-5", "0", "511", "131073", "8192.5", "1e5", "+8192", "８１９２", "99999999999999999999", "<script>alert(1)</script>"} {
+		// Both steps.
+		for _, path := range []string{"/gear/review", "/gear/save"} {
+			// Send it.
+			status, body, _ := gearPost(t, rig, path, "alpha:1b", bad)
+			// The settings page comes back with the reason, and no confirm button.
+			if status != http.StatusOK || !strings.Contains(body, "Not saved.") || strings.Contains(body, "Yes, save it into the model") {
+				// Report the problem.
+				t.Errorf("%s %q: status %d", path, bad, status)
+			} // end of the check
+			// An empty value gets its own, clear reason.
+			if strings.TrimSpace(bad) == "" && !strings.Contains(body, "cannot be empty") {
+				// Report the problem.
+				t.Errorf("%s %q: no 'cannot be empty' reason", path, bad)
+			} // end of the empty check
+			// Markup must come back escaped.
+			if strings.Contains(body, "<script>alert") {
+				// Report the problem.
+				t.Errorf("%s: unescaped markup in the page", path)
+			} // end of the escape check
+		} // end of the path loop
+	} // end of the value loop
+	// Nothing reached Ollama.
+	if f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("a bad value was sent to Ollama")
+	} // end of the change check
+	// The saved value is untouched.
+	if _, n, _ := savedContext(parseParams(f.params)); n != 4096 {
+		// Report the problem.
+		t.Errorf("the saved size changed to %d", n)
+	} // end of the saved check
+} // end of TestGearRejectsBadValues
+
+// TestGearReviewThenSave checks the two-step flow: the review changes nothing, the save sends exactly one precise create request and then verifies.
+func TestGearReviewThenSave(t *testing.T) {
+	// A fake with no saved size.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Step 2: review.
+	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "8192")
+	// The confirmation page with the values to be saved.
+	for _, want := range []string{"This changes the model itself", "not saved in the model", "<strong>8192</strong>", `action="/gear/save"`, `name="num_ctx" value="8192"`, "Yes, save it into the model", "Cancel, do not change"} {
+		// Look for it.
+		if status != http.StatusOK || !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("review page lacks %q (status %d)", want, status)
+		} // end of the check
+	} // end of the loop
+	// The review changed nothing.
+	if f.createCount() != 0 {
+		// Report the problem.
+		t.Fatalf("the review step sent a create request")
+	} // end of the review check
+	// Step 3: save.
+	status, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+	// The result page.
+	if status != http.StatusOK || !strings.Contains(body, "<strong>Saved.</strong>") || !strings.Contains(body, "8192") {
+		// Report the problem.
+		t.Errorf("save page: status %d, body %q", status, body)
+	} // end of the result check
+	// Exactly one create request, with exactly the expected body (keys are sorted by Go's JSON writer).
+	if len(f.creates) != 1 || f.creates[0] != `{"from":"alpha:1b","model":"alpha:1b","parameters":{"num_ctx":8192},"stream":false}` {
+		// Report the problem.
+		t.Errorf("create requests: %v", f.creates)
+	} // end of the create check
+	// The other saved parameter is still there.
+	if !strings.Contains(f.params, "end_of_turn") {
+		// Report the problem.
+		t.Errorf("the stop word was lost: %q", f.params)
+	} // end of the other-parameter check
+} // end of TestGearReviewThenSave
+
+// TestGearSameValueChangesNothing checks that saving the value that is already saved sends nothing (this is also what a second click on Yes does).
+func TestGearSameValueChangesNothing(t *testing.T) {
+	// A fake with 8192 saved.
+	f := newGearFake()
+	// The saved text.
+	f.params = "num_ctx                        8192\n" + f.params
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Both steps.
+	for _, path := range []string{"/gear/review", "/gear/save"} {
+		// Send the same value.
+		_, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
+		// The page says nothing changes.
+		if !strings.Contains(body, "Nothing to change") {
+			// Report the problem.
+			t.Errorf("%s: %q", path, body)
+		} // end of the check
+	} // end of the loop
+	// Nothing was sent.
+	if f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("an unchanged value was sent")
+	} // end of the change check
+} // end of TestGearSameValueChangesNothing
+
+// TestGearVerifiesTheResult checks that a create which Ollama accepts but does not apply, or applies while dropping other settings, is reported honestly.
+func TestGearVerifiesTheResult(t *testing.T) {
+	// Two ways Ollama can misbehave.
+	for _, mode := range []string{"ignore", "drop"} {
+		// A fake.
+		f := newGearFake()
+		// Pick the misbehaviour.
+		f.ignoreCreate, f.dropOthers = mode == "ignore", mode == "drop"
+		// Build the rig.
+		rig := gearRig(t, f)
+		// Save a size.
+		_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+		// The page must not claim success.
+		if strings.Contains(body, "<strong>Saved.</strong>") || !strings.Contains(body, "Please check") {
+			// Report the problem.
+			t.Errorf("%s: %q", mode, body)
+		} // end of the check
+	} // end of the loop
+} // end of TestGearVerifiesTheResult
+
+// TestGearCreateRefused checks Ollama's refusal is shown in plain words, escaped.
+func TestGearCreateRefused(t *testing.T) {
+	// A fake that refuses.
+	f := newGearFake()
+	// The refusal.
+	f.createStatus, f.createMsg = http.StatusInternalServerError, "disk <full>"
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Save a size.
+	status, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+	// The page says what happened.
+	if status != http.StatusBadGateway || !strings.Contains(body, "status 500") || !strings.Contains(body, "disk &lt;full&gt;") || strings.Contains(body, "<strong>Saved.</strong>") {
+		// Report the problem.
+		t.Errorf("status %d, body %q", status, body)
+	} // end of the check
+} // end of TestGearCreateRefused
+
+// TestGearModelLoadedBetweenReviewAndSave checks the save step looks again: a model that was loaded in the meantime is not changed.
+func TestGearModelLoadedBetweenReviewAndSave(t *testing.T) {
+	// A fake.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// The review step is fine.
+	if _, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "8192"); !strings.Contains(body, "Yes, save it into the model") {
+		// Stop the test.
+		t.Fatalf("no review page")
+	} // end of the review check
+	// Someone loads the model now.
+	f.setLoaded("alpha:1b")
+	// The save step.
+	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+	// It must refuse.
+	if !strings.Contains(body, "Unload it first") || f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("a model loaded in the meantime was changed")
+	} // end of the check
+} // end of TestGearModelLoadedBetweenReviewAndSave
+
+// TestGearUnknownMaximum checks that without a known model maximum nothing can be saved, on any step.
+func TestGearUnknownMaximum(t *testing.T) {
+	// A fake whose model reports no limit.
+	f := newGearFake()
+	// No model facts.
+	f.modelInfo = `{}`
+	// Build the rig.
+	rig := gearRig(t, f)
+	// The settings page has no form.
+	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
+	// Check it.
+	if strings.Contains(body, `action="/gear/review"`) || !strings.Contains(body, "does not report this model's maximum") {
+		// Report the problem.
+		t.Errorf("settings page: %q", body)
+	} // end of the check
+	// The other two steps refuse.
+	for _, path := range []string{"/gear/review", "/gear/save"} {
+		// Send a size.
+		_, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
+		// It must refuse.
+		if !strings.Contains(body, "Not saved.") {
+			// Report the problem.
+			t.Errorf("%s: %q", path, body)
+		} // end of the check
+	} // end of the loop
+	// Nothing was sent.
+	if f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("a model without a known limit was changed")
+	} // end of the change check
+} // end of TestGearUnknownMaximum
+
+// TestGearSavedAboveMaximum checks a saved size above the model's limit is pointed out and can be fixed by saving a valid one.
+func TestGearSavedAboveMaximum(t *testing.T) {
+	// A fake with a size far above the limit saved (the experiment showed Ollama accepts such a value).
+	f := newGearFake()
+	// The saved text, in the form Ollama printed.
+	f.params = "num_ctx                        1e+08\n" + f.params
+	// Build the rig.
+	rig := gearRig(t, f)
+	// The settings page.
+	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
+	// It warns, and the field is not pre-filled with a value that would be refused.
+	if !strings.Contains(body, "above what this model supports") {
+		// Report the problem.
+		t.Errorf("no warning in %q", body)
+	} // end of the warning check
+	// Saving a valid size works.
+	_, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+	// The result.
+	if !strings.Contains(body, "<strong>Saved.</strong>") {
+		// Report the problem.
+		t.Errorf("fixing the value failed: %q", body)
+	} // end of the result check
+} // end of TestGearSavedAboveMaximum
+
+// TestGearSecurity checks the three routes need a POST from this page with the right token, like every other changing route.
+func TestGearSecurity(t *testing.T) {
+	// A fake.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Go through the routes.
+	for _, path := range []string{"/gear", "/gear/review", "/gear/save"} {
+		// A GET is not allowed.
+		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
+			// Report the problem.
+			t.Errorf("GET %s = %d", path, status)
+		} // end of the GET check
+		// A POST from another site is refused.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+			// Report the problem.
+			t.Errorf("cross-site %s = %d", path, res.StatusCode)
+		} // end of the origin check
+		// A POST without any browser header is refused.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, nil); res.StatusCode != http.StatusForbidden {
+			// Report the problem.
+			t.Errorf("headerless %s = %d", path, res.StatusCode)
+		} // end of the headerless check
+		// A POST with a wrong token is refused.
+		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+			// Report the problem.
+			t.Errorf("wrong token %s = %d", path, res.StatusCode)
+		} // end of the token check
+		// A POST without a model name is refused.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "num_ctx": {"8192"}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
+			// Report the problem.
+			t.Errorf("no model %s = %d", path, res.StatusCode)
+		} // end of the model check
+	} // end of the route loop
+	// Nothing was changed by any of it.
+	if f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("a refused request changed the model")
+	} // end of the change check
+} // end of TestGearSecurity
+
+// TestGearDoubleClickSavesOnce checks that many simultaneous saves of the same value send only one create request.
+func TestGearDoubleClickSavesOnce(t *testing.T) {
+	// A fake whose create is slow, so the clicks really overlap.
+	f := newGearFake()
+	// A slow create.
+	f.createDelay = 40 * time.Millisecond
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Ten clicks at the same moment.
+	var wg sync.WaitGroup
+	// Start them.
+	for i := 0; i < 10; i++ {
+		// Count one.
+		wg.Add(1)
+		// Send it in its own goroutine.
+		go func() {
+			// Count it done at the end.
+			defer wg.Done()
+			// The same save.
+			gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+		}() // end of the goroutine
+	} // end of the start loop
+	// Wait for all of them.
+	wg.Wait()
+	// Exactly one create request.
+	if n := f.createCount(); n != 1 {
+		// Report the problem.
+		t.Errorf("%d create requests, want 1", n)
+	} // end of the count check
+} // end of TestGearDoubleClickSavesOnce
+
+// TestMainPageGearOnlyForNotLoaded checks the gear appears before the state words of a model that is not loaded, and an empty slot of the same width stands in for a loaded one.
+func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
+	// A fake with one model loaded.
+	f := newGearFake()
+	// Mark it loaded.
+	f.loaded = []string{"alpha:1b"}
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Fetch the page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// The not-loaded model has a gear form with an accessible name.
+	for _, want := range []string{`action="/gear"`, `aria-label="Settings for embed:1b"`, `class="gear"`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The loaded model has none, and only one gear form exists.
+	if strings.Contains(body, `aria-label="Settings for alpha:1b"`) || strings.Count(body, `action="/gear"`) != 1 {
+		// Report the problem.
+		t.Errorf("a loaded model has a gear")
+	} // end of the loaded check
+	// The loaded row has the empty slot.
+	if strings.Count(body, `class="gearslot"`) != 1 {
+		// Report the problem.
+		t.Errorf("the loaded row has no empty gear slot")
+	} // end of the slot check
+	// The gear comes before the state words in its cell.
+	if i, j := strings.Index(body, `class="gearform"`), strings.Index(body, `class="statelabel"`); !(i >= 0 && j >= 0 && i < strings.LastIndex(body, `class="statelabel"`)) {
+		// Report the problem.
+		t.Errorf("gear position: %d %d", i, j)
+	} // end of the order check
+	// The hint line explains the gear.
+	if !strings.Contains(body, "appears only for models that are not loaded") {
+		// Report the problem.
+		t.Errorf("no hint about the gear")
+	} // end of the hint check
+} // end of TestMainPageGearOnlyForNotLoaded
+
+// TestKeepAliveChoiceOnLoadPage checks the load page offers the fixed list with its help bubble, and the choice reaches Ollama exactly as chosen.
+func TestKeepAliveChoiceOnLoadPage(t *testing.T) {
+	// The cases: the form value, the fragment that must appear in the generate request (empty means no keep_alive at all).
+	cases := []struct {
+		// choice is the form value.
+		choice string
+		// want is the expected fragment.
+		want string
+	}{
+		// Ollama's default: nothing is sent.
+		{"", ""},
+		// A time.
+		{"1h", `"keep_alive":"1h"`},
+		// Never unload: a negative number, not text.
+		{"-1", `"keep_alive":-1`},
+	} // end of the case table
+	// Go through the cases.
+	for _, c := range cases {
+		// A fake with nothing loaded.
+		f := &loadFake{}
+		// Build the rig.
+		rig := loadRig(t, f, 16e9)
+		// The warning page has the drop-down and its bubble.
+		res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+		// Read it.
+		page := bodyOf(res)
+		// The parts.
+		for _, want := range []string{`name="keep" form="loadform"`, `<option value="">Ollama&#39;s default (5 minutes)</option>`, `<option value="-1">Until I unload it`, `aria-describedby="tip-keep"`, ">Keep-alive time<"} {
+			// Look for it.
+			if !strings.Contains(page, want) {
+				// Report the gap.
+				t.Errorf("load page lacks %q", want)
+			} // end of the check
+		} // end of the loop
+		// Confirm with the choice.
+		res = post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "keep": {c.choice}}, fromThisPage)
+		// It must work.
+		if res.StatusCode != http.StatusOK {
+			// Report the problem.
+			t.Errorf("choice %q: status %d", c.choice, res.StatusCode)
+		} // end of the status check
+		// One request, with or without the keep-alive.
+		if len(f.calls) != 1 || (c.want == "") == strings.Contains(f.calls[0], "keep_alive") || !strings.Contains(f.calls[0], c.want) {
+			// Report the problem.
+			t.Errorf("choice %q: requests %v", c.choice, f.calls)
+		} // end of the request check
+	} // end of the case loop
+} // end of TestKeepAliveChoiceOnLoadPage
+
+// TestKeepAliveRejectsOtherValues checks anything outside the fixed list is refused before any model is touched.
+func TestKeepAliveRejectsOtherValues(t *testing.T) {
+	// A fake with nothing loaded.
+	f := &loadFake{}
+	// Build the rig.
+	rig := loadRig(t, f, 16e9)
+	// Values that are not in the list.
+	for _, bad := range []string{"abc", "0", "1", "5M", "99h", "-2", " 5m", "5m ", "forever", "1e3", "<b>"} {
+		// Confirm with it.
+		res := post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "keep": {bad}}, fromThisPage)
+		// It must be refused.
+		if res.StatusCode != http.StatusBadRequest {
+			// Report the problem.
+			t.Errorf("keep %q: status %d", bad, res.StatusCode)
+		} // end of the status check
+	} // end of the loop
+	// Nothing was sent to Ollama.
+	if f.callCount() != 0 {
+		// Report the problem.
+		t.Errorf("a refused choice reached Ollama")
+	} // end of the request check
+} // end of TestKeepAliveRejectsOtherValues
+
+// TestKeepAliveReachesEmbeddingFallback checks the choice is also sent when the model has to be loaded through the embedding request.
+func TestKeepAliveReachesEmbeddingFallback(t *testing.T) {
+	// A fake whose generate refuses, like an embedding model.
+	f := &loadFake{generateStatus: http.StatusBadRequest}
+	// Build the rig.
+	rig := loadRig(t, f, 16e9)
+	// Confirm with a choice.
+	post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"embed:1b"}, "keep": {"30m"}}, fromThisPage)
+	// Two requests, and the second is the embedding one with the choice.
+	if len(f.calls) != 2 || !strings.HasPrefix(f.calls[1], "/api/embed ") || !strings.Contains(f.calls[1], `"keep_alive":"30m"`) {
+		// Report the problem.
+		t.Errorf("requests: %v", f.calls)
+	} // end of the check
+} // end of TestKeepAliveReachesEmbeddingFallback
diff --git a/load.go b/load.go
index 20a89a3..518a5b6 100644
--- a/load.go
+++ b/load.go
@@ -39,10 +39,75 @@ const defaultKeepText = "5 minutes"
 // tightFactor decides when free memory counts as "close": less than this many times the model's size.
 const tightFactor = 1.25
 
+// keepChoice is one entry of the "stay loaded for" list on the load page.
+type keepChoice struct {
+	// Value is what the form sends; an empty value means "use Ollama's own default".
+	Value string
+	// Label is what the person reads.
+	Label string
+} // end of keepChoice
+
+// keepChoices is the fixed list the load page offers; nothing outside it is ever sent to Ollama.
+var keepChoices = []keepChoice{
+	// Ollama's own default time.
+	{"", "Ollama's default (" + defaultKeepText + ")"},
+	// Five minutes.
+	{"5m", "5 minutes"},
+	// Half an hour.
+	{"30m", "30 minutes"},
+	// One hour.
+	{"1h", "1 hour"},
+	// One day.
+	{"24h", "24 hours"},
+	// Never unload by itself: Ollama takes a negative number for this.
+	{"-1", "Until I unload it (never unloads by itself)"},
+} // end of keepChoices
+
+// keepAliveValue turns the form's choice into the value sent to Ollama: nil means "send nothing", and ok is false for a choice that is not in the list.
+func keepAliveValue(choice string) (value any, ok bool) {
+	// Go through the fixed list.
+	for _, c := range keepChoices {
+		// Only an exact match counts.
+		if c.Value != choice {
+			// Next choice.
+			continue
+		} // end of the match check
+		// The default: send nothing.
+		if choice == "" {
+			// No keep-alive field.
+			return nil, true
+		} // end of the default case
+		// Never unload: a negative number.
+		if choice == "-1" {
+			// The number.
+			return -1, true
+		} // end of the forever case
+		// A time such as 5m.
+		return choice, true
+	} // end of the loop
+	// Not in the list.
+	return nil, false
+} // end of keepAliveValue
+
 // loadModel asks Ollama to load one model now, without a prompt and without a keep-alive setting, so Ollama's own default time applies; it returns which request worked.
 func loadModel(ctx context.Context, base *url.URL, name string, timeout time.Duration) (string, error) {
+	// No keep-alive field.
+	return loadModelKeep(ctx, base, name, nil, timeout)
+} // end of loadModel
+
+// loadModelKeep is loadModel with an optional keep-alive value (nil means none); it returns which request worked.
+func loadModelKeep(ctx context.Context, base *url.URL, name string, keep any, timeout time.Duration) (string, error) {
+	// The body of the generate request.
+	body := map[string]any{"model": name}
+	// The same for the embedding fallback, which also needs some input.
+	embedBody := map[string]any{"model": name, "input": "load"}
+	// Add the keep-alive value when there is one.
+	if keep != nil {
+		// To both bodies.
+		body["keep_alive"], embedBody["keep_alive"] = keep, keep
+	} // end of the keep-alive case
 	// Chat and text models are loaded through /api/generate with no prompt (the documented way to preload).
-	status, err := postJSON(ctx, base, "api/generate", timeout, map[string]any{"model": name})
+	status, err := postJSON(ctx, base, "api/generate", timeout, body)
 	// No answer at all.
 	if err != nil {
 		// Pass the safe error on.
@@ -56,7 +121,7 @@ func loadModel(ctx context.Context, base *url.URL, name string, timeout time.Dur
 	// Status 400 is what a model that cannot generate text (an embedding model, for example) answers; try the embedding request instead.
 	if status == http.StatusBadRequest {
 		// The one-word input is only there because an embedding request needs some input.
-		status2, err2 := postJSON(ctx, base, "api/embed", timeout, map[string]any{"model": name, "input": "load"})
+		status2, err2 := postJSON(ctx, base, "api/embed", timeout, embedBody)
 		// No answer at all.
 		if err2 != nil {
 			// Pass the safe error on.
@@ -139,6 +204,10 @@ type loadPage struct {
 	Level string
 	// DefaultText is the default time the model stays loaded.
 	DefaultText string
+	// KeepOptions is the list of "stay loaded for" choices.
+	KeepOptions []keepChoice
+	// KeepTip is the help bubble of the keep-alive heading.
+	KeepTip tipView
 	// Remaining is the time left before Ollama unloads the model by itself (done page).
 	Remaining string
 	// Seconds is the same time in seconds, for the ticking timer; 0 means no ticking timer.
@@ -188,11 +257,15 @@ func memoryFacts(u *url.URL, need int64) (avail, note, level string) {
 // loadHandlers builds the two handlers: the first shows the memory warning (it changes nothing), the second does the load.
 func loadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc) {
 	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
-	page := template.Must(template.New("load").Parse(loadTemplateText))
+	page := template.Must(template.New("load").Parse(loadTemplateText + tipsTemplateText))
+	// The help bubble of the keep-alive heading never changes, so build it once.
+	keepTip := makeTip("tip-keep", "Keep-alive time")
 	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
 	show := func(w http.ResponseWriter, r *http.Request, status int, data loadPage) {
 		// Add what every version of the page needs.
 		data.Theme, data.Token, data.DefaultText = themeFromRequest(r), token, defaultKeepText
+		// The choices and the bubble for the keep-alive row.
+		data.KeepOptions, data.KeepTip = keepChoices, keepTip
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
@@ -287,13 +360,22 @@ func loadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Hand
 			// Stop here.
 			return
 		} // end of the form checks
+		// Only a choice from the fixed list is accepted; a missing choice means Ollama's default.
+		keep, keepOK := keepAliveValue(r.PostFormValue("keep"))
+		// Anything else is refused before any model is touched.
+		if !keepOK {
+			// Refuse.
+			http.Error(w, "bad keep-alive choice", http.StatusBadRequest)
+			// Stop here.
+			return
+		} // end of the keep-alive check
 		// Run the model checks again: things may have changed since the warning page.
 		if _, ok := check(w, r, name); !ok {
 			// A page was already shown.
 			return
 		} // end of the model checks
 		// Ask Ollama to load it; this call returns when loading is finished, which can take a while.
-		if _, err := loadModel(r.Context(), addr.URL, name, loadTimeout); err != nil {
+		if _, err := loadModelKeep(r.Context(), addr.URL, name, keep, loadTimeout); err != nil {
 			// Show the plain reason.
 			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
 			// Stop here.
diff --git a/load_test.go b/load_test.go
index 3934197..e68695f 100644
--- a/load_test.go
+++ b/load_test.go
@@ -89,8 +89,8 @@ func (f *loadFake) start(t *testing.T) *httptest.Server {
 				// Stop here.
 				return
 			} // end of the refusal
-			// A request without keep_alive loads; the model name is between the quotes after "model":.
-			if !f.ignore && !strings.Contains(string(b), "keep_alive") {
+			// Every request except a keep_alive of 0 loads; the model name is between the quotes after "model":.
+			if !f.ignore && !strings.Contains(string(b), `"keep_alive":0`) {
 				// Take the name out of the body.
 				name := regexp.MustCompile(`"model":"([^"]*)"`).FindStringSubmatch(string(b))[1]
 				// Add it to the loaded list.
diff --git a/loading_test.go b/loading_test.go
index ca738f9..f5e8b40 100644
--- a/loading_test.go
+++ b/loading_test.go
@@ -25,7 +25,7 @@ func TestLoadWarningHasWaitingBox(t *testing.T) {
 	// Read the page.
 	body := bodyOf(res)
 	// Every part the script needs, and the honest wording.
-	for _, want := range []string{`<form method="post" action="/load/confirm" data-loading>`, `id="choices"`, `id="loading" role="status" aria-live="polite" hidden`, `class="elapsed"`, `<script src="/loading.js" defer></script>`, "not a percentage"} {
+	for _, want := range []string{`<form id="loadform" method="post" action="/load/confirm" data-loading>`, `id="choices"`, `id="loading" role="status" aria-live="polite" hidden`, `class="elapsed"`, `<script src="/loading.js" defer></script>`, "not a percentage"} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the problem.
diff --git a/tableview.go b/tableview.go
index bfd7781..684f771 100644
--- a/tableview.go
+++ b/tableview.go
@@ -12,6 +12,8 @@ import ( // import lists the standard-library packages this file uses.
 
 // tipView is one help bubble as the page template needs it.
 type tipView struct {
+	// Title is the heading text the bubble belongs to (used where the heading is drawn from the bubble data).
+	Title string
 	// ID is the element name that the heading points at with aria-describedby (so screen readers read the bubble too).
 	ID string
 	// Plain, Example, Decide and AlsoKnown are the four parts from tooltips.go.
@@ -71,7 +73,7 @@ func makeTip(id, heading string) tipView {
 	// A heading without a text gives empty parts; a test makes sure that never happens.
 	t, _ := helpFor(heading)
 	// Build the view.
-	return tipView{ID: id, Plain: t.Plain, Example: t.Example, Decide: t.Decide, AlsoKnown: t.AlsoKnown}
+	return tipView{Title: heading, ID: id, Plain: t.Plain, Example: t.Example, Decide: t.Decide, AlsoKnown: t.AlsoKnown}
 } // end of makeTip
 
 // countText says "1 model" or "N models".
diff --git a/tooltips.go b/tooltips.go
index 0b7e2b6..aeafde8 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -19,6 +19,9 @@ var installedColumns = []string{"Model", "State", "Size on disk", "Family", "Par
 // loadedColumns are the five column titles of the Loaded table, in order; a test checks they match render.go.
 var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Loaded context length", "Time until unload"}
 
+// gearHeadings are the headings on the settings page and the Load page that have a help bubble, in the order they appear; a test checks each has a text.
+var gearHeadings = []string{"Context size", "Model maximum", "Smallest allowed", "Saved in the model", "Other saved settings", "Keep-alive time"}
+
 // helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
 // The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
 var helpTexts = map[string]tooltip{
@@ -190,6 +193,60 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Check the model's own page to see what it does.",
 	}, // end of the catch-all category
+	// The context size setting.
+	"Context size": {
+		// What it means.
+		Plain: "How much text the model keeps in mind at once, counted in tokens (word pieces). Bigger needs more memory.",
+		// A real case, measured on the machine this project was built on.
+		Example: "medgemma:latest used 3.8 GB (gigabytes) at 131072 and 3.0 GB (gigabytes) at 8192.",
+		// What it helps with.
+		Decide: "How much memory to spend against how long a text it can handle.",
+	}, // end of Context size
+	// The model's own limit.
+	"Model maximum": {
+		// What it means.
+		Plain: "The largest context size this model was built for. This page refuses anything above it.",
+		// A real case.
+		Example: "medgemma:latest: 131072. qwen3.6:27b: 262144.",
+		// What it helps with.
+		Decide: "The top of the range you can choose.",
+	}, // end of Model maximum
+	// This monitor's own lowest value.
+	"Smallest allowed": {
+		// What it means.
+		Plain: "The lowest context size this monitor lets you save. Ollama itself sets no lowest value.",
+		// A real case.
+		Example: "512. Ollama accepted a size of 1 in a test, which would make the model unusable.",
+		// What it helps with.
+		Decide: "It stops a value that would break the model.",
+	}, // end of Smallest allowed
+	// What is stored in the model.
+	"Saved in the model": {
+		// What it means.
+		Plain: "Settings stored inside the model in Ollama. Programs that do not send their own value use them.",
+		// A real case.
+		Example: "After saving 8192, the next load of the model starts at 8192.",
+		// What it helps with.
+		Decide: "What every program gets when it loads this model.",
+	}, // end of Saved in the model
+	// The other stored settings.
+	"Other saved settings": {
+		// What it means.
+		Plain: "Other settings stored in the model, such as stop words. They are shown here and kept as they are.",
+		// A real case.
+		Example: "medgemma:latest has the stop word end_of_turn.",
+		// What it helps with.
+		Decide: "What the model already does before you change anything.",
+	}, // end of Other saved settings
+	// The keep-alive time on the Load page.
+	"Keep-alive time": {
+		// What it means.
+		Plain: "How long the model stays in memory after its last use, before Ollama unloads it by itself.",
+		// A real case.
+		Example: "5 minutes is Ollama's default. Never unload keeps it until you press Unload.",
+		// What it helps with.
+		Decide: "Fast answers against memory kept free for other work.",
+	}, // end of Keep-alive time
 } // end of helpTexts
 
 // helpFor returns the tooltip for a heading, and false when there is none.
diff --git a/tooltips_test.go b/tooltips_test.go
index 61abe48..416858e 100644
--- a/tooltips_test.go
+++ b/tooltips_test.go
@@ -12,7 +12,7 @@ import ( // import lists the packages this test file uses.
 	"unicode/utf8"
 ) // end of imports
 
-// allHeadings lists every heading that must have a tooltip: both tables' columns plus the four categories, without repeats.
+// allHeadings lists every heading that must have a tooltip: both tables' columns, the settings headings and the four categories, without repeats.
 func allHeadings() []string {
 	// Remember which headings were added already.
 	seen := map[string]bool{}
@@ -28,6 +28,8 @@ func allHeadings() []string {
 			out = append(out, h)
 		} // end of the repeat check
 	} // end of the column loop
+	// Then the headings of the settings page and the Load page.
+	out = append(out, gearHeadings...)
 	// Then the four categories, by their display names.
 	for c := categoryEmbedding; c <= categoryUnclassified; c++ {
 		// Add the category's heading text.
diff --git a/web.go b/web.go
index 84defba..5f8025a 100644
--- a/web.go
+++ b/web.go
@@ -96,6 +96,14 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /load", loadAsk)
 	// Route: a POST request for "/load/confirm" loads the model.
 	mux.HandleFunc("POST /load/confirm", loadConfirm)
+	// Make the three settings handlers: the settings page, the review step and the save (the checks are in gear.go).
+	gearShow, gearReview, gearSave := gearHandlers(addr, token)
+	// Route: a POST request for "/gear" shows a model's settings and changes nothing.
+	mux.HandleFunc("POST /gear", gearShow)
+	// Route: a POST request for "/gear/review" checks the typed size and asks for confirmation.
+	mux.HandleFunc("POST /gear/review", gearReview)
+	// Route: a POST request for "/gear/save" saves the size inside the model.
+	mux.HandleFunc("POST /gear/save", gearSave)
 	// Route: a GET request for "/countdown.js" sends the small script that makes the timers tick (only the message pages use it).
 	mux.HandleFunc("GET /countdown.js", countdownHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
diff --git a/web/app.css b/web/app.css
index 2a44970..eebfc42 100644
--- a/web/app.css
+++ b/web/app.css
@@ -749,8 +749,8 @@ h2 {
   display: block;
   /* A little air above it, not more. */
   margin-top: 0.1rem;
-  /* Start under the dot of the state words. */
-  margin-left: 0;
+  /* Start under the dot of the state words: the gear slot plus the space after it. */
+  margin-left: calc(1.6rem + 0.3rem);
 } /* end of rule */
 
 /* The unload timer itself: italic, in the same font and size as the text around it. */
@@ -773,6 +773,68 @@ h2 {
   content: "]";
 } /* end of rule */
 
+/* The gear form and the empty slot that replaces it on a loaded row; both have the same width, so the state words stay in line. */
+.gearform, .gearslot {
+  /* A box in the line, so it can have a width. */
+  display: inline-block;
+  /* The same width for both. */
+  width: 1.6rem;
+  /* No outer space. */
+  margin: 0;
+} /* end of rule */
+
+/* The gear button: plain, so it does not compete with Load and Unload. */
+.gear {
+  /* Use the page font. */
+  font: inherit;
+  /* No frame and no fill. */
+  border: 0;
+  /* No fill. */
+  background: none;
+  /* A little room to click on. */
+  padding: 0 0.2rem;
+  /* The secondary colour until it is pointed at. */
+  color: var(--muted);
+  /* A hand cursor. */
+  cursor: pointer;
+} /* end of rule */
+
+/* Pointed at or focused: the normal text colour. */
+.gear:hover, .gear:focus-visible {
+  /* Stronger colour. */
+  color: var(--text);
+} /* end of rule */
+
+/* A clear ring for keyboard users. */
+.gear:focus-visible {
+  /* A ring around the gear. */
+  outline: 3px solid var(--text);
+  /* A gap between gear and ring. */
+  outline-offset: 2px;
+} /* end of rule */
+
+/* The number field and the drop-down of the settings and Load pages. */
+.numfield, .keepselect {
+  /* Use the page font. */
+  font: inherit;
+  /* Room inside. */
+  padding: 0.3rem 0.5rem;
+  /* A solid outline, visible without colour. */
+  border: 2px solid var(--border);
+  /* Slightly rounded corners. */
+  border-radius: 0.4rem;
+  /* Colours from the variables, so both themes work. */
+  background: var(--panel);
+  /* Text colour. */
+  color: var(--text);
+} /* end of rule */
+
+/* The number field is only as wide as a big number needs. */
+.numfield {
+  /* Wide enough for 7 digits. */
+  width: 9rem;
+} /* end of rule */
+
 /* The hidden attribute must always win over any display rule. */
 [hidden] {
   /* Not drawn at all. */
diff --git a/web/gear.html b/web/gear.html
new file mode 100644
index 0000000..13600de
--- /dev/null
+++ b/web/gear.html
@@ -0,0 +1,165 @@
+{{/* Settings page template: one page with several versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Model settings - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* A panel that holds the message. */}}
+<section class="panel">
+{{/* The heading names the model, so there is no doubt which one is meant. */}}
+<h1>Settings for <code>{{.Model}}</code></h1>
+{{/* Version 1: the settings and the form. */}}
+{{if eq .Kind "settings"}}
+{{/* A refused value is explained first, with a symbol and a bold lead, so colour is never the only signal. */}}
+{{if .Problem}}
+{{/* The reason. */}}
+<p class="warn" role="alert"><strong>⚠ Not saved.</strong> {{.Problem}}</p>
+{{/* End of the problem note. */}}
+{{end}}
+{{/* A saved value above the model's limit is pointed out. */}}
+{{if .AboveMax}}
+{{/* The note. */}}
+<p class="warn"><strong>⚠ The saved size is above what this model supports.</strong> Saving a valid size below fixes it.</p>
+{{/* End of the above-limit note. */}}
+{{end}}
+{{/* What these settings are. */}}
+<p class="muted">{{template "tipbox" .Tips.saved}}: these settings are stored inside the model in Ollama, so every program that loads it without a value of its own uses them. The model must not be loaded now.</p>
+{{/* The facts, each heading with its help bubble. */}}
+<table class="facts">
+{{/* Row 1: the saved context size. */}}
+<tr><th scope="row">{{template "tipbox" .Tips.ctx}}</th><td>{{.SavedText}}</td></tr>
+{{/* Row 2: the model maximum. */}}
+<tr><th scope="row">{{template "tipbox" .Tips.max}}</th><td>{{if .Max}}{{.Max}} tokens (word pieces){{else}}not reported{{end}}</td></tr>
+{{/* Row 3: the smallest size allowed. */}}
+<tr><th scope="row">{{template "tipbox" .Tips.min}}</th><td>{{.Min}} tokens (word pieces); this is this monitor's own limit</td></tr>
+{{/* Row 4: the other saved settings. */}}
+<tr><th scope="row">{{template "tipbox" .Tips.other}}</th><td>{{if .Others}}{{range $i, $o := .Others}}{{if $i}}, {{end}}<code>{{$o}}</code>{{end}}{{else}}none{{end}}. They are kept as they are.</td></tr>
+{{/* End of the facts. */}}
+</table>
+{{/* The form, only when a safe limit is known. */}}
+{{if .CanSave}}
+{{/* The form goes to the review step, which changes nothing yet. */}}
+<form method="post" action="/gear/review">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Model}}">
+{{/* The label and the number field; the browser also checks the range, and the monitor checks it again. */}}
+<p><label for="num_ctx">New context size (tokens):</label> <input class="numfield" id="num_ctx" name="num_ctx" type="number" inputmode="numeric" min="{{.Min}}" max="{{.Max}}" step="1" required value="{{.Typed}}" list="presets"></p>
+{{/* The suggestions; they appear when the field is clicked. */}}
+<datalist id="presets">{{range .Presets}}<option value="{{.}}"></option>{{end}}</datalist>
+{{/* The rules in plain words. */}}
+<p class="muted">Click the field to see suggestions. A saved size cannot be removed, only changed. To go back to the largest size, choose the model maximum.</p>
+{{/* The button. */}}
+<p><button type="submit" class="btn-load">Review the change</button></p>
+{{/* End of the form. */}}
+</form>
+{{/* No safe limit is known: no form. */}}
+{{else}}
+{{/* Say why. */}}
+<p class="muted">Nothing can be saved here because Ollama does not report this model's maximum context size, so no safe limit can be checked.</p>
+{{/* End of the form case. */}}
+{{end}}
+{{/* A pointer to the other setting. */}}
+<p class="muted">How long a model stays loaded is chosen on the Load page each time you load it.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 2: the review step. */}}
+{{else if eq .Kind "review"}}
+{{/* The warning, with a symbol and a bold lead. */}}
+<p class="warn"><strong>⚠ This changes the model itself.</strong> Every program that loads this model without a size of its own will use the new one.</p>
+{{/* The change. */}}
+<table class="facts">
+{{/* Before. */}}
+<tr><th scope="row">Context size now</th><td>{{.SavedText}}</td></tr>
+{{/* After. */}}
+<tr><th scope="row">Context size after saving</th><td><strong>{{.NewValue}}</strong> tokens (word pieces)</td></tr>
+{{/* End of the change. */}}
+</table>
+{{/* What is and is not affected. */}}
+<ul>
+{{/* A bigger size needs more memory. */}}
+<li>A bigger size needs more memory when the model loads; a smaller one needs less.</li>
+{{/* The weights stay. */}}
+<li>The model's weights are not changed, and its other saved settings are kept.</li>
+{{/* No removal. */}}
+<li>You can change it again later, but a saved size cannot be removed.</li>
+{{/* End of the list. */}}
+</ul>
+{{/* The two choices side by side. */}}
+<div class="choices">
+{{/* The Yes form sends the values to the save step. */}}
+<form method="post" action="/gear/save">
+{{/* The page token. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Model}}">
+{{/* The size to save. */}}
+<input type="hidden" name="num_ctx" value="{{.NewValue}}">
+{{/* The Yes button. */}}
+<button type="submit" class="btn-load">Yes, save it into the model</button>
+{{/* End of the Yes form. */}}
+</form>
+{{/* The Cancel link simply goes back; nothing was changed. */}}
+<a class="btn-plain" href="/">Cancel, do not change</a>
+{{/* End of the choices. */}}
+</div>
+{{/* Version 3: saved and checked. */}}
+{{else if eq .Kind "done"}}
+{{/* Say so; it was checked afterwards. */}}
+<p><strong>Saved.</strong> Ollama now reports a context size of {{.AfterText}} for this model, and its other saved settings are unchanged (both checked).</p>
+{{/* What happens next. */}}
+<p class="muted">The next load of this model uses it. After loading, the Loaded table shows the context size actually used.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 4: the same value was already saved. */}}
+{{else if eq .Kind "nochange"}}
+{{/* Say so. */}}
+<p>Nothing to change: a context size of {{.NewValue}} is already saved.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 5: the model is loaded. */}}
+{{else if eq .Kind "loaded"}}
+{{/* Say what to do. */}}
+<p>This model is loaded now, and a loaded model keeps the settings it was loaded with. Unload it first, then change its settings.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 6: the model is not installed. */}}
+{{else if eq .Kind "notinstalled"}}
+{{/* Say so. */}}
+<p>This model is not installed, so it has no settings to change.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 7: Ollama accepted the change but reports something else. */}}
+{{else if eq .Kind "mismatch"}}
+{{/* Say exactly what is known and what is not. */}}
+<p><strong>Please check.</strong> {{.Detail}}</p>
+{{/* What Ollama reports. */}}
+<p class="muted">Ollama now reports a context size of {{if .AfterText}}{{.AfterText}}{{else}}nothing{{end}}; you asked for {{.NewValue}}.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 8: something went wrong. */}}
+{{else}}
+{{/* Say what went wrong, in the plain words the program already uses. */}}
+<p><strong>Could not do this.</strong> {{.Detail}}</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* End of the versions. */}}
+{{end}}
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/web/index.html b/web/index.html
index 0c1959c..59c76f3 100644
--- a/web/index.html
+++ b/web/index.html
@@ -79,7 +79,7 @@
 {{/* Case 4: the table itself. */}}
 {{else}}
 {{/* A hint above the table so people know the dotted headings have help. */}}
-<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The table scrolls sideways.</p>
+<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The gear ⚙ opens a model's settings; it appears only for models that are not loaded. The table scrolls sideways.</p>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
@@ -136,7 +136,22 @@
 {{/* The model name is the row heading and stays visible while scrolling. */}}
 <th scope="row" class="stickycol">{{.Name}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
-<td><span class="statelabel"><span class="dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}" aria-hidden="true"></span> {{.StateWord}}</span>
+<td>
+{{/* The gear opens this model's settings; a loaded model gets an empty slot of the same width, so the state words stay in line. */}}
+{{if .Loaded}}<span class="gearslot" aria-hidden="true"></span>{{else}}
+{{/* A small form that sends the model name and the page token to the settings page, which changes nothing. */}}
+<form class="gearform" method="post" action="/gear">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{$.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Name}}">
+{{/* The button: the symbol is hidden from screen readers, which read the label instead. */}}
+<button type="submit" class="gear" aria-label="Settings for {{.Name}}"><span aria-hidden="true">⚙</span></button>
+{{/* End of the form. */}}
+</form>
+{{/* End of the gear. */}}
+{{end}}
+<span class="statelabel"><span class="dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}" aria-hidden="true"></span> {{.StateWord}}</span>
 {{- /* Only a loaded model gets the Unload button; it opens a warning page first, so one click never unloads anything. */ -}}
 {{if .Loaded}}
 {{/* A small form that sends the model name and the page token to the warning page. */}}
diff --git a/web/load.html b/web/load.html
index e1d543b..798c235 100644
--- a/web/load.html
+++ b/web/load.html
@@ -38,7 +38,11 @@
 {{/* Row 2: memory needed. */}}
 <tr><th scope="row">This model needs at least</th><td>{{.NeedText}} (its size on disk; the real use is higher once the memory for the conversation context is added)</td></tr>
 {{/* Row 3: the default time. */}}
-<tr><th scope="row">Stays loaded after loading</th><td>Ollama's default is {{.DefaultText}} after the last use, then it unloads the model by itself. Your Ollama may be set to another time; the real countdown appears as soon as the model is loaded.</td></tr>
+<tr><th scope="row">{{template "tipbox" .KeepTip}}</th><td>
+{{/* The choice; it belongs to the Yes form below through its id, so it is sent with it. */}}
+<select class="keepselect" name="keep" form="loadform" aria-label="How long the model stays loaded after its last use">{{range .KeepOptions}}<option value="{{.Value}}">{{.Label}}</option>{{end}}</select>
+{{/* The default in words; the real countdown appears as soon as the model is loaded. */}}
+<br>Ollama's default is {{.DefaultText}} after the last use, then it unloads the model by itself. Your Ollama may be set to another time; the real countdown appears as soon as the model is loaded.</td></tr>
 {{/* End of the facts. */}}
 </table>
 {{/* A hint about the waiting time. */}}
@@ -48,7 +52,7 @@
 {{/* The two choices side by side. */}}
 <div class="choices" id="choices">
 {{/* The Yes form sends the model name and the page token to the second step. */}}
-<form method="post" action="/load/confirm" data-loading>
+<form id="loadform" method="post" action="/load/confirm" data-loading>
 {{/* The page token proves the form comes from this monitor. */}}
 <input type="hidden" name="token" value="{{.Token}}">
 {{/* The model name. */}}
diff --git a/web/tips.html b/web/tips.html
new file mode 100644
index 0000000..fed78ab
--- /dev/null
+++ b/web/tips.html
@@ -0,0 +1,29 @@
+{{/* Shared help-bubble templates, used by the settings page and the load page; the comments are template comments, so they never reach the browser. */}}
+{{/* The bubble content: three labelled parts, and the task names when there are any. */}}
+{{define "tip"}}
+{{/* What the heading means. */}}
+<span class="tip-part"><strong>In plain words:</strong> {{.Plain}}</span>
+{{/* A real example. */}}
+<span class="tip-part"><strong>Example:</strong> {{.Example}}</span>
+{{/* What it helps you decide. */}}
+<span class="tip-part"><strong>Helps you decide:</strong> {{.Decide}}</span>
+{{/* Task names, only for categories. */}}
+{{if .AlsoKnown}}
+{{/* The common names. */}}
+<span class="tip-part"><strong>Also known as:</strong> {{.AlsoKnown}}</span>
+{{/* End of the task-name check. */}}
+{{end}}
+{{/* End of the bubble content. */}}
+{{end}}
+{{/* A heading with its bubble: the dotted heading can be reached with Tab, and the bubble opens on pointing or focus. */}}
+{{define "tipbox"}}
+{{/* The area that opens the bubble. */}}
+<span class="tipbox">
+{{/* The heading text; aria-describedby ties it to its bubble for screen readers. */}}
+<span class="help" tabindex="0" aria-describedby="{{.ID}}">{{.Title}}</span>
+{{/* The bubble. */}}
+<span class="tip" role="tooltip" id="{{.ID}}">{{template "tip" .}}</span>
+{{/* End of the bubble area. */}}
+</span>
+{{/* End of the heading with its bubble. */}}
+{{end}}
diff --git a/webtable_test.go b/webtable_test.go
index 6e2b591..afb97e1 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -98,14 +98,14 @@ func TestTablePageRealModels(t *testing.T) {
 			t.Errorf("empty category %q is shown", hidden)
 		} // end of the hidden check
 	} // end of the hidden loop
-	// Exactly one model is loaded and five are not; only table cells are counted, because the help bubbles mention the same words.
-	if n := strings.Count(body, `<td><span class="statelabel"><span class="dot dot-on" aria-hidden="true"></span> Loaded</span>
+	// Exactly one model is loaded and five are not; only the state labels in the table are counted, because the help bubbles mention the same words.
+	if n := strings.Count(body, `<span class="statelabel"><span class="dot dot-on" aria-hidden="true"></span> Loaded</span>
 `); n != 1 {
 		// Report the difference.
 		t.Errorf("loaded cells = %d, want 1", n)
 	} // end of the loaded count
 	// Five models are not loaded.
-	if n := strings.Count(body, `<td><span class="statelabel"><span class="dot dot-off" aria-hidden="true"></span> Not loaded</span>
+	if n := strings.Count(body, `<span class="statelabel"><span class="dot dot-off" aria-hidden="true"></span> Not loaded</span>
 `); n != 5 {
 		// Report the difference.
 		t.Errorf("not-loaded cells = %d, want 5", n)
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch to the working files.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the changed and new files must have after the patch.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
4970c9ff935b348991bb684a19f47c73550664f1d4736d9690f1471e956374b9  gear.go
3285b570233ddcc084283edd7924b8211e4106ab11ca542d55a2cb2b5d28bdde  gear_test.go
7c75487e291066e1a2f95c372fa6ccacbb18294547eba412b6845b15b63cc382  load.go
bda85011adf8b0fef73501e6c9b55eb5e67515919131c23d3c8a28f4d0d20753  load_test.go
831aaff9ffc6693551f8341c931db5f409c1e715ec7d31175644e55cad3332dd  loading_test.go
52dc3210b8ccb3c99a6169968346c0b11c656114bc24611d0ea4f3ed56f10bc5  tableview.go
8b8661da4ea8626123e4b6505ac4fa554d9523664660d47430d3fa9f6f854bdc  tooltips.go
34b6a9f5c18b04bc78f39063408e8d93c19aca9f5fe90d73bdf3427a12be2fe4  tooltips_test.go
3c146e822fef77ec7542986f2966b2d3b6e5b1544b9804032e6bc22947245b0c  web.go
f3f49d62efbd5b85cd9718d1b522bd77ebf839a517d74700bab3603a579bd41f  web/app.css
12aad586288208e73a7137ddbe294f71baf273e70c2d840e14b6b0d487570bf1  web/gear.html
1e970816a5515f5964b12d946307465d3f5e3a0c69e8a02bd43e28edcefef199  web/index.html
4a52c0170fc3387721a6abe4ca03e176e60679bacef8eecb6130fb06689e43e7  web/load.html
f5ed051a332a475ed075f58abebe5355f7ebed1c3ae3cfc1b483237036355a40  web/tips.html
67b20b1ae86b31349456cbd47133a46d44982ac1641fe790c4ddcefe0e87e9b8  webtable_test.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the 15 changed or new files match the tested versions"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# List the changed files; nothing is committed yet.
git status --short
