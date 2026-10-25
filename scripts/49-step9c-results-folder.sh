#!/usr/bin/env bash
# Script 49: moves the compare button into the heading row of the Installed models panel and saves the performance results in PerformanceCompare next to the project (kept out of GitHub).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-comparison" ] || { echo "FAIL  not on feature/model-comparison"; exit 1; }
# Script 48 must be applied first (it adds the compare button).
grep -q 'comparebtn' web/app.css || { echo "FAIL  script 48 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'historyFolderName' perfstore.go; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/.gitignore b/.gitignore
index b9604fe..d9cbcfe 100644
--- a/.gitignore
+++ b/.gitignore
@@ -15,6 +15,9 @@ coverage.txt
 history/
 *.history.json
 
+# Saved performance test results (numbers about this machine): personal to each machine
+PerformanceCompare/
+
 # Local user settings written by the app: personal to each machine
 settings.json
 
diff --git a/perf_test.go b/perf_test.go
index 72c2a80..d432677 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -1080,6 +1080,8 @@ func TestMain(m *testing.M) {
 	} // end of the folder check
 	// Use it as the configuration folder.
 	userConfigDir = func() (string, error) { return dir, nil }
+	// The program's own place is not used by the tests, so no test can write a folder next to the test program.
+	executablePath = func() (string, error) { return "", errors.New("not used in tests") }
 	// Run the tests.
 	code := m.Run()
 	// Remove the folder.
@@ -1087,3 +1089,48 @@ func TestMain(m *testing.M) {
 	// Leave with the tests' result.
 	os.Exit(code)
 } // end of TestMain
+
+// TestDefaultHistoryPath checks where the saved results go: next to the project when the program runs from its bin folder, next to the program elsewhere, and in the configuration folder when the program's place is unknown.
+func TestDefaultHistoryPath(t *testing.T) {
+	// Put the real lookups back when the test ends.
+	oldExe, oldCfg := executablePath, userConfigDir
+	// Restore them.
+	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
+	// The configuration folder, for the fallback.
+	userConfigDir = func() (string, error) { return "/cfg", nil }
+	// The cases.
+	for _, c := range []struct {
+		// exe is where the program is.
+		exe string
+		// err is the failure of the lookup, when there is one.
+		err error
+		// want is the expected file.
+		want string
+	}{
+		// From the bin folder of the project.
+		{"/home/u/OllamaControlCenter/bin/OllamaControlCenter", nil, "/home/u/OllamaControlCenter/PerformanceCompare/performance.json"},
+		// From any other folder: next to the program.
+		{"/opt/occ/OllamaControlCenter", nil, "/opt/occ/PerformanceCompare/performance.json"},
+		// Unknown place: the configuration folder.
+		{"", errors.New("no path"), "/cfg/OllamaControlCenter/performance.json"},
+	} {
+		// Use this case.
+		executablePath = func() (string, error) { return c.exe, c.err }
+		// Ask.
+		got, note := defaultHistoryPath()
+		// Compare.
+		if filepath.ToSlash(got) != c.want || note != "" {
+			// Report it.
+			t.Errorf("exe %q: path %q note %q, want %q", c.exe, got, note, c.want)
+		} // end of the check
+	} // end of the loop
+	// No program place and no configuration folder: memory only, with a reason.
+	executablePath = func() (string, error) { return "", errors.New("no path") }
+	// No folder either.
+	userConfigDir = func() (string, error) { return "", errors.New("none") }
+	// Ask.
+	if got, note := defaultHistoryPath(); got != "" || note == "" {
+		// Report it.
+		t.Errorf("memory-only case: %q / %q", got, note)
+	} // end of the memory check
+} // end of TestDefaultHistoryPath
diff --git a/perfstore.go b/perfstore.go
index d0fc05e..6837882 100644
--- a/perfstore.go
+++ b/perfstore.go
@@ -45,14 +45,32 @@ type perfStore struct {
 	note string
 } // end of perfStore
 
-// defaultHistoryPath returns the history file in the person's configuration folder, or an empty text and a reason.
+// historyFolderName is the folder, next to the project, that holds the saved performance results.
+const historyFolderName = "PerformanceCompare"
+
+// executablePath finds the running program; a test replaces it.
+var executablePath = os.Executable
+
+// defaultHistoryPath returns the history file: in a folder named PerformanceCompare next to the project (the program normally runs from the project's bin folder, so that is the folder above it), or, when the program's own place cannot be found, in the person's configuration folder; an empty text and a reason mean memory only.
 func defaultHistoryPath() (string, string) {
-	// Ask for the configuration folder.
+	// Where is the running program?
+	if exe, err := executablePath(); err == nil && exe != "" {
+		// The folder that holds it.
+		dir := filepath.Dir(exe)
+		// A program in a folder called bin belongs to the project one level up.
+		if filepath.Base(dir) == "bin" {
+			// Go up one level.
+			dir = filepath.Dir(dir)
+		} // end of the bin check
+		// The results live in their own folder there.
+		return filepath.Join(dir, historyFolderName, "performance.json"), ""
+	} // end of the program check
+	// Ask for the configuration folder instead.
 	dir, err := userConfigDir()
 	// None found.
 	if err != nil || dir == "" {
 		// Memory only.
-		return "", "No configuration folder was found, so results are kept only until the monitor stops."
+		return "", "No folder for the results was found, so they are kept only until the monitor stops."
 	} // end of the lookup check
 	// The file lives in a folder of its own.
 	return filepath.Join(dir, "OllamaControlCenter", "performance.json"), ""
diff --git a/web/app.css b/web/app.css
index 2522d8a..75c1279 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1163,10 +1163,30 @@ button.btn-plain {
   margin-top: 1.4rem;
 } /* end of rule */
 
-/* The bar with the compare button: a little room above and below it. */
+/* The heading row of the Installed models panel: heading on the left, compare button on the right, wrapping below on a narrow window. */
+.panelhead {
+  /* Side by side. */
+  display: flex;
+  /* Wrap when the window is narrow. */
+  flex-wrap: wrap;
+  /* Level with each other. */
+  align-items: center;
+  /* Heading at the left, button at the right. */
+  justify-content: space-between;
+  /* Space between them when they wrap. */
+  gap: 0.4rem 1rem;
+} /* end of rule */
+
+/* The heading inside that row has no extra space of its own. */
+.panelhead h2 {
+  /* The row supplies the spacing. */
+  margin: 0.2rem 0;
+} /* end of rule */
+
+/* The bar with the compare button needs no outer space in the heading row. */
 .comparebar {
-  /* Space between the hint and the table. */
-  margin: 0.5rem 0 0.9rem;
+  /* No outer space. */
+  margin: 0;
 } /* end of rule */
 
 /* The compare button is a little bolder than the other outlined buttons, so it is seen as an action. */
@@ -1182,3 +1202,22 @@ button.btn-plain {
   /* Transparent background like the link version. */
   background: transparent;
 } /* end of rule */
+
+/* The compare button is at the right edge of the window, so its bubble is lined up with the button's right edge and opens towards the left. */
+.comparebar .tip-icon {
+  /* No left edge: the right edge decides. */
+  left: auto;
+  /* The bubble's right edge sits on the button's right edge. */
+  right: anchor(right);
+} /* end of rule */
+
+/* On a narrow window the bubble spans the window again. */
+@media (max-width: 40rem) {
+  /* The compare bubble. */
+  .comparebar .tip-icon {
+    /* Near the left edge. */
+    left: 0.5rem;
+    /* Near the right edge. */
+    right: 0.5rem;
+  } /* end of rule */
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 2c0685f..7315f8c 100644
--- a/web/index.html
+++ b/web/index.html
@@ -63,23 +63,10 @@
 {{/* The Installed models panel. */}}
 <section class="panel" aria-labelledby="installed-title">
 {{/* The panel heading, with the number of models when known. */}}
+{{/* The heading row: the heading on the left and, when there is a table, the compare button on the right. */}}
+<div class="panelhead">
 <h2 id="installed-title">Installed models{{if .HasTable}} ({{.Table.Total}}){{end}}</h2>
-{{/* Case 1: Ollama answered but the lists could not be read; say why in plain words. */}}
-{{if .TableError}}
-{{/* The cross and the word carry the meaning, the colour only supports it. */}}
-<p class="status bad"><span class="symbol" aria-hidden="true">✖</span> <strong>Could not read the model lists</strong> <span class="muted">{{.TableError}}</span></p>
-{{/* Case 2: no table because Ollama did not answer; the status panel above has the reason. */}}
-{{else if not .HasTable}}
-{{/* A plain note. */}}
-<p class="muted">The model tables appear when Ollama answers.</p>
-{{/* Case 3: Ollama answered and has no models. */}}
-{{else if not .Table.Groups}}
-{{/* A plain note. */}}
-<p class="muted">No models are installed.</p>
-{{/* Case 4: the table itself. */}}
-{{else}}
-{{/* A hint above the table so people know the dotted headings have help. */}}
-<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The chart icon 📈 before a model name opens its performance page (a model that is loaded may be in use, so it has none). The button Compare tested models above the table puts the tested models side by side. The table scrolls sideways.</p>
+{{if .HasTable}}{{if .Table.Groups}}
 {{/* The compare button: a labelled button above the table, with the number of models that have been tested. */}}
 <div class="comparebar">
 {{/* A small form that opens the comparison page and changes nothing. */}}
@@ -98,6 +85,24 @@
 </form>
 {{/* End of the compare button bar. */}}
 </div>
+{{end}}{{end}}
+</div>
+{{/* Case 1: Ollama answered but the lists could not be read; say why in plain words. */}}
+{{if .TableError}}
+{{/* The cross and the word carry the meaning, the colour only supports it. */}}
+<p class="status bad"><span class="symbol" aria-hidden="true">✖</span> <strong>Could not read the model lists</strong> <span class="muted">{{.TableError}}</span></p>
+{{/* Case 2: no table because Ollama did not answer; the status panel above has the reason. */}}
+{{else if not .HasTable}}
+{{/* A plain note. */}}
+<p class="muted">The model tables appear when Ollama answers.</p>
+{{/* Case 3: Ollama answered and has no models. */}}
+{{else if not .Table.Groups}}
+{{/* A plain note. */}}
+<p class="muted">No models are installed.</p>
+{{/* Case 4: the table itself. */}}
+{{else}}
+{{/* A hint above the table so people know the dotted headings have help. */}}
+<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The chart icon 📈 before a model name opens its performance page (a model that is loaded may be in use, so it has none). The button Compare tested models, at the top right of this panel, puts the tested models side by side. The table scrolls sideways.</p>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
af82c47b6fac3185b80dbc7df6b391776f22fe3605cc20c03c222b31a413c703  .gitignore
b3d7033c1e63a981576f476d4510cdecbe4f9abc867f64b90bda377ae6edd1f8  perf_test.go
7208d821b864bc99a9909b7be4b55cf72edb0db92354a2ad4c13270b55ad3007  perfstore.go
c97380767fff95716f4dc6eb96aad54d5c25c3e9eb2b72ba0082e33b4c416d87  web/app.css
5c3a60669679e5d476081f45cd96aaa07671f9efa797c5932be862ccae314a34  web/index.html
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
