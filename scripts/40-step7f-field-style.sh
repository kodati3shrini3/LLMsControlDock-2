#!/usr/bin/env bash
# Script 40: renames the first column heading of the settings tables to "Inference parameters" and gives every parameter that is not set in the model a white input field.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/settings-field-style" ] || { echo "FAIL  not on feature/settings-field-style"; exit 1; }
# Script 36 must be applied first (it creates settings.go).
[ -f settings.go ] || { echo "FAIL  script 36 was not applied yet (settings.go is missing)"; exit 1; }
# Refuse to run twice.
if grep -q 'notset' web/gear.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/gear_test.go b/gear_test.go
index 8263957..2880370 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -660,6 +660,16 @@ func TestGearShowsSettings(t *testing.T) {
 		// Report the problem.
 		t.Errorf("wording of the column or the bubbles is wrong")
 	} // end of the wording check
+	// The first column is called "Inference parameters".
+	if !strings.Contains(body, `<th scope="col">Inference parameters</th>`) || strings.Contains(body, `<th scope="col">Setting</th>`) {
+		// Report the problem.
+		t.Errorf("the first column heading is wrong")
+	} // end of the heading check
+	// Fields of parameters that are not set are marked for the white background; fields that hold a value are not.
+	if !regexp.MustCompile(`class="numfield notset" name="s_min_p"`).MatchString(body) || !regexp.MustCompile(`class="numfield" name="s_temperature"`).MatchString(body) || strings.Contains(body, `class="stopfield notset"`) {
+		// Report the problem.
+		t.Errorf("the not-set marking is wrong")
+	} // end of the marking check
 	// Every setting has a field and a help bubble.
 	for _, s := range settingSpecs {
 		// The field.
diff --git a/web/app.css b/web/app.css
index 38d7d8a..5f22719 100644
--- a/web/app.css
+++ b/web/app.css
@@ -829,6 +829,14 @@ h2 {
   color: var(--text);
 } /* end of rule */
 
+/* A field of a parameter that is not set in the model is plain white with dark text in both themes, so it stands out from the fields that already hold a value. */
+.numfield.notset, .stopfield.notset {
+  /* White background. */
+  background: #ffffff;
+  /* Dark text, so what is typed stays readable on white in the dark theme too. */
+  color: #1a1a1a;
+} /* end of rule */
+
 /* The number field is only as wide as a big number needs. */
 .numfield {
   /* Wide enough for 7 digits. */
diff --git a/web/gear.html b/web/gear.html
index a8ef773..f8473a3 100644
--- a/web/gear.html
+++ b/web/gear.html
@@ -38,7 +38,7 @@
 {{/* The table of all settings, one row each. */}}
 <table class="settingtable">
 {{/* The column headings, three with their help bubbles. */}}
-<thead><tr><th scope="col">Setting</th><th scope="col">{{template "tipbox" .Tips.default}}</th><th scope="col">{{template "tipbox" .Tips.saved}}</th><th scope="col">New value</th><th scope="col">{{template "tipbox" .Tips.range}}</th></tr></thead>
+<thead><tr><th scope="col">Inference parameters</th><th scope="col">{{template "tipbox" .Tips.default}}</th><th scope="col">{{template "tipbox" .Tips.saved}}</th><th scope="col">New value</th><th scope="col">{{template "tipbox" .Tips.range}}</th></tr></thead>
 {{/* The body. */}}
 <tbody>
 {{/* One row for each setting; the dollar sign reaches the page-level values from inside the loop. */}}
@@ -72,11 +72,11 @@
 {{/* The stop words are a box with one word per line. */}}
 {{else if eq .Kind "list"}}
 {{/* The box; a saved list can never be emptied. */}}
-<textarea class="stopfield" name="s_{{.Key}}" rows="3" cols="24" maxlength="2000" aria-label="{{.Heading}} for {{$.Model}}, one per line"{{if .HasSaved}} required{{end}}>{{.Typed}}</textarea>
+<textarea class="stopfield{{if not .HasSaved}} notset{{end}}" name="s_{{.Key}}" rows="3" cols="24" maxlength="2000" aria-label="{{.Heading}} for {{$.Model}}, one per line"{{if .HasSaved}} required{{end}}>{{.Typed}}</textarea>
 {{/* Numbers get a number field with the browser's own range check; the monitor checks again. */}}
 {{else}}
 {{/* The field; the suggestions belong to the context size only. */}}
-<input class="numfield" name="s_{{.Key}}" type="number" inputmode="decimal" min="{{.InMin}}" max="{{.InMax}}" step="{{.Step}}" aria-label="{{.Heading}} for {{$.Model}}" value="{{.Typed}}"{{if .HasSaved}} required{{end}}{{if .Presets}} list="presets"{{end}}>
+<input class="numfield{{if not .HasSaved}} notset{{end}}" name="s_{{.Key}}" type="number" inputmode="decimal" min="{{.InMin}}" max="{{.InMax}}" step="{{.Step}}" aria-label="{{.Heading}} for {{$.Model}}" value="{{.Typed}}"{{if .HasSaved}} required{{end}}{{if .Presets}} list="presets"{{end}}>
 {{/* The suggestions for the context size. */}}
 {{if .Presets}}<datalist id="presets">{{range .Presets}}<option value="{{.}}"></option>{{end}}</datalist>{{end}}
 {{/* End of the field choice. */}}
@@ -114,7 +114,7 @@
 {{/* The changes only. */}}
 <table class="settingtable">
 {{/* The headings. */}}
-<thead><tr><th scope="col">Setting</th><th scope="col">Now</th><th scope="col">After saving</th></tr></thead>
+<thead><tr><th scope="col">Inference parameters</th><th scope="col">Now</th><th scope="col">After saving</th></tr></thead>
 {{/* The body. */}}
 <tbody>
 {{/* One row for each change. */}}
@@ -162,7 +162,7 @@
 {{/* The values. */}}
 <table class="settingtable">
 {{/* The headings. */}}
-<thead><tr><th scope="col">Setting</th><th scope="col">Saved now</th></tr></thead>
+<thead><tr><th scope="col">Inference parameters</th><th scope="col">Saved now</th></tr></thead>
 {{/* The body. */}}
 <tbody>
 {{/* One row for each change. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
1bf749f8a064c33fad52f0efecd47a80427cc5e4dd1c4aebf3e875e0b133ffd9  gear_test.go
f4ebf1c303ce43002095ccd17f1dafa24b4ef4e125ba997672c225c01e1ae2f8  web/app.css
3ab9ef25c8e9a62b957fd3038135d0b23110f20b0e25772fa9b9629a6b81db82  web/gear.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
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
