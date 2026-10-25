#!/usr/bin/env bash
# Script 36: the full model settings table (ten settings with Ollama's default, the saved value, the allowed range and a tooltip each); applied on the feature branch.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-settings-table" ] || { echo "FAIL  not on feature/model-settings-table"; exit 1; }
# Refuse when tracked files are already changed or new files other than scripts exist (a clean start keeps the commit clean).
if [ -n "$(git status --porcelain | grep -v '^?? scripts/' || true)" ]; then
  # Show what is in the way.
  echo "FAIL  the working tree is not clean:"; git status --short; exit 1
fi
# Refuse when the change was already applied.
[ ! -f settings.go ] || { echo "FAIL  settings.go already exists; this script was already applied"; exit 1; }
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/gear.go b/gear.go
index d53aaf5..ae3abb1 100644
--- a/gear.go
+++ b/gear.go
@@ -28,8 +28,6 @@ import ( // import lists the standard-library packages this file uses.
 	"net/url"
 	// sort puts the preset sizes in order.
 	"sort"
-	// strconv turns numbers into text and back.
-	"strconv"
 	// strings trims and splits text.
 	"strings"
 	// sync makes sure two saves never run at the same time.
@@ -48,14 +46,11 @@ var gearTemplateText string
 //go:embed web/tips.html
 var tipsTemplateText string
 
-// minContext is the smallest context size this monitor lets you save; Ollama itself sets no smallest value (a test on the real Ollama accepted 1).
-const minContext int64 = 512
-
 // maxShowReply caps how many bytes of an /api/show reply are read (16 MiB, far more than the real reply).
 const maxShowReply = 16 * 1024 * 1024
 
-// maxContextField is the longest text the context size field may hold.
-const maxContextField = 40
+// maxGearForm is the most form data the settings routes read (16 KB: ten settings and up to eight stop words of 100 characters each, even in four-byte characters).
+const maxGearForm = 16 * 1024
 
 // gearTimeout is how long one request to Ollama may take on the settings pages.
 const gearTimeout = 2 * time.Minute
@@ -98,64 +93,6 @@ func parseParams(text string) []paramLine {
 	return out
 } // end of parseParams
 
-// savedContext reads the saved context size: text is what Ollama printed, present says a num_ctx line exists, and n is its value (0 when it is not a usable whole number).
-func savedContext(lines []paramLine) (text string, n int64, present bool) {
-	// The last num_ctx line wins, like in a Modelfile.
-	for _, l := range lines {
-		// Only the context size line counts.
-		if l.Name != "num_ctx" {
-			// Next line.
-			continue
-		} // end of the name check
-		// Remember it.
-		text, present, n = l.Value, true, 0
-		// Ollama may print a big number in the form 1e+08, so read it as a decimal number first.
-		f, err := strconv.ParseFloat(l.Value, 64)
-		// Accept only a whole number in a sane range.
-		if err == nil && f == math.Trunc(f) && f >= 1 && f <= 1e12 {
-			// Keep it.
-			n = int64(f)
-		} // end of the number check
-	} // end of the line loop
-	// Hand back all three.
-	return text, n, present
-} // end of savedContext
-
-// otherParams returns every saved parameter except num_ctx, as "name value" texts in the order Ollama gave them.
-func otherParams(lines []paramLine) []string {
-	// The result.
-	var out []string
-	// Go through the lines.
-	for _, l := range lines {
-		// The context size is handled separately.
-		if l.Name != "num_ctx" {
-			// Keep the rest as they are.
-			out = append(out, l.Name+" "+l.Value)
-		} // end of the name check
-	} // end of the line loop
-	// Hand back the list.
-	return out
-} // end of otherParams
-
-// sameStrings says whether two lists hold the same texts in the same order.
-func sameStrings(a, b []string) bool {
-	// Different lengths cannot be the same.
-	if len(a) != len(b) {
-		// Not the same.
-		return false
-	} // end of the length check
-	// Compare one by one.
-	for i := range a {
-		// A difference.
-		if a[i] != b[i] {
-			// Not the same.
-			return false
-		} // end of the compare
-	} // end of the loop
-	// All equal.
-	return true
-} // end of sameStrings
-
 // modelMaxContext reads the largest context size the model supports from its own facts; the second result is false when it cannot be read.
 func modelMaxContext(info map[string]json.RawMessage) (int64, bool) {
 	// The model's architecture name, such as gemma3, tells which key holds the limit.
@@ -256,49 +193,6 @@ func contextPresets(min, max int64) []int64 {
 	return out
 } // end of contextPresets
 
-// validateContext checks what was typed; it returns the number and an empty text when all is well, or zero and the reason in plain words.
-func validateContext(raw string, min, max int64) (int64, string) {
-	// Spaces around the number do not matter.
-	s := strings.TrimSpace(raw)
-	// An empty value is never allowed: a saved value can be changed but not removed.
-	if s == "" {
-		// Say why.
-		return 0, "The context size cannot be empty. A saved value can be changed, but not removed."
-	} // end of the empty check
-	// Only the digits 0 to 9: no signs, no decimals, no letters, no other scripts.
-	for _, r := range s {
-		// Anything else is refused.
-		if r < '0' || r > '9' {
-			// Say what is expected.
-			return 0, "Use digits only, as a whole number such as 8192."
-		} // end of the digit check
-	} // end of the loop
-	// A number with more than 12 digits is far outside any model.
-	if len(s) > 12 {
-		// Say so with the range.
-		return 0, fmt.Sprintf("That number is too large. The model maximum is %d.", max)
-	} // end of the length check
-	// Read the number; it cannot fail now.
-	n, err := strconv.ParseInt(s, 10, 64)
-	// Defensive: treat a failure as a bad number.
-	if err != nil {
-		// Say what is expected.
-		return 0, "Use digits only, as a whole number such as 8192."
-	} // end of the parse check
-	// Below the smallest allowed size.
-	if n < min {
-		// Say so.
-		return 0, fmt.Sprintf("%d is too small. The smallest size allowed here is %d.", n, min)
-	} // end of the small check
-	// Above the model's maximum.
-	if n > max {
-		// Say so.
-		return 0, fmt.Sprintf("%d is more than this model supports. The model maximum is %d.", n, max)
-	} // end of the large check
-	// All good.
-	return n, ""
-} // end of validateContext
-
 // postForReply sends one JSON body and decodes the JSON reply into out (when out is not nil); it also returns the short error text Ollama may have sent; every error text is fixed and never contains the address.
 func postForReply(ctx context.Context, base *url.URL, path string, timeout time.Duration, payload any, out any) (int, string, error) {
 	// Turn the payload into JSON text.
@@ -371,13 +265,57 @@ func fetchShow(ctx context.Context, base *url.URL, name string, timeout time.Dur
 	return reply, status, err
 } // end of fetchShow
 
-// createWithContext saves a context size inside the model: Ollama rewrites the model's saved settings, keeping everything else (the model is created from itself, so no weights are fetched).
-func createWithContext(ctx context.Context, base *url.URL, name string, n int64, timeout time.Duration) (int, string, error) {
+// createWithParams saves settings inside the model: Ollama rewrites the saved settings of the model, changing only the names sent and keeping everything else (a test on the real Ollama showed this; a new stop list replaces the old one). The model is created from itself, so no weights are fetched.
+func createWithParams(ctx context.Context, base *url.URL, name string, params map[string]any, timeout time.Duration) (int, string, error) {
 	// The body Ollama expects; stream false makes it answer once, when finished.
-	payload := map[string]any{"model": name, "from": name, "parameters": map[string]any{"num_ctx": n}, "stream": false}
+	payload := map[string]any{"model": name, "from": name, "parameters": params, "stream": false}
 	// Send it.
 	return postForReply(ctx, base, "api/create", timeout, payload, nil)
-} // end of createWithContext
+} // end of createWithParams
+
+// settingRow is everything the page shows for one setting.
+type settingRow struct {
+	// Key is the parameter name; the form field is called s_ plus this.
+	Key string
+	// Heading is the setting's name.
+	Heading string
+	// Kind is int, float or list.
+	Kind string
+	// Tip is the help bubble of the heading.
+	Tip tipView
+	// Default is Ollama's own default, in words.
+	Default string
+	// Saved says what the model has saved now, or that nothing is saved.
+	Saved string
+	// HasSaved is true when the model has this setting saved, so the field must never be emptied.
+	HasSaved bool
+	// Typed is the text in the field.
+	Typed string
+	// Editable is false when no safe limit is known for this model.
+	Editable bool
+	// Range describes the allowed values in words.
+	Range string
+	// InMin and InMax are the limits given to the browser's own number check.
+	InMin, InMax string
+	// Step is the browser's step for the number field.
+	Step string
+	// Problem explains why the typed value was refused.
+	Problem string
+	// Warn is a note that is not a refusal, such as a saved value above the model's limit.
+	Warn string
+	// After is the new value, on the review page.
+	After string
+	// Presets are the suggested sizes (only for the context size).
+	Presets []int64
+} // end of settingRow
+
+// hiddenField is one hidden form field of the review page.
+type hiddenField struct {
+	// Name is the field name.
+	Name string
+	// Value is the field value.
+	Value string
+} // end of hiddenField
 
 // gearPage is everything the settings page template can show.
 type gearPage struct {
@@ -385,30 +323,20 @@ type gearPage struct {
 	Kind string
 	// Model is the model name.
 	Model string
-	// SavedText says what is saved now: the number, or a sentence when nothing is saved.
-	SavedText string
-	// Max is the model's largest context size; 0 when unknown.
-	Max int64
-	// Min is the smallest size this monitor allows.
-	Min int64
-	// Presets are the suggested sizes.
-	Presets []int64
-	// Others are the other saved parameters, shown and kept as they are.
+	// Rows are the ten settings, in order.
+	Rows []settingRow
+	// Changed lists the rows that change (review and done pages).
+	Changed []settingRow
+	// Hidden are the values the review page passes on to the save step.
+	Hidden []hiddenField
+	// Others are saved parameters this page does not edit, shown and kept as they are.
 	Others []string
-	// CanSave is false when no safe limit is known, so saving is switched off.
-	CanSave bool
-	// Problem explains why the typed value was refused.
+	// Problem is the general note shown above the table when a value was refused.
 	Problem string
-	// Typed is what was typed, shown again in the field.
-	Typed string
-	// NewValue is the size to be saved (review and done pages).
-	NewValue int64
-	// AfterText is what Ollama reports after the save.
-	AfterText string
 	// Detail is the plain reason shown on the error and mismatch pages.
 	Detail string
-	// AboveMax is true when the saved size is already above the model's maximum.
-	AboveMax bool
+	// Max is the model's largest context size; 0 when unknown.
+	Max int64
 	// Theme is the saved theme choice, as on the main page.
 	Theme string
 	// Token is the page token for the forms on this page.
@@ -421,34 +349,311 @@ type gearPage struct {
 type gearFacts struct {
 	// Page holds the figures for the page.
 	Page gearPage
-	// Lines are the saved parameters.
+	// Saved holds the saved parameters by name.
+	Saved map[string][]string
+	// Lines are the saved parameters in the order Ollama gave them.
 	Lines []paramLine
-	// Current is the saved context size (0 when none or unusable).
-	Current int64
-	// Present says whether a num_ctx line exists.
-	Present bool
+	// Max is the model's context length, 0 when unknown.
+	Max int64
 } // end of gearFacts
 
-// gearTipKeys maps the short names used in the template to the headings of the help texts.
-var gearTipKeys = map[string]string{"ctx": "Context size", "max": "Model maximum", "min": "Smallest allowed", "saved": "Saved in the model", "other": "Other saved settings"}
+// change is one setting that the typed values would change.
+type change struct {
+	// Spec describes the setting.
+	Spec settingSpec
+	// New is the value to save.
+	New settingValue
+} // end of change
+
+// fieldName is the form field name of a setting.
+func fieldName(key string) string {
+	// The same prefix everywhere.
+	return "s_" + key
+} // end of fieldName
+
+// evaluate builds the ten rows from what is saved and, when a form is given, from what was typed; it returns the rows, the changes, and whether any typed value was refused. A setting whose field is missing from the form is left alone.
+func evaluate(f gearFacts, form url.Values, tips map[string]tipView) ([]settingRow, []change, bool) {
+	// The result.
+	var rows []settingRow
+	// The changes.
+	var changes []change
+	// Becomes true when a typed value is refused.
+	refused := false
+	// Go through the ten settings.
+	for _, spec := range settingSpecs {
+		// What is saved now.
+		val, present, readable := readSaved(spec, f.Saved[spec.Key])
+		// The limits for this model.
+		min, max, limitOK := spec.limits(f.Max)
+		// The row starts with the facts.
+		row := settingRow{Key: spec.Key, Heading: spec.Heading, Kind: spec.Kind, Tip: tips[spec.Key], Default: spec.Default, HasSaved: present, Editable: limitOK, Range: spec.rangeText(f.Max)}
+		// The words for the saved value.
+		switch {
+		// Nothing saved.
+		case !present:
+			// Say what that means.
+			row.Saved = "not saved"
+		// Saved but not usable.
+		case !readable:
+			// Show it as it is.
+			row.Saved = strings.Join(f.Saved[spec.Key], ", ") + " (not a usable value)"
+		// A normal value.
+		default:
+			// Show it.
+			row.Saved = val.text(spec)
+		} // end of the saved text
+		// The browser's own checks for number fields.
+		if spec.Kind != kindList && limitOK {
+			// The limits.
+			row.InMin, row.InMax = fmtNum(min), fmtNum(max)
+			// Whole numbers step by one; decimals accept any step.
+			row.Step = "1"
+			// Decimals.
+			if spec.Kind == kindFloat {
+				// Any step.
+				row.Step = "any"
+			} // end of the step choice
+		} // end of the browser limits
+		// Suggestions for the context size.
+		if spec.Key == "num_ctx" && limitOK {
+			// The usual sizes inside the range.
+			row.Presets = contextPresets(int64(min), int64(max))
+		} // end of the preset case
+		// A saved number above this model's limit deserves a note.
+		if present && readable && spec.Kind != kindList && limitOK && val.Num > max {
+			// The note.
+			row.Warn = "The saved value is above what this model supports. Saving a valid value fixes it."
+		} // end of the above-limit note
+		// The text shown in the field when nothing was typed: the saved value.
+		if present && readable {
+			// Lists go one per line.
+			if spec.Kind == kindList {
+				// Join the words.
+				row.Typed = strings.Join(val.List, "\n")
+			} else {
+				// The number.
+				row.Typed = fmtNum(val.Num)
+			} // end of the pre-fill choice
+		} // end of the pre-fill
+		// Without a form this is the plain settings page.
+		values, typedPresent := form[fieldName(spec.Key)]
+		// A missing field means no change.
+		if form == nil || !typedPresent {
+			// Keep the row as it is.
+			rows = append(rows, row)
+			// Next setting.
+			continue
+		} // end of the missing-field case
+		// What was typed: the stop words may arrive as several fields (the review page sends one for each word).
+		typed := strings.Join(values, "\n")
+		// Show what was typed, cut to a sane length.
+		if len(typed) > maxListText {
+			// Cut it.
+			typed = typed[:maxListText]
+		} // end of the cut
+		// Show it again in the field.
+		row.Typed = typed
+		// A blank field.
+		if strings.TrimSpace(typed) == "" {
+			// A saved value can be changed but never removed.
+			if present {
+				// Refuse with the clear reason.
+				row.Problem = "This field cannot be empty. A saved value can be changed, but not removed."
+				// Count the refusal.
+				refused = true
+			} // end of the saved case
+			// An unsaved setting left blank simply stays unsaved.
+			rows = append(rows, row)
+			// Next setting.
+			continue
+		} // end of the blank case
+		// Nothing can be saved without a known limit.
+		if !limitOK {
+			// Refuse.
+			row.Problem = "No safe limit is known for this model, so this setting cannot be changed."
+			// Count the refusal.
+			refused = true
+			// Keep the row.
+			rows = append(rows, row)
+			// Next setting.
+			continue
+		} // end of the limit case
+		// The new value.
+		var nv settingValue
+		// The reason when it is refused.
+		var problem string
+		// Lists and numbers have their own rules.
+		if spec.Kind == kindList {
+			// The stop words.
+			nv.List, problem = parseStopWords(typed)
+		} else {
+			// The number.
+			nv.Num, problem = spec.parseNumber(typed, f.Max)
+		} // end of the rule choice
+		// A refusal.
+		if problem != "" {
+			// Keep it.
+			row.Problem = problem
+			// Count the refusal.
+			refused = true
+			// Keep the row.
+			rows = append(rows, row)
+			// Next setting.
+			continue
+		} // end of the problem check
+		// The same as what is saved: no change.
+		if present && readable && nv.equal(val, spec) {
+			// Keep the row.
+			rows = append(rows, row)
+			// Next setting.
+			continue
+		} // end of the same-value case
+		// A real change.
+		row.After = nv.text(spec)
+		// Remember it.
+		changes = append(changes, change{Spec: spec, New: nv})
+		// Keep the row.
+		rows = append(rows, row)
+	} // end of the setting loop
+	// Hand everything back.
+	return rows, changes, refused
+} // end of evaluate
+
+// changedRows picks the rows that change, in order.
+func changedRows(rows []settingRow) []settingRow {
+	// The result.
+	var out []settingRow
+	// Go through the rows.
+	for _, r := range rows {
+		// A row with a new value changes.
+		if r.After != "" && r.Problem == "" {
+			// Keep it.
+			out = append(out, r)
+		} // end of the check
+	} // end of the loop
+	// Hand back the list.
+	return out
+} // end of changedRows
 
-// gearHandlers builds the three handlers: the settings page (shows, changes nothing), the review page (checks the typed value and asks "are you sure?"), and the save (changes the model).
+// hiddenFor builds the hidden fields the review page passes on: only the changed settings, one field per stop word.
+func hiddenFor(changes []change) []hiddenField {
+	// The result.
+	var out []hiddenField
+	// Go through the changes.
+	for _, c := range changes {
+		// A list is sent one word per field.
+		if c.Spec.Kind == kindList {
+			// Each word.
+			for _, w := range c.New.List {
+				// One field.
+				out = append(out, hiddenField{Name: fieldName(c.Spec.Key), Value: w})
+			} // end of the word loop
+			// Next change.
+			continue
+		} // end of the list case
+		// A number.
+		out = append(out, hiddenField{Name: fieldName(c.Spec.Key), Value: fmtNum(c.New.Num)})
+	} // end of the change loop
+	// Hand back the fields.
+	return out
+} // end of hiddenFor
+
+// paramsFor builds the parameters object of the create request from the changes; whole-number settings are sent as whole numbers.
+func paramsFor(changes []change) map[string]any {
+	// The result.
+	out := map[string]any{}
+	// Go through the changes.
+	for _, c := range changes {
+		// The kind decides the JSON type.
+		switch c.Spec.Kind {
+		// The stop words are a list of texts.
+		case kindList:
+			// The list.
+			out[c.Spec.Key] = c.New.List
+		// Whole numbers.
+		case kindInt:
+			// An integer.
+			out[c.Spec.Key] = int64(c.New.Num)
+		// Decimals.
+		default:
+			// A decimal number.
+			out[c.Spec.Key] = c.New.Num
+		} // end of the kind switch
+	} // end of the loop
+	// Hand back the object.
+	return out
+} // end of paramsFor
+
+// sameSaved says whether two saved-parameter maps hold the same values for every name except the skipped ones; the order of lines does not matter.
+func sameSaved(a, b map[string][]string, skip map[string]bool) bool {
+	// The names of both.
+	names := map[string]bool{}
+	// From a.
+	for k := range a {
+		// Remember it.
+		names[k] = true
+	} // end of a
+	// From b.
+	for k := range b {
+		// Remember it.
+		names[k] = true
+	} // end of b
+	// Compare each name.
+	for k := range names {
+		// A skipped name is not compared.
+		if skip[k] {
+			// Next name.
+			continue
+		} // end of the skip check
+		// Copy and sort both lists.
+		x, y := append([]string{}, a[k]...), append([]string{}, b[k]...)
+		// Sort.
+		sort.Strings(x)
+		// Sort.
+		sort.Strings(y)
+		// Different sizes.
+		if len(x) != len(y) {
+			// Not the same.
+			return false
+		} // end of the size check
+		// Compare each.
+		for i := range x {
+			// A difference.
+			if x[i] != y[i] {
+				// Not the same.
+				return false
+			} // end of the compare
+		} // end of the loop
+	} // end of the name loop
+	// All the same.
+	return true
+} // end of sameSaved
+
+// gearTipKeys maps the short names used in the template to the headings of the help texts; each setting is added by its parameter name.
+var gearTipKeys = map[string]string{"saved": "Saved in the model", "default": "Ollama's default", "range": "Allowed values"}
+
+// gearHandlers builds the three handlers: the settings page (shows, changes nothing), the review page (checks the typed values and asks "are you sure?"), and the save (changes the model).
 func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
 	// Read the template once, together with the shared help-bubble templates; Must stops the program at start-up if it is broken, which a test would catch first.
 	page := template.Must(template.New("gear").Parse(gearTemplateText + tipsTemplateText))
 	// The help bubbles never change, so build them once.
 	tips := map[string]tipView{}
-	// One for each short name.
+	// The fixed ones.
 	for key, heading := range gearTipKeys {
 		// Build it with an element name that is unique on the page.
 		tips[key] = makeTip("tip-gear-"+key, heading)
-	} // end of the tip loop
+	} // end of the fixed tips
+	// One for each setting.
+	for _, spec := range settingSpecs {
+		// Build it.
+		tips[spec.Key] = makeTip("tip-gear-"+spec.Key, spec.Heading)
+	} // end of the setting tips
 	// A lock so two saves never run at the same time (a double click on the Yes button, for example).
 	var saveLock sync.Mutex
 	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
 	show := func(w http.ResponseWriter, r *http.Request, status int, data gearPage) {
 		// Add what every version of the page needs.
-		data.Theme, data.Token, data.Tips, data.Min = themeFromRequest(r), token, tips, minContext
+		data.Theme, data.Token, data.Tips = themeFromRequest(r), token, tips
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
@@ -524,190 +729,134 @@ func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Hand
 			// Stop here.
 			return gearFacts{}, false
 		} // end of the status check
-		// Work out the figures.
+		// The saved parameters.
 		lines := parseParams(info.Parameters)
-		// The saved context size.
-		text, current, present := savedContext(lines)
-		// The model maximum.
-		max, maxOK := modelMaxContext(info.ModelInfo)
-		// Start the page figures.
-		p := gearPage{Model: name, Max: max, Others: otherParams(lines), CanSave: maxOK}
-		// The words for the saved value.
-		switch {
-		// Nothing saved.
-		case !present:
-			// Say what that means.
-			p.SavedText = "not saved in the model (Ollama chooses a size when the model loads)"
-		// Saved but not usable.
-		case current == 0:
-			// Show it as it is.
-			p.SavedText = text + " (not a usable size)"
-		// A normal value.
-		default:
-			// Show the number.
-			p.SavedText = strconv.FormatInt(current, 10)
-		} // end of the saved text
-		// Offer suggestions only when the limit is known.
-		if maxOK {
-			// The suggestions.
-			p.Presets = contextPresets(minContext, max)
-			// A saved value above the maximum deserves a note.
-			p.AboveMax = current > max
-		} // end of the preset case
+		// The model maximum (0 when unknown).
+		max, _ := modelMaxContext(info.ModelInfo)
+		// The parameters this page does not edit are listed as they are.
+		var others []string
+		// Go through the lines.
+		for _, l := range lines {
+			// One of ours?
+			if _, ok := specByKey(l.Name); !ok {
+				// Keep it for the note.
+				others = append(others, l.Name+" "+l.Value)
+			} // end of the check
+		} // end of the loop
 		// Hand everything back.
-		return gearFacts{Page: p, Lines: lines, Current: current, Present: present}, true
+		return gearFacts{Page: gearPage{Model: name, Max: max, Others: others}, Saved: savedMap(lines), Lines: lines, Max: max}, true
 	} // end of facts
-	// check runs the typed value through the rules; it shows the settings page again with the reason when it is refused, and returns false then.
-	check := func(w http.ResponseWriter, r *http.Request, f gearFacts) (int64, bool) {
-		// The typed text, cut to a sane length first.
-		typed := r.PostFormValue("num_ctx")
-		// An absurdly long text is refused at once.
-		if len(typed) > maxContextField {
-			// Cut it for display.
-			typed = typed[:maxContextField]
-		} // end of the length check
-		// Without a known maximum nothing can be saved.
-		if !f.Page.CanSave {
-			// Show the settings page with the reason.
-			p := f.Page
-			// The reason.
-			p.Kind, p.Problem, p.Typed = "settings", "Ollama does not report this model's maximum context size, so no safe limit can be checked and nothing can be saved.", typed
-			// Show it.
-			show(w, r, http.StatusOK, p)
-			// Refused.
-			return 0, false
-		} // end of the limit check
-		// Apply the rules.
-		n, problem := validateContext(r.PostFormValue("num_ctx"), minContext, f.Page.Max)
-		// A refusal.
-		if problem != "" {
-			// Show the settings page with the reason.
-			p := f.Page
-			// The reason and the typed text.
-			p.Kind, p.Problem, p.Typed = "settings", problem, typed
-			// Show it.
-			show(w, r, http.StatusOK, p)
-			// Refused.
-			return 0, false
-		} // end of the problem check
-		// Accepted.
-		return n, true
-	} // end of check
-	// settings is the first step: it shows the saved values and the form; it changes nothing.
-	settings := func(w http.ResponseWriter, r *http.Request) {
-		// Run the shared form checks.
-		name, ok := readModelForm(w, r, token)
+	// begin runs the form checks and the model checks that every step needs; ok is false after a page was shown.
+	begin := func(w http.ResponseWriter, r *http.Request) (gearFacts, bool) {
+		// Run the shared form checks (a larger form limit than the load and unload forms).
+		name, ok := readModelFormLimit(w, r, token, maxGearForm)
 		// A refusal was already sent.
 		if !ok {
 			// Stop here.
-			return
+			return gearFacts{}, false
 		} // end of the form checks
 		// Run the model checks.
-		f, ok := facts(w, r, name)
+		return facts(w, r, name)
+	} // end of begin
+	// settings is the first step: it shows the saved values and the form; it changes nothing.
+	settings := func(w http.ResponseWriter, r *http.Request) {
+		// The checks.
+		f, ok := begin(w, r)
 		// A page was already shown.
 		if !ok {
 			// Stop here.
 			return
-		} // end of the model checks
-		// Show the form; the field starts with the saved value when there is one.
+		} // end of the checks
+		// The rows, filled with the saved values.
 		p := f.Page
 		// The kind of page.
 		p.Kind = "settings"
-		// Pre-fill the field with the saved value.
-		if f.Current > 0 {
-			// The number.
-			p.Typed = strconv.FormatInt(f.Current, 10)
-		} // end of the pre-fill
+		// Build the rows.
+		p.Rows, _, _ = evaluate(f, nil, tips)
 		// Show it.
 		show(w, r, http.StatusOK, p)
 	} // end of settings
-	// review is the second step: it checks the typed value and asks "are you sure?"; it changes nothing.
+	// review is the second step: it checks the typed values and asks "are you sure?"; it changes nothing.
 	review := func(w http.ResponseWriter, r *http.Request) {
-		// Run the shared form checks.
-		name, ok := readModelForm(w, r, token)
-		// A refusal was already sent.
-		if !ok {
-			// Stop here.
-			return
-		} // end of the form checks
-		// Run the model checks.
-		f, ok := facts(w, r, name)
+		// The checks.
+		f, ok := begin(w, r)
 		// A page was already shown.
 		if !ok {
 			// Stop here.
 			return
-		} // end of the model checks
-		// Run the rules.
-		n, ok := check(w, r, f)
-		// A page was already shown.
-		if !ok {
+		} // end of the checks
+		// Check the typed values.
+		rows, changes, refused := evaluate(f, r.PostForm, tips)
+		// The page figures.
+		p := f.Page
+		// The rows.
+		p.Rows = rows
+		// Any refusal: show the settings page again with the reasons; nothing is saved.
+		if refused {
+			// The page and the general note.
+			p.Kind, p.Problem = "settings", "Nothing was saved. Fix the marked settings and review again."
+			// Show it.
+			show(w, r, http.StatusOK, p)
 			// Stop here.
 			return
-		} // end of the rule check
-		// The same value as now: nothing to do.
-		p := f.Page
-		// The size under review.
-		p.NewValue = n
-		// Nothing changes.
-		if f.Present && n == f.Current {
+		} // end of the refusal case
+		// Nothing differs from what is saved.
+		if len(changes) == 0 {
 			// Say so.
 			p.Kind = "nochange"
 			// Show it.
 			show(w, r, http.StatusOK, p)
 			// Stop here.
 			return
-		} // end of the same-value case
-		// Ask for the confirmation.
-		p.Kind = "review"
+		} // end of the no-change case
+		// Ask for the confirmation, listing only what changes.
+		p.Kind, p.Changed, p.Hidden = "review", changedRows(rows), hiddenFor(changes)
 		// Show it.
 		show(w, r, http.StatusOK, p)
 	} // end of review
 	// save is the third step: it checks everything again, saves, and then asks Ollama what is saved now.
 	save := func(w http.ResponseWriter, r *http.Request) {
-		// Run the shared form checks.
-		name, ok := readModelForm(w, r, token)
-		// A refusal was already sent.
-		if !ok {
-			// Stop here.
-			return
-		} // end of the form checks
-		// Only one save at a time.
+		// Only one save at a time; the lock is taken after the form checks, which need no waiting.
 		saveLock.Lock()
 		// Release at the end.
 		defer saveLock.Unlock()
-		// Run the model checks again: things may have changed since the review page.
-		f, ok := facts(w, r, name)
+		// The checks, repeated: things may have changed since the review page.
+		f, ok := begin(w, r)
 		// A page was already shown.
 		if !ok {
 			// Stop here.
 			return
-		} // end of the model checks
-		// Run the rules again.
-		n, ok := check(w, r, f)
-		// A page was already shown.
-		if !ok {
+		} // end of the checks
+		// Check the values again.
+		rows, changes, refused := evaluate(f, r.PostForm, tips)
+		// The page figures.
+		p := f.Page
+		// The rows.
+		p.Rows = rows
+		// Any refusal.
+		if refused {
+			// The page and the general note.
+			p.Kind, p.Problem = "settings", "Nothing was saved. Fix the marked settings and review again."
+			// Show it.
+			show(w, r, http.StatusOK, p)
 			// Stop here.
 			return
-		} // end of the rule check
-		// The page figures for the result pages.
-		p := f.Page
-		// The size being saved.
-		p.NewValue = n
-		// The same value as now: nothing to do (a second click on Yes ends up here).
-		if f.Present && n == f.Current {
+		} // end of the refusal case
+		// Nothing differs: a second click on Yes ends up here.
+		if len(changes) == 0 {
 			// Say so.
 			p.Kind = "nochange"
 			// Show it.
 			show(w, r, http.StatusOK, p)
 			// Stop here.
 			return
-		} // end of the same-value case
-		// Save it inside the model.
-		status, text, err := createWithContext(r.Context(), addr.URL, name, n, gearTimeout)
+		} // end of the no-change case
+		// Save only what changes.
+		status, text, err := createWithParams(r.Context(), addr.URL, f.Page.Model, paramsFor(changes), gearTimeout)
 		// No answer at all.
 		if err != nil {
 			// Show the plain reason.
-			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: err.Error()})
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: f.Page.Model, Detail: err.Error()})
 			// Stop here.
 			return
 		} // end of the send check
