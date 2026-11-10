#!/usr/bin/env bash
# Script 106 (About page, estimate of the program's own use): a new button on the About page runs the System check now and adds what the operating system reports for this program, then shows an estimate of its memory, disk space and graphics card use, with the System check run's time and zone; the last estimate is saved in the data folder and shown again until a new one is made. Every figure is called an estimate. Tests follow.
# Run it from a new branch made from main (after script 105 is merged): cd ~/LLMsControlDock && git switch -c feature/about-own-use-estimate && bash scripts/106-step69-about-own-use-estimate.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 105), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["about.go"]="f7e4c976dd51d15e2281826638a0392fad0ec0468e9701a01d6a7737e67c9317"
BEFORE["web.go"]="2e67258c7106deea5a706547c3c4b613a0d7522374f1353079a2ae5d15cce72b"
BEFORE["web/about.html"]="429e536d1aac5ab6dcc03dca575bb3b12b85f05efc86f369e9f6c59d53145533"
BEFORE["web/app.css"]="b26028a60974a7dcb59ec030a01cb959e0b6a540b32bc50a93292c958717c1ee"
AFTER["about.go"]="483e88b5291d08558cced4c01d89e94fd050b716703d99e4122ce9ae0a0017b8"
AFTER["web.go"]="c4a35c301cb27b92cf82303f4534b064436859cc53211cf86d4da8954d319b20"
AFTER["web/about.html"]="c39ce0430378dd7b84774ac46ca20a42ad7d3725622928690474475330ef2d69"
AFTER["web/app.css"]="9e23db3c0823a8c04bfca47a95bc626f9f957e9d4cb470cb14e6591730a026c6"
AFTER["selfusage.go"]="afda00f61c9f56a9ffd995f0fe74cf188764a16d89aad5a244652c070a35b7f3"
AFTER["selfusage_test.go"]="894e8abafa4f73a641a38aa4da7bb7ce3b8853d3ea07b33df130a082ebba885d"

# Count of passed checks.
PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/about-own-use-estimate"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 105 must have been applied: its test file exists.
[ -f agesort_test.go ] || fail "script 105 must be applied first"
# Report it.
pass "script 105 is applied"

# Refuse to run twice: the new file exists when this change was applied before.
if [ -e selfusage.go ]; then fail "selfusage.go already exists: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files to change are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/about.go b/about.go
index c98bb2f..a331f8e 100644
--- a/about.go
+++ b/about.go
@@ -142,6 +142,10 @@ type aboutPage struct {
 	Services []companyService
 	// Platform is the Go version, the operating system and the processor type.
 	Platform string
+	// Token is the page's secret for the estimate button.
+	Token string
+	// Estimate is the last saved estimate, or nil when there is none.
+	Estimate *estimateView
 } // end of aboutPage
 
 // revisionFromBuild picks the short revision, the modified flag and the revision date (always shown in UTC) out of the recorded build facts.
@@ -192,7 +196,7 @@ func revisionFromBuild() (string, bool, string) {
 } // end of revisionFromBuild
 
 // aboutHandler builds the handler of the read-only About page; it changes nothing and needs no token.
