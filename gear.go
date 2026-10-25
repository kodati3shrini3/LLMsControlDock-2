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

// maxShowReply caps how many bytes of an /api/show reply are read (16 MiB, far more than the real reply).
const maxShowReply = 16 * 1024 * 1024

// maxGearForm is the most form data the settings routes read (16 KB: ten settings and up to eight stop words of 100 characters each, even in four-byte characters).
const maxGearForm = 16 * 1024

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

// createWithParams saves settings inside the model: Ollama rewrites the saved settings of the model, changing only the names sent and keeping everything else (a test on the real Ollama showed this; a new stop list replaces the old one). The model is created from itself, so no weights are fetched.
func createWithParams(ctx context.Context, base *url.URL, name string, params map[string]any, timeout time.Duration) (int, string, error) {
	// The body Ollama expects; stream false makes it answer once, when finished.
	payload := map[string]any{"model": name, "from": name, "parameters": params, "stream": false}
	// Send it.
	return postForReply(ctx, base, "api/create", timeout, payload, nil)
} // end of createWithParams

// settingRow is everything the page shows for one setting.
type settingRow struct {
	// Key is the parameter name; the form field is called s_ plus this.
	Key string
	// Heading is the setting's name.
	Heading string
	// Kind is int, float or list.
	Kind string
	// Tip is the help bubble of the heading.
	Tip tipView
	// Default is Ollama's own default, in words.
	Default string
	// Saved says what the model has saved now, or that nothing is saved.
	Saved string
	// HasSaved is true when the model has this setting saved, so the field must never be emptied.
	HasSaved bool
	// Typed is the text in the field.
	Typed string
	// Editable is false when no safe limit is known for this model.
	Editable bool
	// Range describes the allowed values in words.
	Range string
	// InMin and InMax are the limits given to the browser's own number check.
	InMin, InMax string
	// Step is the browser's step for the number field.
	Step string
	// Problem explains why the typed value was refused.
	Problem string
	// Warn is a note that is not a refusal, such as a saved value above the model's limit.
	Warn string
	// After is the new value, on the review page.
	After string
	// Presets are the suggested sizes (only for the context size).
	Presets []int64
} // end of settingRow

// hiddenField is one hidden form field of the review page.
type hiddenField struct {
	// Name is the field name.
	Name string
	// Value is the field value.
	Value string
} // end of hiddenField

// gearPage is everything the settings page template can show.
type gearPage struct {
	// Kind says which version of the page to draw: settings, review, done, nochange, loaded, notinstalled, mismatch or error.
	Kind string
	// Model is the model name.
	Model string
	// Rows are the ten settings, in order.
	Rows []settingRow
	// Changed lists the rows that change (review and done pages).
	Changed []settingRow
	// Hidden are the values the review page passes on to the save step.
	Hidden []hiddenField
	// Others are saved parameters this page does not edit, shown and kept as they are.
	Others []string
	// Problem is the general note shown above the table when a value was refused.
	Problem string
	// Detail is the plain reason shown on the error and mismatch pages.
	Detail string
	// Max is the model's largest context size; 0 when unknown.
	Max int64
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
	// Saved holds the saved parameters by name.
	Saved map[string][]string
	// Lines are the saved parameters in the order Ollama gave them.
	Lines []paramLine
	// Max is the model's context length, 0 when unknown.
	Max int64
} // end of gearFacts

// change is one setting that the typed values would change.
type change struct {
	// Spec describes the setting.
	Spec settingSpec
	// New is the value to save.
	New settingValue
} // end of change

// fieldName is the form field name of a setting.
func fieldName(key string) string {
	// The same prefix everywhere.
	return "s_" + key
} // end of fieldName

