#!/usr/bin/env bash
# Script 80c (second round of fixes to script 80, after your DGX Spark test): the report now marks a processor name that comes from lscpu as the operating system's own report (core designs, not a product name, not checked against the maker's specification), shows the computer model the firmware reports when there is one, notes graphics memory that the system did not report, and has no back arrow on the very first start (the monitor then opens only through Continue). It must be run on the branch where scripts 80 and 80b were already applied.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ -e syscheck.go ] && [ "$(git branch --show-current)" = "feature/system-check" ] || { echo "FAIL  scripts 80 and 80b are not applied here, or this is not feature/system-check"; exit 1; }
# Refuse to run twice.
if grep -q dmiModel sysreport.go 2>/dev/null; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/syscheck.go b/syscheck.go
index 4f7c4d7..eef70f0 100644
--- a/syscheck.go
+++ b/syscheck.go
@@ -96,6 +96,8 @@ type sysRow struct {
 	Label string
 	// Lines are the value, one per line.
 	Lines []string
+	// Note explains where a value comes from or why it is missing; empty means no note.
+	Note string
 } // end of sysRow
 
 // uninstallItem is one thing the uninstall removes.
@@ -118,6 +120,8 @@ type sysPage struct {
 	Theme, Size string
 	// Token is the page token for the forms.
 	Token string
+	// First is true on the very first start: the monitor can only be reached through Continue, so the page has no back arrow.
+	First bool
 	// Rows is the table "This computer".
 	Rows []sysRow
 	// Online says whether Ollama answered.
@@ -176,21 +180,29 @@ func reportRows(r hostReport) []sysRow {
 			gpus = append(gpus, describeGPU(g))
 		} // end of the card loop
 	} // end of the cards check
-	// The table.
-	return []sysRow{
-		// The operating system.
-		{"Operating system", []string{r.OS}},
-		// The architecture.
-		{"Architecture", []string{r.Arch}},
-		// The processor.
-		{"Processor", []string{cpu}},
-		// The cores.
-		{"Cores", []string{cores}},
-		// The memory.
-		{"Memory", []string{mem}},
-		// The cards.
-		{"Graphics cards", gpus},
-	}
+	// The table, row by row.
+	rows := []sysRow{{Label: "Operating system", Lines: []string{r.OS}}}
+	// The computer model, only when the firmware reports one.
+	if r.Model != "" {
+		// Add it.
+		rows = append(rows, sysRow{Label: "Computer model", Lines: []string{r.Model}})
+	} // end of the model check
+	// The architecture, the processor with its note, the cores and the memory.
+	rows = append(rows, sysRow{Label: "Architecture", Lines: []string{r.Arch}}, sysRow{Label: "Processor", Lines: []string{cpu}, Note: r.CPUNote}, sysRow{Label: "Cores", Lines: []string{cores}}, sysRow{Label: "Memory", Lines: []string{mem}})
+	// The cards, with a note when a card gave no memory figure.
+	gnote := ""
+	// Look for a card without a figure.
+	for _, g := range r.GPUs {
+		// One without memory.
+		if g.MemMiB == 0 {
+			// The note.
+			gnote = "Where no graphics memory is shown, the system did not report it (some graphics processors share the computer's memory)."
+		} // end of the memory check
+	} // end of the card loop
+	// Add the cards.
+	rows = append(rows, sysRow{Label: "Graphics cards", Lines: gpus, Note: gnote})
+	// Hand the table back.
+	return rows
 } // end of reportRows
 
 // guardedRoot says whether a path is exactly this program's own folder inside the standard base folder, so nothing else can ever be deleted.
@@ -304,10 +316,24 @@ func systemCheckHandlers(addr ollamaAddress, mon *monitor, token string, desktop
 		// Hand it back.
 		return *cached
 	} // end of getReport
