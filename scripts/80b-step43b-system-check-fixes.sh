#!/usr/bin/env bash
# Script 80b (fixes to script 80, after your first test on the DGX Spark): the processor name is now also read from lscpu, because ARM computers have no name in /proc/cpuinfo (the DGX Spark has two kinds of core and shows both), and the Continue button is a dull green and the Uninstall button a dull red. It must be run on the branch where script 80 was already applied.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ -e syscheck.go ] && [ "$(git branch --show-current)" = "feature/system-check" ] || { echo "FAIL  script 80 is not applied here, or this is not feature/system-check"; exit 1; }
# Refuse to run twice.
if grep -q parseLscpuModels sysreport.go 2>/dev/null; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/sysreport.go b/sysreport.go
index 44ce65b..14635c6 100644
--- a/sysreport.go
+++ b/sysreport.go
@@ -96,8 +96,12 @@ func realProbe(ctx context.Context, name string, args ...string) (string, error)
 	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
 	// Release the timer at the end.
 	defer cancel()
+	// Prepare the command.
+	cmd := exec.CommandContext(ctx, exe, args...)
+	// Ask for the plain English output, so the labels that the parsers look for never come translated.
+	cmd.Env = append(os.Environ(), "LC_ALL=C")
 	// Run it and collect its output.
-	out, err := exec.CommandContext(ctx, exe, args...).Output()
+	out, err := cmd.Output()
 	// Hand back the text and any error.
 	return strings.TrimSpace(string(out)), err
 } // end of realProbe
@@ -292,6 +296,37 @@ func parseLscpuCores(text string) int {
 	return len(seen)
 } // end of parseLscpuCores
 