// evaluate builds the ten rows from what is saved and, when a form is given, from what was typed; it returns the rows, the changes, and whether any typed value was refused. A setting whose field is missing from the form is left alone.
func evaluate(f gearFacts, form url.Values, tips map[string]tipView) ([]settingRow, []change, bool) {
	// The result.
	var rows []settingRow
	// The changes.
	var changes []change
	// Becomes true when a typed value is refused.
	refused := false
	// Go through the ten settings.
	for _, spec := range settingSpecs {
		// What is saved now.
		val, present, readable := readSaved(spec, f.Saved[spec.Key])
		// The limits for this model.
		min, max, limitOK := spec.limits(f.Max)
		// The row starts with the facts.
		row := settingRow{Key: spec.Key, Heading: spec.Heading, Kind: spec.Kind, Tip: tips[spec.Key], Default: spec.Default, HasSaved: present, Editable: limitOK, Range: spec.rangeText(f.Max)}
		// The words for the saved value.
		switch {
		// Nothing saved.
		case !present:
			// Say what that means.
			row.Saved = "not set"
		// Saved but not usable.
		case !readable:
			// Show it as it is.
			row.Saved = strings.Join(f.Saved[spec.Key], ", ") + " (not a usable value)"
		// A normal value.
		default:
			// Show it.
			row.Saved = val.text(spec)
		} // end of the saved text
		// The browser's own checks for number fields.
		if spec.Kind != kindList && limitOK {
			// The limits.
			row.InMin, row.InMax = fmtNum(min), fmtNum(max)
			// Whole numbers step by one; decimals accept any step.
			row.Step = "1"
			// Decimals.
			if spec.Kind == kindFloat {
				// Any step.
				row.Step = "any"
			} // end of the step choice
		} // end of the browser limits
		// Suggestions for the context size.
		if spec.Key == "num_ctx" && limitOK {
			// The usual sizes inside the range.
			row.Presets = contextPresets(int64(min), int64(max))
		} // end of the preset case
		// A saved number above this model's limit deserves a note.
		if present && readable && spec.Kind != kindList && limitOK && val.Num > max {
			// The note.
			row.Warn = "The saved value is above what this model supports. Saving a valid value fixes it."
		} // end of the above-limit note
		// The text shown in the field when nothing was typed: the saved value.
		if present && readable {
			// Lists go one per line.
			if spec.Kind == kindList {
				// Join the words.
				row.Typed = strings.Join(val.List, "\n")
			} else {
				// The number.
				row.Typed = fmtNum(val.Num)
			} // end of the pre-fill choice
		} // end of the pre-fill
		// Without a form this is the plain settings page.
		values, typedPresent := form[fieldName(spec.Key)]
		// A missing field means no change.
		if form == nil || !typedPresent {
			// Keep the row as it is.
			rows = append(rows, row)
			// Next setting.
			continue
		} // end of the missing-field case
		// What was typed: the stop words may arrive as several fields (the review page sends one for each word).
		typed := strings.Join(values, "\n")
		// Show what was typed, cut to a sane length.
		if len(typed) > maxListText {
			// Cut it.
			typed = typed[:maxListText]
		} // end of the cut
		// Show it again in the field.
		row.Typed = typed
		// A blank field.
		if strings.TrimSpace(typed) == "" {
			// A saved value can be changed but never removed.
			if present {
				// Refuse with the clear reason.
				row.Problem = "This field cannot be empty. A saved value can be changed, but not removed."
				// Count the refusal.
				refused = true
			} // end of the saved case
			// An unsaved setting left blank simply stays unsaved.
			rows = append(rows, row)
			// Next setting.
			continue
		} // end of the blank case
		// Nothing can be saved without a known limit.
		if !limitOK {
			// Refuse.
			row.Problem = "No safe limit is known for this model, so this setting cannot be changed."
			// Count the refusal.
			refused = true
			// Keep the row.
			rows = append(rows, row)
			// Next setting.
			continue
		} // end of the limit case
		// The new value.
		var nv settingValue
		// The reason when it is refused.
		var problem string
		// Lists and numbers have their own rules.
		if spec.Kind == kindList {
			// The stop words.
			nv.List, problem = parseStopWords(typed)
		} else {
			// The number.
			nv.Num, problem = spec.parseNumber(typed, f.Max)
		} // end of the rule choice
		// A refusal.
		if problem != "" {
			// Keep it.
			row.Problem = problem
			// Count the refusal.
			refused = true
			// Keep the row.
			rows = append(rows, row)
			// Next setting.
			continue
		} // end of the problem check
		// The same as what is saved: no change.
		if present && readable && nv.equal(val, spec) {
			// Keep the row.
			rows = append(rows, row)
			// Next setting.
			continue
		} // end of the same-value case
		// A real change.
		row.After = nv.text(spec)
		// Remember it.
		changes = append(changes, change{Spec: spec, New: nv})
		// Keep the row.
		rows = append(rows, row)
	} // end of the setting loop
	// Hand everything back.
	return rows, changes, refused
} // end of evaluate

// changedRows picks the rows that change, in order.
func changedRows(rows []settingRow) []settingRow {
	// The result.
	var out []settingRow
	// Go through the rows.
	for _, r := range rows {
		// A row with a new value changes.
		if r.After != "" && r.Problem == "" {
			// Keep it.
			out = append(out, r)
		} // end of the check
	} // end of the loop
	// Hand back the list.
	return out
} // end of changedRows

