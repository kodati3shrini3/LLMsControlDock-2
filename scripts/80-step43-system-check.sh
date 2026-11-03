#!/usr/bin/env bash
# Script 80 (first-start system report with Continue or Uninstall, version 0.28.0): on the first start the program shows what this computer offers (operating system, architecture, processor, cores, memory, graphics cards), judged only against the minimums Ollama publishes on its GPU page, says plainly that the tool works with Ollama only (not vLLM), and offers Continue or Uninstall, each with a tooltip. The report stays available later under System check. Uninstall removes the desktop icon and the three program folders after a confirmation, stops the monitor, and shows the program file for you to delete.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/system-check" ] || { echo "FAIL  not on feature/system-check"; exit 1; }
# Refuse to run twice.
if [ -e syscheck.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index 6bc449a..cfe683b 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.27.1"
+const appVersion = "0.28.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/desktopicon.go b/desktopicon.go
index 4fdd8be..194a829 100644
--- a/desktopicon.go
+++ b/desktopicon.go
@@ -405,8 +405,8 @@ func (d desktopIcon) create() error {
 	return d.remember("created")
 } // end of create
 
-// remove deletes the launcher and the picture, and remembers "declined" so the question does not return by itself.
-func (d desktopIcon) remove() error {
+// removeFiles deletes the launcher and the picture and remembers nothing (the uninstall uses this, because remembering would re-create the settings folder).
+func (d desktopIcon) removeFiles() error {
 	// The launcher.
 	if p := d.desktopPath(); p != "" {
 		// Delete it; a missing file is fine.
@@ -423,6 +423,17 @@ func (d desktopIcon) remove() error {
 			return err
 		} // end of the delete check
 	} // end of the picture case
+	// Done.
+	return nil
+} // end of removeFiles
+
+// remove deletes the launcher and the picture, and remembers "declined" so the question does not return by itself.
+func (d desktopIcon) remove() error {
+	// Delete the files.
+	if err := d.removeFiles(); err != nil {
+		// Report it.
+		return err
+	} // end of the delete check
 	// Keep the answer.
 	return d.remember("declined")
 } // end of remove
diff --git a/main.go b/main.go
index 3e36ecf..3f08ef2 100644
--- a/main.go
+++ b/main.go
@@ -207,6 +207,8 @@ func main() {
 	mon := newMonitorWith(store)
 	// The real desktop, so the first-run banner and the Settings buttons can place the icon.
 	mon.denv = realDesktopEnv()
+	// The first start shows the System check.
+	mon.firstRunCheck = true
 	// The listen address: the -listen option if it was given, else "other machines allowed" from the settings, else this computer only.
 	listenAddr, listenSource := chooseListen(*listen, listenGiven(), store.get().AllowOthers)
 	// Tell the Settings page how the program was started.
@@ -229,7 +231,7 @@ func main() {
 			// Release the timer at the end.
 			defer cancel()
 			// With the history file switched on, write the checks one last time, so a stop loses nothing.
-			if store.get().SaveHistory {
+			if store.get().SaveHistory && !noSaveOnStop.Load() {
 				// A failed write is not fatal.
 				_ = store.saveSamples(mon.hist.all())
 			} // end of the history write
diff --git a/monitor.go b/monitor.go
index 9fd71af..2cd210d 100644
--- a/monitor.go
+++ b/monitor.go
@@ -153,6 +153,8 @@ func (h *sampleHistory) since(from time.Time) []sample {
 
 // monitor holds what the page shows about Ollama's health: the counters and the history of checks.
 type monitor struct {
+	// firstRunCheck is true in the real program: the first start shows the System check before the monitor.
+	firstRunCheck bool
 	// health counts the failed checks (the API health box).
 	health *apiHealth
 	// hist keeps the checks for the charts.
diff --git a/syscheck.go b/syscheck.go
new file mode 100644
index 0000000..4f7c4d7
--- /dev/null
+++ b/syscheck.go
@@ -0,0 +1,447 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds a page in memory first.
+	"bytes"
+	// context limits how long the detection may take.
+	"context"
+	// encoding/json keeps the first-start answer in a small file.
+	"encoding/json"
+	// fmt builds the result words.
+	"fmt"
+	// html/template fills the page and escapes everything.
+	"html/template"
+	// io limits how much of a file is read.
+	"io"
+	// log reports template errors.
+	"log"
+	// net/http is the web server.
+	"net/http"
+	// os removes folders and reads their state.
+	"os"
+	// path/filepath joins and checks paths.
+	"path/filepath"
+	// strings joins labels.
+	"strings"
+	// sync keeps the detection and the stop to one run.
+	"sync"
+	// sync/atomic holds the flag that stops the history save.
+	"sync/atomic"
+	// time sets waits and limits.
+	"time"
+
+	// embed stores the page template inside the program.
+	_ "embed"
+) // end of imports
+
+// systemCheckTemplateText holds the System check pages, stored inside the executable at build time.
+//
+//go:embed web/systemcheck.html
+var systemCheckTemplateText string
+
+// systemCheckFileName is the small file in the settings folder that remembers the first start was answered.
+const systemCheckFileName = "system-check.json"
+
+// systemCheckCookie is a session note that the first-start report was answered, so a settings folder that cannot be written never causes a loop.
+const systemCheckCookie = "occ-syscheck"
+
+// noSaveOnStop is set by the uninstall so that the stop does not write the check history again (that would re-create the folder).
+var noSaveOnStop atomic.Bool
+
+// checkSeen says whether the first-start report was already answered.
+func checkSeen(dir string) bool {
+	// No folder: nothing can be remembered.
+	if dir == "" {
+		// Not remembered.
+		return false
+	} // end of the folder check
+	// Open the file.
+	f, err := os.Open(filepath.Join(dir, systemCheckFileName))
+	// A missing file means not answered yet.
+	if err != nil {
+		// Not answered.
+		return false
+	} // end of the open check
+	// Close it at the end.
+	defer f.Close()
+	// The content: a flag.
+	var c struct {
+		// Seen is true after Continue.
+		Seen bool `json:"seen"`
+	} // end of the content shape
+	// Read at most 1 KiB; a damaged file counts as not answered.
+	if err := json.NewDecoder(io.LimitReader(f, 1024)).Decode(&c); err != nil {
+		// Not answered.
+		return false
+	} // end of the decode check
+	// The flag.
+	return c.Seen
+} // end of checkSeen
+
+// markSeen remembers that the first-start report was answered.
+func markSeen(dir string) error {
+	// Nowhere to write.
+	if dir == "" {
+		// Nothing to keep.
+		return nil
+	} // end of the folder check
+	// Write it the safe way (a private file).
+	return writeFile(dir, systemCheckFileName, []byte("{\"seen\":true}\n"))
+} // end of markSeen
+
+// sysRow is one row of the table "This computer".
+type sysRow struct {
+	// Label is the row heading.
+	Label string
+	// Lines are the value, one per line.
+	Lines []string
+} // end of sysRow
+
+// uninstallItem is one thing the uninstall removes.
+type uninstallItem struct {
+	// What names it in words.
+	What string
+	// Where is its full path.
+	Where string
+	// Result is filled in after the removal.
+	Result string
+	// remove deletes it.
+	remove func() error
+} // end of uninstallItem
+
+// sysPage is what the System check templates show.
+type sysPage struct {
+	// Kind is report, uninstall or removed.
+	Kind string
+	// Theme and Size are the saved look.
+	Theme, Size string
+	// Token is the page token for the forms.
+	Token string
+	// Rows is the table "This computer".
+	Rows []sysRow
+	// Online says whether Ollama answered.
+	Online bool
+	// Address is the Ollama address, with any password hidden.
+	Address string
+	// Version is Ollama's version when it answered.
+	Version string
+	// Reason is why it did not answer.
+	Reason string
+	// Findings are the verdict lines.
+	Findings []finding
+	// Source names the page the verdicts come from.
+	Source string
+	// Items are the things an uninstall removes.
+	Items []uninstallItem
+	// Program is the full path of the program file the person deletes.
+	Program string
+} // end of sysPage
+
+// notReported is the word for a figure the system did not give.
+const notReported = "not reported"
+
+// reportRows turns the report into the rows of the table.
+func reportRows(r hostReport) []sysRow {
+	// The processor.
+	cpu := r.CPU
+	// Not known.
+	if cpu == "" {
+		// Say so.
+		cpu = notReported
+	} // end of the processor check
+	// The cores.
+	cores := fmt.Sprintf("%d logical (physical cores %s)", r.Logical, notReported)
+	// Physical cores known.
+	if r.Physical > 0 {
+		// Both.
+		cores = fmt.Sprintf("%d logical (%d physical)", r.Logical, r.Physical)
+	} // end of the cores check
+	// The memory.
+	mem := notReported
+	// Known.
+	if r.MemBytes > 0 {
+		// In GB.
+		mem = gigabytes(r.MemBytes)
+	} // end of the memory check
+	// The graphics cards.
+	gpus := []string{"none reported"}
+	// Some found.
+	if len(r.GPUs) > 0 {
+		// The heading line.
+		gpus = []string{fmt.Sprintf("%d found:", len(r.GPUs))}
+		// One line each.
+		for _, g := range r.GPUs {
+			// Add it.
+			gpus = append(gpus, describeGPU(g))
+		} // end of the card loop
+	} // end of the cards check
+	// The table.
+	return []sysRow{
+		// The operating system.
+		{"Operating system", []string{r.OS}},
+		// The architecture.
+		{"Architecture", []string{r.Arch}},
+		// The processor.
+		{"Processor", []string{cpu}},
+		// The cores.
+		{"Cores", []string{cores}},
+		// The memory.
+		{"Memory", []string{mem}},
+		// The cards.
+		{"Graphics cards", gpus},
+	}
+} // end of reportRows
+
+// guardedRoot says whether a path is exactly this program's own folder inside the standard base folder, so nothing else can ever be deleted.
+func guardedRoot(root string, lookup func() (string, error)) bool {
+	// Ask for the base folder.
+	base, err := lookup()
+	// None known.
+	if err != nil || base == "" || root == "" {
+		// Not safe.
+		return false
+	} // end of the base check
+	// The path must be absolute, end in the program's folder name, and be exactly base + name.
+	return filepath.IsAbs(root) && filepath.Base(root) == dataFolderName && root == filepath.Join(base, dataFolderName)
+} // end of guardedRoot
+
+// uninstallPlan lists what an uninstall would remove, and only what exists now.
+func uninstallPlan(d desktopIcon) []uninstallItem {
+	// The items.
+	var items []uninstallItem
+	// The desktop icon.
+	if d.exists() {
+		// Add it.
+		items = append(items, uninstallItem{What: "Desktop icon", Where: d.desktopPath(), remove: d.removeFiles})
+	} // end of the icon case
+	// The three folders; on macOS they are the same folder, so equal paths are joined into one line.
+	type folder struct {
+		// what names it.
+		what string
+		// root is its path.
+		root string
+		// lookup finds its base folder.
+		lookup func() (string, error)
+	} // end of folder
+	// The three.
+	folders := []folder{
+		// Settings.
+		{"Settings", configRoot(), userConfigDir},
+		// Results.
+		{"Results, saved copies and deleted models", dataRoot(), userDataDir},
+		// History and log.
+		{"Check history and log", stateRoot(), userStateDir},
+	} // end of the folder list
+	// Index of each path in items.
+	at := map[string]int{}
+	// Go through them.
+	for _, f := range folders {
+		// Not present: nothing to remove.
+		if f.root == "" {
+			// Next.
+			continue
+		} // end of the empty check
+		// Is the folder there?
+		if _, err := os.Stat(f.root); err != nil {
+			// Next.
+			continue
+		} // end of the exists check
+		// Already listed under another name: join the names.
+		if i, ok := at[f.root]; ok {
+			// Join.
+			items[i].What += " and " + strings.ToLower(f.what[:1]) + f.what[1:]
+			// Next.
+			continue
+		} // end of the duplicate check
+		// Keep the values for the closure.
+		root, lookup := f.root, f.lookup
+		// Remember the position.
+		at[root] = len(items)
+		// Add it.
+		items = append(items, uninstallItem{What: f.what, Where: root, remove: func() error {
+			// Only the program's own folder may ever be deleted.
+			if !guardedRoot(root, lookup) {
+				// Refuse.
+				return fmt.Errorf("refused: this is not the program's own folder")
+			} // end of the guard
+			// Delete the folder and everything in it.
+			return os.RemoveAll(root)
+		}}) // end of the item
+	} // end of the folder loop
+	// Hand the list back.
+	return items
+} // end of uninstallPlan
+
+// systemCheckHandlers builds the four handlers: the report, Continue, the uninstall question and the uninstall itself.
+func systemCheckHandlers(addr ollamaAddress, mon *monitor, token string, desktop desktopIcon) (show, cont, ask, confirm http.HandlerFunc) {
+	// Read the template once.
+	page := template.Must(template.New("syscheck").Parse(systemCheckTemplateText))
+	// The hardware report is made once, when first needed; the hardware does not change while the program runs.
+	var (
+		// mu protects the cached report.
+		mu sync.Mutex
+		// cached is the report.
+		cached *hostReport
+	) // end of the cache variables
+	// getReport returns the cached report, making it on first use.
+	getReport := func(ctx context.Context) hostReport {
+		// One at a time.
+		mu.Lock()
+		// Release at the end.
+		defer mu.Unlock()
+		// Make it once.
+		if cached == nil {
+			// Detect, with a limit.
+			c, cancel := context.WithTimeout(ctx, 60*time.Second)
+			// Release the timer.
+			defer cancel()
+			// The report.
+			r := collectReport(c)
+			// Keep it.
+			cached = &r
+		} // end of the first-use case
+		// Hand it back.
+		return *cached
+	} // end of getReport
+	// send builds a page in memory first, so a template error gives a clean 500.
+	send := func(w http.ResponseWriter, r *http.Request, data sysPage) {
+		// What every page needs.
+		data.Theme, data.Token, data.Size = themeFromRequest(r), token, sizeFromRequest(r)
+		// Build the page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason.
+			log.Printf("system check page error: %v", err)
+			// Send a plain 500.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the page.
+		w.Write(buf.Bytes())
+	} // end of send
+	// formOK runs the checks every form shares.
+	formOK := func(w http.ResponseWriter, r *http.Request) bool {
+		// A form is small.
+		r.Body = http.MaxBytesReader(w, r.Body, 1024)
+		// Only a form on this very page may send this request.
+		if !sameOrigin(r) {
+			// Refuse.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return false
+		} // end of the origin check
+		// Read the form.
+		if err := r.ParseForm(); err != nil {
+			// Refuse.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return false
+		} // end of the form check
+		// The token must match.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return false
+		} // end of the token check
+		// All good.
+		return true
+	} // end of formOK
+	// show: the report, with a fresh Ollama check.
+	show = func(w http.ResponseWriter, r *http.Request) {
+		// The hardware.
+		rep := getReport(r.Context())
+		// Ask Ollama once.
+		res := checkOllama(r.Context(), addr.URL, mon.timeoutOr(defaultCheckTimeout))
+		// Fill in the page.
+		send(w, r, sysPage{Kind: "report", Rows: reportRows(rep), Online: res.Online, Address: addr.URL.Redacted(), Version: res.Version, Reason: res.Reason, Findings: judgeReport(rep), Source: ollamaGPUSource})
+	} // end of show
+	// cont: remember the answer and open the monitor.
+	cont = func(w http.ResponseWriter, r *http.Request) {
+		// The checks.
+		if !formOK(w, r) {
+			// A refusal was already sent.
+			return
+		} // end of the checks
+		// Remember it in the settings folder (a failure is not fatal).
+		_ = markSeen(mon.store.dir)
+		// And for this session, so a folder that cannot be written never causes a loop.
+		http.SetCookie(w, &http.Cookie{Name: systemCheckCookie, Value: "1", Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode})
+		// Open the monitor.
+		http.Redirect(w, r, "/", http.StatusSeeOther)
+	} // end of cont
+	// ask: the confirmation page; it changes nothing.
+	ask = func(w http.ResponseWriter, r *http.Request) {
+		// The program file the person deletes afterwards.
+		exe, _ := executablePath()
+		// Show what would be removed.
+		send(w, r, sysPage{Kind: "uninstall", Items: uninstallPlan(desktop), Program: exe})
+	} // end of ask
+	// Stop only once, however many times the button is pressed.
+	var once sync.Once
+	// confirm: remove the items, then stop the monitor.
+	confirm = func(w http.ResponseWriter, r *http.Request) {
+		// The checks.
+		if !formOK(w, r) {
+			// A refusal was already sent.
+			return
+		} // end of the checks
+		// Do the removal once.
+		var items []uninstallItem
+		// The program file.
+		exe, _ := executablePath()
+		// Only the first press does the work.
+		once.Do(func() {
+			// What exists now.
+			items = uninstallPlan(desktop)
+			// Remove each and record the result in words.
+			for i := range items {
+				// Do it.
+				if err := items[i].remove(); err != nil {
+					// Say so, honestly.
+					items[i].Result = "could not be removed completely: " + err.Error()
+				} else {
+					// Done.
+					items[i].Result = "removed"
+				} // end of the result choice
+			} // end of the item loop
+			// From now on nothing is saved again, or the folders would come back.
+			mon.store.mu.Lock()
+			// No settings folder.
+			mon.store.dir = ""
+			// No state folder.
+			mon.store.stateDir = ""
+			// Release.
+			mon.store.mu.Unlock()
+			// The stop must not write the history.
+			noSaveOnStop.Store(true)
+			// Stop in the background once the page has been sent.
+			go func() {
+				// A short moment for the page to arrive.
+				time.Sleep(300 * time.Millisecond)
+				// Undo what running work changed, within a time limit.
+				ctx, cancel := context.WithTimeout(context.Background(), stopCleanupLimit)
+				// Run the clean-ups.
+				activeWork.runCleanups(ctx)
+				// Release the timer.
+				cancel()
+				// Shut the program down.
+				stopRequest()
+			}() // end of the goroutine
+		}) // end of once
+		// Send the result page.
+		send(w, r, sysPage{Kind: "removed", Items: items, Program: exe})
+		// Send it now, so it reaches the browser before the program ends.
+		if f, ok := w.(http.Flusher); ok {
+			// Flush.
+			f.Flush()
+		} // end of the flush check
+	} // end of confirm
+	// Hand the four back.
+	return show, cont, ask, confirm
+} // end of systemCheckHandlers
diff --git a/syscheck_test.go b/syscheck_test.go
new file mode 100644
index 0000000..87a8da8
--- /dev/null
+++ b/syscheck_test.go
@@ -0,0 +1,458 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this test uses.
+	// errors builds the failure of a missing tool.
+	"errors"
+	// context is part of the fake runner's signature.
+	"context"
+	// io reads reply bodies.
+	"io"
+	// net/http gives the status codes.
+	"net/http"
+	// net/url builds form values.
+	"net/url"
+	// os makes and checks folders.
+	"os"
+	// path/filepath joins paths.
+	"path/filepath"
+	// regexp finds the page token.
+	"regexp"
+	// strings searches page text.
+	"strings"
+	// sync/atomic counts stops.
+	"sync/atomic"
+	// testing is Go's test framework.
+	"testing"
+	// time is used for the handler's timeout.
+	"time"
+) // end of imports
+
+// sysRig is a web handler whose three standard folders are fake folders of the test.
+type sysRig struct {
+	// h is the handler.
+	h http.Handler
+	// mon is the monitor.
+	mon *monitor
+	// token is the page token.
+	token string
+	// cfg, data and state are the program's own folders (they exist).
+	cfg, data, state string
+	// stops counts the stop requests.
+	stops *atomic.Int32
+	// icon is the fake desktop icon helper.
+	icon desktopIcon
+} // end of sysRig
+
+// newSysRig builds the rig; first says whether the first-start check is switched on, and same puts all three folders in one place (the macOS layout).
+func newSysRig(t *testing.T, first, same bool) *sysRig {
+	// Mark this as a helper.
+	t.Helper()
+	// A calm machine, and fake tools that are all missing.
+	quietMachine(t)
+	// No tools.
+	fakeProbes(t, map[string]string{})
+	// Replace the three base folders; put the originals back at the end.
+	saveFolderLookups(t)
+	// One base folder per kind, or the same one.
+	root := t.TempDir()
+	// The bases.
+	cb, db, sb := filepath.Join(root, "c"), filepath.Join(root, "d"), filepath.Join(root, "s")
+	// The macOS layout.
+	if same {
+		// One folder for all.
+		cb, db, sb = filepath.Join(root, "a"), filepath.Join(root, "a"), filepath.Join(root, "a")
+	} // end of the same-folder case
+	// The lookups.
+	userConfigDir = func() (string, error) { return cb, nil }
+	// Data.
+	userDataDir = func() (string, error) { return db, nil }
+	// State.
+	userStateDir = func() (string, error) { return sb, nil }
+	// The program's own folders.
+	cfg, data, state := configRoot(), dataRoot(), stateRoot()
+	// Create them with a file each.
+	for _, d := range []string{cfg, data, state} {
+		// The folder.
+		if err := os.MkdirAll(d, 0o700); err != nil {
+			// Stop.
+			t.Fatal(err)
+		} // end of the folder check
+		// A file in it.
+		if err := os.WriteFile(filepath.Join(d, "x.txt"), []byte("x"), 0o600); err != nil {
+			// Stop.
+			t.Fatal(err)
+		} // end of the file check
+	} // end of the loop
+	// A fake Ollama that is online.
+	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.21.2"}`))
+	// The address.
+	addr, err := resolve(srv.URL, "")
+	// A bad address means the test is wrong.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the address check
+	// The monitor with its settings in the fake folder, and a fake Linux desktop.
+	mon := newMonitorWith(openSettingsStore(cfg, ""))
+	// The state folder.
+	mon.store.stateDir = state
+	// The fake desktop.
+	f := newFakeDesktop(t)
+	// Use it.
+	mon.denv = f.env
+	// Switch the first-start check on or off.
+	mon.firstRunCheck = first
+	// The desktop icon helper with the same values the handler gets.
+	icon := desktopIcon{env: f.env, dir: cfg, dataDir: data}
+	// Create the icon so that it is part of the plan.
+	if err := icon.create(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the icon check
+	// Count the stops.
+	var n atomic.Int32
+	// Remember the real one.
+	old := stopRequest
+	// Count instead of stopping.
+	stopRequest = func() { n.Add(1) }
+	// Put it back and clear the flag at the end.
+	t.Cleanup(func() { stopRequest = old; noSaveOnStop.Store(false) })
+	// The handler.
+	h := newWebHandlerWith(addr, time.Second, mon)
+	// The token is in the System check page.
+	_, _, body := get(t, h, http.MethodGet, "/systemcheck")
+	// Find it.
+	m := regexp.MustCompile(`name="token" value="([0-9a-f]+)"`).FindStringSubmatch(body)
+	// There must be one.
+	if m == nil {
+		// Stop.
+		t.Fatal("the System check page has no token")
+	} // end of the token check
+	// Hand back the rig.
+	return &sysRig{h: h, mon: mon, token: m[1], cfg: cfg, data: data, state: state, stops: &n, icon: icon}
+} // end of newSysRig
+
+// TestFirstStartRedirect checks that the first start shows the report, and Continue ends it.
+func TestFirstStartRedirect(t *testing.T) {
+	// The first-start check is on.
+	r := newSysRig(t, true, false)
+	// The main page redirects to the report.
+	code, hdr, _ := get(t, r.h, http.MethodGet, "/")
+	// Compare.
+	if code != http.StatusSeeOther || hdr.Get("Location") != "/systemcheck" {
+		// Report it.
+		t.Fatalf("first visit = %d %q", code, hdr.Get("Location"))
+	} // end of the redirect check
+	// A form from elsewhere is refused.
+	if res := post(t, r.h, "/systemcheck/continue", url.Values{"token": {r.token}}, nil); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("foreign form = %d", res.StatusCode)
+	} // end of the origin check
+	// A wrong token is refused.
+	if res := post(t, r.h, "/systemcheck/continue", url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("wrong token = %d", res.StatusCode)
+	} // end of the token check
+	// Continue.
+	res := post(t, r.h, "/systemcheck/continue", url.Values{"token": {r.token}}, fromThisPage)
+	// It goes to the monitor.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
+		// Report it.
+		t.Fatalf("continue = %d %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the continue check
+	// The answer is kept in the settings folder.
+	if !checkSeen(r.cfg) {
+		// Report it.
+		t.Errorf("the answer was not saved")
+	} // end of the saved check
+	// And the main page opens now.
+	if code, _, body := get(t, r.h, http.MethodGet, "/"); code != http.StatusOK || !strings.Contains(body, "System check") {
+		// Report it.
+		t.Errorf("after continue = %d", code)
+	} // end of the open check
+} // end of TestFirstStartRedirect
+
+// TestNoRedirectWhenOffOrCookie checks the two cases where the first start does not redirect.
+func TestNoRedirectWhenOffOrCookie(t *testing.T) {
+	// Switched off (the tests and a missing folder).
+	r := newSysRig(t, false, false)
+	// The page opens.
+	if code, _, _ := get(t, r.h, http.MethodGet, "/"); code != http.StatusOK {
+		// Report it.
+		t.Errorf("switched off = %d", code)
+	} // end of the check
+	// Switched on, but the answer cannot be saved: the session note stops a loop.
+	on := newSysRig(t, true, false)
+	// A folder that cannot be written: the settings folder is gone.
+	on.mon.store.dir = filepath.Join(t.TempDir(), "nope", "x")
+	// Make a file where the folder should be, so writing fails.
+	blocker := filepath.Join(t.TempDir(), "file")
+	// Write it.
+	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the blocker check
+	// A folder below a file cannot be created.
+	on.mon.store.dir = filepath.Join(blocker, "sub")
+	// The continue still sets the cookie.
+	res := post(t, on.h, "/systemcheck/continue", url.Values{"token": {on.token}}, fromThisPage)
+	// Find the cookie.
+	var got bool
+	// Look.
+	for _, c := range res.Cookies() {
+		// The note.
+		if c.Name == systemCheckCookie {
+			// Found.
+			got = true
+		} // end of the name check
+	} // end of the loop
+	// It must be there.
+	if !got {
+		// Report it.
+		t.Errorf("no session note was set")
+	} // end of the cookie check
+} // end of TestNoRedirectWhenOffOrCookie
+
+// TestSystemCheckPage checks the contents of the report and the tooltips.
+func TestSystemCheckPage(t *testing.T) {
+	// The rig.
+	r := newSysRig(t, false, false)
+	// The page.
+	code, _, body := get(t, r.h, http.MethodGet, "/systemcheck")
+	// It opens.
+	if code != http.StatusOK {
+		// Stop.
+		t.Fatalf("status = %d", code)
+	} // end of the status check
+	// The parts that must be there.
+	for _, want := range []string{"This computer", "Architecture", "Operating system", "Graphics cards", "Ollama was found at", "version 0.21.2", "Against Ollama", "docs.ollama.com/gpu", "Continue to the monitor", "Uninstall this tool", "This report stays available later under System check", "You then delete the program file yourself", `role="tooltip"`} {
+		// Each must be there.
+		if !strings.Contains(body, want) {
+			// Report it.
+			t.Errorf("missing %q", want)
+		} // end of the check
+	} // end of the loop
+	// Every tooltip id that is referred to must exist.
+	for _, m := range regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1) {
+		// The id.
+		if !strings.Contains(body, `id="`+m[1]+`"`) {
+			// Report it.
+			t.Errorf("tooltip %q has no text", m[1])
+		} // end of the check
+	} // end of the loop
+	// The main page links to it.
+	if _, _, home := get(t, r.h, http.MethodGet, "/"); !strings.Contains(home, `href="/systemcheck"`) {
+		// Report it.
+		t.Errorf("the main page has no System check link")
+	} // end of the link check
+} // end of TestSystemCheckPage
+
+// TestSystemCheckWithoutOllama checks the "Ollama only" message.
+func TestSystemCheckWithoutOllama(t *testing.T) {
+	// The rig first, then a handler pointing at a closed port.
+	r := newSysRig(t, false, false)
+	// A handler for an address where nothing listens.
+	h := newWebHandlerWith(mustResolve(t, "http://"+closedAddress(t)), time.Second, r.mon)
+	// The page.
+	_, _, body := get(t, h, http.MethodGet, "/systemcheck")
+	// The messages.
+	for _, want := range []string{"Ollama was not found at", "This tool works with Ollama only", "vLLM", "No graphics card could be confirmed"} {
+		// Each must be there.
+		if !strings.Contains(body, want) {
+			// Report it.
+			t.Errorf("missing %q", want)
+		} // end of the check
+	} // end of the loop
+} // end of TestSystemCheckWithoutOllama
+
+// mustResolve resolves an address for a test.
+func mustResolve(t *testing.T, raw string) ollamaAddress {
+	// Mark this as a helper.
+	t.Helper()
+	// Resolve.
+	a, err := resolve(raw, "")
+	// A failure means the test is wrong.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the check
+	// Hand it back.
+	return a
+} // end of mustResolve
+
+// TestUninstallQuestion checks that the question lists the paths and removes nothing.
+func TestUninstallQuestion(t *testing.T) {
+	// The rig.
+	r := newSysRig(t, false, false)
+	// The question page.
+	code, _, body := get(t, r.h, http.MethodGet, "/uninstall")
+	// It opens.
+	if code != http.StatusOK {
+		// Stop.
+		t.Fatalf("status = %d", code)
+	} // end of the status check
+	// The paths and words.
+	for _, want := range []string{"Desktop icon", r.cfg, r.data, r.state, "Yes, remove these files", "No, go back", "This cannot be undone", "Nothing is removed"} {
+		// Each must be there.
+		if !strings.Contains(body, want) {
+			// Report it.
+			t.Errorf("missing %q", want)
+		} // end of the check
+	} // end of the loop
+	// Nothing was deleted.
+	for _, d := range []string{r.cfg, r.data, r.state} {
+		// Still there.
+		if _, err := os.Stat(d); err != nil {
+			// Report it.
+			t.Errorf("%s was removed by the question page", d)
+		} // end of the check
+	} // end of the loop
+} // end of TestUninstallQuestion
+
+// TestUninstallConfirm checks the removal, the stop and that nothing is saved again.
+func TestUninstallConfirm(t *testing.T) {
+	// The rig.
+	r := newSysRig(t, false, false)
+	// A folder next to the program's own folders that must survive.
+	other := filepath.Join(filepath.Dir(r.cfg), "SomethingElse")
+	// Make it.
+	if err := os.MkdirAll(other, 0o700); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the folder check
+	// A foreign form is refused and removes nothing.
+	if res := post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}}, nil); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("foreign form = %d", res.StatusCode)
+	} // end of the origin check
+	// A wrong token is refused.
+	if res := post(t, r.h, "/uninstall/confirm", url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("wrong token = %d", res.StatusCode)
+	} // end of the token check
+	// Nothing was removed so far.
+	if _, err := os.Stat(r.cfg); err != nil {
+		// Report it.
+		t.Fatalf("a refused form removed the folder")
+	} // end of the safe check
+	// The real request.
+	res := post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}}, fromThisPage)
+	// Read the page.
+	b, _ := io.ReadAll(res.Body)
+	// The result page.
+	body := string(b)
+	// It says what happened and names the program file.
+	for _, want := range []string{"The monitor has stopped", "removed", "delete the program file yourself", r.cfg, "Ollama and its models were not touched"} {
+		// Each must be there.
+		if !strings.Contains(body, want) {
+			// Report it.
+			t.Errorf("missing %q in the result page", want)
+		} // end of the check
+	} // end of the loop
+	// The three folders and the icon are gone.
+	for _, d := range []string{r.cfg, r.data, r.state} {
+		// Gone.
+		if _, err := os.Stat(d); err == nil {
+			// Report it.
+			t.Errorf("%s still exists", d)
+		} // end of the check
+	} // end of the loop
+	// The desktop icon is gone.
+	if r.icon.exists() {
+		// Report it.
+		t.Errorf("the desktop icon is still there")
+	} // end of the icon check
+	// The other folder survived.
+	if _, err := os.Stat(other); err != nil {
+		// Report it.
+		t.Errorf("an unrelated folder was removed")
+	} // end of the survivor check
+	// The stop happens in the background shortly after.
+	deadline := time.Now().Add(3 * time.Second)
+	// Wait for it.
+	for r.stops.Load() == 0 && time.Now().Before(deadline) {
+		// A short sleep.
+		time.Sleep(20 * time.Millisecond)
+	} // end of the wait
+	// Exactly one stop.
+	if n := r.stops.Load(); n != 1 {
+		// Report it.
+		t.Errorf("stops = %d, want 1", n)
+	} // end of the stop check
+	// The stop must not write the history again.
+	if !noSaveOnStop.Load() {
+		// Report it.
+		t.Errorf("the history save was not switched off")
+	} // end of the flag check
+	// Saving anything now does not re-create the folders.
+	_ = r.mon.store.saveSamples([]sample{{}})
+	// Still gone.
+	if _, err := os.Stat(r.state); err == nil {
+		// Report it.
+		t.Errorf("the state folder came back")
+	} // end of the re-create check
+	// A second press does not stop twice.
+	post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}}, fromThisPage)
+	// Give it a moment.
+	time.Sleep(500 * time.Millisecond)
+	// Still one.
+	if n := r.stops.Load(); n != 1 {
+		// Report it.
+		t.Errorf("stops after a second press = %d", n)
+	} // end of the second-press check
+} // end of TestUninstallConfirm
+
+// TestUninstallSameFolder checks the macOS layout, where the three folders are one: one line, one removal.
+func TestUninstallSameFolder(t *testing.T) {
+	// The rig with one shared folder.
+	r := newSysRig(t, false, true)
+	// The plan has the icon and one folder.
+	plan := uninstallPlan(r.icon)
+	// Count the folder lines.
+	n := 0
+	// Look.
+	for _, it := range plan {
+		// A folder line.
+		if it.Where == r.cfg {
+			// One more.
+			n++
+			// It names all three.
+			if !strings.Contains(it.What, "Settings") || !strings.Contains(it.What, "results") || !strings.Contains(it.What, "history") {
+				// Report it.
+				t.Errorf("merged name = %q", it.What)
+			} // end of the names check
+		} // end of the folder-line check
+	} // end of the loop
+	// Exactly one.
+	if n != 1 {
+		// Report it.
+		t.Errorf("folder lines = %d, want 1", n)
+	} // end of the count check
+} // end of TestUninstallSameFolder
+
+// TestGuardedRoot checks that only the program's own folder inside the standard base folder may be deleted.
+func TestGuardedRoot(t *testing.T) {
+	// A base folder lookup.
+	look := func() (string, error) { return "/home/ann/.config", nil }
+	// The good path.
+	if !guardedRoot("/home/ann/.config/"+dataFolderName, look) {
+		// Report it.
+		t.Errorf("the program's own folder was refused")
+	} // end of the good case
+	// The bad paths.
+	for _, p := range []string{"", "/", "/home/ann", "/home/ann/.config", "/home/ann/.config/Other", "/home/ann/.config/" + dataFolderName + "/sub", "relative/" + dataFolderName, "/home/ann/.config/../" + dataFolderName} {
+		// Each is refused.
+		if guardedRoot(p, look) {
+			// Report it.
+			t.Errorf("%q must be refused", p)
+		} // end of the check
+	} // end of the loop
+	// No base folder known.
+	if guardedRoot("/x/"+dataFolderName, func() (string, error) { return "", errors.New("none") }) {
+		// Report it.
+		t.Errorf("a path without a known base must be refused")
+	} // end of the none case
+	// The unused import guard for the context package in this file.
+	var _ context.Context
+} // end of TestGuardedRoot
diff --git a/sysreport.go b/sysreport.go
new file mode 100644
index 0000000..44ce65b
--- /dev/null
+++ b/sysreport.go
@@ -0,0 +1,698 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context limits how long a tool may run.
+	"context"
+	// encoding/json reads the JSON that PowerShell and system_profiler print.
+	"encoding/json"
+	// fmt builds the sentences of the report.
+	"fmt"
+	// os reads the operating-system description file and the Windows folder variable.
+	"os"
+	// os/exec runs the tools that describe the hardware.
+	"os/exec"
+	// path/filepath joins paths and tells absolute names from bare ones.
+	"path/filepath"
+	// runtime gives the operating system and the architecture the program was built for.
+	"runtime"
+	// strings splits and trims text.
+	"strings"
+	// time sets the limit for each tool.
+	"time"
+) // end of imports
+
+// gpuInfo describes one graphics card; every figure that the system did not report stays empty or zero and is shown as "not reported", never guessed.
+type gpuInfo struct {
+	// Vendor is one of nvidia, amd, intel, apple or other.
+	Vendor string
+	// Name is the card's name as the system reports it.
+	Name string
+	// MemMiB is the graphics memory in MiB; 0 means not reported (shared-memory cards report none).
+	MemMiB int64
+	// Driver is the driver version text; empty means not reported.
+	Driver string
+	// Compute is the NVIDIA compute capability such as "6.1"; empty means not reported.
+	Compute string
+} // end of gpuInfo
+
+// hostReport is everything the System check shows about this computer.
+type hostReport struct {
+	// OS is the operating system in words.
+	OS string
+	// Arch is the architecture the program was built for.
+	Arch string
+	// CPU is the processor name; empty means not reported.
+	CPU string
+	// Logical is the number of logical processors.
+	Logical int
+	// Physical is the number of physical cores; 0 means not reported.
+	Physical int
+	// MemBytes is the memory in bytes; 0 means not reported.
+	MemBytes int64
+	// GPUs are the graphics cards that were found.
+	GPUs []gpuInfo
+} // end of hostReport
+
+// finding is one line of the verdict part: a level (ok, warn or info) and the sentence.
+type finding struct {
+	// Level is "ok", "warn" or "info".
+	Level string
+	// Text is the sentence shown to the person.
+	Text string
+} // end of finding
+
+// The replaceable parts, so a test never runs a real tool.
+var (
+	// reportOS is the operating system the report is made for.
+	reportOS = runtime.GOOS
+	// reportArch is the architecture the report is made for.
+	reportArch = runtime.GOARCH
+	// reportLogical is the number of logical processors.
+	reportLogical = runtime.NumCPU
+	// osReleasePath is the Linux file that names the distribution.
+	osReleasePath = "/etc/os-release"
+	// probeRun runs one tool with fixed arguments and returns what it printed; a bare name is searched in the PATH.
+	probeRun = realProbe
+) // end of the replaceable parts
+
+// realProbe runs a tool with fixed arguments (nothing typed by a person ever reaches it) and waits at most twenty seconds.
+func realProbe(ctx context.Context, name string, args ...string) (string, error) {
+	// A bare name is looked up in the PATH; a full path is used as it is.
+	exe := name
+	// Is it a bare name?
+	if !filepath.IsAbs(name) {
+		// Look for it.
+		found, err := exec.LookPath(name)
+		// Not installed: the caller shows "not reported".
+		if err != nil {
+			// Hand the error back.
+			return "", err
+		} // end of the lookup check
+		// Use the full path found.
+		exe = found
+	} // end of the bare-name case
+	// Never wait long.
+	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
+	// Release the timer at the end.
+	defer cancel()
+	// Run it and collect its output.
+	out, err := exec.CommandContext(ctx, exe, args...).Output()
+	// Hand back the text and any error.
+	return strings.TrimSpace(string(out)), err
+} // end of realProbe
+
+// archLabel names an architecture the way people say it.
+func archLabel(goarch string) string {
+	// Pick by name.
+	switch goarch {
+	// Intel and AMD, 64 bit.
+	case "amd64":
+		// The common name too.
+		return "amd64 (x86-64)"
+	// ARM, 64 bit.
+	case "arm64":
+		// The common name too.
+		return "arm64 (ARM64)"
+	// Anything else: show what Go says.
+	default:
+		// Unchanged.
+		return goarch
+	} // end of the switch
+} // end of archLabel
+
+// vendorOf sorts a graphics card by the words in its vendor or name.
+func vendorOf(text string) string {
+	// Compare in lower case.
+	t := strings.ToLower(text)
+	// Pick by the first match.
+	switch {
+	// NVIDIA.
+	case strings.Contains(t, "nvidia"):
+		// Name it.
+		return "nvidia"
+	// AMD, also written Advanced Micro Devices or ATI.
+	case strings.Contains(t, "amd"), strings.Contains(t, "advanced micro"), strings.Contains(t, "radeon"), strings.Contains(t, "ati "):
+		// Name it.
+		return "amd"
+	// Apple.
+	case strings.HasPrefix(t, "apple"), strings.Contains(t, "sppci_vendor_apple"):
+		// Name it.
+		return "apple"
+	// Intel.
+	case strings.Contains(t, "intel"):
+		// Name it.
+		return "intel"
+	// Anything else.
+	default:
+		// Other.
+		return "other"
+	} // end of the switch
+} // end of vendorOf
+
+// parseCompute reads a compute capability such as "6.1" into its two numbers.
+func parseCompute(s string) (major, minor int, ok bool) {
+	// Split at the dot.
+	a, b, found := strings.Cut(strings.TrimSpace(s), ".")
+	// Both parts are needed.
+	if !found {
+		// Not a capability.
+		return 0, 0, false
+	} // end of the dot check
+	// The major number.
+	ma, okA := leadingNumber(a)
+	// The minor number.
+	mi, okB := leadingNumber(b)
+	// Both must be numbers, and the text must have no more than digits.
+	if !okA || !okB || a != fmt.Sprint(ma) {
+		// Not a capability.
+		return 0, 0, false
+	} // end of the number check
+	// Hand both back.
+	return int(ma), int(mi), true
+} // end of parseCompute
+
+// parseNvidiaCSV reads the lines printed by nvidia-smi --query-gpu=name,memory.total,driver_version[,compute_cap] --format=csv,noheader,nounits.
+func parseNvidiaCSV(text string) []gpuInfo {
+	// The cards found.
+	var out []gpuInfo
+	// One card per line.
+	for _, line := range strings.Split(text, "\n") {
+		// Split at the commas.
+		parts := strings.Split(strings.TrimSpace(line), ",")
+		// A card line has at least the name, the memory and the driver.
+		if len(parts) < 3 {
+			// Skip other lines.
+			continue
+		} // end of the shape check
+		// Trim every part.
+		for i := range parts {
+			// Remove the spaces.
+			parts[i] = strings.TrimSpace(parts[i])
+		} // end of the trim loop
+		// The card; the tool prints "[N/A]" or "Not Supported" for a figure it cannot give.
+		g := gpuInfo{Vendor: "nvidia", Name: parts[0]}
+		// The memory in MiB.
+		if n, ok := leadingNumber(parts[1]); ok {
+			// Keep it.
+			g.MemMiB = n
+		} // end of the memory check
+		// The driver: a version starts with a digit.
+		if len(parts[2]) > 0 && parts[2][0] >= '0' && parts[2][0] <= '9' {
+			// Keep it.
+			g.Driver = parts[2]
+		} // end of the driver check
+		// The compute capability, when the tool gave one.
+		if len(parts) >= 4 {
+			// Only a real capability is kept.
+			if _, _, ok := parseCompute(parts[3]); ok {
+				// Keep it.
+				g.Compute = parts[3]
+			} // end of the capability check
+		} // end of the fourth-field check
+		// Add the card.
+		out = append(out, g)
+	} // end of the line loop
+	// Hand them back.
+	return out
+} // end of parseNvidiaCSV
+
+// splitQuoted returns the texts between double quotes in a line of "lspci -mm".
+func splitQuoted(line string) []string {
+	// The texts.
+	var out []string
+	// Where the current text starts; -1 means outside quotes.
+	start := -1
+	// Walk along the line.
+	for i, c := range line {
+		// A quote mark opens or closes a text.
+		if c == '"' {
+			// Closing.
+			if start >= 0 {
+				// Keep the text.
+				out = append(out, line[start:i])
+				// Outside again.
+				start = -1
+			} else {
+				// Opening: the text starts after the mark.
+				start = i + 1
+			} // end of the open/close choice
+		} // end of the quote check
+	} // end of the walk
+	// Hand them back.
+	return out
+} // end of splitQuoted
+
+// parseLspci reads the output of "lspci -mm" and returns the display adapters.
+func parseLspci(text string) []gpuInfo {
+	// The cards found.
+	var out []gpuInfo
+	// One device per line.
+	for _, line := range strings.Split(text, "\n") {
+		// The quoted fields: class, vendor, device, and more.
+		f := splitQuoted(line)
+		// A device line has at least these three.
+		if len(f) < 3 {
+			// Skip other lines.
+			continue
+		} // end of the shape check
+		// The class decides whether it is a display adapter.
+		class := strings.ToLower(f[0])
+		// Not a display adapter.
+		if !strings.Contains(class, "vga") && !strings.Contains(class, "3d controller") && !strings.Contains(class, "display controller") {
+			// Skip it.
+			continue
+		} // end of the class check
+		// The vendor without the company suffix.
+		vendor := strings.TrimSpace(strings.NewReplacer(" Corporation", "", " Corp.", "").Replace(f[1]))
+		// Add the card.
+		out = append(out, gpuInfo{Vendor: vendorOf(f[1]), Name: strings.TrimSpace(vendor + " " + f[2])})
+	} // end of the line loop
+	// Hand them back.
+	return out
+} // end of parseLspci
+
+// parseLscpuCores counts the physical cores from "lscpu -p=CORE,SOCKET" (each different pair is one core); 0 means not reported.
+func parseLscpuCores(text string) int {
+	// The pairs seen.
+	seen := map[string]bool{}
+	// One logical processor per line.
+	for _, line := range strings.Split(text, "\n") {
+		// Trim the line.
+		line = strings.TrimSpace(line)
+		// Skip comments and empty lines.
+		if line == "" || strings.HasPrefix(line, "#") {
+			// Next line.
+			continue
+		} // end of the skip check
+		// Remember the pair.
+		seen[line] = true
+	} // end of the line loop
+	// The number of different pairs.
+	return len(seen)
+} // end of parseLscpuCores
+
+// osReleaseName reads PRETTY_NAME from the text of /etc/os-release.
+func osReleaseName(text string) string {
+	// One setting per line.
+	for _, line := range strings.Split(text, "\n") {
+		// The line we want.
+		if v, ok := strings.CutPrefix(line, "PRETTY_NAME="); ok {
+			// Remove the quotes.
+			return strings.Trim(strings.TrimSpace(v), `"'`)
+		} // end of the prefix check
+	} // end of the line loop
+	// Not there.
+	return ""
+} // end of osReleaseName
+
+// winProbeScript is the one PowerShell command that describes a Windows computer; it only reads and prints JSON.
+const winProbeScript = `$o=Get-CimInstance Win32_OperatingSystem;$c=@(Get-CimInstance Win32_Processor);$g=@(Get-CimInstance Win32_VideoController);` +
+	`[pscustomobject]@{os=$o.Caption;cpu=$c[0].Name;cores=($c|Measure-Object NumberOfCores -Sum).Sum;` +
+	`gpus=@($g|ForEach-Object{[pscustomobject]@{name=$_.Name;ram=$_.AdapterRAM}})}|ConvertTo-Json -Depth 4 -Compress`
+
+// winGPU is one video controller in the PowerShell JSON.
+type winGPU struct {
+	// Name is the controller's name.
+	Name string `json:"name"`
+	// RAM is the AdapterRAM figure in bytes; Windows caps it at 4 GiB, so a large or zero value means "not reported".
+	RAM *int64 `json:"ram"`
+} // end of winGPU
+
+// winReport is the JSON that winProbeScript prints.
+type winReport struct {
+	// OS is the Windows edition in words.
+	OS string `json:"os"`
+	// CPU is the processor name.
+	CPU string `json:"cpu"`
+	// Cores is the number of physical cores over all processors.
+	Cores *int `json:"cores"`
+	// GPUs is a list (PowerShell may print a single entry without the list brackets).
+	GPUs json.RawMessage `json:"gpus"`
+} // end of winReport
+
+// winRAMLimit is the value from which Windows' AdapterRAM can no longer be trusted (it is a 32-bit figure).
+const winRAMLimit = 4293918720
+
+// parseWindowsReport reads the JSON of winProbeScript.
+func parseWindowsReport(text string) (osName, cpu string, cores int, gpus []gpuInfo, ok bool) {
+	// Skip anything printed before the JSON starts.
+	i := strings.Index(text, "{")
+	// No JSON at all.
+	if i < 0 {
+		// Nothing to read.
+		return "", "", 0, nil, false
+	} // end of the start check
+	// Decode.
+	var w winReport
+	// A damaged text gives nothing.
+	if err := json.Unmarshal([]byte(text[i:]), &w); err != nil {
+		// Nothing to read.
+		return "", "", 0, nil, false
+	} // end of the decode check
+	// The cards: a list or a single entry.
+	var list []winGPU
+	// Try the list first.
+	if err := json.Unmarshal(w.GPUs, &list); err != nil {
+		// Then a single entry.
+		var one winGPU
+		// Keep it when it reads.
+		if json.Unmarshal(w.GPUs, &one) == nil && one.Name != "" {
+			// A list of one.
+			list = []winGPU{one}
+		} // end of the single-entry case
+	} // end of the list attempt
+	// Convert every card.
+	for _, g := range list {
+		// Skip nameless entries.
+		if strings.TrimSpace(g.Name) == "" {
+			// Next card.
+			continue
+		} // end of the name check
+		// The card.
+		gi := gpuInfo{Vendor: vendorOf(g.Name), Name: strings.TrimSpace(g.Name)}
+		// A trustworthy memory figure.
+		if g.RAM != nil && *g.RAM > 0 && *g.RAM < winRAMLimit {
+			// In MiB.
+			gi.MemMiB = *g.RAM >> 20
+		} // end of the memory check
+		// Add it.
+		gpus = append(gpus, gi)
+	} // end of the card loop
+	// The core count, when reported.
+	if w.Cores != nil && *w.Cores > 0 {
+		// Keep it.
+		cores = *w.Cores
+	} // end of the cores check
+	// Hand everything back.
+	return strings.TrimSpace(w.OS), strings.TrimSpace(w.CPU), cores, gpus, true
+} // end of parseWindowsReport
+
+// parseMacDisplays reads "system_profiler SPDisplaysDataType -json"; fields that are missing stay empty.
+func parseMacDisplays(text string) []gpuInfo {
+	// The shape of the JSON that we use.
+	var d struct {
+		// Items are the graphics adapters.
+		Items []struct {
+			// Model is the adapter's name.
+			Model string `json:"sppci_model"`
+			// Vendor is the vendor code such as sppci_vendor_Apple.
+			Vendor string `json:"spdisplays_vendor"`
+		} `json:"SPDisplaysDataType"`
+	} // end of the shape
+	// Skip anything before the JSON.
+	i := strings.Index(text, "{")
+	// No JSON.
+	if i < 0 {
+		// Nothing.
+		return nil
+	} // end of the start check
+	// Decode.
+	if err := json.Unmarshal([]byte(text[i:]), &d); err != nil {
+		// Nothing.
+		return nil
+	} // end of the decode check
+	// The cards.
+	var out []gpuInfo
+	// Convert each.
+	for _, it := range d.Items {
+		// Skip nameless entries.
+		if strings.TrimSpace(it.Model) == "" {
+			// Next.
+			continue
+		} // end of the name check
+		// The vendor comes from the code or from the name.
+		v := vendorOf(it.Vendor + " " + it.Model)
+		// Add it.
+		out = append(out, gpuInfo{Vendor: v, Name: strings.TrimSpace(it.Model)})
+	} // end of the loop
+	// Hand them back.
+	return out
+} // end of parseMacDisplays
+
+// powershellPath is the full path of Windows PowerShell, so no other program with that name is ever run.
+func powershellPath() string {
+	// The Windows folder.
+	root := os.Getenv("SystemRoot")
+	// Unset: the usual place.
+	if root == "" {
+		// The default.
+		root = `C:\Windows`
+	} // end of the default
+	// The standard place of Windows PowerShell 5.1.
+	return root + `\System32\WindowsPowerShell\v1.0\powershell.exe`
+} // end of powershellPath
+
+// mergeGPUs adds the cards from the general list that the NVIDIA tool did not already describe (the tool gives more detail, so it wins).
+func mergeGPUs(detailed, general []gpuInfo) []gpuInfo {
+	// Start with the detailed ones.
+	out := append([]gpuInfo{}, detailed...)
+	// Is there an NVIDIA card with detail?
+	haveNvidia := len(detailed) > 0
+	// Go through the general list.
+	for _, g := range general {
+		// The same NVIDIA cards are already described.
+		if haveNvidia && g.Vendor == "nvidia" {
+			// Skip.
+			continue
+		} // end of the duplicate check
+		// Add it.
+		out = append(out, g)
+	} // end of the loop
+	// Hand the list back.
+	return out
+} // end of mergeGPUs
+
+// nvidiaCards asks nvidia-smi for the cards; older drivers do not know the compute_cap field, so the question is asked again without it.
+func nvidiaCards(ctx context.Context) []gpuInfo {
+	// With the capability.
+	out, err := probeRun(ctx, "nvidia-smi", "--query-gpu=name,memory.total,driver_version,compute_cap", "--format=csv,noheader,nounits")
+	// An old driver, or a failure: ask again without it.
+	if err != nil {
+		// Without the capability.
+		out, err = probeRun(ctx, "nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader,nounits")
+	} // end of the retry
+	// No tool, or it failed again: nothing is known from it.
+	if err != nil {
+		// Nothing.
+		return nil
+	} // end of the second check
+	// Read the lines.
+	return parseNvidiaCSV(out)
+} // end of nvidiaCards
+
+// collectReport asks the system what it can; whatever it cannot tell stays empty and is shown as "not reported".
+func collectReport(ctx context.Context) hostReport {
+	// The facts that are always known.
+	r := hostReport{Arch: archLabel(reportArch), Logical: reportLogical(), OS: reportOS}
+	// The memory, from the reader the monitor already uses.
+	if mi, err := readMemInfo(); err == nil {
+		// Keep the total.
+		r.MemBytes = mi.TotalBytes
+	} // end of the memory check
+	// The processor name, from the reader the monitor already uses.
+	r.CPU = readCPUName()
+	// The detailed NVIDIA cards.
+	nv := nvidiaCards(ctx)
+	// The general list of cards.
+	var general []gpuInfo
+	// Each system describes itself in its own way.
+	switch reportOS {
+	// Linux.
+	case "linux":
+		// The distribution name.
+		if data, err := os.ReadFile(osReleasePath); err == nil {
+			// Use it when it has a name.
+			if n := osReleaseName(string(data)); n != "" {
+				// Keep it.
+				r.OS = n
+			} // end of the name check
+		} // end of the file check
+		// The physical cores.
+		if out, err := probeRun(ctx, "lscpu", "-p=CORE,SOCKET"); err == nil {
+			// Count them.
+			r.Physical = parseLscpuCores(out)
+		} // end of the lscpu check
+		// The display adapters.
+		if out, err := probeRun(ctx, "lspci", "-mm"); err == nil {
+			// Read them.
+			general = parseLspci(out)
+		} // end of the lspci check
+	// Windows: one PowerShell call.
+	case "windows":
+		// Run the script without a profile and without questions.
+		if out, err := probeRun(ctx, powershellPath(), "-NoProfile", "-NonInteractive", "-Command", winProbeScript); err == nil {
+			// Read the JSON.
+			if name, cpu, cores, gpus, ok := parseWindowsReport(out); ok {
+				// The edition, when reported.
+				if name != "" {
+					// Keep it.
+					r.OS = name
+				} // end of the name check
+				// The processor name from Windows is better than the short identifier.
+				if cpu != "" {
+					// Keep it.
+					r.CPU = cpu
+				} // end of the cpu check
+				// The physical cores.
+				r.Physical = cores
+				// The cards.
+				general = gpus
+			} // end of the parse check
+		} // end of the PowerShell check
+	// macOS.
+	case "darwin":
+		// The system name and version.
+		if name, err := probeRun(ctx, "/usr/bin/sw_vers", "-productName"); err == nil && name != "" {
+			// The version.
+			ver, _ := probeRun(ctx, "/usr/bin/sw_vers", "-productVersion")
+			// Both together.
+			r.OS = strings.TrimSpace(name + " " + ver)
+		} // end of the name check
+		// The physical cores.
+		if out, err := probeRun(ctx, "/usr/sbin/sysctl", "-n", "hw.physicalcpu"); err == nil {
+			// Read the number.
+			if n, ok := leadingNumber(out); ok {
+				// Keep it.
+				r.Physical = int(n)
+			} // end of the number check
+		} // end of the sysctl check
+		// The graphics adapters.
+		if out, err := probeRun(ctx, "/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"); err == nil {
+			// Read them.
+			general = parseMacDisplays(out)
+		} // end of the profiler check
+	} // end of the system switch
+	// Join the two lists of cards.
+	r.GPUs = mergeGPUs(nv, general)
+	// Hand the report back.
+	return r
+} // end of collectReport
+
+// gigabytes writes a size in MiB or bytes as "4 GB" or "20.0 GB" (powers of 1024, as the operating systems show them).
+func gigabytes(bytes int64) string {
+	// Under 1 GB: show megabytes.
+	if bytes < 1<<30 {
+		// Whole megabytes.
+		return fmt.Sprintf("%d MB", bytes>>20)
+	} // end of the small case
+	// A whole number of GB reads better without the decimal.
+	if bytes%(1<<30) == 0 {
+		// Whole.
+		return fmt.Sprintf("%d GB", bytes>>30)
+	} // end of the whole case
+	// One decimal.
+	return fmt.Sprintf("%.1f GB", float64(bytes)/float64(1<<30))
+} // end of gigabytes
+
+// describeGPU writes one card as a line; unknown figures are left out and the line says so once.
+func describeGPU(g gpuInfo) string {
+	// The name first.
+	parts := []string{g.Name}
+	// The memory.
+	if g.MemMiB > 0 {
+		// Keep it.
+		parts = append(parts, gigabytes(g.MemMiB<<20))
+	} else {
+		// Say so.
+		parts = append(parts, "graphics memory not reported")
+	} // end of the memory choice
+	// The compute capability (NVIDIA only).
+	if g.Compute != "" {
+		// Keep it.
+		parts = append(parts, "compute capability "+g.Compute)
+	} // end of the capability check
+	// The driver.
+	if g.Driver != "" {
+		// Keep it.
+		parts = append(parts, "driver "+g.Driver)
+	} // end of the driver check
+	// Join with commas.
+	return strings.Join(parts, ", ")
+} // end of describeGPU
+
+// ollamaGPUSource is the page the verdicts come from.
+const ollamaGPUSource = "Ollama documentation, GPU page (docs.ollama.com/gpu)"
+
+// judgeNvidia judges one NVIDIA card against the published minimums: compute capability 5.0 or higher, and driver 550 or higher (570 or higher for capabilities from 5.0 to 6.2).
+func judgeNvidia(g gpuInfo) (supported bool, f finding) {
+	// The capability must be known to judge.
+	maj, min, ok := parseCompute(g.Compute)
+	// Not reported.
+	if !ok {
+		// Say so; no guess.
+		return false, finding{"info", g.Name + ": the compute capability was not reported, so it cannot be judged against Ollama's published minimum (5.0 or higher)."}
+	} // end of the capability check
+	// Below the minimum.
+	if maj < 5 {
+		// A clear problem.
+		return false, finding{"warn", fmt.Sprintf("%s: compute capability %d.%d is below the published minimum of 5.0.", g.Name, maj, min)}
+	} // end of the minimum check
+	// Cards from 5.0 to 6.2 need the newer driver.
+	need := 550
+	// Is it one of them?
+	if maj < 6 || (maj == 6 && min <= 2) {
+		// The higher driver.
+		need = 570
+	} // end of the driver choice
+	// The driver must be known to judge.
+	drv, okD := leadingNumber(g.Driver)
+	// Not reported.
+	if !okD {
+		// Say so; no guess.
+		return false, finding{"info", fmt.Sprintf("%s: compute capability %d.%d is high enough, but the driver version was not reported (the published minimum is %d).", g.Name, maj, min, need)}
+	} // end of the driver check
+	// Too old.
+	if int(drv) < need {
+		// A clear problem.
+		return false, finding{"warn", fmt.Sprintf("%s: driver %s is older than the published minimum of %d for a card with compute capability %d.%d.", g.Name, g.Driver, need, maj, min)}
+	} // end of the old-driver case
+	// All good.
+	return true, finding{"ok", fmt.Sprintf("%s: compute capability %d.%d is at least 5.0, and driver %s is at least %d.", g.Name, maj, min, g.Driver, need)}
+} // end of judgeNvidia
+
+// judgeReport turns the report into the lines of the verdict part; it uses Ollama's published facts only.
+func judgeReport(r hostReport) []finding {
+	// The lines.
+	var out []finding
+	// How many cards were confirmed.
+	supported := 0
+	// Judge each card.
+	for _, g := range r.GPUs {
+		// By vendor.
+		switch g.Vendor {
+		// NVIDIA has published numbers.
+		case "nvidia":
+			// Judge it.
+			ok, f := judgeNvidia(g)
+			// Count a confirmed card.
+			if ok {
+				// One more.
+				supported++
+			} // end of the count
+			// Keep the line.
+			out = append(out, f)
+		// Apple: Ollama lists Metal; no minimum is published.
+		case "apple":
+			// One more confirmed.
+			supported++
+			// The line.
+			out = append(out, finding{"ok", g.Name + ": Ollama lists Apple Metal as supported. It publishes no minimum for it."})
+		// AMD: the published list is a driver stack, not a simple number.
+		case "amd":
+			// Not judged.
+			out = append(out, finding{"info", g.Name + ": Ollama supports AMD cards through the ROCm v7 driver stack (Linux and Windows). This tool does not judge AMD cards; check the card list on the GPU page."})
+		// Others.
+		default:
+			// Not judged.
+			out = append(out, finding{"info", g.Name + ": not judged (Ollama publishes no minimum for this kind of card here)."})
+		} // end of the vendor switch
+	} // end of the card loop
+	// Nothing confirmed.
+	if supported == 0 {
+		// The main warning.
+		out = append(out, finding{"warn", "No graphics card could be confirmed as meeting Ollama's published GPU minimum, so Ollama may run models on the processor, which is much slower. This tool is then less useful, because the speed you measure will not be the speed of a supported graphics card."})
+	} // end of the nothing-confirmed case
+	// Hand the lines back.
+	return out
+} // end of judgeReport
diff --git a/sysreport_test.go b/sysreport_test.go
new file mode 100644
index 0000000..f90e183
--- /dev/null
+++ b/sysreport_test.go
@@ -0,0 +1,383 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this test uses.
+	// context is passed to the detection.
+	"context"
+	// errors builds the failure of a missing tool.
+	"errors"
+	// os writes the fake os-release file.
+	"os"
+	// path/filepath joins the fake file path.
+	"path/filepath"
+	// strings searches the verdict texts.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestParseNvidiaCSV checks the card lines, including figures the tool cannot give.
+func TestParseNvidiaCSV(t *testing.T) {
+	// A normal card with the capability, and a shared-memory card with unsupported figures.
+	got := parseNvidiaCSV("NVIDIA GeForce GTX 1050, 4096, 576.80, 6.1\nNVIDIA GB10, [N/A], 580.95.05, 12.1\n")
+	// Two cards.
+	if len(got) != 2 {
+		// Report it.
+		t.Fatalf("got %d cards, want 2", len(got))
+	} // end of the count check
+	// The first card.
+	if g := got[0]; g.Name != "NVIDIA GeForce GTX 1050" || g.MemMiB != 4096 || g.Driver != "576.80" || g.Compute != "6.1" || g.Vendor != "nvidia" {
+		// Report it.
+		t.Errorf("first card = %+v", g)
+	} // end of the first-card check
+	// The shared-memory card has no memory figure.
+	if got[1].MemMiB != 0 || got[1].Compute != "12.1" {
+		// Report it.
+		t.Errorf("second card = %+v", got[1])
+	} // end of the second-card check
+	// A line without the capability field, and a "Not Supported" driver.
+	old := parseNvidiaCSV("Some Card, 8192, Not Supported")
+	// One card, no driver, no capability.
+	if len(old) != 1 || old[0].Driver != "" || old[0].Compute != "" {
+		// Report it.
+		t.Errorf("old-style line = %+v", old)
+	} // end of the old-style check
+	// Rubbish gives nothing.
+	if len(parseNvidiaCSV("NVIDIA-SMI has failed because it couldn't communicate")) != 0 {
+		// Report it.
+		t.Errorf("an error text must not give a card")
+	} // end of the rubbish check
+} // end of TestParseNvidiaCSV
+
+// TestParseCompute checks the capability reader.
+func TestParseCompute(t *testing.T) {
+	// Good values.
+	if a, b, ok := parseCompute("6.1"); !ok || a != 6 || b != 1 {
+		// Report it.
+		t.Errorf("6.1 -> %d %d %v", a, b, ok)
+	} // end of the good case
+	// Bad values.
+	for _, s := range []string{"", "[N/A]", "6", "x.1", "6.x", "Not Supported"} {
+		// Each is refused.
+		if _, _, ok := parseCompute(s); ok {
+			// Report it.
+			t.Errorf("%q must not parse", s)
+		} // end of the check
+	} // end of the loop
+} // end of TestParseCompute
+
+// TestParseLspci checks that only display adapters are kept and the vendors are told apart.
+func TestParseLspci(t *testing.T) {
+	// A sample in the format of lspci -mm.
+	text := `00:00.0 "Host bridge" "Intel Corporation" "Device 1234" -r07 "Dell" "Device 0001"
+00:02.0 "VGA compatible controller" "Intel Corporation" "UHD Graphics 620" -r07 "Dell" "Device 0002"
+01:00.0 "3D controller" "NVIDIA Corporation" "GP107M [GeForce GTX 1050 Mobile]" -ra1 "Dell" "Device 0003"
+02:00.0 "Display controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Vega 8" "Dell" "Device 0004"
+`
+	// Read it.
+	got := parseLspci(text)
+	// Three adapters.
+	if len(got) != 3 {
+		// Report it.
+		t.Fatalf("got %d adapters: %+v", len(got), got)
+	} // end of the count check
+	// The vendors, in order.
+	want := []string{"intel", "nvidia", "amd"}
+	// Compare.
+	for i, w := range want {
+		// One vendor.
+		if got[i].Vendor != w {
+			// Report it.
+			t.Errorf("adapter %d vendor = %q, want %q", i, got[i].Vendor, w)
+		} // end of the vendor check
+	} // end of the loop
+	// The name joins vendor and device.
+	if got[0].Name != "Intel UHD Graphics 620" {
+		// Report it.
+		t.Errorf("name = %q", got[0].Name)
+	} // end of the name check
+} // end of TestParseLspci
+
+// TestParseLscpuAndOSRelease checks the core count and the distribution name.
+func TestParseLscpuAndOSRelease(t *testing.T) {
+	// Eight logical processors on four cores (two threads each).
+	text := "# comment\n0,0\n1,0\n2,0\n3,0\n0,0\n1,0\n2,0\n3,0\n"
+	// Four cores.
+	if n := parseLscpuCores(text); n != 4 {
+		// Report it.
+		t.Errorf("cores = %d, want 4", n)
+	} // end of the core check
+	// Nothing to count.
+	if n := parseLscpuCores("# only a comment\n"); n != 0 {
+		// Report it.
+		t.Errorf("cores = %d, want 0", n)
+	} // end of the empty check
+	// The name.
+	if n := osReleaseName("NAME=\"Ubuntu\"\nPRETTY_NAME=\"Ubuntu 24.04.3 LTS\"\nID=ubuntu\n"); n != "Ubuntu 24.04.3 LTS" {
+		// Report it.
+		t.Errorf("name = %q", n)
+	} // end of the name check
+	// A missing name.
+	if n := osReleaseName("ID=x\n"); n != "" {
+		// Report it.
+		t.Errorf("name = %q, want empty", n)
+	} // end of the missing check
+} // end of TestParseLscpuAndOSRelease
+
+// TestParseWindowsReport checks the PowerShell JSON, with a list, a single entry and the 4 GiB cap.
+func TestParseWindowsReport(t *testing.T) {
+	// Two controllers; the second one reports the capped value, which means "not reported".
+	text := `{"os":"Microsoft Windows 11 Pro","cpu":"Intel(R) Core(TM) i7-8550U CPU @ 1.80GHz","cores":4,"gpus":[{"name":"NVIDIA GeForce GTX 1050","ram":4293918720},{"name":"Intel(R) UHD Graphics 620","ram":1073741824}]}`
+	// Read it.
+	osName, cpu, cores, gpus, ok := parseWindowsReport(text)
+	// It must read.
+	if !ok || osName != "Microsoft Windows 11 Pro" || cores != 4 || !strings.HasPrefix(cpu, "Intel") {
+		// Report it.
+		t.Fatalf("got %q %q %d %v", osName, cpu, cores, ok)
+	} // end of the basic check
+	// Two cards.
+	if len(gpus) != 2 || gpus[0].Vendor != "nvidia" || gpus[0].MemMiB != 0 || gpus[1].Vendor != "intel" || gpus[1].MemMiB != 1024 {
+		// Report it.
+		t.Errorf("gpus = %+v", gpus)
+	} // end of the card check
+	// A single entry without list brackets, as PowerShell may print it.
+	_, _, _, one, ok := parseWindowsReport(`{"os":"Windows","gpus":{"name":"AMD Radeon RX 580","ram":null}}`)
+	// One card.
+	if !ok || len(one) != 1 || one[0].Vendor != "amd" {
+		// Report it.
+		t.Errorf("single = %+v %v", one, ok)
+	} // end of the single check
+	// Rubbish.
+	if _, _, _, _, ok := parseWindowsReport("not json"); ok {
+		// Report it.
+		t.Errorf("rubbish must not parse")
+	} // end of the rubbish check
+} // end of TestParseWindowsReport
+
+// TestParseMacDisplays checks the system_profiler JSON.
+func TestParseMacDisplays(t *testing.T) {
+	// An Apple Silicon sample.
+	got := parseMacDisplays(`{"SPDisplaysDataType":[{"sppci_model":"Apple M2","spdisplays_vendor":"sppci_vendor_Apple"}]}`)
+	// One Apple card.
+	if len(got) != 1 || got[0].Vendor != "apple" || got[0].Name != "Apple M2" {
+		// Report it.
+		t.Errorf("got %+v", got)
+	} // end of the check
+	// Rubbish.
+	if len(parseMacDisplays("nope")) != 0 {
+		// Report it.
+		t.Errorf("rubbish must give nothing")
+	} // end of the rubbish check
+} // end of TestParseMacDisplays
+
+// TestArchLabel checks the architecture words.
+func TestArchLabel(t *testing.T) {
+	// The cases.
+	for in, want := range map[string]string{"amd64": "amd64 (x86-64)", "arm64": "arm64 (ARM64)", "riscv64": "riscv64"} {
+		// One case.
+		if got := archLabel(in); got != want {
+			// Report it.
+			t.Errorf("archLabel(%q) = %q, want %q", in, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestArchLabel
+
+// TestJudgeNvidia checks the published minimums: capability 5.0 or higher; driver 550 or higher, 570 or higher for capabilities 5.0 to 6.2.
+func TestJudgeNvidia(t *testing.T) {
+	// The cases.
+	for _, tc := range []struct {
+		// name describes the case.
+		name string
+		// g is the card.
+		g gpuInfo
+		// supported is the expected answer.
+		supported bool
+		// level is the expected level.
+		level string
+	}{
+		{"GTX 1050 with a new driver", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "6.1", Driver: "576.80"}, true, "ok"},
+		{"GTX 1050 with driver 560 (needs 570)", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "6.1", Driver: "560.10"}, false, "warn"},
+		{"capability 8.6 with driver 555 (needs 550)", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "8.6", Driver: "555.1"}, true, "ok"},
+		{"capability 6.3 with driver 550", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "6.3", Driver: "550.1"}, true, "ok"},
+		{"capability 6.2 with driver 550 (needs 570)", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "6.2", Driver: "550.1"}, false, "warn"},
+		{"capability 3.5", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "3.5", Driver: "576.80"}, false, "warn"},
+		{"capability not reported", gpuInfo{Vendor: "nvidia", Name: "A", Driver: "576.80"}, false, "info"},
+		{"driver not reported", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "8.6"}, false, "info"},
+	} {
+		// One case.
+		ok, f := judgeNvidia(tc.g)
+		// Compare.
+		if ok != tc.supported || f.Level != tc.level {
+			// Report it.
+			t.Errorf("%s: supported=%v level=%s (%s)", tc.name, ok, f.Level, f.Text)
+		} // end of the check
+	} // end of the loop
+} // end of TestJudgeNvidia
+
+// TestJudgeReport checks the whole verdict, including the warning when no card is confirmed.
+func TestJudgeReport(t *testing.T) {
+	// A confirmed card gives no warning.
+	good := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.9", Driver: "560.1"}}})
+	// Look at the levels.
+	for _, f := range good {
+		// No warning.
+		if f.Level == "warn" {
+			// Report it.
+			t.Errorf("unexpected warning: %s", f.Text)
+		} // end of the check
+	} // end of the loop
+	// An AMD card is not judged, so the "nothing confirmed" warning appears; the text must say so honestly.
+	amd := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "amd", Name: "Radeon X"}}})
+	// Collect the text.
+	var all string
+	// Join it.
+	for _, f := range amd {
+		// Add it.
+		all += f.Level + ":" + f.Text + "\n"
+	} // end of the join
+	// Both the note and the warning.
+	if !strings.Contains(all, "info:Radeon X") || !strings.Contains(all, "warn:No graphics card could be confirmed") || !strings.Contains(all, "ROCm v7") {
+		// Report it.
+		t.Errorf("amd verdict:\n%s", all)
+	} // end of the check
+	// No cards at all also warns.
+	none := judgeReport(hostReport{})
+	// One warning.
+	if len(none) != 1 || none[0].Level != "warn" {
+		// Report it.
+		t.Errorf("no-card verdict = %+v", none)
+	} // end of the none check
+	// Apple counts as confirmed.
+	apple := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "apple", Name: "Apple M2"}}})
+	// One ok line.
+	if len(apple) != 1 || apple[0].Level != "ok" {
+		// Report it.
+		t.Errorf("apple verdict = %+v", apple)
+	} // end of the apple check
+} // end of TestJudgeReport
+
+// fakeProbes replaces the tool runner with answers from a map (key: the tool name); a missing key is a missing tool.
+func fakeProbes(t *testing.T, answers map[string]string) {
+	// Mark this as a helper.
+	t.Helper()
+	// Remember the real ones.
+	oldRun, oldOS, oldArch, oldLogical, oldRel := probeRun, reportOS, reportArch, reportLogical, osReleasePath
+	// Put them back at the end.
+	t.Cleanup(func() {
+		probeRun, reportOS, reportArch, reportLogical, osReleasePath = oldRun, oldOS, oldArch, oldLogical, oldRel
+	})
+	// The fake runner.
+	probeRun = func(ctx context.Context, name string, args ...string) (string, error) {
+		// The key is the base name of the tool (cut at either kind of slash, so a Windows path works on any system).
+		if out, ok := answers[name[strings.LastIndexAny(name, `/\\`)+1:]]; ok {
+			// The canned answer.
+			return out, nil
+		} // end of the answer check
+		// A missing tool.
+		return "", errors.New("not installed")
+	} // end of the fake runner
+	// Eight logical processors.
+	reportLogical = func() int { return 8 }
+} // end of fakeProbes
+
+// TestCollectReportLinux checks the Linux path end to end with fake tools.
+func TestCollectReportLinux(t *testing.T) {
+	// A calm machine.
+	quietMachine(t)
+	// The tools.
+	fakeProbes(t, map[string]string{"nvidia-smi": "NVIDIA GeForce GTX 1050, 4096, 576.80, 6.1", "lscpu": "0,0\n1,0\n0,0\n1,0\n", "lspci": `00:02.0 "VGA compatible controller" "Intel Corporation" "UHD Graphics 620" -r07 "Dell" "x"` + "\n" + `01:00.0 "3D controller" "NVIDIA Corporation" "GP107M" -ra1 "Dell" "y"`})
+	// The system.
+	reportOS, reportArch = "linux", "amd64"
+	// The distribution file.
+	rel := filepath.Join(t.TempDir(), "os-release")
+	// Write it.
+	if err := os.WriteFile(rel, []byte("PRETTY_NAME=\"Ubuntu 24.04\"\n"), 0o600); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// Use it.
+	osReleasePath = rel
+	// Collect.
+	r := collectReport(context.Background())
+	// The facts.
+	if r.OS != "Ubuntu 24.04" || r.Arch != "amd64 (x86-64)" || r.Physical != 2 || r.Logical != 8 || r.CPU != "Test Processor 9000" || r.MemBytes != 16_384_000_000 {
+		// Report it.
+		t.Errorf("report = %+v", r)
+	} // end of the facts check
+	// The NVIDIA card appears once (the tool's detailed entry wins over the lspci entry), plus the Intel one.
+	if len(r.GPUs) != 2 || r.GPUs[0].Compute != "6.1" || r.GPUs[1].Vendor != "intel" {
+		// Report it.
+		t.Errorf("gpus = %+v", r.GPUs)
+	} // end of the card check
+} // end of TestCollectReportLinux
+
+// TestCollectReportWindowsAndMac checks the other two paths with fake tools.
+func TestCollectReportWindowsAndMac(t *testing.T) {
+	// A calm machine.
+	quietMachine(t)
+	// Windows: no NVIDIA tool, one PowerShell answer.
+	fakeProbes(t, map[string]string{"powershell.exe": `{"os":"Microsoft Windows 11 Home","cpu":"Intel i7","cores":4,"gpus":[{"name":"NVIDIA GeForce GTX 1050","ram":null}]}`})
+	// The system.
+	reportOS, reportArch = "windows", "amd64"
+	// Collect.
+	w := collectReport(context.Background())
+	// The facts.
+	if w.OS != "Microsoft Windows 11 Home" || w.Physical != 4 || w.CPU != "Intel i7" || len(w.GPUs) != 1 {
+		// Report it.
+		t.Errorf("windows report = %+v", w)
+	} // end of the Windows check
+	// Without nvidia-smi the capability is unknown, so the verdict is "cannot be judged", never a guess.
+	if f := judgeReport(w); f[0].Level != "info" {
+		// Report it.
+		t.Errorf("windows verdict = %+v", f)
+	} // end of the verdict check
+	// macOS.
+	fakeProbes(t, map[string]string{"sw_vers": "x", "sysctl": "8", "system_profiler": `{"SPDisplaysDataType":[{"sppci_model":"Apple M2","spdisplays_vendor":"sppci_vendor_Apple"}]}`})
+	// The system.
+	reportOS, reportArch = "darwin", "arm64"
+	// Collect.
+	m := collectReport(context.Background())
+	// The facts.
+	if m.Physical != 8 || len(m.GPUs) != 1 || m.GPUs[0].Vendor != "apple" || m.Arch != "arm64 (ARM64)" {
+		// Report it.
+		t.Errorf("mac report = %+v", m)
+	} // end of the Mac check
+} // end of TestCollectReportWindowsAndMac
+
+// TestReportRows checks the words in the table, including "not reported".
+func TestReportRows(t *testing.T) {
+	// An empty report.
+	rows := reportRows(hostReport{OS: "X", Arch: "amd64 (x86-64)", Logical: 4})
+	// Join all lines.
+	var all string
+	// Collect them.
+	for _, r := range rows {
+		// Add the row.
+		all += r.Label + "=" + strings.Join(r.Lines, "|") + "\n"
+	} // end of the join
+	// The unknown figures are named, never guessed.
+	for _, want := range []string{"Processor=not reported", "4 logical (physical cores not reported)", "Memory=not reported", "Graphics cards=none reported"} {
+		// Each must be there.
+		if !strings.Contains(all, want) {
+			// Report it.
+			t.Errorf("missing %q in:\n%s", want, all)
+		} // end of the check
+	} // end of the loop
+	// A full report.
+	rows = reportRows(hostReport{OS: "X", Logical: 8, Physical: 4, MemBytes: 20 << 30, CPU: "P", GPUs: []gpuInfo{{Name: "G", MemMiB: 4096, Compute: "6.1", Driver: "576.80"}}})
+	// Look at the lines.
+	all = ""
+	// Collect them.
+	for _, r := range rows {
+		// Add the row.
+		all += strings.Join(r.Lines, "|") + "\n"
+	} // end of the join
+	// The figures.
+	for _, want := range []string{"8 logical (4 physical)", "20 GB", "1 found:", "G, 4 GB, compute capability 6.1, driver 576.80"} {
+		// Each must be there.
+		if !strings.Contains(all, want) {
+			// Report it.
+			t.Errorf("missing %q in:\n%s", want, all)
+		} // end of the check
+	} // end of the loop
+} // end of TestReportRows
diff --git a/web.go b/web.go
index 77f1f1e..3b5b7a7 100644
--- a/web.go
+++ b/web.go
@@ -154,6 +154,16 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	desktop := desktopIcon{env: mon.denv, dir: mon.store.dir, dataDir: dataRoot()}
 	// Route: a POST request for "/desktopicon" creates or removes the launcher, or records "no".
 	mux.HandleFunc("POST /desktopicon", desktopHandler(token, desktop))