@@ -721,27 +870,39 @@ func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Hand
 				detail += " Ollama said: " + text
 			} // end of the message
 			// Show it.
-			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: detail})
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: f.Page.Model, Detail: detail})
 			// Stop here.
 			return
 		} // end of the refusal check
 		// Do not trust the success alone: ask Ollama what is saved now.
-		after, status, err := fetchShow(r.Context(), addr.URL, name, gearTimeout)
+		after, status, err := fetchShow(r.Context(), addr.URL, f.Page.Model, gearTimeout)
 		// The check could not be done.
 		if err != nil || status != http.StatusOK {
 			// Say exactly what is known.
-			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: name, Detail: "Ollama accepted the change, but the check afterwards failed. Open the settings again to see what is saved."})
+			show(w, r, http.StatusBadGateway, gearPage{Kind: "error", Model: f.Page.Model, Detail: "Ollama accepted the change, but the check afterwards failed. Open the settings again to see what is saved."})
 			// Stop here.
 			return
 		} // end of the check read
 		// Read the saved values again.
-		afterLines := parseParams(after.Parameters)
-		// The saved context size now.
-		afterText, afterN, afterPresent := savedContext(afterLines)
-		// What Ollama reports, for the page.
-		p.AfterText = afterText
-		// The size must be the new one, and every other saved parameter must be exactly as before.
-		if !afterPresent || afterN != n || !sameStrings(otherParams(f.Lines), otherParams(afterLines)) {
+		afterSaved := savedMap(parseParams(after.Parameters))
+		// The names that changed.
+		changed := map[string]bool{}
+		// Becomes false when a changed setting is not what was asked.
+		allSet := true
+		// Check each change.
+		for _, c := range changes {
+			// Remember the name.
+			changed[c.Spec.Key] = true
+			// What Ollama reports now.
+			v, present, readable := readSaved(c.Spec, afterSaved[c.Spec.Key])
+			// It must be the new value.
+			if !present || !readable || !v.equal(c.New, c.Spec) {
+				// Not as asked.
+				allSet = false
+			} // end of the value check
+		} // end of the change loop
+		// Every other saved parameter must be exactly as before.
+		if !allSet || !sameSaved(f.Saved, afterSaved, changed) {
 			// Say honestly that the result is not what was asked.
 			p.Kind = "mismatch"
 			// The detail.
@@ -752,7 +913,7 @@ func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Hand
 			return
 		} // end of the verify check
 		// Everything checked out.
-		p.Kind = "done"
+		p.Kind, p.Changed = "done", changedRows(rows)
 		// Show it.
 		show(w, r, http.StatusOK, p)
 	} // end of save