+	// firstStart says whether this is the very first start, before the person has pressed Continue.
+	firstStart := func(r *http.Request) bool {
+		// Only the real program switches the check on, and only with a settings folder.
+		if !mon.firstRunCheck || mon.store.dir == "" || checkSeen(mon.store.dir) {
+			// Not the first start.
+			return false
+		} // end of the switch check
+		// A session note means Continue was pressed although the folder could not be written.
+		_, err := r.Cookie(systemCheckCookie)
+		// No note: still the first start.
+		return err != nil
+	} // end of firstStart
 	// send builds a page in memory first, so a template error gives a clean 500.
 	send := func(w http.ResponseWriter, r *http.Request, data sysPage) {
 		// What every page needs.
 		data.Theme, data.Token, data.Size = themeFromRequest(r), token, sizeFromRequest(r)
+		// On the first start there is no way back to the monitor except Continue.
+		data.First = firstStart(r)
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/syscheck_test.go b/syscheck_test.go
index 87a8da8..d5d025d 100644
--- a/syscheck_test.go
+++ b/syscheck_test.go
@@ -456,3 +456,31 @@ func TestGuardedRoot(t *testing.T) {
 	// The unused import guard for the context package in this file.
 	var _ context.Context
 } // end of TestGuardedRoot
+
+// TestNoBackArrowOnFirstStart checks that the very first start has no way back to the monitor except Continue, and that later visits have one.
+func TestNoBackArrowOnFirstStart(t *testing.T) {
+	// The first-start check is on and Continue was not pressed.
+	r := newSysRig(t, true, false)
+	// The report and the uninstall question have no arrow.
+	for _, path := range []string{"/systemcheck", "/uninstall"} {
+		// The page.
+		_, _, body := get(t, r.h, http.MethodGet, path)
+		// No back arrow.
+		if strings.Contains(body, "backcircle") {
+			// Report it.
+			t.Errorf("%s has a back arrow on the first start", path)
+		} // end of the check
+	} // end of the loop
+	// Press Continue.
+	post(t, r.h, "/systemcheck/continue", url.Values{"token": {r.token}}, fromThisPage)
+	// Later visits have the arrow.
+	for _, path := range []string{"/systemcheck", "/uninstall"} {
+		// The page.
+		_, _, body := get(t, r.h, http.MethodGet, path)
+		// The back arrow.
+		if !strings.Contains(body, "backcircle") {
+			// Report it.
+			t.Errorf("%s has no back arrow after Continue", path)
+		} // end of the check
+	} // end of the loop
+} // end of TestNoBackArrowOnFirstStart
diff --git a/sysreport.go b/sysreport.go
index 14635c6..06631fc 100644
--- a/sysreport.go
+++ b/sysreport.go
@@ -44,6 +44,12 @@ type hostReport struct {
 	Arch string
 	// CPU is the processor name; empty means not reported.
 	CPU string
+	// CPUSource names the tool the processor name came from when it is not the usual place ("lscpu"); empty means the usual place.
+	CPUSource string
+	// CPUNote says where the processor name came from when it is not a product name; empty otherwise.
+	CPUNote string
+	// Model is the computer's model as the firmware reports it (for example "NVIDIA DGX Spark"); empty means not reported.
+	Model string
 	// Logical is the number of logical processors.
 	Logical int
 	// Physical is the number of physical cores; 0 means not reported.
@@ -70,6 +76,8 @@ var (
 	reportArch = runtime.GOARCH
 	// reportLogical is the number of logical processors.
 	reportLogical = runtime.NumCPU
+	// dmiDir is the Linux folder where the firmware describes the computer (vendor and product name).
+	dmiDir = "/sys/class/dmi/id"
 	// osReleasePath is the Linux file that names the distribution.
 	osReleasePath = "/etc/os-release"
 	// probeRun runs one tool with fixed arguments and returns what it printed; a bare name is searched in the PATH.
@@ -327,6 +335,45 @@ func parseLscpuModels(text string) string {
 	return strings.Join(names, " + ")
 } // end of parseLscpuModels
 
+// dmiModel reads the vendor and product name that the firmware reports; placeholder texts that makers leave in are ignored.
+func dmiModel() string {
+	// One value from a file.
+	read := func(name string) string {
+		// Read it.
+		data, err := os.ReadFile(filepath.Join(dmiDir, name))
+		// Not readable.
+		if err != nil {
+			// Not reported.
+			return ""
+		} // end of the read check
+		// The text.
+		v := strings.TrimSpace(string(data))
+		// Texts that mean nothing.
+		switch strings.ToLower(v) {
+		// The usual placeholders.
+		case "", "unknown", "default string", "system product name", "system manufacturer", "to be filled by o.e.m.", "not specified", "none":
+			// Not reported.
+			return ""
+		} // end of the placeholder check
+		// The value.
+		return v
+	} // end of read
+	// The two parts.
+	vendor, product := read("sys_vendor"), read("product_name")
+	// No product: nothing useful.
+	if product == "" {
+		// Not reported.
+		return ""
+	} // end of the product check
+	// The product already starts with the vendor name (for example "NVIDIA DGX Spark").
+	if vendor == "" || strings.HasPrefix(strings.ToLower(product), strings.ToLower(vendor)) {
+		// Just the product.
+		return product
+	} // end of the vendor check
+	// Both.
+	return vendor + " " + product
+} // end of dmiModel
+
 // osReleaseName reads PRETTY_NAME from the text of /etc/os-release.
 func osReleaseName(text string) string {
 	// One setting per line.
@@ -543,6 +590,8 @@ func collectReport(ctx context.Context) hostReport {
 				r.OS = n
 			} // end of the name check
 		} // end of the file check
+		// The computer model from the firmware.
+		r.Model = dmiModel()
 		// The physical cores.
 		if out, err := probeRun(ctx, "lscpu", "-p=CORE,SOCKET"); err == nil {
 			// Count them.
@@ -554,6 +603,16 @@ func collectReport(ctx context.Context) hostReport {
 			if out, err := probeRun(ctx, "lscpu"); err == nil {
 				// Use the names it prints.
 				r.CPU = parseLscpuModels(out)
+				// Say where it came from, so the page can mark it.
+				if r.CPU != "" {
+					// The tool.
+					r.CPUSource = "lscpu"
+				} // end of the source mark
+				// Say where the name comes from, because it is a core design and not a product name.
+				if r.CPU != "" {
+					// The note.
+					r.CPUNote = "Core designs as reported by the operating system (lscpu). This computer does not report a product name for its processor."
+				} // end of the note check
 			} // end of the lscpu check
 		} // end of the missing-name case
 		// The display adapters.
diff --git a/sysreport_test.go b/sysreport_test.go
index 9a69c58..9f6ea3a 100644
--- a/sysreport_test.go
+++ b/sysreport_test.go
@@ -415,9 +415,57 @@ func TestCollectReportArmProcessorName(t *testing.T) {
 	reportOS, reportArch = "linux", "arm64"
 	// Collect.
 	r := collectReport(context.Background())
+	// The note says the name is a core design, not a product name.
+	if !strings.Contains(r.CPUNote, "Core designs") {
+		// Report it.
+		t.Errorf("note = %q", r.CPUNote)
+	} // end of the note check
 	// The name comes from lscpu.
-	if r.CPU != "Cortex-X925 + Cortex-A725" {
+	if r.CPU != "Cortex-X925 + Cortex-A725" || r.CPUSource != "lscpu" {
 		// Report it.
 		t.Errorf("cpu = %q", r.CPU)
 	} // end of the name check
 } // end of TestCollectReportArmProcessorName
+
+// TestDmiModel checks the computer model from the firmware, and that placeholders are ignored.
+func TestDmiModel(t *testing.T) {
+	// Put the folder back at the end.
+	old := dmiDir
+	// Restore.
+	t.Cleanup(func() { dmiDir = old })
+	// A fake folder.
+	dmiDir = t.TempDir()
+	// Write one value.
+	put := func(name, v string) {
+		// Write the file.
+		if err := os.WriteFile(filepath.Join(dmiDir, name), []byte(v+"\n"), 0o600); err != nil {
+			// Stop.
+			t.Fatal(err)
+		} // end of the write check
+	} // end of put
+	// The product already holds the vendor.
+	put("sys_vendor", "NVIDIA")
+	// The product.
+	put("product_name", "NVIDIA DGX Spark")
+	// Only the product.
+	if got := dmiModel(); got != "NVIDIA DGX Spark" {
+		// Report it.
+		t.Errorf("model = %q", got)
+	} // end of the check
+	// Vendor and product are joined when the product lacks the vendor.
+	put("sys_vendor", "Dell Inc.")
+	// The product.
+	put("product_name", "XPS 15")
+	// Joined.
+	if got := dmiModel(); got != "Dell Inc. XPS 15" {
+		// Report it.
+		t.Errorf("model = %q", got)
+	} // end of the join check
+	// A placeholder is ignored.
+	put("product_name", "To Be Filled By O.E.M.")
+	// Nothing.
+	if got := dmiModel(); got != "" {
+		// Report it.
+		t.Errorf("placeholder = %q", got)
+	} // end of the placeholder check
+} // end of TestDmiModel
diff --git a/web/systemcheck.html b/web/systemcheck.html
index e3c3dba..72af781 100644
--- a/web/systemcheck.html
+++ b/web/systemcheck.html
@@ -18,8 +18,8 @@
 <main>
 {{/* A panel that holds the content. */}}
 <section class="panel">
-{{/* After the monitor has stopped there is nothing to go back to, so that page has no arrow. */}}
-{{if ne .Kind "removed"}}
+{{/* After the monitor has stopped there is nothing to go back to, and on the very first start the monitor opens only through Continue, so those pages have no arrow. */}}
+{{if and (ne .Kind "removed") (not .First)}}
 {{/* The back arrow in the top right corner: a round link to the monitor; it only follows a link and changes nothing. */}}
 <span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{end}}
@@ -30,7 +30,7 @@
 <h2>This computer</h2>
 {{/* The facts of this computer; a figure the system did not give says "not reported". */}}
 <table class="settingtable"><tbody>
-{{range .Rows}}<tr><th scope="row">{{.Label}}</th><td>{{range $i, $l := .Lines}}{{if $i}}<br>{{end}}{{$l}}{{end}}</td></tr>
+{{range .Rows}}<tr><th scope="row">{{.Label}}</th><td>{{range $i, $l := .Lines}}{{if $i}}<br>{{end}}{{$l}}{{end}}{{if .Note}}<br><span class="muted">{{.Note}}</span>{{end}}</td></tr>
 {{end}}</tbody></table>
 <h2>Ollama</h2>
 {{if .Online}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
1b4e5135516e6c48a606a288eaca254fb88b897c32d7234c9ba288e15f1dfa41  syscheck.go
028b9d93c4e47686be6fa6448372b5e292cd45331c639ae1b666cde1ca4cee36  syscheck_test.go
d654d7e2aee84cdb72330b9d469cda5e682cbcf3cfb5030fa776ebe6bd3e824d  sysreport.go
7efbb9cc6633fb7e3c167466cbcb45cad144ed8dcd001b33378c1e0f745699a0  sysreport_test.go
6cb89e4faa2706e0b39931dce78061537ad8f1f539679f34792432d4ba592bf5  web/systemcheck.html
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
echo "NEXT  start ./bin/OllamaControlCenter and open http://127.0.0.1:8765/systemcheck : check the Computer model and Processor rows; the arrow at the top right must be gone until you press Continue; then commit, push and merge"
# List the changed files; nothing is committed yet.
git status --short
