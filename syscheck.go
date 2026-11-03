// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds a page in memory first.
	"bytes"
	// context limits how long the detection may take.
	"context"
	// encoding/json keeps the first-start answer in a small file.
	"encoding/json"
	// fmt builds the result words.
	"fmt"
	// html/template fills the page and escapes everything.
	"html/template"
	// io limits how much of a file is read.
	"io"
	// log reports template errors.
	"log"
	// net/http is the web server.
	"net/http"
	// os removes folders and reads their state.
	"os"
	// path/filepath joins and checks paths.
	"path/filepath"
	// strings joins labels.
	"strings"
	// sync keeps the detection and the stop to one run.
	"sync"
	// sync/atomic holds the flag that stops the history save.
	"sync/atomic"
	// time sets waits and limits.
	"time"

	// embed stores the page template inside the program.
	_ "embed"
) // end of imports

// systemCheckTemplateText holds the System check pages, stored inside the executable at build time.
//
//go:embed web/systemcheck.html
var systemCheckTemplateText string

// systemCheckFileName is the small file in the settings folder that remembers the first start was answered.
const systemCheckFileName = "system-check.json"

// systemCheckCookie is a session note that the first-start report was answered, so a settings folder that cannot be written never causes a loop.
const systemCheckCookie = "occ-syscheck"

// noSaveOnStop is set by the uninstall so that the stop does not write the check history again (that would re-create the folder).
var noSaveOnStop atomic.Bool

// checkSeen says whether the first-start report was already answered.
func checkSeen(dir string) bool {
	// No folder: nothing can be remembered.
	if dir == "" {
		// Not remembered.
		return false
	} // end of the folder check
	// Open the file.
	f, err := os.Open(filepath.Join(dir, systemCheckFileName))
	// A missing file means not answered yet.
	if err != nil {
		// Not answered.
		return false
	} // end of the open check
	// Close it at the end.
	defer f.Close()
	// The content: a flag.
	var c struct {
		// Seen is true after Continue.
		Seen bool `json:"seen"`
	} // end of the content shape
	// Read at most 1 KiB; a damaged file counts as not answered.
	if err := json.NewDecoder(io.LimitReader(f, 1024)).Decode(&c); err != nil {
		// Not answered.
		return false
	} // end of the decode check
	// The flag.
	return c.Seen
} // end of checkSeen

// markSeen remembers that the first-start report was answered.
func markSeen(dir string) error {
	// Nowhere to write.
	if dir == "" {
		// Nothing to keep.
		return nil
	} // end of the folder check
	// Write it the safe way (a private file).
	return writeFile(dir, systemCheckFileName, []byte("{\"seen\":true}\n"))
} // end of markSeen

// sysRow is one row of the table "This computer".
type sysRow struct {
	// Label is the row heading.
	Label string
	// Lines are the value, one per line.
	Lines []string
	// Note explains where a value comes from or why it is missing; empty means no note.
	Note string
} // end of sysRow

// uninstallItem is one thing the uninstall removes.
type uninstallItem struct {
	// What names it in words.
	What string
	// Where is its full path.
	Where string
	// Result is filled in after the removal.
	Result string
	// remove deletes it.
	remove func() error
} // end of uninstallItem

// sysPage is what the System check templates show.
type sysPage struct {
	// Kind is report, uninstall or removed.
	Kind string
	// Theme and Size are the saved look.
	Theme, Size string
	// Token is the page token for the forms.
	Token string
	// WordWrong is true when the uninstall form came back without the typed word.
	WordWrong bool
	// First is true on the very first start: the monitor can only be reached through Continue, so the page has no back arrow.
	First bool
	// Rows is the table "This computer".
	Rows []sysRow
	// Online says whether Ollama answered.
	Online bool
	// Address is the Ollama address, with any password hidden.
	Address string
	// Version is Ollama's version when it answered.
	Version string
	// Reason is why it did not answer.
	Reason string
	// Findings are the verdict lines.
	Findings []finding
	// Source names the page the verdicts come from.
	Source string
	// Items are the things an uninstall removes.
	Items []uninstallItem
	// Program is the full path of the program file the person deletes.
	Program string
} // end of sysPage