+	// The System check: the hardware report, Continue, and the uninstall (see syscheck.go).
+	sysShow, sysContinue, uninstallAsk, uninstallDo := systemCheckHandlers(addr, mon, token, desktop)
+	// Route: a GET request for "/systemcheck" shows the report.
+	mux.HandleFunc("GET /systemcheck", sysShow)
+	// Route: a POST request for "/systemcheck/continue" records the answer and opens the monitor.
+	mux.HandleFunc("POST /systemcheck/continue", sysContinue)
+	// Route: a GET request for "/uninstall" shows what would be removed and changes nothing.
+	mux.HandleFunc("GET /uninstall", uninstallAsk)
+	// Route: a POST request for "/uninstall/confirm" removes the files and stops the monitor.
+	mux.HandleFunc("POST /uninstall/confirm", uninstallDo)
 	// Route: a GET request for "/icon.png" sends the program's icon (the page header, the browser tab and the desktop icon use it).
 	mux.HandleFunc("GET /icon.png", func(w http.ResponseWriter, r *http.Request) {
 		// Tell the browser this is a PNG image.
@@ -282,6 +292,16 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	mux.HandleFunc("GET /loading.js", loadingHandler)
 	// Route: a GET request for exactly "/" shows the page; other paths get 404 and other methods get 405 from the router.
 	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
+		// The very first start: show the System check once, before the monitor.
+		if mon.firstRunCheck && mon.store.dir != "" && !checkSeen(mon.store.dir) {
+			// A session note means it was answered although the folder could not be written.
+			if _, err := r.Cookie(systemCheckCookie); err != nil {
+				// Go to the report.
+				http.Redirect(w, r, "/systemcheck", http.StatusSeeOther)
+				// Stop here.
+				return
+			} // end of the cookie check
+		} // end of the first-start check
 		// Ask Ollama once; the request's own context cancels the check if the browser goes away.
 		// The check timeout from the Settings page, or the built-in one.
 		timeout := mon.timeoutOr(timeout)
diff --git a/web/app.css b/web/app.css
index 95dcb2a..20c3f2d 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2355,3 +2355,9 @@ html[data-size="medium"] svg[width="22"] {
   /* Space between them. */
   gap: 0.7rem;
 } /* end of rule */
+
+/* A line of the System check that reports good news or a note: a symbol plus words, so colour is never the only signal. */
+.okline {
+  /* A little room above and below. */
+  margin: 0.3rem 0;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 4dbcc43..aebfefe 100644
--- a/web/index.html
+++ b/web/index.html
@@ -593,6 +593,8 @@
 </div>
 {{/* The two buttons on the right. */}}
 <div class="brandbtns">
+{{/* The System check page: what this computer offers for Ollama. */}}
+<a class="brandbtn" href="/systemcheck">System check</a>
 {{/* The About page of this program. */}}
 <a class="brandbtn" href="/about">About this program</a>
 {{/* The company website, in a new window with no link back and no referrer. */}}
diff --git a/web/systemcheck.html b/web/systemcheck.html
new file mode 100644
index 0000000..84b719d
--- /dev/null
+++ b/web/systemcheck.html
@@ -0,0 +1,100 @@
+{{/* System check pages: the report, the uninstall question and the uninstall result. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* Both colour schemes are supported. */}}
+<meta name="color-scheme" content="light dark">
+{{/* The title shown on the browser tab. */}}
+<title>{{if eq .Kind "report"}}System check{{else}}Uninstall{{end}} - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+<main>
+{{/* A panel that holds the content. */}}
+<section class="panel">
+{{/* After the monitor has stopped there is nothing to go back to, so that page has no arrow. */}}
+{{if ne .Kind "removed"}}
+{{/* The back arrow in the top right corner: a round link to the monitor; it only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
+{{end}}
+{{/* Version 1: the report. */}}
+{{if eq .Kind "report"}}
+<h1>System check</h1>
+<p>OllamaControlCenter helps you switch between models while you develop applications, and shows how large language models perform. Here is what this computer offers.</p>
+<h2>This computer</h2>
+{{/* The facts of this computer; a figure the system did not give says "not reported". */}}
+<table class="settingtable"><tbody>
+{{range .Rows}}<tr><th scope="row">{{.Label}}</th><td>{{range $i, $l := .Lines}}{{if $i}}<br>{{end}}{{$l}}{{end}}</td></tr>
+{{end}}</tbody></table>
+<h2>Ollama</h2>
+{{if .Online}}
+<p class="okline"><span class="symbol" aria-hidden="true">&#10004;</span> Ollama was found at <code>{{.Address}}</code>{{if .Version}} (version {{.Version}}){{end}}.</p>
+{{else}}
+<p class="warn" role="alert"><strong>&#9888;</strong> Ollama was not found at <code>{{.Address}}</code>. <strong>This tool works with Ollama only.</strong> It does not work with other model servers such as vLLM. Install and start Ollama (ollama.com), or set its address under Settings.</p>
+{{if .Reason}}<p class="muted">{{.Reason}}</p>{{end}}
+{{end}}
+<h2>Against Ollama&rsquo;s published minimums</h2>
+{{range .Findings}}
+{{if eq .Level "ok"}}<p class="okline"><span class="symbol" aria-hidden="true">&#10004;</span> {{.Text}}</p>
+{{else if eq .Level "warn"}}<p class="warn"><strong>&#9888;</strong> {{.Text}}</p>
+{{else}}<p class="okline"><span class="symbol" aria-hidden="true">&#8505;</span> {{.Text}}</p>
+{{end}}
+{{end}}
+<p class="muted">Source: {{.Source}}. It states no minimum for processor, memory or graphics memory, so these are shown without a verdict. A model larger than the graphics memory runs partly on the processor and is slower. Anything the system did not report is shown as &ldquo;not reported&rdquo; and is never guessed.</p>
+{{/* The two choices side by side, each with its tooltip. */}}
+<div class="choices">
+{{/* Continue: records the answer and opens the monitor. */}}
+<form method="post" action="/systemcheck/continue">
+<input type="hidden" name="token" value="{{.Token}}">
+<span class="tipbox"><button type="submit" class="btn-solid" aria-describedby="tipcontinue">Continue to the monitor</button><span class="tip" role="tooltip" id="tipcontinue">Open the monitor. This report stays available later under System check, and you will not be asked again.</span></span>
+</form>
+{{/* Uninstall: only goes to the confirmation page; nothing is removed yet. */}}
+<span class="tipbox"><a class="btn-plain" href="/uninstall" aria-describedby="tipuninstall">Uninstall this tool</a><span class="tip" role="tooltip" id="tipuninstall">Removes the desktop icon and this program&rsquo;s saved settings, results and history, after you confirm. Your Ollama and its models are not touched. You then delete the program file yourself.</span></span>
+</div>
+{{/* Version 2: the uninstall question. */}}
+{{else if eq .Kind "uninstall"}}
+<h1>Uninstall OllamaControlCenter</h1>
+{{if .Items}}
+<p>This removes the following. Nothing is deleted until you press the button.</p>
+<table class="settingtable"><thead><tr><th scope="col">What</th><th scope="col">Where</th></tr></thead><tbody>
+{{range .Items}}<tr><th scope="row">{{.What}}</th><td>{{.Where}}</td></tr>
+{{end}}</tbody></table>
+{{else}}
+<p>There is nothing to remove: no desktop icon and no saved folders were found. You can still stop the monitor here and see which program file to delete.</p>
+{{end}}
+<p class="muted">Not touched: Ollama and your models, and the program file itself.</p>
+<div class="choices">
+{{/* Confirm: the real removal, then the monitor stops. */}}
+<form method="post" action="/uninstall/confirm">
+<input type="hidden" name="token" value="{{.Token}}">
+{{if .Items}}<span class="tipbox"><button type="submit" class="btn-solid" aria-describedby="tipyes">Yes, remove these files</button><span class="tip" role="tooltip" id="tipyes">Deletes the items above and stops the monitor. This cannot be undone.</span></span>{{else}}<span class="tipbox"><button type="submit" class="btn-solid" aria-describedby="tipyes">Stop the monitor</button><span class="tip" role="tooltip" id="tipyes">Nothing is deleted. The monitor stops and the program file to delete is shown.</span></span>{{end}}
+</form>
+{{/* The safe choice goes back to the report and changes nothing. */}}
+<span class="tipbox"><a class="btn-plain" href="/systemcheck" aria-describedby="tipno">No, go back</a><span class="tip" role="tooltip" id="tipno">Nothing is removed. You return to the System check.</span></span>
+</div>
+{{/* Version 3: the result. */}}
+{{else}}
+<h1>The monitor has stopped</h1>
+{{if .Items}}
+<table class="settingtable"><thead><tr><th scope="col">What</th><th scope="col">Where</th><th scope="col">Result</th></tr></thead><tbody>
+{{range .Items}}<tr><th scope="row">{{.What}}</th><td>{{.Where}}</td><td>{{.Result}}</td></tr>
+{{end}}</tbody></table>
+{{else}}
+<p>There was nothing to remove.</p>
+{{end}}
+<p>To finish, delete the program file yourself (a running program cannot reliably delete itself):</p>
+{{if .Program}}<p><code>{{.Program}}</code></p>{{else}}<p class="muted">The location of the program file could not be found; it is the file you started.</p>{{end}}
+<p class="muted">Ollama and its models were not touched.</p>
+{{end}}
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
0ae38a308c1a09706a3a40619acb729a4a0486c4a953e70043b5d15a7c9e28e3  about.go
a0d65dc438f520f9cfd1878beb95608d18e694dbd372b7ac696e84e1fbc1f6a9  desktopicon.go
5231b2054440e45dd95ad6057632f4f37ef499d0432853ca815d05cc0864d9a8  main.go
963b8a81c0dc803e761cd5be2f0cb322c4ee92b4380ee360a90ba9fa0f752e87  monitor.go
e0e55beb42e7a6103022630e103acd39bf4448eb120e28d575c9835b65a7c808  syscheck.go
649f656cf7caacfa7b7722731525c529e424f75a1f284b89e1c4d09c1e961b3d  syscheck_test.go
9173dd6b7327b37404f4c12010d4465563cd7b9063d0507be96530049d457f46  sysreport.go
cd0ea365906a2d14d01b094f8b11b1c3da5856f8cbcc1f9037758c40dfe5549f  sysreport_test.go
4240124fa6ec6fcba70ea24bae54734038e812f94e94121abedf505739ac58fd  web.go
93510925216edadde687725e5e207aa550bdbf5b498c28b451da567792239ad5  web/app.css
3679cb5ca9b4c7b52baaea90fcdf1a93abe5b0dc27b1ec6f45a594c4651cdcaf  web/index.html
5084d2d79072a4e0671cf2f49718ca2fd549e13af2e5dca5305733163c5dad37  web/systemcheck.html
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
echo "NEXT  start ./bin/OllamaControlCenter and open http://127.0.0.1:8765/ : the first start shows the System check page; test Continue, the System check link, and Uninstall (press No on the confirmation unless you really want to remove your settings); then commit, push and merge"
# List the changed files; nothing is committed yet.
git status --short