// hiddenFor builds the hidden fields the review page passes on: only the changed settings, one field per stop word.
func hiddenFor(changes []change) []hiddenField {
	// The result.
	var out []hiddenField
	// Go through the changes.
	for _, c := range changes {
		// A list is sent one word per field.
		if c.Spec.Kind == kindList {
			// Each word.
			for _, w := range c.New.List {
				// One field.
				out = append(out, hiddenField{Name: fieldName(c.Spec.Key), Value: w})
			} // end of the word loop
			// Next change.
			continue
		} // end of the list case
		// A number.
		out = append(out, hiddenField{Name: fieldName(c.Spec.Key), Value: fmtNum(c.New.Num)})
	} // end of the change loop
	// Hand back the fields.
	return out
} // end of hiddenFor

// paramsFor builds the parameters object of the create request from the changes; whole-number settings are sent as whole numbers.
func paramsFor(changes []change) map[string]any {
	// The result.
	out := map[string]any{}
	// Go through the changes.
	for _, c := range changes {
		// The kind decides the JSON type.
		switch c.Spec.Kind {
		// The stop words are a list of texts.
		case kindList:
			// The list.
			out[c.Spec.Key] = c.New.List
		// Whole numbers.
		case kindInt:
			// An integer.
			out[c.Spec.Key] = int64(c.New.Num)
		// Decimals.
		default:
			// A decimal number.
			out[c.Spec.Key] = c.New.Num
		} // end of the kind switch
	} // end of the loop
	// Hand back the object.
	return out
} // end of paramsFor

// sameSaved says whether two saved-parameter maps hold the same values for every name except the skipped ones; the order of lines does not matter.
func sameSaved(a, b map[string][]string, skip map[string]bool) bool {
	// The names of both.
	names := map[string]bool{}
	// From a.
	for k := range a {
		// Remember it.
		names[k] = true
	} // end of a
	// From b.
	for k := range b {
		// Remember it.
		names[k] = true
	} // end of b
	// Compare each name.
	for k := range names {
		// A skipped name is not compared.
		if skip[k] {
			// Next name.
			continue
		} // end of the skip check
		// Copy and sort both lists.
		x, y := append([]string{}, a[k]...), append([]string{}, b[k]...)
		// Sort.
		sort.Strings(x)
		// Sort.
		sort.Strings(y)
		// Different sizes.
		if len(x) != len(y) {
			// Not the same.
			return false
		} // end of the size check
		// Compare each.
		for i := range x {
			// A difference.
			if x[i] != y[i] {
				// Not the same.
				return false
			} // end of the compare
		} // end of the loop
	} // end of the name loop
	// All the same.
	return true
} // end of sameSaved

// gearTipKeys maps the short names used in the template to the headings of the help texts; each setting is added by its parameter name.
var gearTipKeys = map[string]string{"saved": "Set in the model", "default": "Ollama's default", "range": "Allowed values"}