// uninstallWord is the word the person types to confirm an uninstall after the tool has been in use.
const uninstallWord = "uninstall"

// notReported is the word for a figure the system did not give.
const notReported = "not reported"

// reportRows turns the report into the rows of the table.
func reportRows(r hostReport) []sysRow {
	// The processor.
	cpu := r.CPU
	// Not known.
	if cpu == "" {
		// Say so.
		cpu = notReported
	} // end of the processor check
	// The cores.
	cores := fmt.Sprintf("%d logical (physical cores %s)", r.Logical, notReported)
	// Physical cores known.
	if r.Physical > 0 {
		// Both.
		cores = fmt.Sprintf("%d logical (%d physical)", r.Logical, r.Physical)
	} // end of the cores check
	// The memory.
	mem := notReported
	// Known.
	if r.MemBytes > 0 {
		// In GB.
		mem = gigabytes(r.MemBytes)
	} // end of the memory check
	// The graphics cards.
	gpus := []string{"none reported"}
	// Some found.
	if len(r.GPUs) > 0 {
		// The heading line.
		gpus = []string{fmt.Sprintf("%d found:", len(r.GPUs))}
		// One line each.
		for _, g := range r.GPUs {
			// Add it.
			gpus = append(gpus, describeGPU(g))
		} // end of the card loop
	} // end of the cards check
	// The table, row by row.
	rows := []sysRow{{Label: "Operating system", Lines: []string{r.OS}}}
	// The computer model, only when the firmware reports one.
	if r.Model != "" {
		// Add it.
		rows = append(rows, sysRow{Label: "Computer model", Lines: []string{r.Model}})
	} // end of the model check
	// The architecture, the processor with its note, the cores and the memory.
	rows = append(rows, sysRow{Label: "Architecture", Lines: []string{r.Arch}}, sysRow{Label: "Processor", Lines: []string{cpu}, Note: r.CPUNote}, sysRow{Label: "Cores", Lines: []string{cores}}, sysRow{Label: "Memory", Lines: []string{mem}})
	// The cards, with a note when a card gave no memory figure.
	gnote := ""
	// Look for a card without a figure.
	for _, g := range r.GPUs {
		// One without memory.
		if g.MemMiB == 0 {
			// The note.
			gnote = "Where no graphics memory is shown, the system did not report it (some graphics processors share the computer's memory)."
		} // end of the memory check
	} // end of the card loop
	// Add the cards.
	rows = append(rows, sysRow{Label: "Graphics cards", Lines: gpus, Note: gnote})
	// Hand the table back.
	return rows
} // end of reportRows

// guardedRoot says whether a path is exactly this program's own folder inside the standard base folder, so nothing else can ever be deleted.
func guardedRoot(root string, lookup func() (string, error)) bool {
	// Ask for the base folder.
	base, err := lookup()
	// None known.
	if err != nil || base == "" || root == "" {
		// Not safe.
		return false
	} // end of the base check
	// The path must be absolute, end in the program's folder name, and be exactly base + name.
	return filepath.IsAbs(root) && filepath.Base(root) == dataFolderName && root == filepath.Join(base, dataFolderName)
} // end of guardedRoot

