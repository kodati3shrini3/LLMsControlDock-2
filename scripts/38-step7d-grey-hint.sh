#!/usr/bin/env bash
# Script 38: Ollama's default shown as a grey hint inside every empty field of the settings table (option A); applied on the feature branch.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-settings-table" ] || { echo "FAIL  not on feature/model-settings-table"; exit 1; }
# Script 36 must be applied first (it creates settings.go); script 37 too.
[ -f settings.go ] || { echo "FAIL  script 36 was not applied yet (settings.go is missing)"; exit 1; }
# Script 37 (the "not set" wording) must be applied first.
grep -q 'row.Saved = "not set"' gear.go || { echo "FAIL  script 37 was not applied yet"; exit 1; }
# Refuse when this change was already applied.
if grep -q 'func (s settingSpec) Hint' settings.go; then
  # Say so and stop.
  echo "FAIL  this script was already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/gear.go b/gear.go
index 8de029a..34002b6 100644
--- a/gear.go
+++ b/gear.go
@@ -285,6 +285,8 @@ type settingRow struct {
 	Tip tipView
 	// Default is Ollama's own default, in words.
 	Default string
+	// Hint is the default in a few characters, shown in grey inside an empty field.
+	Hint string
 	// Saved says what the model has saved now, or that nothing is saved.
 	Saved string
 	// HasSaved is true when the model has this setting saved, so the field must never be emptied.
@@ -386,7 +388,7 @@ func evaluate(f gearFacts, form url.Values, tips map[string]tipView) ([]settingR
 		// The limits for this model.
 		min, max, limitOK := spec.limits(f.Max)
 		// The row starts with the facts.
-		row := settingRow{Key: spec.Key, Heading: spec.Heading, Kind: spec.Kind, Tip: tips[spec.Key], Default: spec.Default, HasSaved: present, Editable: limitOK, Range: spec.rangeText(f.Max)}
+		row := settingRow{Key: spec.Key, Heading: spec.Heading, Kind: spec.Kind, Tip: tips[spec.Key], Default: spec.Default, Hint: spec.Hint(), HasSaved: present, Editable: limitOK, Range: spec.rangeText(f.Max)}
 		// The words for the saved value.
 		switch {
 		// Nothing saved.
diff --git a/gear_test.go b/gear_test.go
index 8263957..9aef86e 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -690,6 +690,45 @@ func TestGearShowsSettings(t *testing.T) {
 	} // end of the change check
 } // end of TestGearShowsSettings
 
+// TestGearShowsDefaultAsGreyHint checks every field carries Ollama's default as a placeholder (the grey hint), that it is only a placeholder and never a typed value, and that the page explains it.
+func TestGearShowsDefaultAsGreyHint(t *testing.T) {
+	// A fake where nothing but the stop word is saved.
+	f := newGearFake()
+	// Only the stop word.
+	f.params = []paramLine{{"stop", `"<end_of_turn>"`}}
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Open the settings.
+	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
+	// The expected hints, setting by setting.
+	hints := map[string]string{"num_ctx": "automatic", "temperature": "0.8", "top_k": "40", "top_p": "0.9", "min_p": "0", "repeat_penalty": "1", "repeat_last_n": "64", "seed": "0", "num_predict": "-1"}
+	// Check each field.
+	for key, hint := range hints {
+		// The field has the hint as a placeholder and no value.
+		if !regexp.MustCompile(`name="s_` + key + `"[^>]*placeholder="` + regexp.QuoteMeta(hint) + `" value=""`).MatchString(body) {
+			// Report the gap.
+			t.Errorf("%s has no placeholder %q", key, hint)
+		} // end of the check
+	} // end of the loop
+	// The stop box shows its hint too, once its saved value is replaced by nothing: here it holds the saved word, so only the attribute is checked.
+	if !strings.Contains(body, `placeholder="none"`) {
+		// Report the gap.
+		t.Errorf("the stop word box has no placeholder")
+	} // end of the stop check
+	// The page explains the grey value.
+	if !strings.Contains(body, "A grey value inside an empty field is Ollama's default") {
+		// Report the gap.
+		t.Errorf("the grey hint is not explained")
+	} // end of the explanation check
+	// An empty field with only a hint changes nothing when sent.
+	_, body, _ = gearPost(t, rig, "/gear/review", "alpha:1b", "s_temperature", "")
+	// Nothing to change, and no hint was saved.
+	if !strings.Contains(body, "Nothing to change") || f.createCount() != 0 {
+		// Report the problem.
+		t.Errorf("an empty field changed something")
+	} // end of the empty check
+} // end of TestGearShowsDefaultAsGreyHint
+
 // TestGearListsUnknownSavedSettings checks a saved setting this page does not edit is listed and kept.
 func TestGearListsUnknownSavedSettings(t *testing.T) {
 	// A fake with an extra saved setting.
diff --git a/settings.go b/settings.go
index bc1e929..79bb220 100644
--- a/settings.go
+++ b/settings.go
@@ -86,6 +86,14 @@ var settingSpecs = []settingSpec{
 	{Key: "stop", Heading: "Stop words", Kind: kindList, Default: "none"},
 } // end of settingSpecs
 
+// Hint is Ollama's default in a few characters, shown in grey inside an empty field: the default text up to the first bracket.
+func (s settingSpec) Hint() string {
+	// Cut at the first " (" so "automatic (docs: 2048)" becomes "automatic" and "0 (off)" becomes "0".
+	hint, _, _ := strings.Cut(s.Default, " (")
+	// Hand it back.
+	return hint
+} // end of Hint
+
 // specByKey finds the spec of a parameter name; the second result is false for a name this page does not edit.
 func specByKey(key string) (settingSpec, bool) {
 	// Look through the list.
diff --git a/web/app.css b/web/app.css
index 38d7d8a..bc008e3 100644
--- a/web/app.css
+++ b/web/app.css
@@ -898,6 +898,16 @@ h2 {
   } /* end of rule */
 } /* end of the narrow-screen rules */
 
+/* The grey hint inside an empty field (Ollama's default): italic and in the muted text colour, which keeps enough contrast in both themes. */
+.numfield::placeholder, .stopfield::placeholder {
+  /* The muted colour of the page. */
+  color: var(--muted);
+  /* Italic, so it cannot be mistaken for a typed value even without colour. */
+  font-style: italic;
+  /* Browsers fade placeholders by default; keep the full colour. */
+  opacity: 1;
+} /* end of rule */
+
 /* The stop word box: one word per line, resizable only downwards. */
 .stopfield {
   /* Wide enough for a typical stop word. */
diff --git a/web/gear.html b/web/gear.html
index a8ef773..febe97a 100644
--- a/web/gear.html
+++ b/web/gear.html
@@ -28,7 +28,7 @@
 {{/* End of the problem note. */}}
 {{end}}
 {{/* What these settings are. */}}
-<p class="muted">{{template "tipbox" .Tips.saved}}: these settings are stored inside the model in Ollama, so every program that loads it without a value of its own uses them. The model must not be loaded now. Leave a setting empty to leave it as it is; a saved setting can be changed but never emptied.</p>
+<p class="muted">{{template "tipbox" .Tips.saved}}: these settings are stored inside the model in Ollama, so every program that loads it without a value of its own uses them. The model must not be loaded now. A grey value inside an empty field is Ollama's default, and an empty field leaves the setting as it is; a setting that is set can be changed but never emptied.</p>
 {{/* The form goes to the review step, which changes nothing yet. */}}
 <form method="post" action="/gear/review">
 {{/* The page token proves the form comes from this monitor. */}}
@@ -72,11 +72,11 @@
 {{/* The stop words are a box with one word per line. */}}
 {{else if eq .Kind "list"}}
 {{/* The box; a saved list can never be emptied. */}}
-<textarea class="stopfield" name="s_{{.Key}}" rows="3" cols="24" maxlength="2000" aria-label="{{.Heading}} for {{$.Model}}, one per line"{{if .HasSaved}} required{{end}}>{{.Typed}}</textarea>
+<textarea class="stopfield" name="s_{{.Key}}" rows="3" cols="24" maxlength="4000" placeholder="{{.Hint}}" aria-label="{{.Heading}} for {{$.Model}}, one per line"{{if .HasSaved}} required{{end}}>{{.Typed}}</textarea>
 {{/* Numbers get a number field with the browser's own range check; the monitor checks again. */}}
 {{else}}
 {{/* The field; the suggestions belong to the context size only. */}}
-<input class="numfield" name="s_{{.Key}}" type="number" inputmode="decimal" min="{{.InMin}}" max="{{.InMax}}" step="{{.Step}}" aria-label="{{.Heading}} for {{$.Model}}" value="{{.Typed}}"{{if .HasSaved}} required{{end}}{{if .Presets}} list="presets"{{end}}>
+<input class="numfield" name="s_{{.Key}}" type="number" inputmode="decimal" min="{{.InMin}}" max="{{.InMax}}" step="{{.Step}}" aria-label="{{.Heading}} for {{$.Model}}" placeholder="{{.Hint}}" value="{{.Typed}}"{{if .HasSaved}} required{{end}}{{if .Presets}} list="presets"{{end}}>
 {{/* The suggestions for the context size. */}}
 {{if .Presets}}<datalist id="presets">{{range .Presets}}<option value="{{.}}"></option>{{end}}</datalist>{{end}}
 {{/* End of the field choice. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch to the working files.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the changed files must have after the patch.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
d517948365b2196d2862e3f455551c7a639db27bfd64ad709098c1673caae273  gear.go
9ff59425fe0af0f9720f745d17bc976af53b699c779ec537723a09e9df0b0b39  gear_test.go
5dfb91b469d75b5c3c25135733d987c185290fbdb3162a5428dccaa43f2886cf  settings.go
a5fb2415d3020c61b4170211872a48ad1bdcc13b13057b9806ce37859cfea615  web/app.css
a3db062cc04921c1ff36ed8bb067871cd8b45ce802b5fc193c6c7cc1bf72cb79  web/gear.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the changed files match the tested versions"
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