-func aboutHandler() http.HandlerFunc {
+func aboutHandler(token string) http.HandlerFunc {
 	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
 	page := template.Must(template.New("about").Parse(aboutTemplateText))
 	// The handler itself.
@@ -239,9 +243,18 @@ func aboutHandler() http.HandlerFunc {
 			CompanyURL: companyLink("about-card"),
 			// The services.
 			Services: companyServices,
+			// The form's token for the estimate button.
+			Token: token,
 			// Go version, system and processor.
 			Platform: runtime.Version() + " on " + runtime.GOOS + "/" + runtime.GOARCH,
 		} // end of the data
+		// The last saved estimate, if there is one.
+		if e, ok := loadSelfEstimate(); ok {
+			// Its texts.
+			v := viewOfEstimate(e)
+			// Show it.
+			data.Estimate = &v
+		} // end of the estimate check
 		// Build the page in memory first, so a template error produces a clean 500 and not a half page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/selfusage.go b/selfusage.go
new file mode 100644
index 0000000..a4f9889
--- /dev/null
+++ b/selfusage.go
@@ -0,0 +1,406 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context limits how long the System check may take.
+	"context"
+	// encoding/json writes and reads the saved estimate.
+	"encoding/json"
+	// fmt builds the size texts.
+	"fmt"
+	// io limits how much of a file is read.
+	"io"
+	// io/fs lets the folder walk skip what it cannot read.
+	"io/fs"
+	// log writes the reason when saving fails.
+	"log"
+	// net/http provides requests and status codes.
+	"net/http"
+	// os reads, writes and measures files.
+	"os"
+	// path/filepath joins folder and file names for any operating system.
+	"path/filepath"
+	// runtime reports the memory the program holds.
+	"runtime"
+	// strconv turns the numbers in the memory file into integers.
+	"strconv"
+	// strings splits and trims text.
+	"strings"
+	// time stamps the estimate.
+	"time"
+) // end of imports
+
+// selfEstimateFile is the file that keeps the last estimate, inside the program's data folder.
+const selfEstimateFile = "selfestimate.json"
+
+// maxSelfEstimateFile is the largest saved estimate that is read (a real one is under 2 KiB).
+const maxSelfEstimateFile = 64 * 1024
+
+// The readers below are variables so that a test can replace them.
+var (
+	// selfReport runs the System check (the same function the System check page uses).
+	selfReport = collectReport
+	// selfMemory reads the memory this program holds now, in bytes, and says which kind of figure it is.
+	selfMemory = osSelfMemory
+	// selfNow gives the current time.
+	selfNow = time.Now
+) // end of the reader variables
+
+// selfEstimate is one estimate of what this program uses; every figure is an estimate from one run, not a promise.
+type selfEstimate struct {
+	// At is the moment of the run.
+	At time.Time `json:"at"`
+	// RAMBytes is the memory this program held at that moment; 0 means not reported.
+	RAMBytes int64 `json:"ram_bytes"`
+	// RAMKind says what kind of figure RAMBytes is: "resident" (the memory the operating system says this program occupies) or "runtime" (the memory the Go runtime asked from the system, used where the first is not available).
+	RAMKind string `json:"ram_kind"`
+	// ExeBytes is the size of the program file; 0 means not reported.
+	ExeBytes int64 `json:"exe_bytes"`
+	// DataBytes is the size of the saved data (results, copies, snapshots, settings and logs).
+	DataBytes int64 `json:"data_bytes"`
+	// MachineRAM is the memory of this computer as the System check reported it; 0 means not reported.
+	MachineRAM int64 `json:"machine_ram"`
+	// FreeDisk is the free disk space where the data is kept; 0 means not reported.
+	FreeDisk int64 `json:"free_disk"`
+	// GPUs are the graphics cards the System check found, as lines of text.
+	GPUs []string `json:"gpus"`
+} // end of selfEstimate
+
+// osSelfMemory reads the memory this program holds now: on Linux the resident size from the operating system, elsewhere (or when that cannot be read) the memory the Go runtime obtained from the system.
+func osSelfMemory() (int64, string) {
+	// Linux keeps the figure in a text file.
+	if runtime.GOOS == "linux" {
+		// Read the file.
+		if data, err := os.ReadFile("/proc/self/status"); err == nil {
+			// Look at every line.
+			for _, line := range strings.Split(string(data), "\n") {
+				// The resident size line looks like "VmRSS:   12345 kB".
+				if strings.HasPrefix(line, "VmRSS:") {
+					// The words after the name.
+					f := strings.Fields(strings.TrimPrefix(line, "VmRSS:"))
+					// A number and a unit.
+					if len(f) >= 1 {
+						// Read the number (kibibytes).
+						if kb, err := strconv.ParseInt(f[0], 10, 64); err == nil && kb > 0 {
+							// In bytes.
+							return kb * 1024, "resident"
+						} // end of the number check
+					} // end of the words check
+				} // end of the line check
+			} // end of the line loop
+		} // end of the read check
+	} // end of the Linux case
+	// The Go runtime's own count.
+	var ms runtime.MemStats
+	// Fill it in.
+	runtime.ReadMemStats(&ms)
+	// Its total obtained from the system.
+	return int64(ms.Sys), "runtime"
+} // end of osSelfMemory
+
+// folderBytes adds up the sizes of the files in a folder and below it; what cannot be read is skipped, and a missing folder counts as 0.
+func folderBytes(dir string) int64 {
+	// No folder given.
+	if dir == "" {
+		// Nothing.
+		return 0
+	} // end of the empty check
+	// The sum.
+	var total int64
+	// Walk the folder.
+	filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
+		// Skip what cannot be read.
+		if err != nil {
+			// Carry on with the rest.
+			return nil
+		} // end of the error check
+		// Only files have a size to add.
+		if !d.IsDir() {
+			// Its information.
+			if info, err := d.Info(); err == nil {
+				// Add it.
+				total += info.Size()
+			} // end of the information check
+		} // end of the file check
+		// Carry on.
+		return nil
+	}) // end of the walk
+	// The sum.
+	return total
+} // end of folderBytes
+
+// measureSelf runs the System check and then reads the figures of this program; it is read-only and changes nothing.
+func measureSelf(ctx context.Context) selfEstimate {
+	// The moment of the run.
+	e := selfEstimate{At: selfNow()}
+	// The System check: the computer's memory and graphics cards.
+	rep := selfReport(ctx)
+	// The computer's memory.
+	e.MachineRAM = rep.MemBytes
+	// The graphics cards, as lines.
+	for _, g := range rep.GPUs {
+		// One line each.
+		e.GPUs = append(e.GPUs, describeGPU(g))
+	} // end of the card loop
+	// The memory this program holds now.
+	e.RAMBytes, e.RAMKind = selfMemory()
+	// The program file.
+	if exe, err := executablePath(); err == nil {
+		// Its size.
+		if info, err := os.Stat(exe); err == nil {
+			// Keep it.
+			e.ExeBytes = info.Size()
+		} // end of the size check
+	} // end of the program check
+	// The saved data: the data folder and the state folder (they may be the same one).
+	data, state := dataRoot(), stateRoot()
+	// The data folder.
+	e.DataBytes = folderBytes(data)
+	// The state folder, when it is another one.
+	if state != data {
+		// Add it.
+		e.DataBytes += folderBytes(state)
+	} // end of the state check
+	// The free space where the data is kept.
+	if data != "" {
+		// Ask the system.
+		if free, err := osFreeDiskBytes(nearestFolder(data)); err == nil {
+			// Keep it.
+			e.FreeDisk = int64(free)
+		} // end of the free check
+	} // end of the data check
+	// The finished estimate.
+	return e
+} // end of measureSelf
+
+// nearestFolder returns the folder itself, or the nearest folder above it that exists (the data folder may not have been made yet).
+func nearestFolder(dir string) string {
+	// Go up until a folder exists.
+	for dir != "" {
+		// Does it exist?
+		if info, err := os.Stat(dir); err == nil && info.IsDir() {
+			// Found.
+			return dir
+		} // end of the exist check
+		// One level up.
+		up := filepath.Dir(dir)
+		// The top was reached.
+		if up == dir {
+			// Give up.
+			return dir
+		} // end of the top check
+		// Try the next one.
+		dir = up
+	} // end of the loop
+	// Nothing.
+	return dir
+} // end of nearestFolder
+
+// saveSelfEstimate keeps the estimate in the data folder; a failure is logged and the page still shows the result of this run.
+func saveSelfEstimate(e selfEstimate) {
+	// The folder.
+	dir := dataRoot()
+	// No folder known.
+	if dir == "" {
+		// Nothing to write.
+		return
+	} // end of the folder check
+	// Make the folder when it does not exist yet.
+	if err := os.MkdirAll(dir, 0o700); err != nil {
+		// Log it.
+		log.Printf("About: the estimate could not be saved: %v", err)
+		// Stop.
+		return
+	} // end of the folder creation
+	// The text of the file.
+	body, err := json.Marshal(e)
+	// A failure here is a bug.
+	if err != nil {
+		// Log it.
+		log.Printf("About: the estimate could not be written: %v", err)
+		// Stop.
+		return
+	} // end of the encoding check
+	// Write to a temporary file first, so a power cut never leaves half a file.
+	tmp, err := os.CreateTemp(dir, "selfestimate-*.tmp")
+	// A failure.
+	if err != nil {
+		// Log it.
+		log.Printf("About: the estimate could not be started: %v", err)
+		// Stop.
+		return
+	} // end of the temp check
+	// Remove the temporary file if something below fails.
+	defer os.Remove(tmp.Name())
+	// Write it.
+	if _, err := tmp.Write(body); err != nil {
+		// Close it.
+		tmp.Close()
+		// Log it.
+		log.Printf("About: the estimate could not be written: %v", err)
+		// Stop.
+		return
+	} // end of the write check
+	// Finish the file.
+	if err := tmp.Close(); err != nil {
+		// Log it.
+		log.Printf("About: the estimate could not be finished: %v", err)
+		// Stop.
+		return
+	} // end of the close check
+	// Private to this person; not fatal on systems without file modes.
+	os.Chmod(tmp.Name(), 0o600)
+	// Put it in place in one step.
+	if err := os.Rename(tmp.Name(), filepath.Join(dir, selfEstimateFile)); err != nil {
+		// Log it.
+		log.Printf("About: the estimate could not be put in place: %v", err)
+	} // end of the rename check
+} // end of saveSelfEstimate
+
+// loadSelfEstimate reads the saved estimate; ok is false when there is none or the file is damaged (a damaged file is never shown).
+func loadSelfEstimate() (selfEstimate, bool) {
+	// The folder.
+	dir := dataRoot()
+	// No folder known.
+	if dir == "" {
+		// None.
+		return selfEstimate{}, false
+	} // end of the folder check
+	// Open the file.
+	f, err := os.Open(filepath.Join(dir, selfEstimateFile))
+	// Missing.
+	if err != nil {
+		// None.
+		return selfEstimate{}, false
+	} // end of the open check
+	// Close it at the end.
+	defer f.Close()
+	// Read it, with a limit.
+	body, err := io.ReadAll(io.LimitReader(f, maxSelfEstimateFile))
+	// A failure.
+	if err != nil {
+		// None.
+		return selfEstimate{}, false
+	} // end of the read check
+	// Decode it.
+	var e selfEstimate
+	// Damaged, or without a time.
+	if err := json.Unmarshal(body, &e); err != nil || e.At.IsZero() {
+		// None.
+		return selfEstimate{}, false
+	} // end of the decode check
+	// The estimate.
+	return e, true
+} // end of loadSelfEstimate
+
+// sizeText writes a number of bytes in the unit that reads best (powers of 1024, as the operating systems show them); 0 reads as "not reported".
+func sizeText(n int64) string {
+	// Nothing known.
+	if n <= 0 {
+		// Say so.
+		return "not reported"
+	} // end of the empty check
+	// Bytes.
+	if n < 1<<10 {
+		// As bytes.
+		return fmt.Sprintf("%d bytes", n)
+	} // end of the byte case
+	// Kilobytes.
+	if n < 1<<20 {
+		// One decimal.
+		return fmt.Sprintf("%.1f KB", float64(n)/float64(1<<10))
+	} // end of the kilobyte case
+	// Megabytes.
+	if n < 1<<30 {
+		// One decimal.
+		return fmt.Sprintf("%.1f MB", float64(n)/float64(1<<20))
+	} // end of the megabyte case
+	// Gigabytes.
+	return fmt.Sprintf("%.1f GB", float64(n)/float64(1<<30))
+} // end of sizeText
+
+// estimateView is the estimate as the About page shows it.
+type estimateView struct {
+	// When is the moment of the run, with its time zone.
+	When string
+	// RAM is the memory this program held, as text.
+	RAM string
+	// RAMKind explains which kind of figure the memory is.
+	RAMKind string
+	// RAMShare is the memory as a share of the computer's memory, or empty.
+	RAMShare string
+	// Exe is the size of the program file.
+	Exe string
+	// Data is the size of the saved data.
+	Data string
+	// Disk is the program file and the saved data together, with the free space.
+	Disk string
+	// GPUs are the cards the System check found.
+	GPUs []string
+} // end of estimateView
+
+// viewOfEstimate turns a saved estimate into the texts of the page.
+func viewOfEstimate(e selfEstimate) estimateView {
+	// The time, in the computer's own zone, with the zone's name and offset.
+	v := estimateView{When: e.At.Local().Format("2006-01-02 15:04:05 MST (UTC-07:00)")}
+	// The memory.
+	v.RAM = sizeText(e.RAMBytes)
+	// Which kind of figure it is.
+	if e.RAMKind == "resident" {
+		// The operating system's figure.
+		v.RAMKind = "the memory the operating system says this program occupies"
+	} else {
+		// The Go runtime's figure.
+		v.RAMKind = "the memory the Go runtime obtained from the system (this system gives no closer figure)"
+	} // end of the kind choice
+	// The share of the computer's memory.
+	if e.RAMBytes > 0 && e.MachineRAM > 0 {
+		// One decimal.
+		v.RAMShare = fmt.Sprintf("about %.1f%% of the %s this computer has", float64(e.RAMBytes)*100/float64(e.MachineRAM), sizeText(e.MachineRAM))
+	} // end of the share check
+	// The program file.
+	v.Exe = sizeText(e.ExeBytes)
+	// The saved data; an empty folder is 0 bytes, which is a real figure.
+	if e.DataBytes > 0 {
+		// The size.
+		v.Data = sizeText(e.DataBytes)
+	} else {
+		// A real zero.
+		v.Data = "none yet"
+	} // end of the data choice
+	// Both together, with the free space.
+	total := e.ExeBytes + e.DataBytes
+	// The text.
+	v.Disk = sizeText(total)
+	// The free space.
+	if e.FreeDisk > 0 {
+		// Add it.
+		v.Disk += ", on a disk with " + sizeText(e.FreeDisk) + " free"
+	} // end of the free check
+	// The cards.
+	v.GPUs = e.GPUs
+	// The finished view.
+	return v
+} // end of viewOfEstimate
+
+// selfEstimateHandler runs the System check, measures this program, saves the result and goes back to the About page; only the page's own form may start it.
+func selfEstimateHandler(token string) http.HandlerFunc {
+	// The handler itself.
+	return func(w http.ResponseWriter, r *http.Request) {
+		// Only the page's own form may do this.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "forbidden", http.StatusForbidden)
+			// Stop.
+			return
+		} // end of the token check
+		// The System check may take a few seconds; stop it after the limit.
+		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
+		// Release the timer at the end.
+		defer cancel()
+		// Measure and keep.
+		saveSelfEstimate(measureSelf(ctx))
+		// Back to the estimate; a redirect keeps a reload from running it again.
+		http.Redirect(w, r, "/about#estimate", http.StatusSeeOther)
+	} // end of the handler
+} // end of selfEstimateHandler
diff --git a/selfusage_test.go b/selfusage_test.go
new file mode 100644
index 0000000..b082929
--- /dev/null
+++ b/selfusage_test.go
@@ -0,0 +1,181 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages the tests use.
+	// context is passed to the measuring function.
+	"context"
+	// net/http gives the method names and status codes.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// os writes test files.
+	"os"
+	// path/filepath joins file names.
+	"path/filepath"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time gives fixed moments.
+	"time"
+) // end of imports
+
+// fakeSelfReaders replaces the System check, the memory reader and the clock with fixed answers, and puts the real ones back at the end.
+func fakeSelfReaders(t *testing.T) {
+	// Mark this as a helper.
+	t.Helper()
+	// Keep the real ones.
+	oldReport, oldMem, oldNow := selfReport, selfMemory, selfNow
+	// Put them back at the end.
+	t.Cleanup(func() { selfReport, selfMemory, selfNow = oldReport, oldMem, oldNow })
+	// A computer with 64 GiB and one card.
+	selfReport = func(ctx context.Context) hostReport {
+		// The fixed report.
+		return hostReport{MemBytes: 64 << 30, GPUs: []gpuInfo{{Vendor: "nvidia", Name: "Test Card", MemMiB: 8192}}}
+	} // end of the fake report
+	// The program holds 256 MiB.
+	selfMemory = func() (int64, string) { return 256 << 20, "resident" }
+	// A fixed moment (UTC).
+	selfNow = func() time.Time { return time.Date(2026, 11, 10, 16, 0, 0, 0, time.UTC) }
+} // end of fakeSelfReaders
+
+// TestSizeText checks the size texts, including the "not reported" case.
+func TestSizeText(t *testing.T) {
+	// The cases.
+	for n, want := range map[int64]string{0: "not reported", 500: "500 bytes", 1536: "1.5 KB", 5 << 20: "5.0 MB", 3 << 30: "3.0 GB"} {
+		// Compare.
+		if got := sizeText(n); got != want {
+			// Report.
+			t.Errorf("sizeText(%d) = %q, want %q", n, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestSizeText
+
+// TestFolderBytesAddsFiles checks the folder size: files in sub-folders count, a missing folder is 0.
+func TestFolderBytesAddsFiles(t *testing.T) {
+	// A folder with two files.
+	dir := t.TempDir()
+	// A sub-folder.
+	os.MkdirAll(filepath.Join(dir, "sub"), 0o700)
+	// Ten bytes.
+	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("0123456789"), 0o600)
+	// Five bytes.
+	os.WriteFile(filepath.Join(dir, "sub", "b.txt"), []byte("01234"), 0o600)
+	// The sum.
+	if got := folderBytes(dir); got != 15 {
+		// Report.
+		t.Errorf("folderBytes = %d, want 15", got)
+	} // end of the sum check
+	// A missing folder and an empty name.
+	if folderBytes(filepath.Join(dir, "none")) != 0 || folderBytes("") != 0 {
+		// Report.
+		t.Error("a missing folder must count as 0")
+	} // end of the missing check
+} // end of TestFolderBytesAddsFiles
+
+// TestMeasureSelfUsesTheSystemCheck checks that the estimate carries the System check's figures and the program's own.
+func TestMeasureSelfUsesTheSystemCheck(t *testing.T) {
+	// A throw-away data folder with 10 bytes in it.
+	isolateFindData(t)
+	// Fixed readers.
+	fakeSelfReaders(t)
+	// A program file of 7 bytes (the tests' own lookup may point elsewhere).
+	exe := filepath.Join(t.TempDir(), "prog")
+	// Write it.
+	os.WriteFile(exe, []byte("1234567"), 0o700)
+	// Put the real lookup back at the end.
+	oldExe := executablePath
+	t.Cleanup(func() { executablePath = oldExe })
+	// Use it.
+	executablePath = func() (string, error) { return exe, nil }
+	// Some saved data.
+	os.WriteFile(filepath.Join(dataRoot(), "x.txt"), []byte("0123456789"), 0o600)
+	// Measure.
+	e := measureSelf(context.Background())
+	// The checks.
+	if e.MachineRAM != 64<<30 || e.RAMBytes != 256<<20 || e.RAMKind != "resident" || len(e.GPUs) != 1 || !strings.Contains(e.GPUs[0], "Test Card") || e.DataBytes < 10 || e.ExeBytes != 7 || e.FreeDisk <= 0 {
+		// Report.
+		t.Errorf("estimate %+v", e)
+	} // end of the checks
+} // end of TestMeasureSelfUsesTheSystemCheck
+
+// TestSelfEstimateSaveLoadAndDamaged checks that a saved estimate comes back and that a damaged file is ignored.
+func TestSelfEstimateSaveLoadAndDamaged(t *testing.T) {
+	// A throw-away data folder.
+	isolateFindData(t)
+	// Nothing saved yet.
+	if _, ok := loadSelfEstimate(); ok {
+		// Report.
+		t.Fatal("an estimate exists before any was saved")
+	} // end of the empty check
+	// Save one.
+	at := time.Date(2026, 11, 10, 16, 0, 0, 0, time.UTC)
+	// The save.
+	saveSelfEstimate(selfEstimate{At: at, RAMBytes: 123, RAMKind: "runtime"})
+	// Read it back.
+	e, ok := loadSelfEstimate()
+	// The checks.
+	if !ok || e.RAMBytes != 123 || !e.At.Equal(at) {
+		// Report.
+		t.Errorf("loaded %+v, %v", e, ok)
+	} // end of the check
+	// Damage the file.
+	os.WriteFile(filepath.Join(dataRoot(), selfEstimateFile), []byte("{not json"), 0o600)
+	// A damaged file is never shown.
+	if _, ok := loadSelfEstimate(); ok {
+		// Report.
+		t.Error("a damaged file was accepted")
+	} // end of the damaged check
+} // end of TestSelfEstimateSaveLoadAndDamaged
+
+// TestAboutEstimateButtonAndResult checks the whole round trip on the About page: the button and the "no estimate yet" text first, a refused wrong token, then a run that saves the result and shows it with the word "estimate" and the time.
+func TestAboutEstimateButtonAndResult(t *testing.T) {
+	// A throw-away data folder.
+	isolateFindData(t)
+	// Fixed readers.
+	fakeSelfReaders(t)
+	// The rig.
+	rig := newThemeRig(t)
+	// The page before any estimate.
+	_, _, first := get(t, rig.h, http.MethodGet, "/about")
+	// The button, the explanation and the empty state; no script.
+	for _, want := range []string{`action="/about/estimate"`, "Estimate what this program uses", "No estimate has been made yet.", "based on that one run"} {
+		// Look for it.
+		if !strings.Contains(first, want) {
+			// Report.
+			t.Errorf("the About page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// No script on the About page.
+	if strings.Contains(first, "<script") {
+		// Report.
+		t.Error("the About page carries a script")
+	} // end of the script check
+	// A wrong token is refused and saves nothing.
+	if res := post(t, rig.h, "/about/estimate", url.Values{"token": {"wrong"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+		// Report.
+		t.Errorf("wrong token = %d, want 403", res.StatusCode)
+	} // end of the token check
+	// Nothing was saved.
+	if _, ok := loadSelfEstimate(); ok {
+		// Report.
+		t.Error("a refused request saved an estimate")
+	} // end of the refused check
+	// A real run redirects back to the estimate.
+	res := post(t, rig.h, "/about/estimate", url.Values{"token": {rig.token}}, fromThisPage)
+	// The redirect.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/about#estimate" {
+		// Report.
+		t.Fatalf("estimate = %d to %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the redirect check
+	// The page now shows the figures.
+	_, _, after := get(t, rig.h, http.MethodGet, "/about")
+	// What must be there.
+	for _, want := range []string{"Memory (estimated)", "256.0 MB", "about 0.4% of the 64.0 GB", "Disk space (estimated)", "Graphics card (estimated)", "None used by this program itself", "Test Card", "Estimated on ", "from the System check run at that moment", "Estimate again"} {
+		// Look for it.
+		if !strings.Contains(after, want) {
+			// Report.
+			t.Errorf("the estimate lacks %q", want)
+		} // end of the look
+	} // end of the loop
+} // end of TestAboutEstimateButtonAndResult
diff --git a/web/about.html b/web/about.html
index 5eb50b2..7b474ac 100644
--- a/web/about.html
+++ b/web/about.html
@@ -47,6 +47,42 @@
 <tr><th scope="row">Licence</th><td><a href="{{.LicenceURL}}" target="_blank" rel="noopener noreferrer">{{.Licence}}<span class="sr-only"> (opens in a new window)</span></a>. {{.Copyright}}</td></tr>
 {{/* End of the table. */}}
 </table>
+{{/* The estimate of what this program itself uses. Every figure is called an estimate and is tied to the System check run behind it. */}}
+<section id="estimate" class="estimatecard" aria-labelledby="esttitle">
+{{/* The heading. */}}
+<h2 id="esttitle">What this program uses (estimate)</h2>
+{{/* What the button does, and what the figures are. */}}
+<p class="muted">The button runs the System check now and adds what the operating system reports for this program. The figures are an <strong>estimate</strong> based on that one run: they change with use, and the models that Ollama loads are not counted here, because Ollama holds them, not this program.</p>
+{{/* The button: a form that only this page can send. */}}
+<form method="post" action="/about/estimate">
+{{/* The page's secret. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The button. */}}
+<button type="submit" class="btn-plain">{{if .Estimate}}Estimate again{{else}}Estimate what this program uses{{end}}</button>
+{{/* End of the form. */}}
+</form>
+{{/* The last saved estimate. */}}
+{{if .Estimate}}
+{{/* The table of estimated figures. */}}
+<table class="aboutfacts">
+{{/* The caption for screen readers. */}}
+<caption class="sr-only">Estimated use of this program, from one System check run</caption>
+{{/* The memory. */}}
+<tr><th scope="row">Memory (estimated)</th><td>{{.Estimate.RAM}}{{if .Estimate.RAMShare}}, {{.Estimate.RAMShare}}{{end}}. This is {{.Estimate.RAMKind}}.</td></tr>
+{{/* The disk. */}}
+<tr><th scope="row">Disk space (estimated)</th><td>{{.Estimate.Disk}}. Program file: {{.Estimate.Exe}}. Saved data (results, copies, snapshots, settings and logs): {{.Estimate.Data}}.</td></tr>
+{{/* The graphics card. */}}
+<tr><th scope="row">Graphics card (estimated)</th><td>None used by this program itself; it only shows pages and talks to Ollama.{{if .Estimate.GPUs}} Cards the System check found, which Ollama may use: {{range $i, $g := .Estimate.GPUs}}{{if $i}}; {{end}}{{$g}}{{end}}.{{else}} The System check found no graphics card.{{end}}</td></tr>
+{{/* End of the table. */}}
+</table>
+{{/* When it was made. */}}
+<p class="muted"><small>Estimated on {{.Estimate.When}}, from the System check run at that moment. Press the button again for a new estimate.</small></p>
+{{else}}
+{{/* Nothing made yet. */}}
+<p class="muted">No estimate has been made yet.</p>
+{{end}}
+{{/* End of the estimate card. */}}
+</section>
 {{/* The dedication, set apart so it stands out. */}}
 <blockquote class="dedication">{{.Dedication}}</blockquote>
 {{/* The developer's company: what it does, and a way to find out more. */}}
diff --git a/web/app.css b/web/app.css
index bca9fa0..dc88a49 100644
--- a/web/app.css
+++ b/web/app.css
@@ -3018,3 +3018,23 @@ html[data-size="medium"] svg[width="22"] {
   /* The normal text colour. */
   color: var(--text);
 } /* end of rule */
+
+/* The estimate card on the About page: the same outline as the company card. */
+.estimatecard {
+  /* Space above and below the card. */
+  margin: 1.25rem 0;
+  /* Air inside. */
+  padding: 1rem 1.25rem;
+  /* A solid outline. */
+  border: 2px solid var(--border);
+  /* Rounded corners. */
+  border-radius: 0.5rem;
+} /* end of rule */
+
+/* The heading of the estimate card. */
+.estimatecard h2 {
+  /* Tight to the top. */
+  margin: 0.1rem 0 0.3rem;
+  /* A little larger than body text. */
+  font-size: 1.1rem;
+} /* end of rule */
diff --git a/web.go b/web.go
index cdfa48e..a2fac1d 100644
--- a/web.go
+++ b/web.go
@@ -179,7 +179,9 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 		w.Write(appIcon)
 	}) // end of the icon route
 	// Route: a GET request for "/about" shows the read-only About page (see about.go).
-	mux.HandleFunc("GET /about", aboutHandler())
+	mux.HandleFunc("GET /about", aboutHandler(token))
+	// Route: a POST request for "/about/estimate" runs the System check, measures this program and saves the estimate.
+	mux.HandleFunc("POST /about/estimate", selfEstimateHandler(token))
 	// Make the two Settings handlers: the first shows the page, the second saves the form (see settingspage.go).
 	settingsShow, settingsSave := settingsHandlers(addr, mon, token)
 	// Route: a GET request for "/settings" shows the Settings page.
OCC_PATCH_94_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched and new files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done


# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and open the About page and press the new estimate button (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