// uninstallPlan lists what an uninstall would remove, and only what exists now.
func uninstallPlan(d desktopIcon) []uninstallItem {
	// The items.
	var items []uninstallItem
	// The desktop icon.
	if d.exists() {
		// Add it.
		items = append(items, uninstallItem{What: "Desktop icon", Where: d.desktopPath(), remove: d.removeFiles})
	} // end of the icon case
	// The three folders; on macOS they are the same folder, so equal paths are joined into one line.
	type folder struct {
		// what names it.
		what string
		// root is its path.
		root string
		// lookup finds its base folder.
		lookup func() (string, error)
	} // end of folder
	// The three.
	folders := []folder{
		// Settings.
		{"Settings", configRoot(), userConfigDir},
		// Results.
		{"Results, saved copies and deleted models", dataRoot(), userDataDir},
		// History and log.
		{"Check history and log", stateRoot(), userStateDir},
	} // end of the folder list
	// Index of each path in items.
	at := map[string]int{}
	// Go through them.
	for _, f := range folders {
		// Not present: nothing to remove.
		if f.root == "" {
			// Next.
			continue
		} // end of the empty check
		// Is the folder there?
		if _, err := os.Stat(f.root); err != nil {
			// Next.
			continue
		} // end of the exists check
		// Already listed under another name: join the names.
		if i, ok := at[f.root]; ok {
			// Join.
			items[i].What += " and " + strings.ToLower(f.what[:1]) + f.what[1:]
			// Next.
			continue
		} // end of the duplicate check
		// Keep the values for the closure.
		root, lookup := f.root, f.lookup
		// Remember the position.
		at[root] = len(items)
		// Add it.
		items = append(items, uninstallItem{What: f.what, Where: root, remove: func() error {
			// Only the program's own folder may ever be deleted.
			if !guardedRoot(root, lookup) {
				// Refuse.
				return fmt.Errorf("refused: this is not the program's own folder")
			} // end of the guard
			// Delete the folder and everything in it.
			return os.RemoveAll(root)
		}}) // end of the item
	} // end of the folder loop
	// Hand the list back.
	return items
} // end of uninstallPlan