diff --git a/gear_test.go b/gear_test.go
index 7581bd9..8015258 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -14,6 +14,10 @@ import ( // import lists the packages this test file uses.
 	"net/url"
 	// regexp finds the token in the page.
 	"regexp"
+	// sort puts the keys of a request in order.
+	"sort"
+	// strconv quotes text the way Ollama prints it.
+	"strconv"
 	// strings searches the page text.
 	"strings"
 	// sync protects the fake's records and runs the double-click test.
@@ -24,12 +28,12 @@ import ( // import lists the packages this test file uses.
 	"time"
 ) // end of imports
 
-// gearFake is a fake Ollama with two installed models and a saved-parameters text that /api/create changes like the real one did in the experiment (it replaces num_ctx and keeps every other line).
+// gearFake is a fake Ollama with two installed models and saved parameters that /api/create changes like the real one did in the experiment: only the names sent change, and a new stop list replaces the old one.
 type gearFake struct {
 	// mu protects every field below.
 	mu sync.Mutex
-	// params is the saved parameters text of every installed model (one shared text keeps the tests short).
-	params string
+	// params is the saved parameters of every installed model (one shared set keeps the tests short), in print order.
+	params []paramLine
 	// modelInfo is the model_info JSON of every installed model.
 	modelInfo string
 	// loaded lists the names /api/ps reports.
@@ -50,18 +54,103 @@ type gearFake struct {
 	createDelay time.Duration
 } // end of gearFake
 
-// newGearFake builds a fake whose model supports 131072 tokens and has one saved stop word.
+// newGearFake builds a fake whose model supports 131072 tokens and has the settings a real gemma model has saved.
 func newGearFake() *gearFake {
 	// The values.
 	return &gearFake{
-		// A stop word, formatted the way Ollama prints it (name, spaces, value).
-		params: "stop                           \"<end_of_turn>\"",
+		// Saved settings, formatted the way Ollama prints them.
+		params: []paramLine{{"temperature", "1"}, {"top_k", "64"}, {"top_p", "0.95"}, {"stop", `"<end_of_turn>"`}},
 		// The model's own facts: architecture and its limit, plus a long list that must not matter.
 		modelInfo: `{"general.architecture":"gemma3","gemma3.context_length":131072,"tokenizer.ggml.tokens":["a","b","c"]}`,
 	} // end of the values
 } // end of newGearFake
 
-// start runs the fake as a server and returns it.
+// paramsText renders the saved parameters the way /api/show prints them.
+func (f *gearFake) paramsText() string {
+	// One line each: the name, spaces, the value.
+	var lines []string
+	// Go through the parameters.
+	for _, p := range f.params {
+		// Pad the name like Ollama does.
+		lines = append(lines, fmt.Sprintf("%-31s%s", p.Name, p.Value))
+	} // end of the loop
+	// Join.
+	return strings.Join(lines, "\n")
+} // end of paramsText
+
+// saved returns the printed values of one parameter.
+func (f *gearFake) saved(name string) []string {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// Collect the values.
+	var out []string
+	// Go through the parameters.
+	for _, p := range f.params {
+		// A match.
+		if p.Name == name {
+			// Keep it.
+			out = append(out, p.Value)
+		} // end of the match check
+	} // end of the loop
+	// Hand back the list.
+	return out
+} // end of saved
+
+// apply changes the saved parameters like the real Ollama: each name sent replaces every old line of that name and the rest stay.
+func (f *gearFake) apply(body []byte) {
+	// The body shape.
+	var req struct {
+		// Parameters holds the wanted values, left raw so numbers keep their text.
+		Parameters map[string]json.RawMessage `json:"parameters"`
+	} // end of the request shape
+	// Decode it.
+	_ = json.Unmarshal(body, &req)
+	// Work in a stable order.
+	keys := make([]string, 0, len(req.Parameters))
+	// Collect the names.
+	for k := range req.Parameters {
+		// Add it.
+		keys = append(keys, k)
+	} // end of the collect
+	// Sort.
+	sort.Strings(keys)
+	// Start from the old lines, or from nothing when the fake drops them.
+	var out []paramLine
+	// Keep the lines of names that were not sent.
+	if !f.dropOthers {
+		// Go through the old lines.
+		for _, p := range f.params {
+			// Not sent: keep.
+			if _, sent := req.Parameters[p.Name]; !sent {
+				// Keep it.
+				out = append(out, p)
+			} // end of the check
+		} // end of the loop
+	} // end of the keep case
+	// Add the new values.
+	for _, k := range keys {
+		// A list becomes one quoted line per entry.
+		var list []string
+		// Try a list first.
+		if err := json.Unmarshal(req.Parameters[k], &list); err == nil {
+			// Each entry.
+			for _, w := range list {
+				// Quoted with Go's rules, like Ollama prints it.
+				out = append(out, paramLine{k, strconv.Quote(w)})
+			} // end of the entries
+			// Next name.
+			continue
+		} // end of the list case
+		// A number keeps its text.
+		out = append(out, paramLine{k, string(req.Parameters[k])})
+	} // end of the loop
+	// Store the new set.
+	f.params = out
+} // end of apply
+
+// start runs the fake as a server and returns its address.
 func (f *gearFake) start(t *testing.T) string {
 	// Mark this as a helper.
 	t.Helper()
@@ -113,7 +202,7 @@ func (f *gearFake) start(t *testing.T) string {
 				return
 			} // end of the unknown check
 			// The reply, with the parameters as one string.
-			out, _ := json.Marshal(map[string]any{"parameters": f.params, "model_info": json.RawMessage(f.modelInfo)})
+			out, _ := json.Marshal(map[string]any{"parameters": f.paramsText(), "model_info": json.RawMessage(f.modelInfo)})
 			// Send it.
 			w.Write(out)
 		// The create request.
@@ -139,36 +228,10 @@ func (f *gearFake) start(t *testing.T) string {
 				return
 			} // end of the refusal
 			// Accepted but without effect.
-			if f.ignoreCreate {
-				// Say success.
-				w.Write([]byte(`{"status":"success"}`))
-				// Stop here.
-				return
-			} // end of the ignore case
-			// Read the wanted size.
-			var req struct {
-				// Parameters holds the wanted values.
-				Parameters map[string]float64 `json:"parameters"`
-			} // end of the request shape
-			// Decode it.
-			_ = json.Unmarshal(b, &req)
-			// Keep the other lines (unless the test wants them dropped) and put the new size on top, like the real one did.
-			var lines []string
-			// The new size first.
-			lines = append(lines, fmt.Sprintf("num_ctx                        %d", int64(req.Parameters["num_ctx"])))
-			// Keep every other line.
-			if !f.dropOthers {
-				// Go through the old lines.
-				for _, l := range strings.Split(f.params, "\n") {
-					// Skip the old size line and blank lines.
-					if strings.TrimSpace(l) != "" && !strings.HasPrefix(strings.TrimSpace(l), "num_ctx") {
-						// Keep it.
-						lines = append(lines, l)
-					} // end of the skip check
-				} // end of the line loop
-			} // end of the keep case
-			// Store the new text.
-			f.params = strings.Join(lines, "\n")
+			if !f.ignoreCreate {
+				// Change the saved parameters.
+				f.apply(b)
+			} // end of the effect
 			// Say success.
 			w.Write([]byte(`{"status":"success"}`))
 		// Anything else is a load or unload request or unknown.
@@ -222,16 +285,224 @@ func gearRig(t *testing.T, f *gearFake) themeRig {
 	return themeRig{h: h, token: m[1]}
 } // end of gearRig
 
-// gearPost sends a form to one of the three settings routes as the page's own form would.
-func gearPost(t *testing.T, rig themeRig, path, model, size string) (int, string, http.Header) {
+// gearPost sends a form to one of the three settings routes as the page's own form would; pairs are field name, value, field name, value, and so on (a name may repeat).
+func gearPost(t *testing.T, rig themeRig, path, model string, pairs ...string) (int, string, http.Header) {
 	// Mark this as a helper.
 	t.Helper()
+	// The form with the token and the model.
+	form := url.Values{"token": {rig.token}, "model": {model}}
+	// Add the pairs.
+	for i := 0; i+1 < len(pairs); i += 2 {
+		// Add one field.
+		form.Add(pairs[i], pairs[i+1])
+	} // end of the loop
 	// Send it.
-	res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {model}, "num_ctx": {size}}, fromThisPage)
+	res := post(t, rig.h, path, form, fromThisPage)
 	// Hand back status, body and headers.
 	return res.StatusCode, bodyOf(res), res.Header
 } // end of gearPost
 
+// TestSettingSpecsAreSound checks the table of ten settings: unique names, the expected order, and sensible limits.
+func TestSettingSpecsAreSound(t *testing.T) {
+	// The expected names in order.
+	want := []string{"num_ctx", "temperature", "top_k", "top_p", "min_p", "repeat_penalty", "repeat_last_n", "seed", "num_predict", "stop"}
+	// The count.
+	if len(settingSpecs) != len(want) {
+		// Report the problem.
+		t.Fatalf("%d settings, want %d", len(settingSpecs), len(want))
+	} // end of the count check
+	// Go through them.
+	for i, s := range settingSpecs {
+		// The name and order.
+		if s.Key != want[i] {
+			// Report the problem.
+			t.Errorf("setting %d is %q, want %q", i, s.Key, want[i])
+		} // end of the name check
+		// Every setting has a default text and a heading.
+		if s.Default == "" || s.Heading == "" {
+			// Report the problem.
+			t.Errorf("%s lacks a default or a heading", s.Key)
+		} // end of the text check
+		// A fixed range must be a real range.
+		if s.Kind != kindList && !s.FromModel && !(s.Min < s.Max) {
+			// Report the problem.
+			t.Errorf("%s has the range %v to %v", s.Key, s.Min, s.Max)
+		} // end of the range check
+		// A model-dependent setting needs the model maximum.
+		if _, _, ok := s.limits(0); ok == s.FromModel {
+			// Report the problem.
+			t.Errorf("%s: limits without a model maximum ok=%v", s.Key, ok)
+		} // end of the limit check
+		// The heading has a help text.
+		if _, ok := helpFor(s.Heading); !ok {
+			// Report the problem.
+			t.Errorf("%s has no help text", s.Heading)
+		} // end of the help check
+	} // end of the loop
+} // end of TestSettingSpecsAreSound
+
+// TestParseNumber checks the rules for typed numbers, setting by setting.
+func TestParseNumber(t *testing.T) {
+	// A helper to find a spec.
+	spec := func(key string) settingSpec {
+		// Look it up.
+		s, ok := specByKey(key)
+		// A test bug if missing.
+		if !ok {
+			// Stop.
+			t.Fatalf("no spec %s", key)
+		} // end of the check
+		// Hand back.
+		return s
+	} // end of spec
+	// The cases: setting, typed text, whether accepted, and the number.
+	cases := []struct {
+		// key is the setting.
+		key string
+		// in is what was typed.
+		in string
+		// ok says whether it is accepted.
+		ok bool
+		// n is the expected number.
+		n float64
+	}{
+		// The context size: limits 512 and the model maximum 131072.
+		{"num_ctx", "512", true, 512}, {"num_ctx", "131072", true, 131072}, {"num_ctx", " 8192 ", true, 8192}, {"num_ctx", "511", false, 0}, {"num_ctx", "131073", false, 0}, {"num_ctx", "8192.5", false, 0}, {"num_ctx", "-8192", false, 0}, {"num_ctx", "1e5", false, 0}, {"num_ctx", "+8192", false, 0}, {"num_ctx", "８１９２", false, 0}, {"num_ctx", "0x2000", false, 0},
+		// Temperature 0 to 2.
+		{"temperature", "0", true, 0}, {"temperature", "0.2", true, 0.2}, {"temperature", "2", true, 2}, {"temperature", "2.01", false, 0}, {"temperature", "-0.1", false, 0}, {"temperature", ".5", false, 0}, {"temperature", "1.", false, 0}, {"temperature", "1.2.3", false, 0}, {"temperature", "abc", false, 0}, {"temperature", "0,5", false, 0}, {"temperature", "NaN", false, 0}, {"temperature", "Inf", false, 0},
+		// Top-k 1 to 1000, whole numbers.
+		{"top_k", "1", true, 1}, {"top_k", "1000", true, 1000}, {"top_k", "0", false, 0}, {"top_k", "1001", false, 0}, {"top_k", "40.5", false, 0},
+		// Top-p 0.01 to 1.
+		{"top_p", "0.01", true, 0.01}, {"top_p", "1", true, 1}, {"top_p", "0", false, 0}, {"top_p", "1.5", false, 0},
+		// Min-p 0 to 1.
+		{"min_p", "0", true, 0}, {"min_p", "0.05", true, 0.05}, {"min_p", "1.01", false, 0},
+		// Repeat penalty 0.5 to 2.
+		{"repeat_penalty", "0.5", true, 0.5}, {"repeat_penalty", "1.1", true, 1.1}, {"repeat_penalty", "2", true, 2}, {"repeat_penalty", "0.4", false, 0}, {"repeat_penalty", "2.1", false, 0},
+		// Repeat window -1 to the model maximum.
+		{"repeat_last_n", "-1", true, -1}, {"repeat_last_n", "0", true, 0}, {"repeat_last_n", "64", true, 64}, {"repeat_last_n", "-2", false, 0}, {"repeat_last_n", "131073", false, 0}, {"repeat_last_n", "--1", false, 0}, {"repeat_last_n", "1-", false, 0},
+		// Seed 0 to 2147483647.
+		{"seed", "0", true, 0}, {"seed", "42", true, 42}, {"seed", "2147483647", true, 2147483647}, {"seed", "2147483648", false, 0}, {"seed", "-1", false, 0},
+		// Answer length: -1, or 1 and up; never 0.
+		{"num_predict", "-1", true, -1}, {"num_predict", "512", true, 512}, {"num_predict", "0", false, 0}, {"num_predict", "-2", false, 0}, {"num_predict", "131073", false, 0},
+		// Too long to read.
+		{"temperature", "0.00000000000000000000001", false, 0}, {"top_k", strings.Repeat("9", 400), false, 0},
+	} // end of the case table
+	// Go through the cases.
+	for _, c := range cases {
+		// Check it against a model that supports 131072.
+		n, problem := spec(c.key).parseNumber(c.in, 131072)
+		// Compare.
+		if (problem == "") != c.ok || n != c.n {
+			// Cut a long input for the report.
+			in := c.in
+			// Cut it.
+			if len(in) > 30 {
+				// Keep the start.
+				in = in[:30]
+			} // end of the cut
+			// Report.
+			t.Errorf("%s %q: got (%v, %q), want ok=%v n=%v", c.key, in, n, problem, c.ok, c.n)
+		} // end of the compare
+	} // end of the case loop
+	// Without a known model maximum the three model-dependent settings refuse everything.
+	for _, key := range []string{"num_ctx", "repeat_last_n", "num_predict"} {
+		// Try a normal value.
+		if _, problem := spec(key).parseNumber("64", 0); problem == "" {
+			// Report the problem.
+			t.Errorf("%s accepted a value without a known model maximum", key)
+		} // end of the check
+	} // end of the loop
+} // end of TestParseNumber
+
+// TestParseStopWords checks the rules for the stop word box.
+func TestParseStopWords(t *testing.T) {
+	// Good input: lines, Windows line breaks, blank lines skipped, inner spaces and quotes kept.
+	got, problem := parseStopWords("AAA\r\n\r\na b\nsay \"hi\"\nback\\slash\n")
+	// It must be accepted and exact.
+	if problem != "" || fmt.Sprintf("%q", got) != `["AAA" "a b" "say \"hi\"" "back\\slash"]` {
+		// Report the problem.
+		t.Errorf("good input: %q %q", got, problem)
+	} // end of the good check
+	// Bad input.
+	for name, in := range map[string]string{
+		// A control character.
+		"tab": "a\tb",
+		// A bell.
+		"bell": "a\x07b",
+		// Invalid UTF-8.
+		"utf8": "a\xffb",
+		// Too many.
+		"nine": "1\n2\n3\n4\n5\n6\n7\n8\n9",
+		// A repeat.
+		"repeat": "AAA\nAAA",
+		// Too long a word.
+		"long": strings.Repeat("x", 101),
+		// Far too much text.
+		"huge": strings.Repeat("x\n", 2000),
+	} { // end of the bad map
+		// Check it.
+		if _, problem := parseStopWords(in); problem == "" {
+			// Report the problem.
+			t.Errorf("%s was accepted", name)
+		} // end of the check
+	} // end of the loop
+	// Exactly the limits are fine.
+	if _, problem := parseStopWords(strings.Repeat("x", 100) + "\n2\n3\n4\n5\n6\n7\n8"); problem != "" {
+		// Report the problem.
+		t.Errorf("the limits were refused: %q", problem)
+	} // end of the limit check
+} // end of TestParseStopWords
+
+// TestReadSavedAndCompare checks how saved text is read, in every format seen on the real Ollama, and how values are compared.
+func TestReadSavedAndCompare(t *testing.T) {
+	// The specs.
+	temp, _ := specByKey("temperature")
+	// The stop words.
+	stop, _ := specByKey("stop")
+	// A normal number.
+	if v, present, ok := readSaved(temp, []string{"0.2"}); !present || !ok || v.Num != 0.2 {
+		// Report the problem.
+		t.Errorf("0.2 -> %v %v %v", v, present, ok)
+	} // end of the number check
+	// Ollama printed a big number like this.
+	if v, _, ok := readSaved(temp, []string{"1e+08"}); !ok || v.Num != 1e8 {
+		// Report the problem.
+		t.Errorf("1e+08 -> %v %v", v, ok)
+	} // end of the exponent check
+	// Text instead of a number: present but unreadable.
+	if _, present, ok := readSaved(temp, []string{`"abc"`}); !present || ok {
+		// Report the problem.
+		t.Errorf("text value: present=%v readable=%v", present, ok)
+	} // end of the text check
+	// Nothing saved.
+	if _, present, _ := readSaved(temp, nil); present {
+		// Report the problem.
+		t.Errorf("nothing saved was reported as saved")
+	} // end of the nothing check
+	// The last line of a number wins.
+	if v, _, _ := readSaved(temp, []string{"1", "2"}); v.Num != 2 {
+		// Report the problem.
+		t.Errorf("last line did not win: %v", v)
+	} // end of the last-wins check
+	// Quoted stop words are unquoted, including escapes.
+	v, _, _ := readSaved(stop, []string{`"a b"`, `"say \"hi\""`, `"back\\slash"`})
+	// Check.
+	if fmt.Sprintf("%q", v.List) != `["a b" "say \"hi\"" "back\\slash"]` {
+		// Report the problem.
+		t.Errorf("stop words -> %q", v.List)
+	} // end of the stop check
+	// Lists compare without regard to order.
+	if !(settingValue{List: []string{"a", "b"}}).equal(settingValue{List: []string{"b", "a"}}, stop) {
+		// Report the problem.
+		t.Errorf("order mattered")
+	} // end of the order check
+	// Different lists differ.
+	if (settingValue{List: []string{"a"}}).equal(settingValue{List: []string{"a", "b"}}, stop) {
+		// Report the problem.
+		t.Errorf("different lists were equal")
+	} // end of the difference check
+} // end of TestReadSavedAndCompare
+
 // TestParseParams checks the parameters text is split into names and values, the way Ollama prints it.
 func TestParseParams(t *testing.T) {
 	// The real format: the name, many spaces, the value; blank lines appear too.
@@ -258,48 +529,6 @@ func TestParseParams(t *testing.T) {
 	} // end of the empty check
 } // end of TestParseParams
 
-// TestSavedContext checks the saved size is read from every format Ollama was seen to print.
-func TestSavedContext(t *testing.T) {
-	// The cases: text, then the expected text, number and presence.
-	cases := []struct {
-		// name for the report.
-		name string
-		// in is the parameters text.
-		in string
-		// text is the expected value text.
-		text string
-		// n is the expected number.
-		n int64
-		// present is the expected presence.
-		present bool
-	}{
-		// Nothing saved.
-		{"none", "stop \"x\"", "", 0, false},
-		// A plain number.
-		{"plain", "num_ctx   8192", "8192", 8192, true},
-		// Ollama printed a big number like this in the experiment.
-		{"exponent", "num_ctx   1e+08", "1e+08", 100000000, true},
-		// Text instead of a number.
-		{"garbage", "num_ctx   lots", "lots", 0, true},
-		// A decimal is not a size.
-		{"decimal", "num_ctx   8192.5", "8192.5", 0, true},
-		// Zero is not a size.
-		{"zero", "num_ctx   0", "0", 0, true},
-		// The last line wins.
-		{"twice", "num_ctx 4096\nnum_ctx 8192", "8192", 8192, true},
-	} // end of the case table
-	// Go through the cases.
-	for _, c := range cases {
-		// Read it.
-		text, n, present := savedContext(parseParams(c.in))
-		// Compare.
-		if text != c.text || n != c.n || present != c.present {
-			// Report the difference.
-			t.Errorf("%s: got (%q, %d, %v), want (%q, %d, %v)", c.name, text, n, present, c.text, c.n, c.present)
-		} // end of the compare
-	} // end of the case loop
-} // end of TestSavedContext
-
 // TestModelMaxContext checks the model maximum is read from the architecture key, or from a single other key, and never guessed.
 func TestModelMaxContext(t *testing.T) {
 	// A helper that builds the map from JSON.
@@ -357,49 +586,6 @@ func TestModelMaxContext(t *testing.T) {
 	} // end of the nil check
 } // end of TestModelMaxContext
 
-// TestValidateContext checks every rule for the typed size, including the ones that keep a saved value from being emptied.
-func TestValidateContext(t *testing.T) {
-	// The cases: typed text and whether it is accepted.
-	cases := []struct {
-		// in is what was typed.
-		in string
-		// n is the expected number when accepted.
-		n int64
-		// ok says whether it is accepted.
-		ok bool
-	}{
-		// The smallest and the largest allowed values, and normal ones.
-		{"512", 512, true}, {"8192", 8192, true}, {"131072", 131072, true}, {"  8192  ", 8192, true}, {"0008192", 8192, true},
-		// Empty and blank: never allowed.
-		{"", 0, false}, {"   ", 0, false},
-		// Outside the range.
-		{"511", 0, false}, {"131073", 0, false}, {"0", 0, false},
-		// Not a plain whole number.
-		{"-8192", 0, false}, {"+8192", 0, false}, {"8192.0", 0, false}, {"8,192", 0, false}, {"1e4", 0, false}, {"0x2000", 0, false}, {"abc", 0, false}, {"８１９２", 0, false}, {"٨١٩٢", 0, false}, {"8 192", 0, false},
-		// Far too long.
-		{"99999999999999999999", 0, false}, {strings.Repeat("9", 400), 0, false},
-		// Markup.
-		{"<script>alert(1)</script>", 0, false},
-	} // end of the case table
-	// Go through the cases.
-	for _, c := range cases {
-		// Check it against a model that supports 131072.
-		n, problem := validateContext(c.in, minContext, 131072)
-		// Compare.
-		if (problem == "") != c.ok || n != c.n {
-			// Report the difference (the input is cut so a long one does not flood the report).
-			in := c.in
-			// Cut it.
-			if len(in) > 30 {
-				// Keep the start.
-				in = in[:30]
-			} // end of the cut
-			// Report.
-			t.Errorf("%q: got (%d, %q), want ok=%v n=%d", in, n, problem, c.ok, c.n)
-		} // end of the compare
-	} // end of the case loop
-} // end of TestValidateContext
-
 // TestContextPresets checks the suggestions stay inside the range, in order, and always include the maximum.
 func TestContextPresets(t *testing.T) {
 	// A model that supports 131072: the powers of two up to it.
@@ -429,14 +615,14 @@ func TestContextPresets(t *testing.T) {
 	} // end of the compare
 } // end of TestContextPresets
 
-// TestGearShowsSettings checks the settings page: the facts, the form with its limits and suggestions, the help bubbles, no script, and nothing changed.
+// TestGearShowsSettings checks the settings page: all ten settings with defaults and saved values, the fields with their limits, the help bubbles, no script, and nothing changed.
 func TestGearShowsSettings(t *testing.T) {
-	// A fake with no saved size.
+	// A fake with the settings a real gemma model has saved.
 	f := newGearFake()
 	// Build the rig.
 	rig := gearRig(t, f)
 	// Open the settings of the first model.
-	status, body, header := gearPost(t, rig, "/gear", "alpha:1b", "")
+	status, body, header := gearPost(t, rig, "/gear", "alpha:1b")
 	// It must load.
 	if status != http.StatusOK {
 		// Stop the test.
@@ -446,24 +632,21 @@ func TestGearShowsSettings(t *testing.T) {
 	for _, want := range []string{
 		// The heading names the model.
 		"Settings for <code>alpha:1b</code>",
-		// Nothing is saved yet.
-		"not saved in the model",
-		// The model's own limit.
-		"131072 tokens",
-		// The smallest allowed value.
-		"512 tokens",
-		// The other saved setting is shown, and escaped.
-		"stop &#34;&lt;end_of_turn&gt;&#34;",
 		// The form goes to the review step.
 		`action="/gear/review"`,
-		// The field has the limits and cannot be left empty.
-		`min="512" max="131072" step="1" required`,
-		// The suggestions.
+		// The saved values appear in the Saved column.
+		`">1</td>`, `">64</td>`, `">0.95</td>`, `">&#34;&lt;end_of_turn&gt;&#34;</td>`,
+		// Settings with nothing saved say so.
+		`">not saved</td>`,
+		// Ollama's defaults.
+		"automatic (docs: 2048)", `">0.8</td>`, `">40</td>`, `">0.9</td>`, "0 (off)", "1 (off)", `">64</td>`, "-1 (no limit)", `">none</td>`,
+		// The allowed values.
+		"512 to 131072", "0 to 2", "1 to 1000", "0.01 to 1", "0.5 to 2", "-1 to 131072", "0 to 2147483647", "-1, or 1 to 131072", "up to 8 words",
+		// The context size has suggestions.
 		`<option value="8192">`,
 		// The rule about removing.
-		"cannot be removed, only changed",
-		// The five help bubbles, each with the three standard parts.
-		`aria-describedby="tip-gear-ctx"`, `aria-describedby="tip-gear-max"`, `aria-describedby="tip-gear-min"`, `aria-describedby="tip-gear-saved"`, `aria-describedby="tip-gear-other"`,
+		"never emptied",
+		// The help bubbles, each with the three standard parts.
 		"In plain words:", "Example:", "Helps you decide:",
 	} { // end of the list
 		// Look for it.
@@ -472,6 +655,24 @@ func TestGearShowsSettings(t *testing.T) {
 			t.Errorf("page lacks %q", want)
 		} // end of the check
 	} // end of the loop
+	// Every setting has a field and a help bubble.
+	for _, s := range settingSpecs {
+		// The field.
+		if !strings.Contains(body, `name="s_`+s.Key+`"`) || !strings.Contains(body, `aria-describedby="tip-gear-`+s.Key+`"`) {
+			// Report the gap.
+			t.Errorf("no field or bubble for %s", s.Key)
+		} // end of the check
+	} // end of the loop
+	// Saved settings must not be emptiable in the browser, and unsaved ones may be left empty.
+	if !regexp.MustCompile(`name="s_temperature"[^>]*value="1" required`).MatchString(body) || regexp.MustCompile(`name="s_min_p"[^>]*required`).MatchString(body) {
+		// Report the problem.
+		t.Errorf("the required flags are wrong")
+	} // end of the required check
+	// The number fields carry the limits for the browser.
+	if !regexp.MustCompile(`name="s_temperature" type="number" inputmode="decimal" min="0" max="2" step="any"`).MatchString(body) || !regexp.MustCompile(`name="s_top_k" type="number" inputmode="decimal" min="1" max="1000" step="1"`).MatchString(body) {
+		// Report the problem.
+		t.Errorf("the browser limits are wrong")
+	} // end of the limit check
 	// No script and the strict policy.
 	if strings.Contains(body, "<script") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
 		// Report the problem.
@@ -484,22 +685,29 @@ func TestGearShowsSettings(t *testing.T) {
 	} // end of the change check
 } // end of TestGearShowsSettings
 
-// TestGearPrefillsSavedValue checks the field starts with the saved size, so it is never blank.
-func TestGearPrefillsSavedValue(t *testing.T) {
-	// A fake with 4096 saved.
+// TestGearListsUnknownSavedSettings checks a saved setting this page does not edit is listed and kept.
+func TestGearListsUnknownSavedSettings(t *testing.T) {
+	// A fake with an extra saved setting.
 	f := newGearFake()
-	// The saved text.
-	f.params = "num_ctx                        4096\n" + f.params
+	// Add it.
+	f.params = append(f.params, paramLine{"mirostat", "2"})
 	// Build the rig.
 	rig := gearRig(t, f)
 	// Open the settings.
-	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
-	// The field value and the facts.
-	if !strings.Contains(body, `required value="4096"`) || !strings.Contains(body, "<td>4096</td>") {
-		// Report the gap.
-		t.Errorf("the saved value is not shown or pre-filled")
+	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
+	// It is listed, once.
+	if !strings.Contains(body, "kept as they are: <code>mirostat 2</code>") {
+		// Report the problem.
+		t.Errorf("the extra setting is not listed")
+	} // end of the check
+	// Saving another setting keeps it.
+	gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
+	// Still there.
+	if got := f.saved("mirostat"); len(got) != 1 || got[0] != "2" {
+		// Report the problem.
+		t.Errorf("mirostat is now %v", got)
 	} // end of the check
-} // end of TestGearPrefillsSavedValue
+} // end of TestGearListsUnknownSavedSettings
 
 // TestGearRefusesLoadedModel checks a loaded model gets no form on any of the three steps, and nothing is saved.
 func TestGearRefusesLoadedModel(t *testing.T) {
@@ -511,8 +719,8 @@ func TestGearRefusesLoadedModel(t *testing.T) {
 	rig := gearRig(t, f)
 	// All three steps.
 	for _, path := range []string{"/gear", "/gear/review", "/gear/save"} {
-		// Send a valid size.
-		status, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
+		// Send a valid value.
+		status, body, _ := gearPost(t, rig, path, "alpha:1b", "s_temperature", "0.2")
 		// The page explains and offers no form.
 		if status != http.StatusOK || !strings.Contains(body, "Unload it first") || strings.Contains(body, `action="/gear/`) {
 			// Report the problem.
@@ -535,7 +743,7 @@ func TestGearNotInstalled(t *testing.T) {
 	// All three steps with a made-up name.
 	for _, path := range []string{"/gear", "/gear/review", "/gear/save"} {
 		// Send it.
-		_, body, _ := gearPost(t, rig, path, "ghost:1b", "8192")
+		_, body, _ := gearPost(t, rig, path, "ghost:1b", "s_temperature", "0.2")
 		// The page says so.
 		if !strings.Contains(body, "not installed") {
 			// Report the problem.
@@ -549,101 +757,184 @@ func TestGearNotInstalled(t *testing.T) {
 	} // end of the change check
 } // end of TestGearNotInstalled
 
-// TestGearRejectsBadValues checks every bad value is refused on the review step and on the save step, shown back escaped, and never reaches Ollama.
+// TestGearRejectsBadValues checks every bad value of every setting is refused on the review step and on the save step, shown back escaped with a reason, and never reaches Ollama.
 func TestGearRejectsBadValues(t *testing.T) {
-	// A fake with 4096 saved, so "emptying" would mean losing something.
+	// A fake where seed and num_ctx are saved too, so "emptying" would mean losing something.
 	f := newGearFake()
-	// The saved text.
-	f.params = "num_ctx                        4096\n" + f.params
+	// Add saved values.
+	f.params = append(f.params, paramLine{"num_ctx", "4096"}, paramLine{"seed", "42"}, paramLine{"num_predict", "512"})
 	// Build the rig.
 	rig := gearRig(t, f)
-	// The bad values.
-	for _, bad := range []string{"", "   ", "abc", "-5", "0", "511", "131073", "8192.5", "1e5", "+8192", "８１９２", "99999999999999999999", "<script>alert(1)</script>"} {
-		// Both steps.
-		for _, path := range []string{"/gear/review", "/gear/save"} {
-			// Send it.
-			status, body, _ := gearPost(t, rig, path, "alpha:1b", bad)
-			// The settings page comes back with the reason, and no confirm button.
-			if status != http.StatusOK || !strings.Contains(body, "Not saved.") || strings.Contains(body, "Yes, save it into the model") {
-				// Report the problem.
-				t.Errorf("%s %q: status %d", path, bad, status)
-			} // end of the check
-			// An empty value gets its own, clear reason.
-			if strings.TrimSpace(bad) == "" && !strings.Contains(body, "cannot be empty") {
-				// Report the problem.
-				t.Errorf("%s %q: no 'cannot be empty' reason", path, bad)
-			} // end of the empty check
-			// Markup must come back escaped.
-			if strings.Contains(body, "<script>alert") {
-				// Report the problem.
-				t.Errorf("%s: unescaped markup in the page", path)
-			} // end of the escape check
-		} // end of the path loop
-	} // end of the value loop
+	// The bad values for each setting.
+	bad := map[string][]string{
+		// Context size.
+		"num_ctx": {"", "   ", "abc", "-5", "0", "511", "131073", "8192.5", "1e5", "+8192", "８１９２", "99999999999999999999", "<script>alert(1)</script>"},
+		// Temperature (saved).
+		"temperature": {"", "3", "-1", "x", "1,5", "NaN", "<b>"},
+		// Top-k (saved).
+		"top_k": {"", "0", "1.5", "5000"},
+		// Top-p (saved).
+		"top_p": {"", "0", "2"},
+		// Min-p (not saved): an empty field is fine, so only wrong values.
+		"min_p": {"2", "-0.5", "x"},
+		// Repeat penalty (not saved).
+		"repeat_penalty": {"0.1", "9"},
+		// Repeat window (not saved).
+		"repeat_last_n": {"-5", "9999999"},
+		// Seed (saved).
+		"seed": {"", "-1", "99999999999"},
+		// Answer length (saved).
+		"num_predict": {"", "0", "-2", "x"},
+		// Stop words (saved).
+		"stop": {"", "   \n  ", "a\tb", "1\n2\n3\n4\n5\n6\n7\n8\n9", "AAA\nAAA"},
+	} // end of the bad values
+	// Go through the settings.
+	for key, values := range bad {
+		// Go through the values.
+		for _, v := range values {
+			// Both steps.
+			for _, path := range []string{"/gear/review", "/gear/save"} {
+				// Send it.
+				status, body, _ := gearPost(t, rig, path, "alpha:1b", "s_"+key, v)
+				// The settings page comes back with the reason, and no confirm button.
+				if status != http.StatusOK || !strings.Contains(body, "Not saved.") || !strings.Contains(body, `role="alert"><strong>⚠</strong>`) || strings.Contains(body, "Yes, save them into the model") {
+					// Report the problem.
+					t.Errorf("%s %s %q: status %d", path, key, v, status)
+				} // end of the check
+				// An empty value of a saved setting gets its own, clear reason.
+				if strings.TrimSpace(v) == "" && !strings.Contains(body, "cannot be empty") {
+					// Report the problem.
+					t.Errorf("%s %s %q: no 'cannot be empty' reason", path, key, v)
+				} // end of the empty check
+				// Markup must come back escaped.
+				if strings.Contains(body, "<script>alert") || strings.Contains(body, "<b>") {
+					// Report the problem.
+					t.Errorf("%s %s: unescaped markup in the page", path, key)
+				} // end of the escape check
+			} // end of the path loop
+		} // end of the value loop
+	} // end of the setting loop
+	// One bad value blocks the good ones next to it.
+	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2", "s_top_k", "0")
+	// Nothing is saved.
+	if !strings.Contains(body, "Not saved.") {
+		// Report the problem.
+		t.Errorf("a good value was saved next to a bad one")
+	} // end of the mixed check
 	// Nothing reached Ollama.
 	if f.createCount() != 0 {
 		// Report the problem.
 		t.Errorf("a bad value was sent to Ollama")
 	} // end of the change check
-	// The saved value is untouched.
-	if _, n, _ := savedContext(parseParams(f.params)); n != 4096 {
+	// The saved values are untouched.
+	if got := f.saved("num_ctx"); len(got) != 1 || got[0] != "4096" {
 		// Report the problem.
-		t.Errorf("the saved size changed to %d", n)
+		t.Errorf("the saved size changed to %v", got)
 	} // end of the saved check
 } // end of TestGearRejectsBadValues
 
-// TestGearReviewThenSave checks the two-step flow: the review changes nothing, the save sends exactly one precise create request and then verifies.
+// TestGearEmptyUnsavedIsFine checks an unsaved setting left empty is not an error and not a change.
+func TestGearEmptyUnsavedIsFine(t *testing.T) {
+	// A fake.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Empty fields for settings that are not saved.
+	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "s_min_p", "", "s_seed", "  ", "s_stop_nothing", "x")
+	// It is "nothing to change", not an error.
+	if status != http.StatusOK || !strings.Contains(body, "Nothing to change") || strings.Contains(body, "Not saved.") {
+		// Report the problem.
+		t.Errorf("status %d, body %q", status, body)
+	} // end of the check
+} // end of TestGearEmptyUnsavedIsFine
+
+// TestGearReviewThenSave checks the two-step flow with several settings: the review changes nothing and lists only the changes, the save sends exactly one precise create request with only the changed names, and then verifies.
 func TestGearReviewThenSave(t *testing.T) {
-	// A fake with no saved size.
+	// A fake with the gemma-like settings.
 	f := newGearFake()
 	// Build the rig.
 	rig := gearRig(t, f)
+	// The typed form: a changed context size, temperature, top-k, new stop words, an unchanged top-p, and an empty unsaved field.
+	typed := []string{"s_num_ctx", "8192", "s_temperature", "0.2", "s_top_k", "40", "s_top_p", "0.95", "s_min_p", "", "s_stop", "AAA\r\nBBB"}
 	// Step 2: review.
-	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "8192")
+	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", typed...)
 	// The confirmation page with the values to be saved.
-	for _, want := range []string{"This changes the model itself", "not saved in the model", "<strong>8192</strong>", `action="/gear/save"`, `name="num_ctx" value="8192"`, "Yes, save it into the model", "Cancel, do not change"} {
+	for _, want := range []string{"This changes the model itself", "<th scope=\"row\">Context size</th><td>not saved</td><td><strong>8192</strong></td>", "<th scope=\"row\">Temperature</th><td>1</td><td><strong>0.2</strong></td>", "<th scope=\"row\">Top-k</th><td>64</td><td><strong>40</strong></td>", `<strong>&#34;AAA&#34;, &#34;BBB&#34;</strong>`, `action="/gear/save"`, `name="s_stop" value="AAA"`, `name="s_stop" value="BBB"`, `name="s_num_ctx" value="8192"`, "Yes, save them into the model", "Cancel, do not change"} {
 		// Look for it.
 		if status != http.StatusOK || !strings.Contains(body, want) {
 			// Report the gap.
 			t.Errorf("review page lacks %q (status %d)", want, status)
 		} // end of the check
 	} // end of the loop
+	// The unchanged top-p is not listed.
+	if strings.Contains(body, "Top-p</th>") && strings.Contains(body, `name="s_top_p"`) {
+		// Report the problem.
+		t.Errorf("an unchanged setting is listed")
+	} // end of the unchanged check
 	// The review changed nothing.
 	if f.createCount() != 0 {
 		// Report the problem.
 		t.Fatalf("the review step sent a create request")
 	} // end of the review check
-	// Step 3: save.
-	status, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+	// Step 3: save, with the values the review page passes on (only the changes).
+	status, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "s_num_ctx", "8192", "s_stop", "AAA", "s_stop", "BBB", "s_temperature", "0.2", "s_top_k", "40")
 	// The result page.
 	if status != http.StatusOK || !strings.Contains(body, "<strong>Saved.</strong>") || !strings.Contains(body, "8192") {
 		// Report the problem.
 		t.Errorf("save page: status %d, body %q", status, body)
 	} // end of the result check
-	// Exactly one create request, with exactly the expected body (keys are sorted by Go's JSON writer).
-	if len(f.creates) != 1 || f.creates[0] != `{"from":"alpha:1b","model":"alpha:1b","parameters":{"num_ctx":8192},"stream":false}` {
+	// Exactly one create request, with only the changed names (keys are sorted by Go's JSON writer).
+	if len(f.creates) != 1 || f.creates[0] != `{"from":"alpha:1b","model":"alpha:1b","parameters":{"num_ctx":8192,"stop":["AAA","BBB"],"temperature":0.2,"top_k":40},"stream":false}` {
 		// Report the problem.
 		t.Errorf("create requests: %v", f.creates)
 	} // end of the create check
-	// The other saved parameter is still there.
-	if !strings.Contains(f.params, "end_of_turn") {
+	// The untouched setting is still there, and the old stop word is gone (a new list replaces the old one).
+	if got := f.saved("top_p"); len(got) != 1 || got[0] != "0.95" {
 		// Report the problem.
-		t.Errorf("the stop word was lost: %q", f.params)
+		t.Errorf("top_p is now %v", got)
 	} // end of the other-parameter check
+	// The stop words are the new ones.
+	if got := f.saved("stop"); fmt.Sprint(got) != `["AAA" "BBB"]` {
+		// Report the problem.
+		t.Errorf("stop words are now %v", got)
+	} // end of the stop check
 } // end of TestGearReviewThenSave
 
-// TestGearSameValueChangesNothing checks that saving the value that is already saved sends nothing (this is also what a second click on Yes does).
+// TestGearSpecialValuesRoundTrip checks the special values and awkward stop words survive a save and the check afterwards.
+func TestGearSpecialValuesRoundTrip(t *testing.T) {
+	// A fake.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Special numbers and stop words with a space, a quote and a backslash.
+	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_num_predict", "-1", "s_repeat_last_n", "-1", "s_seed", "0", "s_temperature", "0", "s_top_p", "1", "s_stop", "a b\nsay \"hi\"\nback\\slash")
+	// It must succeed.
+	if !strings.Contains(body, "<strong>Saved.</strong>") {
+		// Report the problem.
+		t.Fatalf("save failed: %q", body)
+	} // end of the result check
+	// The request has whole numbers as whole numbers.
+	if len(f.creates) != 1 || !strings.Contains(f.creates[0], `"num_predict":-1`) || !strings.Contains(f.creates[0], `"repeat_last_n":-1`) || !strings.Contains(f.creates[0], `"seed":0`) || !strings.Contains(f.creates[0], `"stop":["a b","say \"hi\"","back\\slash"]`) {
+		// Report the problem.
+		t.Errorf("create requests: %v", f.creates)
+	} // end of the request check
+	// The fake printed the stop words quoted; the saved list has three.
+	if got := f.saved("stop"); len(got) != 3 {
+		// Report the problem.
+		t.Errorf("stop lines: %v", got)
+	} // end of the stop check
+} // end of TestGearSpecialValuesRoundTrip
+
+// TestGearSameValueChangesNothing checks that saving values that are already saved sends nothing (this is also what a second click on Yes does).
 func TestGearSameValueChangesNothing(t *testing.T) {
-	// A fake with 8192 saved.
+	// A fake.
 	f := newGearFake()
-	// The saved text.
-	f.params = "num_ctx                        8192\n" + f.params
 	// Build the rig.
 	rig := gearRig(t, f)
-	// Both steps.
+	// Both steps, with the saved values, also written differently (1.0 is 1).
 	for _, path := range []string{"/gear/review", "/gear/save"} {
-		// Send the same value.
-		_, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
+		// Send the same values.
+		_, body, _ := gearPost(t, rig, path, "alpha:1b", "s_temperature", "1.0", "s_top_k", "64", "s_stop", "<end_of_turn>")
 		// The page says nothing changes.
 		if !strings.Contains(body, "Nothing to change") {
 			// Report the problem.
@@ -667,8 +958,8 @@ func TestGearVerifiesTheResult(t *testing.T) {
 		f.ignoreCreate, f.dropOthers = mode == "ignore", mode == "drop"
 		// Build the rig.
 		rig := gearRig(t, f)
-		// Save a size.
-		_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+		// Save a value.
+		_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
 		// The page must not claim success.
 		if strings.Contains(body, "<strong>Saved.</strong>") || !strings.Contains(body, "Please check") {
 			// Report the problem.
@@ -685,8 +976,8 @@ func TestGearCreateRefused(t *testing.T) {
 	f.createStatus, f.createMsg = http.StatusInternalServerError, "disk <full>"
 	// Build the rig.
 	rig := gearRig(t, f)
-	// Save a size.
-	status, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+	// Save a value.
+	status, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
 	// The page says what happened.
 	if status != http.StatusBadGateway || !strings.Contains(body, "status 500") || !strings.Contains(body, "disk &lt;full&gt;") || strings.Contains(body, "<strong>Saved.</strong>") {
 		// Report the problem.
@@ -701,14 +992,14 @@ func TestGearModelLoadedBetweenReviewAndSave(t *testing.T) {
 	// Build the rig.
 	rig := gearRig(t, f)
 	// The review step is fine.
-	if _, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "8192"); !strings.Contains(body, "Yes, save it into the model") {
+	if _, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "s_temperature", "0.2"); !strings.Contains(body, "Yes, save them into the model") {
 		// Stop the test.
 		t.Fatalf("no review page")
 	} // end of the review check
 	// Someone loads the model now.
 	f.setLoaded("alpha:1b")
 	// The save step.
-	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
 	// It must refuse.
 	if !strings.Contains(body, "Unload it first") || f.createCount() != 0 {
 		// Report the problem.
@@ -716,7 +1007,7 @@ func TestGearModelLoadedBetweenReviewAndSave(t *testing.T) {
 	} // end of the check
 } // end of TestGearModelLoadedBetweenReviewAndSave
 
-// TestGearUnknownMaximum checks that without a known model maximum nothing can be saved, on any step.
+// TestGearUnknownMaximum checks that without a known model maximum the three settings that depend on it cannot be changed, while the others still can.
 func TestGearUnknownMaximum(t *testing.T) {
 	// A fake whose model reports no limit.
 	f := newGearFake()
@@ -724,19 +1015,19 @@ func TestGearUnknownMaximum(t *testing.T) {
 	f.modelInfo = `{}`
 	// Build the rig.
 	rig := gearRig(t, f)
-	// The settings page has no form.
-	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
+	// The settings page has three fields fewer and says why.
+	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
 	// Check it.
-	if strings.Contains(body, `action="/gear/review"`) || !strings.Contains(body, "does not report this model's maximum") {
+	if strings.Count(body, "cannot be changed: Ollama does not report") != 3 || strings.Contains(body, `name="s_num_ctx"`) || !strings.Contains(body, `name="s_temperature"`) {
 		// Report the problem.
-		t.Errorf("settings page: %q", body)
+		t.Errorf("settings page: %d notes", strings.Count(body, "cannot be changed"))
 	} // end of the check
-	// The other two steps refuse.
+	// A forged value for one of them is refused on both steps.
 	for _, path := range []string{"/gear/review", "/gear/save"} {
 		// Send a size.
-		_, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
+		_, body, _ := gearPost(t, rig, path, "alpha:1b", "s_num_ctx", "8192")
 		// It must refuse.
-		if !strings.Contains(body, "Not saved.") {
+		if !strings.Contains(body, "Not saved.") || !strings.Contains(body, "No safe limit is known") {
 			// Report the problem.
 			t.Errorf("%s: %q", path, body)
 		} // end of the check
@@ -744,8 +1035,13 @@ func TestGearUnknownMaximum(t *testing.T) {
 	// Nothing was sent.
 	if f.createCount() != 0 {
 		// Report the problem.
-		t.Errorf("a model without a known limit was changed")
+		t.Errorf("a setting without a known limit was changed")
 	} // end of the change check
+	// The other settings can still be saved.
+	if _, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2"); !strings.Contains(body, "<strong>Saved.</strong>") {
+		// Report the problem.
+		t.Errorf("a normal setting could not be saved: %q", body)
+	} // end of the normal save
 } // end of TestGearUnknownMaximum
 
 // TestGearSavedAboveMaximum checks a saved size above the model's limit is pointed out and can be fixed by saving a valid one.
@@ -753,18 +1049,18 @@ func TestGearSavedAboveMaximum(t *testing.T) {
 	// A fake with a size far above the limit saved (the experiment showed Ollama accepts such a value).
 	f := newGearFake()
 	// The saved text, in the form Ollama printed.
-	f.params = "num_ctx                        1e+08\n" + f.params
+	f.params = append(f.params, paramLine{"num_ctx", "1e+08"})
 	// Build the rig.
 	rig := gearRig(t, f)
 	// The settings page.
-	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
-	// It warns, and the field is not pre-filled with a value that would be refused.
+	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
+	// It warns.
 	if !strings.Contains(body, "above what this model supports") {
 		// Report the problem.
 		t.Errorf("no warning in %q", body)
 	} // end of the warning check
 	// Saving a valid size works.
-	_, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+	_, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "s_num_ctx", "8192")
 	// The result.
 	if !strings.Contains(body, "<strong>Saved.</strong>") {
 		// Report the problem.
@@ -772,6 +1068,59 @@ func TestGearSavedAboveMaximum(t *testing.T) {
 	} // end of the result check
 } // end of TestGearSavedAboveMaximum
 
+// TestGearUnreadableSavedValue checks a saved value that is not a number (Ollama accepts text) is shown as it is, and can be replaced by a valid number.
+func TestGearUnreadableSavedValue(t *testing.T) {
+	// A fake with text saved as the temperature.
+	f := newGearFake()
+	// Replace the temperature.
+	f.params[0] = paramLine{"temperature", `"abc"`}
+	// Build the rig.
+	rig := gearRig(t, f)
+	// The settings page shows it and does not pre-fill the field.
+	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
+	// Check.
+	if !strings.Contains(body, "(not a usable value)") || strings.Contains(body, `name="s_temperature" type="number" inputmode="decimal" min="0" max="2" step="any" aria-label="Temperature for alpha:1b" value="abc"`) {
+		// Report the problem.
+		t.Errorf("unreadable value shown wrongly")
+	} // end of the check
+	// A valid number replaces it.
+	_, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.7")
+	// It works.
+	if !strings.Contains(body, "<strong>Saved.</strong>") {
+		// Report the problem.
+		t.Errorf("replacing failed: %q", body)
+	} // end of the check
+} // end of TestGearUnreadableSavedValue
+
+// TestGearLargestForm checks a form with the longest possible stop words (eight words of 100 four-byte characters) is accepted, and a form beyond the limit is refused.
+func TestGearLargestForm(t *testing.T) {
+	// A fake.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Eight words of 100 characters, each four bytes long.
+	var words []string
+	// Build them, each different.
+	for i := 0; i < 8; i++ {
+		// One word.
+		words = append(words, strings.Repeat("𝔘", 99)+string(rune('a'+i)))
+	} // end of the loop
+	// The review step must accept it.
+	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "s_stop", strings.Join(words, "\n"))
+	// Check.
+	if status != http.StatusOK || !strings.Contains(body, "Yes, save them into the model") {
+		// Report the problem.
+		t.Errorf("the largest valid form failed: status %d", status)
+	} // end of the check
+	// A form of 20 KB is refused as a bad form.
+	status, _, _ = gearPost(t, rig, "/gear/review", "alpha:1b", "s_stop", strings.Repeat("x", 20000))
+	// Check.
+	if status != http.StatusBadRequest {
+		// Report the problem.
+		t.Errorf("an oversized form gave status %d", status)
+	} // end of the size check
+} // end of TestGearLargestForm
+
 // TestGearSecurity checks the three routes need a POST from this page with the right token, like every other changing route.
 func TestGearSecurity(t *testing.T) {
 	// A fake.
@@ -786,22 +1135,22 @@ func TestGearSecurity(t *testing.T) {
 			t.Errorf("GET %s = %d", path, status)
 		} // end of the GET check
 		// A POST from another site is refused.
-		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "s_temperature": {"0.2"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
 			// Report the problem.
 			t.Errorf("cross-site %s = %d", path, res.StatusCode)
 		} // end of the origin check
 		// A POST without any browser header is refused.
-		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, nil); res.StatusCode != http.StatusForbidden {
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "s_temperature": {"0.2"}}, nil); res.StatusCode != http.StatusForbidden {
 			// Report the problem.
 			t.Errorf("headerless %s = %d", path, res.StatusCode)
 		} // end of the headerless check
 		// A POST with a wrong token is refused.
-		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "model": {"alpha:1b"}, "s_temperature": {"0.2"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
 			// Report the problem.
 			t.Errorf("wrong token %s = %d", path, res.StatusCode)
 		} // end of the token check
 		// A POST without a model name is refused.
-		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "num_ctx": {"8192"}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "s_temperature": {"0.2"}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
 			// Report the problem.
 			t.Errorf("no model %s = %d", path, res.StatusCode)
 		} // end of the model check
@@ -813,7 +1162,7 @@ func TestGearSecurity(t *testing.T) {
 	} // end of the change check
 } // end of TestGearSecurity
 
-// TestGearDoubleClickSavesOnce checks that many simultaneous saves of the same value send only one create request.
+// TestGearDoubleClickSavesOnce checks that many simultaneous saves of the same values send only one create request.
 func TestGearDoubleClickSavesOnce(t *testing.T) {
 	// A fake whose create is slow, so the clicks really overlap.
 	f := newGearFake()
@@ -832,7 +1181,7 @@ func TestGearDoubleClickSavesOnce(t *testing.T) {
 			// Count it done at the end.
 			defer wg.Done()
 			// The same save.
-			gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
+			gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
 		}() // end of the goroutine
 	} // end of the start loop
 	// Wait for all of them.
diff --git a/load.go b/load.go
index 518a5b6..2ed82ff 100644
--- a/load.go
+++ b/load.go
@@ -409,7 +409,13 @@ func loadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Hand
 // readModelForm runs the checks the load forms share (same rules as the unload forms): origin, form, token and model name; ok is false when a refusal was already sent.
 func readModelForm(w http.ResponseWriter, r *http.Request, token string) (string, bool) {
 	// Never read more than 2 KB of form data; the real form is tiny.
-	r.Body = http.MaxBytesReader(w, r.Body, 2048)
+	return readModelFormLimit(w, r, token, 2048)
+} // end of readModelForm
+
+// readModelFormLimit does the same checks with a chosen limit on the form size (the settings forms are larger).
+func readModelFormLimit(w http.ResponseWriter, r *http.Request, token string, limit int64) (string, bool) {
+	// Never read more than the limit.
+	r.Body = http.MaxBytesReader(w, r.Body, limit)
 	// Only a form on this very page may send this request (requirement S2).
 	if !sameOrigin(r) {
 		// Refuse.
@@ -442,4 +448,4 @@ func readModelForm(w http.ResponseWriter, r *http.Request, token string) (string
 	} // end of the name check
 	// All checks passed.
 	return name, true
-} // end of readModelForm
+} // end of readModelFormLimit
diff --git a/settings.go b/settings.go
new file mode 100644
index 0000000..bc1e929
--- /dev/null
+++ b/settings.go
@@ -0,0 +1,388 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds formatted text.
+	"fmt"
+	// math checks that numbers are finite and whole.
+	"math"
+	// sort puts lists in order so they can be compared.
+	"sort"
+	// strconv turns numbers into text and back.
+	"strconv"
+	// strings trims and splits text.
+	"strings"
+	// unicode finds control characters.
+	"unicode"
+	// unicode/utf8 counts characters and checks that text is valid.
+	"unicode/utf8"
+) // end of imports
+
+// The kinds of setting.
+const (
+	// kindInt is a whole number.
+	kindInt = "int"
+	// kindFloat is a number with an optional decimal part.
+	kindFloat = "float"
+	// kindList is a list of texts (the stop words).
+	kindList = "list"
+) // end of the kinds
+
+// The limits of the stop word list.
+const (
+	// maxStopWords is the most stop words one model may hold here.
+	maxStopWords = 8
+	// maxStopLength is the longest stop word, in characters.
+	maxStopLength = 100
+	// maxNumberText is the longest number text that is read.
+	maxNumberText = 20
+	// maxListText is the longest text accepted for the stop word box, in bytes (eight words of 100 four-byte characters fit).
+	maxListText = 4000
+) // end of the limits
+
+// settingSpec describes one model setting: what it is called, what kind it is, Ollama's default and the limits this monitor enforces.
+type settingSpec struct {
+	// Key is the parameter name Ollama uses.
+	Key string
+	// Heading is the name shown to the person, also the key of its help text.
+	Heading string
+	// Kind is kindInt, kindFloat or kindList.
+	Kind string
+	// Default is Ollama's own default, in words, from the Modelfile reference.
+	Default string
+	// Min is the smallest value this monitor allows.
+	Min float64
+	// Max is the largest value this monitor allows (ignored when FromModel is set).
+	Max float64
+	// FromModel says the largest value is the model's own context length.
+	FromModel bool
+	// NoZero says zero is refused (an answer length of zero would produce nothing).
+	NoZero bool
+	// Special explains the special values in a few words, or is empty.
+	Special string
+} // end of settingSpec
+
+// settingSpecs lists the ten settings in the order they are shown. The defaults come from Ollama's Modelfile reference (https://docs.ollama.com/modelfile); the minimum and maximum are this monitor's own limits, because Ollama sets none (a test on the real Ollama accepted any value, even text).
+var settingSpecs = []settingSpec{
+	// The context size; the documentation says 2048, but a test on Ollama 0.34.4 loaded a model at its own maximum.
+	{Key: "num_ctx", Heading: "Context size", Kind: kindInt, Default: "automatic (docs: 2048)", Min: 512, FromModel: true},
+	// Randomness of the answers.
+	{Key: "temperature", Heading: "Temperature", Kind: kindFloat, Default: "0.8", Min: 0, Max: 2},
+	// How many of the likeliest words are considered.
+	{Key: "top_k", Heading: "Top-k", Kind: kindInt, Default: "40", Min: 1, Max: 1000},
+	// How much of the probability is considered.
+	{Key: "top_p", Heading: "Top-p", Kind: kindFloat, Default: "0.9", Min: 0.01, Max: 1},
+	// The cut-off relative to the best word.
+	{Key: "min_p", Heading: "Min-p", Kind: kindFloat, Default: "0 (off)", Min: 0, Max: 1},
+	// How strongly repeats are punished.
+	{Key: "repeat_penalty", Heading: "Repeat penalty", Kind: kindFloat, Default: "1 (off)", Min: 0.5, Max: 2},
+	// How far back repeats are looked for; 0 is off and -1 is the whole context.
+	{Key: "repeat_last_n", Heading: "Repeat window", Kind: kindInt, Default: "64", Min: -1, FromModel: true, Special: "0 switches it off; -1 uses the whole context size"},
+	// The random seed.
+	{Key: "seed", Heading: "Seed", Kind: kindInt, Default: "0", Min: 0, Max: 2147483647},
+	// The longest answer; -1 means no limit.
+	{Key: "num_predict", Heading: "Answer length limit", Kind: kindInt, Default: "-1 (no limit)", Min: -1, FromModel: true, NoZero: true, Special: "-1 means no limit"},
+	// The words that end an answer.
+	{Key: "stop", Heading: "Stop words", Kind: kindList, Default: "none"},
+} // end of settingSpecs
+
+// specByKey finds the spec of a parameter name; the second result is false for a name this page does not edit.
+func specByKey(key string) (settingSpec, bool) {
+	// Look through the list.
+	for _, s := range settingSpecs {
+		// A match.
+		if s.Key == key {
+			// Found.
+			return s, true
+		} // end of the match check
+	} // end of the loop
+	// Not one of ours.
+	return settingSpec{}, false
+} // end of specByKey
+
+// limits returns the smallest and largest allowed value for a setting; modelMax is the model's context length (0 when unknown) and ok is false when a model-dependent limit cannot be known.
+func (s settingSpec) limits(modelMax int64) (min, max float64, ok bool) {
+	// A limit that follows the model needs the model's maximum.
+	if s.FromModel {
+		// Unknown: this setting cannot be edited safely.
+		if modelMax <= 0 {
+			// No limit known.
+			return 0, 0, false
+		} // end of the unknown check
+		// The model's own value is the top.
+		return s.Min, float64(modelMax), true
+	} // end of the model case
+	// A fixed range.
+	return s.Min, s.Max, true
+} // end of limits
+
+// fmtNum writes a number the way Ollama prints it: no trailing zeros, no exponent.
+func fmtNum(f float64) string {
+	// Shortest exact form.
+	return strconv.FormatFloat(f, 'f', -1, 64)
+} // end of fmtNum
+
+// rangeText describes the allowed values in plain words for the page.
+func (s settingSpec) rangeText(modelMax int64) string {
+	// The stop words have their own rule.
+	if s.Kind == kindList {
+		// Say it.
+		return fmt.Sprintf("up to %d words, each 1 to %d characters, one per line", maxStopWords, maxStopLength)
+	} // end of the list case
+	// The numbers.
+	min, max, ok := s.limits(modelMax)
+	// Unknown model limit.
+	if !ok {
+		// Say why nothing can be edited.
+		return "needs the model maximum, which Ollama does not report"
+	} // end of the unknown check
+	// The basic range.
+	text := fmtNum(min) + " to " + fmtNum(max)
+	// An answer length of -1 and then 1 to the maximum.
+	if s.NoZero {
+		// Spell it out.
+		text = "-1, or " + fmtNum(1) + " to " + fmtNum(max)
+	} // end of the no-zero case
+	// Add the special values.
+	if s.Special != "" {
+		// Append them.
+		text += " (" + s.Special + ")"
+	} // end of the special case
+	// Hand back the text.
+	return text
+} // end of rangeText
+
+// parseNumber checks a typed number against the rules of one setting; it returns the number, or zero and the reason in plain words.
+func (s settingSpec) parseNumber(raw string, modelMax int64) (float64, string) {
+	// Spaces around the number do not matter.
+	t := strings.TrimSpace(raw)
+	// An absurdly long text is refused before anything else.
+	if len(t) > maxNumberText {
+		// Say so.
+		return 0, "That number is too long."
+	} // end of the length check
+	// The limits.
+	min, max, ok := s.limits(modelMax)
+	// Without them nothing can be checked.
+	if !ok {
+		// Say so.
+		return 0, "No safe limit is known for this model, so this setting cannot be changed."
+	} // end of the limit check
+	// Read the characters: digits, one leading minus where negatives are allowed, one decimal point for decimals.
+	dots, digits := 0, 0
+	// Go through the characters.
+	for i, r := range t {
+		// A digit.
+		if r >= '0' && r <= '9' {
+			// Count it.
+			digits++
+			// Next character.
+			continue
+		} // end of the digit check
+		// A leading minus where a negative value is meaningful.
+		if r == '-' && i == 0 && min < 0 {
+			// Fine.
+			continue
+		} // end of the minus check
+		// One decimal point in a decimal setting.
+		if r == '.' && s.Kind == kindFloat && dots == 0 && digits > 0 {
+			// Count it.
+			dots++
+			// Next character.
+			continue
+		} // end of the point check
+		// Anything else is refused.
+		if s.Kind == kindFloat {
+			// Say what is expected.
+			return 0, "Use digits and at most one decimal point, such as 0.7."
+		} // end of the decimal wording
+		// Whole numbers.
+		return 0, "Use digits only, as a whole number such as 40."
+	} // end of the character loop
+	// A decimal point must be followed by a digit, and there must be at least one digit.
+	if digits == 0 || strings.HasSuffix(t, ".") {
+		// Say what is expected.
+		return 0, "That is not a number."
+	} // end of the digit-count check
+	// Read it; it cannot fail now, but never trust that.
+	v, err := strconv.ParseFloat(t, 64)
+	// A failure or a value that is not finite.
+	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) {
+		// Say so.
+		return 0, "That is not a number."
+	} // end of the parse check
+	// Zero is refused for the answer length.
+	if s.NoZero && v == 0 {
+		// Say why.
+		return 0, "0 would produce no answer at all. Use -1 for no limit, or a number from 1."
+	} // end of the zero check
+	// Too small.
+	if v < min {
+		// Say so with the range.
+		return 0, fmt.Sprintf("%s is too small. Allowed: %s.", fmtNum(v), s.rangeText(modelMax))
+	} // end of the small check
+	// Too large.
+	if v > max {
+		// Say so with the range.
+		return 0, fmt.Sprintf("%s is too large. Allowed: %s.", fmtNum(v), s.rangeText(modelMax))
+	} // end of the large check
+	// All good.
+	return v, ""
+} // end of parseNumber
+
+// parseStopWords checks the typed stop words (one per line) and returns the list, or nil and the reason; blank lines are skipped.
+func parseStopWords(raw string) ([]string, string) {
+	// An absurdly long text is refused first.
+	if len(raw) > maxListText {
+		// Say so.
+		return nil, "That is too much text for stop words."
+	} // end of the length check
+	// Unify the line breaks a browser may send.
+	text := strings.ReplaceAll(strings.ReplaceAll(raw, "\r\n", "\n"), "\r", "\n")
+	// The result.
+	var out []string
+	// Go through the lines.
+	for _, line := range strings.Split(text, "\n") {
+		// A blank line holds nothing.
+		if strings.TrimSpace(line) == "" {
+			// Next line.
+			continue
+		} // end of the blank check
+		// The text must be valid and printable (a tab or other control character would be invisible).
+		if !utf8.ValidString(line) || strings.IndexFunc(line, unicode.IsControl) >= 0 {
+			// Say so.
+			return nil, "A stop word may contain letters, digits, spaces and symbols, but no control characters."
+		} // end of the character check
+		// Too long.
+		if utf8.RuneCountInString(line) > maxStopLength {
+			// Say so.
+			return nil, fmt.Sprintf("A stop word may have at most %d characters.", maxStopLength)
+		} // end of the long check
+		// Keep it exactly as typed.
+		out = append(out, line)
+	} // end of the line loop
+	// Too many.
+	if len(out) > maxStopWords {
+		// Say so.
+		return nil, fmt.Sprintf("At most %d stop words are allowed.", maxStopWords)
+	} // end of the count check
+	// The same word twice is a typing slip.
+	seen := map[string]bool{}
+	// Check each.
+	for _, w := range out {
+		// A repeat.
+		if seen[w] {
+			// Say which.
+			return nil, "The same stop word is listed twice."
+		} // end of the repeat check
+		// Remember it.
+		seen[w] = true
+	} // end of the duplicate loop
+	// Hand back the list.
+	return out, ""
+} // end of parseStopWords
+
+// settingValue is one setting's value, either a number or a list of texts.
+type settingValue struct {
+	// Num is the number for number settings.
+	Num float64
+	// List holds the texts for the stop words.
+	List []string
+} // end of settingValue
+
+// text writes the value for the page.
+func (v settingValue) text(s settingSpec) string {
+	// The stop words are shown quoted, joined by commas.
+	if s.Kind == kindList {
+		// Quote each.
+		parts := make([]string, len(v.List))
+		// Go through them.
+		for i, w := range v.List {
+			// Quote with Go's rules (the same ones Ollama uses when printing).
+			parts[i] = strconv.Quote(w)
+		} // end of the loop
+		// Join.
+		return strings.Join(parts, ", ")
+	} // end of the list case
+	// A number.
+	return fmtNum(v.Num)
+} // end of text
+
+// equal says whether two values are the same for the given setting.
+func (v settingValue) equal(o settingValue, s settingSpec) bool {
+	// Lists compare as sets, because Ollama may print them in another order.
+	if s.Kind == kindList {
+		// Copy and sort both.
+		a, b := append([]string{}, v.List...), append([]string{}, o.List...)
+		// Sort.
+		sort.Strings(a)
+		// Sort.
+		sort.Strings(b)
+		// Different sizes.
+		if len(a) != len(b) {
+			// Not equal.
+			return false
+		} // end of the size check
+		// Compare each.
+		for i := range a {
+			// A difference.
+			if a[i] != b[i] {
+				// Not equal.
+				return false
+			} // end of the compare
+		} // end of the loop
+		// Equal.
+		return true
+	} // end of the list case
+	// Numbers.
+	return v.Num == o.Num
+} // end of equal
+
+// savedMap collects the saved parameters by name; a name can appear several times (the stop words).
+func savedMap(lines []paramLine) map[string][]string {
+	// The result.
+	m := map[string][]string{}
+	// Go through the lines.
+	for _, l := range lines {
+		// Add the value under its name.
+		m[l.Name] = append(m[l.Name], l.Value)
+	} // end of the loop
+	// Hand back the map.
+	return m
+} // end of savedMap
+
+// readSaved turns the printed lines of one setting into a value; the second result is false when nothing is saved, and the third when something is saved but cannot be read.
+func readSaved(s settingSpec, raws []string) (settingValue, bool, bool) {
+	// Nothing saved.
+	if len(raws) == 0 {
+		// Not present.
+		return settingValue{}, false, true
+	} // end of the nothing case
+	// The stop words are quoted texts.
+	if s.Kind == kindList {
+		// The list.
+		var list []string
+		// Each line.
+		for _, r := range raws {
+			// Remove the quotes with Go's rules; fall back to the raw text when it is not quoted.
+			if u, err := strconv.Unquote(r); err == nil {
+				// Use it.
+				list = append(list, u)
+			} else {
+				// Keep it as printed.
+				list = append(list, r)
+			} // end of the unquote check
+		} // end of the loop
+		// Present and readable.
+		return settingValue{List: list}, true, true
+	} // end of the list case
+	// A number: the last line wins, like in a Modelfile.
+	f, err := strconv.ParseFloat(raws[len(raws)-1], 64)
+	// Not a number, or not finite.
+	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
+		// Present but unreadable.
+		return settingValue{}, true, false
+	} // end of the number check
+	// Present and readable.
+	return settingValue{Num: f}, true, true
+} // end of readSaved
diff --git a/tooltips.go b/tooltips.go
index aeafde8..fc79407 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -20,7 +20,7 @@ var installedColumns = []string{"Model", "State", "Size on disk", "Family", "Par
 var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Loaded context length", "Time until unload"}
 
 // gearHeadings are the headings on the settings page and the Load page that have a help bubble, in the order they appear; a test checks each has a text.
-var gearHeadings = []string{"Context size", "Model maximum", "Smallest allowed", "Saved in the model", "Other saved settings", "Keep-alive time"}
+var gearHeadings = []string{"Saved in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}
 
 // helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
 // The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
@@ -202,24 +202,6 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "How much memory to spend against how long a text it can handle.",
 	}, // end of Context size
-	// The model's own limit.
-	"Model maximum": {
-		// What it means.
-		Plain: "The largest context size this model was built for. This page refuses anything above it.",
-		// A real case.
-		Example: "medgemma:latest: 131072. qwen3.6:27b: 262144.",
-		// What it helps with.
-		Decide: "The top of the range you can choose.",
-	}, // end of Model maximum
-	// This monitor's own lowest value.
-	"Smallest allowed": {
-		// What it means.
-		Plain: "The lowest context size this monitor lets you save. Ollama itself sets no lowest value.",
-		// A real case.
-		Example: "512. Ollama accepted a size of 1 in a test, which would make the model unusable.",
-		// What it helps with.
-		Decide: "It stops a value that would break the model.",
-	}, // end of Smallest allowed
 	// What is stored in the model.
 	"Saved in the model": {
 		// What it means.
@@ -229,15 +211,105 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "What every program gets when it loads this model.",
 	}, // end of Saved in the model
-	// The other stored settings.
-	"Other saved settings": {
+	// The default column.
+	"Ollama's default": {
+		// What it means.
+		Plain: "The value Ollama uses for this setting when the model has none saved and a program sends none.",
+		// A real case.
+		Example: "Temperature 0.8 and top-k 40. The context size is chosen by Ollama when the model loads.",
+		// What it helps with.
+		Decide: "Whether changing the setting would change anything at all.",
+	}, // end of Ollama's default
+	// The allowed range column.
+	"Allowed values": {
+		// What it means.
+		Plain: "The range this monitor accepts. Ollama sets no range itself, so these limits protect the model from bad values.",
+		// A real case.
+		Example: "Temperature 0 to 2. The context size goes up to what the model supports.",
+		// What it helps with.
+		Decide: "What you can type before the monitor refuses it.",
+	}, // end of Allowed values
+	// The temperature setting.
+	"Temperature": {
+		// What it means.
+		Plain: "How random the answers are. Low is predictable, high is more varied.",
+		// A real case.
+		Example: "0.2 suits code and facts; 1 suits chat and stories.",
+		// What it helps with.
+		Decide: "How exact or how creative you want the answers.",
+	}, // end of Temperature
+	// The top-k setting.
+	"Top-k": {
+		// What it means.
+		Plain: "Each next word is chosen only from the K likeliest words. Smaller is safer.",
+		// A real case.
+		Example: "40 is Ollama's default; 1 always takes the single likeliest word.",
+		// What it helps with.
+		Decide: "How much variety to allow in the choice of words.",
+	}, // end of Top-k
+	// The top-p setting.
+	"Top-p": {
+		// What it means.
+		Plain: "Each next word comes from the likeliest words whose chances add up to this share.",
+		// A real case.
+		Example: "0.9 keeps the likeliest words that together make up 90% (percent).",
+		// What it helps with.
+		Decide: "Lower is more focused, higher is more varied.",
+	}, // end of Top-p
+	// The min-p setting.
+	"Min-p": {
+		// What it means.
+		Plain: "Drops words that are far less likely than the best one. 0 switches it off.",
+		// A real case.
+		Example: "0.05 drops words below 5% (percent) of the best word's chance.",
+		// What it helps with.
+		Decide: "A way to cut odd words while keeping variety.",
+	}, // end of Min-p
+	// The repeat penalty setting.
+	"Repeat penalty": {
+		// What it means.
+		Plain: "How strongly repeating itself is discouraged. 1 means no penalty.",
+		// A real case.
+		Example: "1.1 is a mild penalty; 1.5 is strong and can make text odd.",
+		// What it helps with.
+		Decide: "Raise it a little if the model loops or repeats.",
+	}, // end of Repeat penalty
+	// The repeat window setting.
+	"Repeat window": {
+		// What it means.
+		Plain: "How many recent tokens (word pieces) are checked for repeats. 0 is off, -1 is the whole context size.",
+		// A real case.
+		Example: "64 is Ollama's default.",
+		// What it helps with.
+		Decide: "How far back a repeat is noticed.",
+	}, // end of Repeat window
+	// The seed setting.
+	"Seed": {
+		// What it means.
+		Plain: "A starting number for the random choices. The same seed gives the same answer.",
+		// A real case.
+		Example: "With seed 42 the same question gives the same text each time.",
+		// What it helps with.
+		Decide: "Set it only when you need repeatable answers.",
+	}, // end of Seed
+	// The answer length setting.
+	"Answer length limit": {
+		// What it means.
+		Plain: "The most tokens (word pieces) one answer may have. -1 means no limit.",
+		// A real case.
+		Example: "512 stops every answer after about 380 words.",
+		// What it helps with.
+		Decide: "Stops runaway answers; too small cuts answers short.",
+	}, // end of Answer length limit
+	// The stop words setting.
+	"Stop words": {
 		// What it means.
-		Plain: "Other settings stored in the model, such as stop words. They are shown here and kept as they are.",
+		Plain: "Text that makes the model stop writing when it produces it. You can give several.",
 		// A real case.
-		Example: "medgemma:latest has the stop word end_of_turn.",
+		Example: "medgemma:latest stops at the text end_of_turn.",
 		// What it helps with.
-		Decide: "What the model already does before you change anything.",
-	}, // end of Other saved settings
+		Decide: "Changing it can make answers end too early or never.",
+	}, // end of Stop words
 	// The keep-alive time on the Load page.
 	"Keep-alive time": {
 		// What it means.
diff --git a/web/app.css b/web/app.css
index eebfc42..38d7d8a 100644
--- a/web/app.css
+++ b/web/app.css
@@ -813,8 +813,8 @@ h2 {
   outline-offset: 2px;
 } /* end of rule */
 
-/* The number field and the drop-down of the settings and Load pages. */
-.numfield, .keepselect {
+/* The number field, the stop word box and the drop-down of the settings and Load pages. */
+.numfield, .stopfield, .keepselect {
   /* Use the page font. */
   font: inherit;
   /* Room inside. */
@@ -835,6 +835,77 @@ h2 {
   width: 9rem;
 } /* end of rule */
 
+/* The table of settings: thin lines between rows, text on the left, top-aligned cells. */
+.settingtable {
+  /* No double lines. */
+  border-collapse: collapse;
+  /* Room above and below. */
+  margin: 0.6rem 0 1rem;
+} /* end of rule */
+
+/* Cells of the settings table. */
+.settingtable th, .settingtable td {
+  /* Text starts on the left. */
+  text-align: left;
+  /* Room around the text. */
+  padding: 0.45rem 1rem 0.45rem 0.4rem;
+  /* A thin line between rows, visible without colour. */
+  border-bottom: 1px solid var(--border);
+  /* Align the top lines of tall cells (the stop word box). */
+  vertical-align: top;
+} /* end of rule */
+
+/* The column headings of the settings table stand out without colour. */
+.settingtable thead th {
+  /* A stronger line under the headings. */
+  border-bottom: 2px solid var(--border);
+} /* end of rule */
+
+/* On a narrow screen each setting becomes a small card: the column headings are hidden and every cell carries its own label, so nothing runs off the screen. */
+@media (max-width: 720px) {
+  /* The table and its parts stop behaving like a table. */
+  .settingtable, .settingtable tbody, .settingtable tr, .settingtable th, .settingtable td {
+    /* Each part fills the width, one under the other. */
+    display: block;
+    /* Never wider than the screen. */
+    max-width: 100%;
+  } /* end of rule */
+  /* The headings row is replaced by the labels in each cell. */
+  .settingtable thead {
+    /* Hidden from the screen. */
+    display: none;
+  } /* end of rule */
+  /* A line between settings. */
+  .settingtable tr {
+    /* A thin line under each card. */
+    border-bottom: 1px solid var(--border);
+    /* Room around. */
+    padding: 0.4rem 0;
+  } /* end of rule */
+  /* Cells lose their own lines and get less padding. */
+  .settingtable th, .settingtable td {
+    /* No line inside a card. */
+    border-bottom: 0;
+    /* Little room. */
+    padding: 0.15rem 0.4rem;
+  } /* end of rule */
+  /* The label in front of each cell value. */
+  .settingtable td[data-label]::before {
+    /* The text comes from the attribute. */
+    content: attr(data-label) ": ";
+    /* Bold, so the label stands apart without colour. */
+    font-weight: 700;
+  } /* end of rule */
+} /* end of the narrow-screen rules */
+
+/* The stop word box: one word per line, resizable only downwards. */
+.stopfield {
+  /* Wide enough for a typical stop word. */
+  width: 14rem;
+  /* The user may make it taller, not wider. */
+  resize: vertical;
+} /* end of rule */
+
 /* The hidden attribute must always win over any display rule. */
 [hidden] {
   /* Not drawn at all. */
diff --git a/web/gear.html b/web/gear.html
index 13600de..e515dfa 100644
--- a/web/gear.html
+++ b/web/gear.html
@@ -21,56 +21,88 @@
 <h1>Settings for <code>{{.Model}}</code></h1>
 {{/* Version 1: the settings and the form. */}}
 {{if eq .Kind "settings"}}
-{{/* A refused value is explained first, with a symbol and a bold lead, so colour is never the only signal. */}}
+{{/* A general note when values were refused. */}}
 {{if .Problem}}
-{{/* The reason. */}}
+{{/* The note, with a symbol and a bold lead, so colour is never the only signal. */}}
 <p class="warn" role="alert"><strong>⚠ Not saved.</strong> {{.Problem}}</p>
 {{/* End of the problem note. */}}
 {{end}}
-{{/* A saved value above the model's limit is pointed out. */}}
-{{if .AboveMax}}
-{{/* The note. */}}
-<p class="warn"><strong>⚠ The saved size is above what this model supports.</strong> Saving a valid size below fixes it.</p>
-{{/* End of the above-limit note. */}}
-{{end}}
 {{/* What these settings are. */}}
-<p class="muted">{{template "tipbox" .Tips.saved}}: these settings are stored inside the model in Ollama, so every program that loads it without a value of its own uses them. The model must not be loaded now.</p>
-{{/* The facts, each heading with its help bubble. */}}
-<table class="facts">
-{{/* Row 1: the saved context size. */}}
-<tr><th scope="row">{{template "tipbox" .Tips.ctx}}</th><td>{{.SavedText}}</td></tr>
-{{/* Row 2: the model maximum. */}}
-<tr><th scope="row">{{template "tipbox" .Tips.max}}</th><td>{{if .Max}}{{.Max}} tokens (word pieces){{else}}not reported{{end}}</td></tr>
-{{/* Row 3: the smallest size allowed. */}}
-<tr><th scope="row">{{template "tipbox" .Tips.min}}</th><td>{{.Min}} tokens (word pieces); this is this monitor's own limit</td></tr>
-{{/* Row 4: the other saved settings. */}}
-<tr><th scope="row">{{template "tipbox" .Tips.other}}</th><td>{{if .Others}}{{range $i, $o := .Others}}{{if $i}}, {{end}}<code>{{$o}}</code>{{end}}{{else}}none{{end}}. They are kept as they are.</td></tr>
-{{/* End of the facts. */}}
-</table>
-{{/* The form, only when a safe limit is known. */}}
-{{if .CanSave}}
+<p class="muted">{{template "tipbox" .Tips.saved}}: these settings are stored inside the model in Ollama, so every program that loads it without a value of its own uses them. The model must not be loaded now. Leave a setting empty to leave it as it is; a saved setting can be changed but never emptied.</p>
 {{/* The form goes to the review step, which changes nothing yet. */}}
 <form method="post" action="/gear/review">
 {{/* The page token proves the form comes from this monitor. */}}
 <input type="hidden" name="token" value="{{.Token}}">
 {{/* The model name. */}}
 <input type="hidden" name="model" value="{{.Model}}">
-{{/* The label and the number field; the browser also checks the range, and the monitor checks it again. */}}
-<p><label for="num_ctx">New context size (tokens):</label> <input class="numfield" id="num_ctx" name="num_ctx" type="number" inputmode="numeric" min="{{.Min}}" max="{{.Max}}" step="1" required value="{{.Typed}}" list="presets"></p>
-{{/* The suggestions; they appear when the field is clicked. */}}
-<datalist id="presets">{{range .Presets}}<option value="{{.}}"></option>{{end}}</datalist>
-{{/* The rules in plain words. */}}
-<p class="muted">Click the field to see suggestions. A saved size cannot be removed, only changed. To go back to the largest size, choose the model maximum.</p>
+{{/* The table of all settings, one row each. */}}
+<table class="settingtable">
+{{/* The column headings, three with their help bubbles. */}}
+<thead><tr><th scope="col">Setting</th><th scope="col">{{template "tipbox" .Tips.default}}</th><th scope="col">{{template "tipbox" .Tips.saved}}</th><th scope="col">New value</th><th scope="col">{{template "tipbox" .Tips.range}}</th></tr></thead>
+{{/* The body. */}}
+<tbody>
+{{/* One row for each setting; the dollar sign reaches the page-level values from inside the loop. */}}
+{{range .Rows}}
+{{/* The row. */}}
+<tr>
+{{/* The setting's name with its help bubble. */}}
+<th scope="row">{{template "tipbox" .Tip}}</th>
+{{/* Ollama's own default. */}}
+<td data-label="Ollama's default">{{.Default}}</td>
+{{/* What the model has saved now. */}}
+<td data-label="Saved in the model">{{.Saved}}</td>
+{{/* The field, or the reason there is none. */}}
+<td data-label="New value">
+{{/* A refusal for this setting, first. */}}
+{{if .Problem}}
+{{/* The reason, with a symbol. */}}
+<p class="warn" role="alert"><strong>⚠</strong> {{.Problem}}</p>
+{{/* End of the refusal. */}}
+{{end}}
+{{/* A note that is not a refusal. */}}
+{{if .Warn}}
+{{/* The note. */}}
+<p class="warn"><strong>⚠</strong> {{.Warn}}</p>
+{{/* End of the note. */}}
+{{end}}
+{{/* No safe limit known: no field. */}}
+{{if not .Editable}}
+{{/* Say why. */}}
+<span class="muted">cannot be changed: Ollama does not report this model's maximum context size</span>
+{{/* The stop words are a box with one word per line. */}}
+{{else if eq .Kind "list"}}
+{{/* The box; a saved list can never be emptied. */}}
+<textarea class="stopfield" name="s_{{.Key}}" rows="3" cols="24" maxlength="2000" aria-label="{{.Heading}} for {{$.Model}}, one per line"{{if .HasSaved}} required{{end}}>{{.Typed}}</textarea>
+{{/* Numbers get a number field with the browser's own range check; the monitor checks again. */}}
+{{else}}
+{{/* The field; the suggestions belong to the context size only. */}}
+<input class="numfield" name="s_{{.Key}}" type="number" inputmode="decimal" min="{{.InMin}}" max="{{.InMax}}" step="{{.Step}}" aria-label="{{.Heading}} for {{$.Model}}" value="{{.Typed}}"{{if .HasSaved}} required{{end}}{{if .Presets}} list="presets"{{end}}>
+{{/* The suggestions for the context size. */}}
+{{if .Presets}}<datalist id="presets">{{range .Presets}}<option value="{{.}}"></option>{{end}}</datalist>{{end}}
+{{/* End of the field choice. */}}
+{{end}}
+{{/* End of the field cell. */}}
+</td>
+{{/* The allowed values. */}}
+<td data-label="Allowed values">{{.Range}}</td>
+{{/* End of the row. */}}
+</tr>
+{{/* End of the row loop. */}}
+{{end}}
+{{/* End of the body. */}}
+</tbody>
+{{/* End of the table. */}}
+</table>
+{{/* Settings saved in the model that this page does not edit. */}}
+{{if .Others}}
+{{/* They are kept as they are. */}}
+<p class="muted">Also saved in the model and kept as they are: {{range $i, $o := .Others}}{{if $i}}, {{end}}<code>{{$o}}</code>{{end}}.</p>
+{{/* End of the other settings. */}}
+{{end}}
 {{/* The button. */}}
-<p><button type="submit" class="btn-load">Review the change</button></p>
+<p><button type="submit" class="btn-load">Review the changes</button></p>
 {{/* End of the form. */}}
 </form>
-{{/* No safe limit is known: no form. */}}
-{{else}}
-{{/* Say why. */}}
-<p class="muted">Nothing can be saved here because Ollama does not report this model's maximum context size, so no safe limit can be checked.</p>
-{{/* End of the form case. */}}
-{{end}}
 {{/* A pointer to the other setting. */}}
 <p class="muted">How long a model stays loaded is chosen on the Load page each time you load it.</p>
 {{/* A link back. */}}
@@ -78,37 +110,45 @@
 {{/* Version 2: the review step. */}}
 {{else if eq .Kind "review"}}
 {{/* The warning, with a symbol and a bold lead. */}}
-<p class="warn"><strong>⚠ This changes the model itself.</strong> Every program that loads this model without a size of its own will use the new one.</p>
-{{/* The change. */}}
-<table class="facts">
-{{/* Before. */}}
-<tr><th scope="row">Context size now</th><td>{{.SavedText}}</td></tr>
-{{/* After. */}}
-<tr><th scope="row">Context size after saving</th><td><strong>{{.NewValue}}</strong> tokens (word pieces)</td></tr>
-{{/* End of the change. */}}
+<p class="warn"><strong>⚠ This changes the model itself.</strong> Every program that loads this model without a value of its own will use the new values.</p>
+{{/* The changes only. */}}
+<table class="settingtable">
+{{/* The headings. */}}
+<thead><tr><th scope="col">Setting</th><th scope="col">Now</th><th scope="col">After saving</th></tr></thead>
+{{/* The body. */}}
+<tbody>
+{{/* One row for each change. */}}
+{{range .Changed}}
+{{/* The row. */}}
+<tr><th scope="row">{{.Heading}}</th><td>{{.Saved}}</td><td><strong>{{.After}}</strong></td></tr>
+{{/* End of the loop. */}}
+{{end}}
+{{/* End of the body. */}}
+</tbody>
+{{/* End of the table. */}}
 </table>
 {{/* What is and is not affected. */}}
 <ul>
-{{/* A bigger size needs more memory. */}}
-<li>A bigger size needs more memory when the model loads; a smaller one needs less.</li>
+{{/* Memory. */}}
+<li>A bigger context size needs more memory when the model loads; a smaller one needs less.</li>
 {{/* The weights stay. */}}
-<li>The model's weights are not changed, and its other saved settings are kept.</li>
+<li>The model's weights are not changed, and every setting not listed above is kept.</li>
 {{/* No removal. */}}
-<li>You can change it again later, but a saved size cannot be removed.</li>
+<li>You can change a setting again later, but a saved setting cannot be removed.</li>
 {{/* End of the list. */}}
 </ul>
 {{/* The two choices side by side. */}}
 <div class="choices">
-{{/* The Yes form sends the values to the save step. */}}
+{{/* The Yes form sends only the changed values to the save step. */}}
 <form method="post" action="/gear/save">
 {{/* The page token. */}}
 <input type="hidden" name="token" value="{{.Token}}">
 {{/* The model name. */}}
 <input type="hidden" name="model" value="{{.Model}}">
-{{/* The size to save. */}}
-<input type="hidden" name="num_ctx" value="{{.NewValue}}">
+{{/* The values to save. */}}
+{{range .Hidden}}<input type="hidden" name="{{.Name}}" value="{{.Value}}">{{end}}
 {{/* The Yes button. */}}
-<button type="submit" class="btn-load">Yes, save it into the model</button>
+<button type="submit" class="btn-load">Yes, save them into the model</button>
 {{/* End of the Yes form. */}}
 </form>
 {{/* The Cancel link simply goes back; nothing was changed. */}}
@@ -118,15 +158,31 @@
 {{/* Version 3: saved and checked. */}}
 {{else if eq .Kind "done"}}
 {{/* Say so; it was checked afterwards. */}}
-<p><strong>Saved.</strong> Ollama now reports a context size of {{.AfterText}} for this model, and its other saved settings are unchanged (both checked).</p>
+<p><strong>Saved.</strong> Ollama now reports these values for this model, and every other saved setting is unchanged (both checked).</p>
+{{/* The values. */}}
+<table class="settingtable">
+{{/* The headings. */}}
+<thead><tr><th scope="col">Setting</th><th scope="col">Saved now</th></tr></thead>
+{{/* The body. */}}
+<tbody>
+{{/* One row for each change. */}}
+{{range .Changed}}
+{{/* The row. */}}
+<tr><th scope="row">{{.Heading}}</th><td>{{.After}}</td></tr>
+{{/* End of the loop. */}}
+{{end}}
+{{/* End of the body. */}}
+</tbody>
+{{/* End of the table. */}}
+</table>
 {{/* What happens next. */}}
-<p class="muted">The next load of this model uses it. After loading, the Loaded table shows the context size actually used.</p>
+<p class="muted">The next load of this model uses them. After loading, the Loaded table shows the context size actually used.</p>
 {{/* A link back. */}}
 <p><a class="btn-plain" href="/">Back to the monitor</a></p>
-{{/* Version 4: the same value was already saved. */}}
+{{/* Version 4: nothing differs from what is saved. */}}
 {{else if eq .Kind "nochange"}}
 {{/* Say so. */}}
-<p>Nothing to change: a context size of {{.NewValue}} is already saved.</p>
+<p>Nothing to change: the values you entered are already what the model has saved, or the fields were left empty.</p>
 {{/* A link back. */}}
 <p><a class="btn-plain" href="/">Back to the monitor</a></p>
 {{/* Version 5: the model is loaded. */}}
@@ -146,7 +202,7 @@
 {{/* Say exactly what is known and what is not. */}}
 <p><strong>Please check.</strong> {{.Detail}}</p>
 {{/* What Ollama reports. */}}
-<p class="muted">Ollama now reports a context size of {{if .AfterText}}{{.AfterText}}{{else}}nothing{{end}}; you asked for {{.NewValue}}.</p>
+<p class="muted">Open the settings again to see what Ollama reports now.</p>
 {{/* A link back. */}}
 <p><a class="btn-plain" href="/">Back to the monitor</a></p>
 {{/* Version 8: something went wrong. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch to the working files.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the changed and new files must have after the patch.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
7d2d58ea2978090afbdfcdd819c64972755aa9c11b0f4d39ca566e4a78690480  gear.go
762a41ac504c715f57b420176c1ebbcdc1c2490c369d1bd508aa7eea86dfadbe  gear_test.go
78501800b0c39904930c1bc4449704569a6be11fe940b060f4a33e56b23bb794  load.go
172a3f95b78220e1797064eb1aad93b05df941bbab408b861df725986104a2b0  settings.go
5972e5331e3f927ef9ef41a91f80588b180288642a197bf63c3866ee962880e4  tooltips.go
332de45c44419753e144082fa443a37c64b0f41646e58c127167b149bd77f53b  web/app.css
4a5bafcd3fbdafff9fc029852ff9df1358bf8e2000ab6635d6387c8ee588a7e1  web/gear.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the 7 changed or new files match the tested versions"
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