// gearHandlers builds the three handlers: the settings page (shows, changes nothing), the review page (checks the typed values and asks "are you sure?"), and the save (changes the model).
func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
	// Read the template once, together with the shared help-bubble templates; Must stops the program at start-up if it is broken, which a test would catch first.
	page := template.Must(template.New("gear").Parse(gearTemplateText + tipsTemplateText))
	// The help bubbles never change, so build them once.
	tips := map[string]tipView{}
	// The fixed ones.
	for key, heading := range gearTipKeys {
		// Build it with an element name that is unique on the page.
		tips[key] = makeTip("tip-gear-"+key, heading)
	} // end of the fixed tips
	// One for each setting.
	for _, spec := range settingSpecs {
		// Build it.
		tips[spec.Key] = makeTip("tip-gear-"+spec.Key, spec.Heading)
	} // end of the setting tips
	// A lock so two saves never run at the same time (a double click on the Yes button, for example).
	var saveLock sync.Mutex
	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, status int, data gearPage) {
		// Add what every version of the page needs.
		data.Theme, data.Token, data.Tips = themeFromRequest(r), token, tips
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
		// The saved parameters.
		lines := parseParams(info.Parameters)
		// The model maximum (0 when unknown).
		max, _ := modelMaxContext(info.ModelInfo)
		// The parameters this page does not edit are listed as they are.
		var others []string
		// Go through the lines.
		for _, l := range lines {
			// One of ours?
			if _, ok := specByKey(l.Name); !ok {
				// Keep it for the note.
				others = append(others, l.Name+" "+l.Value)
			} // end of the check
		} // end of the loop
		// Hand everything back.
		return gearFacts{Page: gearPage{Model: name, Max: max, Others: others}, Saved: savedMap(lines), Lines: lines, Max: max}, true
	} // end of facts
	// begin runs the form checks and the model checks that every step needs; ok is false after a page was shown.
	begin := func(w http.ResponseWriter, r *http.Request) (gearFacts, bool) {
		// Run the shared form checks (a larger form limit than the load and unload forms).
		name, ok := readModelFormLimit(w, r, token, maxGearForm)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return gearFacts{}, false
		} // end of the form checks
		// Run the model checks.
		return facts(w, r, name)
	} // end of begin
	// settings is the first step: it shows the saved values and the form; it changes nothing.
	settings := func(w http.ResponseWriter, r *http.Request) {
		// The checks.
		f, ok := begin(w, r)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// The rows, filled with the saved values.
		p := f.Page
		// The kind of page.
		p.Kind = "settings"
		// Build the rows.
		p.Rows, _, _ = evaluate(f, nil, tips)
		// Show it.
		show(w, r, http.StatusOK, p)
	} // end of settings
	// review is the second step: it checks the typed values and asks "are you sure?"; it changes nothing.
	review := func(w http.ResponseWriter, r *http.Request) {
		// The checks.
		f, ok := begin(w, r)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Check the typed values.
		rows, changes, refused := evaluate(f, r.PostForm, tips)
		// The page figures.
		p := f.Page
		// The rows.
		p.Rows = rows
		// Any refusal: show the settings page again with the reasons; nothing is saved.
		if refused {
			// The page and the general note.
			p.Kind, p.Problem = "settings", "Nothing was saved. Fix the marked settings and review again."
			// Show it.
			show(w, r, http.StatusOK, p)
			// Stop here.
			return
		} // end of the refusal case
		// Nothing differs from what is saved.
		if len(changes) == 0 {
			// Say so.
			p.Kind = "nochange"
			// Show it.
			show(w, r, http.StatusOK, p)
			// Stop here.
			return
		} // end of the no-change case
		// Ask for the confirmation, listing only what changes.
		p.Kind, p.Changed, p.Hidden = "review", changedRows(rows), hiddenFor(changes)
		// Show it.
		show(w, r, http.StatusOK, p)
	} // end of review
	// save is the third step: it checks everything again, saves, and then asks Ollama what is saved now.
	save := func(w http.ResponseWriter, r *http.Request) {
		// Only one save at a time; the lock is taken after the form checks, which need no waiting.
		saveLock.Lock()
		// Release at the end.
		defer saveLock.Unlock()
		// The checks, repeated: things may have changed since the review page.
		f, ok := begin(w, r)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Check the values again.
		rows, changes, refused := evaluate(f, r.PostForm, tips)
		// The page figures.
		p := f.Page
		// The rows.
		p.Rows = rows
		// Any refusal.
		if refused {
			// The page and the general note.
			p.Kind, p.Problem = "settings", "Nothing was saved. Fix the marked settings and review again."
			// Show it.
			show(w, r, http.StatusOK, p)
			// Stop here.
			return
		} // end of the refusal case
		// Nothing differs: a second click on Yes ends up here.
		if len(changes) == 0 {
			// Say so.
			p.Kind = "nochange"
			// Show it.
			show(w, r, http.StatusOK, p)
			// Stop here.
			return
		} // end of the no-change case
		// Save only what changes.
		status, text, err := createWithParams(r.Context(), addr.URL, f.Page.Model, paramsFor(changes), gearTimeout)
		// No answer at all.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: f.Page.Model, Detail: err.Error()})
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
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: f.Page.Model, Detail: detail})
			// Stop here.
			return
		} // end of the refusal check
		// Do not trust the success alone: ask Ollama what is saved now.
		after, status, err := fetchShow(r.Context(), addr.URL, f.Page.Model, gearTimeout)
		// The check could not be done.
		if err != nil || status != http.StatusOK {
			// Say exactly what is known.
			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: f.Page.Model, Detail: "Ollama accepted the change, but the check afterwards failed. Open the settings again to see what is saved."})
			// Stop here.
			return
		} // end of the check read
		// Read the saved values again.
		afterSaved := savedMap(parseParams(after.Parameters))
		// The names that changed.
		changed := map[string]bool{}
		// Becomes false when a changed setting is not what was asked.
		allSet := true
		// Check each change.
		for _, c := range changes {
			// Remember the name.
			changed[c.Spec.Key] = true
			// What Ollama reports now.
			v, present, readable := readSaved(c.Spec, afterSaved[c.Spec.Key])
			// It must be the new value.
			if !present || !readable || !v.equal(c.New, c.Spec) {
				// Not as asked.
				allSet = false
			} // end of the value check
		} // end of the change loop
		// Every other saved parameter must be exactly as before.
		if !allSet || !sameSaved(f.Saved, afterSaved, changed) {
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
		p.Kind, p.Changed = "done", changedRows(rows)
		// Show it.
		show(w, r, http.StatusOK, p)
	} // end of save
	// Hand the three back.
	return settings, review, save
} // end of gearHandlers