// systemCheckHandlers builds the four handlers: the report, Continue, the uninstall question and the uninstall itself.
func systemCheckHandlers(addr ollamaAddress, mon *monitor, token string, desktop desktopIcon) (show, cont, ask, confirm http.HandlerFunc) {
	// Read the template once.
	page := template.Must(template.New("syscheck").Parse(systemCheckTemplateText))
	// The hardware report is made once, when first needed; the hardware does not change while the program runs.
	var (
		// mu protects the cached report.
		mu sync.Mutex
		// cached is the report.
		cached *hostReport
	) // end of the cache variables
	// getReport returns the cached report, making it on first use.
	getReport := func(ctx context.Context) hostReport {
		// One at a time.
		mu.Lock()
		// Release at the end.
		defer mu.Unlock()
		// Make it once.
		if cached == nil {
			// Detect, with a limit.
			c, cancel := context.WithTimeout(ctx, 60*time.Second)
			// Release the timer.
			defer cancel()
			// The report.
			r := collectReport(c)
			// Keep it.
			cached = &r
		} // end of the first-use case
		// Hand it back.
		return *cached
	} // end of getReport
	// firstStart says whether this is the very first start, before the person has pressed Continue.
	firstStart := func(r *http.Request) bool {
		// Only the real program switches the check on, and only with a settings folder.
		if !mon.firstRunCheck || mon.store.dir == "" || checkSeen(mon.store.dir) {
			// Not the first start.
			return false
		} // end of the switch check
		// A session note means Continue was pressed although the folder could not be written.
		_, err := r.Cookie(systemCheckCookie)
		// No note: still the first start.
		return err != nil
	} // end of firstStart
	// send builds a page in memory first, so a template error gives a clean 500.
	send := func(w http.ResponseWriter, r *http.Request, data sysPage) {
		// What every page needs.
		data.Theme, data.Token, data.Size = themeFromRequest(r), token, sizeFromRequest(r)
		// On the first start there is no way back to the monitor except Continue.
		data.First = firstStart(r)
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason.
			log.Printf("system check page error: %v", err)
			// Send a plain 500.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the page.
		w.Write(buf.Bytes())
	} // end of send
	// formOK runs the checks every form shares.
	formOK := func(w http.ResponseWriter, r *http.Request) bool {
		// A form is small.
		r.Body = http.MaxBytesReader(w, r.Body, 1024)
		// Only a form on this very page may send this request.
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return false
		} // end of the origin check
		// Read the form.
		if err := r.ParseForm(); err != nil {
			// Refuse.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return false
		} // end of the form check
		// The token must match.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return false
		} // end of the token check
		// All good.
		return true
	} // end of formOK
	// show: the report, with a fresh Ollama check.
	show = func(w http.ResponseWriter, r *http.Request) {
		// The hardware.
		rep := getReport(r.Context())
		// Ask Ollama once.
		res := checkOllama(r.Context(), addr.URL, mon.timeoutOr(defaultCheckTimeout))
		// Fill in the page.
		send(w, r, sysPage{Kind: "report", Rows: reportRows(rep), Online: res.Online, Address: addr.URL.Redacted(), Version: res.Version, Reason: res.Reason, Findings: judgeReport(rep), Source: ollamaGPUSource})
	} // end of show
	// cont: remember the answer and open the monitor.
	cont = func(w http.ResponseWriter, r *http.Request) {
		// The checks.
		if !formOK(w, r) {
			// A refusal was already sent.
			return
		} // end of the checks
		// Remember it in the settings folder (a failure is not fatal).
		_ = markSeen(mon.store.dir)
		// And for this session, so a folder that cannot be written never causes a loop.
		http.SetCookie(w, &http.Cookie{Name: systemCheckCookie, Value: "1", Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Open the monitor.
		http.Redirect(w, r, "/", http.StatusSeeOther)
	} // end of cont
	// ask: the confirmation page; it changes nothing.
	ask = func(w http.ResponseWriter, r *http.Request) {
		// The program file the person deletes afterwards.
		exe, _ := executablePath()
		// Show what would be removed.
		send(w, r, sysPage{Kind: "uninstall", Items: uninstallPlan(desktop), Program: exe})
	} // end of ask
	// Stop only once, however many times the button is pressed.
	var once sync.Once
	// confirm: remove the items, then stop the monitor.
	confirm = func(w http.ResponseWriter, r *http.Request) {
		// The checks.
		if !formOK(w, r) {
			// A refusal was already sent.
			return
		} // end of the checks
		// After the tool has been in use, the person must type the word; capital letters do not matter. The check is made here as well as in the browser, so a hand-made request cannot skip it.
		if !firstStart(r) && !strings.EqualFold(strings.TrimSpace(r.PostFormValue("confirm")), uninstallWord) {
			// Show the question again with a note; nothing is removed.
			exe, _ := executablePath()
			// The page.
			send(w, r, sysPage{Kind: "uninstall", Items: uninstallPlan(desktop), Program: exe, WordWrong: true})
			// Stop here.
			return
		} // end of the word check
		// Do the removal once.
		var items []uninstallItem
		// The program file.
		exe, _ := executablePath()
		// Only the first press does the work.
		once.Do(func() {
			// What exists now.
			items = uninstallPlan(desktop)
			// Remove each and record the result in words.
			for i := range items {
				// Do it.
				if err := items[i].remove(); err != nil {
					// Say so, honestly.
					items[i].Result = "could not be removed completely: " + err.Error()
				} else {
					// Done.
					items[i].Result = "removed"
				} // end of the result choice
			} // end of the item loop
			// From now on nothing is saved again, or the folders would come back.
			mon.store.mu.Lock()
			// No settings folder.
			mon.store.dir = ""
			// No state folder.
			mon.store.stateDir = ""
			// Release.
			mon.store.mu.Unlock()
			// The stop must not write the history.
			noSaveOnStop.Store(true)
			// Stop in the background once the page has been sent.
			go func() {
				// A short moment for the page to arrive.
				time.Sleep(300 * time.Millisecond)
				// Undo what running work changed, within a time limit.
				ctx, cancel := context.WithTimeout(context.Background(), stopCleanupLimit)
				// Run the clean-ups.
				activeWork.runCleanups(ctx)
				// Release the timer.
				cancel()
				// Shut the program down.
				stopRequest()
			}() // end of the goroutine
		}) // end of once
		// Send the result page.
		send(w, r, sysPage{Kind: "removed", Items: items, Program: exe})
		// Send it now, so it reaches the browser before the program ends.
		if f, ok := w.(http.Flusher); ok {
			// Flush.
			f.Flush()
		} // end of the flush check
	} // end of confirm
	// Hand the four back.
	return show, cont, ask, confirm
} // end of systemCheckHandlers