+// parseLscpuModels reads the "Model name:" lines of the plain "lscpu" output and joins the different names; computers with two kinds of core (such as the DGX Spark, with Cortex-X925 and Cortex-A725 cores) print one such line per kind, and ARM computers have no name in /proc/cpuinfo at all.
+func parseLscpuModels(text string) string {
+	// The names in the order found.
+	var names []string
+	// The names already seen.
+	seen := map[string]bool{}
+	// One line at a time.
+	for _, line := range strings.Split(text, "\n") {
+		// Split at the first colon.
+		k, v, ok := strings.Cut(line, ":")
+		// Only the model name lines count.
+		if !ok || strings.TrimSpace(k) != "Model name" {
+			// Next line.
+			continue
+		} // end of the key check
+		// The name.
+		v = strings.TrimSpace(v)
+		// Skip empty and repeated names.
+		if v == "" || seen[v] {
+			// Next line.
+			continue
+		} // end of the skip check
+		// Remember it.
+		seen[v] = true
+		// Keep it.
+		names = append(names, v)
+	} // end of the line loop
+	// Join the kinds with a plus sign.
+	return strings.Join(names, " + ")
+} // end of parseLscpuModels
+
 // osReleaseName reads PRETTY_NAME from the text of /etc/os-release.
 func osReleaseName(text string) string {
 	// One setting per line.
@@ -513,6 +548,14 @@ func collectReport(ctx context.Context) hostReport {
 			// Count them.
 			r.Physical = parseLscpuCores(out)
 		} // end of the lscpu check
+		// No processor name in /proc/cpuinfo (ARM computers): take it from lscpu.
+		if r.CPU == "" {
+			// Ask lscpu.
+			if out, err := probeRun(ctx, "lscpu"); err == nil {
+				// Use the names it prints.
+				r.CPU = parseLscpuModels(out)
+			} // end of the lscpu check
+		} // end of the missing-name case
 		// The display adapters.
 		if out, err := probeRun(ctx, "lspci", "-mm"); err == nil {
 			// Read them.
diff --git a/sysreport_test.go b/sysreport_test.go
index f90e183..9a69c58 100644
--- a/sysreport_test.go
+++ b/sysreport_test.go
@@ -381,3 +381,43 @@ func TestReportRows(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 } // end of TestReportRows
+
+// TestParseLscpuModels checks the processor names of a computer with two kinds of core, and of one kind.
+func TestParseLscpuModels(t *testing.T) {
+	// Two kinds of core, each with its own Model name line (indented, as lscpu prints them).
+	two := "Architecture: aarch64\nVendor ID: ARM\n  Model name: Cortex-X925\n  Core(s) per socket: 10\n  Model name: Cortex-A725\n  Core(s) per socket: 10\n"
+	// Joined in order.
+	if got := parseLscpuModels(two); got != "Cortex-X925 + Cortex-A725" {
+		// Report it.
+		t.Errorf("two kinds = %q", got)
+	} // end of the two-kinds check
+	// The same name twice is shown once.
+	if got := parseLscpuModels("Model name: Cortex-A76\nModel name: Cortex-A76\n"); got != "Cortex-A76" {
+		// Report it.
+		t.Errorf("repeated = %q", got)
+	} // end of the repeat check
+	// No such line: nothing.
+	if got := parseLscpuModels("Architecture: x\n"); got != "" {
+		// Report it.
+		t.Errorf("none = %q", got)
+	} // end of the none check
+} // end of TestParseLscpuModels
+
+// TestCollectReportArmProcessorName checks that a Linux computer without a name in /proc/cpuinfo gets its processor name from lscpu.
+func TestCollectReportArmProcessorName(t *testing.T) {
+	// A calm machine, then no name from the normal reader.
+	quietMachine(t)
+	// The ARM case: /proc/cpuinfo has no name.
+	readCPUName = func() string { return "" }
+	// The tools.
+	fakeProbes(t, map[string]string{"lscpu": "Model name: Cortex-X925\nModel name: Cortex-A725\n"})
+	// Linux on ARM.
+	reportOS, reportArch = "linux", "arm64"
+	// Collect.
+	r := collectReport(context.Background())
+	// The name comes from lscpu.
+	if r.CPU != "Cortex-X925 + Cortex-A725" {
+		// Report it.
+		t.Errorf("cpu = %q", r.CPU)
+	} // end of the name check
+} // end of TestCollectReportArmProcessorName
diff --git a/web/app.css b/web/app.css
index 20c3f2d..96452ce 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2361,3 +2361,66 @@ html[data-size="medium"] svg[width="22"] {
   /* A little room above and below. */
   margin: 0.3rem 0;
 } /* end of rule */
+
+/* System check buttons: a dull green for Continue and a dull red for Uninstall; each has a word on it, so colour is never the only signal (text contrast is at least 4.5:1 on each colour). */
+:root {
+  /* Continue: fill and text. */
+  --go: #2f6b3f;
+  /* Text on the green. */
+  --go-text: #ffffff;
+  /* Uninstall: fill and text. */
+  --danger: #9c3b36;
+  /* Text on the red. */
+  --danger-text: #ffffff;
+} /* end of rule */
+
+/* The same colours for a chosen dark theme: lighter fills with dark text. */
+:root[data-theme="dark"] {
+  /* Continue. */
+  --go: #86c795;
+  /* Text on the green. */
+  --go-text: #121417;
+  /* Uninstall. */
+  --danger: #dc918b;
+  /* Text on the red. */
+  --danger-text: #121417;
+} /* end of rule */
+
+/* And when the system is dark and no theme was chosen. */
+@media (prefers-color-scheme: dark) {
+  /* Only without a chosen theme. */
+  :root:not([data-theme]) {
+    /* Continue. */
+    --go: #86c795;
+    /* Text on the green. */
+    --go-text: #121417;
+    /* Uninstall. */
+    --danger: #dc918b;
+    /* Text on the red. */
+    --danger-text: #121417;
+  } /* end of rule */
+} /* end of media query */
+
+/* The green button. */
+.btn-go {
+  /* Outline and fill. */
+  border-color: var(--go);
+  /* Fill. */
+  background: var(--go);
+  /* Text. */
+  color: var(--go-text);
+} /* end of rule */
+
+/* The red button; it may be a link, so it also drops the underline. */
+.btn-danger {
+  /* Outline. */
+  border-color: var(--danger);
+  /* Fill. */
+  background: var(--danger);
+  /* Text. */
+  color: var(--danger-text);
+  /* No underline when it is a link. */
+  text-decoration: none;
+  /* Sit in the line like a button. */
+  display: inline-block;
+} /* end of rule */
diff --git a/web/systemcheck.html b/web/systemcheck.html
index 84b719d..e3c3dba 100644
--- a/web/systemcheck.html
+++ b/web/systemcheck.html
@@ -52,10 +52,10 @@
 {{/* Continue: records the answer and opens the monitor. */}}
 <form method="post" action="/systemcheck/continue">
 <input type="hidden" name="token" value="{{.Token}}">
-<span class="tipbox"><button type="submit" class="btn-solid" aria-describedby="tipcontinue">Continue to the monitor</button><span class="tip" role="tooltip" id="tipcontinue">Open the monitor. This report stays available later under System check, and you will not be asked again.</span></span>
+<span class="tipbox"><button type="submit" class="btn-solid btn-go" aria-describedby="tipcontinue">Continue to the monitor</button><span class="tip" role="tooltip" id="tipcontinue">Open the monitor. This report stays available later under System check, and you will not be asked again.</span></span>
 </form>
 {{/* Uninstall: only goes to the confirmation page; nothing is removed yet. */}}
-<span class="tipbox"><a class="btn-plain" href="/uninstall" aria-describedby="tipuninstall">Uninstall this tool</a><span class="tip" role="tooltip" id="tipuninstall">Removes the desktop icon and this program&rsquo;s saved settings, results and history, after you confirm. Your Ollama and its models are not touched. You then delete the program file yourself.</span></span>
+<span class="tipbox"><a class="btn-solid btn-danger" href="/uninstall" aria-describedby="tipuninstall">Uninstall this tool</a><span class="tip" role="tooltip" id="tipuninstall">Removes the desktop icon and this program&rsquo;s saved settings, results and history, after you confirm. Your Ollama and its models are not touched. You then delete the program file yourself.</span></span>
 </div>
 {{/* Version 2: the uninstall question. */}}
 {{else if eq .Kind "uninstall"}}
@@ -73,7 +73,7 @@
 {{/* Confirm: the real removal, then the monitor stops. */}}
 <form method="post" action="/uninstall/confirm">
 <input type="hidden" name="token" value="{{.Token}}">
-{{if .Items}}<span class="tipbox"><button type="submit" class="btn-solid" aria-describedby="tipyes">Yes, remove these files</button><span class="tip" role="tooltip" id="tipyes">Deletes the items above and stops the monitor. This cannot be undone.</span></span>{{else}}<span class="tipbox"><button type="submit" class="btn-solid" aria-describedby="tipyes">Stop the monitor</button><span class="tip" role="tooltip" id="tipyes">Nothing is deleted. The monitor stops and the program file to delete is shown.</span></span>{{end}}
+{{if .Items}}<span class="tipbox"><button type="submit" class="btn-solid btn-danger" aria-describedby="tipyes">Yes, remove these files</button><span class="tip" role="tooltip" id="tipyes">Deletes the items above and stops the monitor. This cannot be undone.</span></span>{{else}}<span class="tipbox"><button type="submit" class="btn-solid btn-danger" aria-describedby="tipyes">Stop the monitor</button><span class="tip" role="tooltip" id="tipyes">Nothing is deleted. The monitor stops and the program file to delete is shown.</span></span>{{end}}
 </form>
 {{/* The safe choice goes back to the report and changes nothing. */}}
 <span class="tipbox"><a class="btn-plain" href="/systemcheck" aria-describedby="tipno">No, go back</a><span class="tip" role="tooltip" id="tipno">Nothing is removed. You return to the System check.</span></span>
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
a853152ba0527dba459fbfb3e4b2205ef72b82bf3dcc269a1e4f535241bb892d  sysreport.go
d519bfe072871a33b564ae8d6eee8e83abaeaad43c4062ac21b2824ccc9e2bfd  sysreport_test.go
c8ed39238a91434f2b1e959885f3e871bd68645943c6ad1ed8e7e5b990b1d47c  web/app.css
28ffe4bbc838d9bfd463e30060c2ead8b2f5b57518458ee23c995295c19ea893  web/systemcheck.html
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
# Build for this computer the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Check that the program also compiles for Windows and macOS (nothing is kept).
for target in windows/amd64 darwin/arm64 darwin/amd64; do
  # Build for one target and throw the file away.
  GOOS="${target%/*}" GOARCH="${target#*/}" CGO_ENABLED=0 go build -trimpath -o /dev/null . || { echo "FAIL  build for $target"; exit 1; }
  # Report it.
  echo "PASS  compiles for $target"
done
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
# Tell the person what to look at.
echo "NEXT  start ./bin/OllamaControlCenter and open http://127.0.0.1:8765/systemcheck : check the Processor row and the two button colours; then commit, push and merge"
# List the changed files; nothing is committed yet.
git status --short
