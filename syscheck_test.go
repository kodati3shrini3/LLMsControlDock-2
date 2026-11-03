// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this test uses.
	// errors builds the failure of a missing tool.
	"errors"
	// context is part of the fake runner's signature.
	"context"
	// io reads reply bodies.
	"io"
	// net/http gives the status codes.
	"net/http"
	// net/url builds form values.
	"net/url"
	// os makes and checks folders.
	"os"
	// path/filepath joins paths.
	"path/filepath"
	// regexp finds the page token.
	"regexp"
	// strings searches page text.
	"strings"
	// sync/atomic counts stops.
	"sync/atomic"
	// testing is Go's test framework.
	"testing"
	// time is used for the handler's timeout.
	"time"
) // end of imports

// sysRig is a web handler whose three standard folders are fake folders of the test.
type sysRig struct {
	// h is the handler.
	h http.Handler
	// mon is the monitor.
	mon *monitor
	// token is the page token.
	token string
	// cfg, data and state are the program's own folders (they exist).
	cfg, data, state string
	// stops counts the stop requests.
	stops *atomic.Int32
	// icon is the fake desktop icon helper.
	icon desktopIcon
} // end of sysRig

// newSysRig builds the rig; first says whether the first-start check is switched on, and same puts all three folders in one place (the macOS layout).
func newSysRig(t *testing.T, first, same bool) *sysRig {
	// Mark this as a helper.
	t.Helper()
	// A calm machine, and fake tools that are all missing.
	quietMachine(t)
	// No tools.
	fakeProbes(t, map[string]string{})
	// Replace the three base folders; put the originals back at the end.
	saveFolderLookups(t)
	// One base folder per kind, or the same one.
	root := t.TempDir()
	// The bases.
	cb, db, sb := filepath.Join(root, "c"), filepath.Join(root, "d"), filepath.Join(root, "s")
	// The macOS layout.
	if same {
		// One folder for all.
		cb, db, sb = filepath.Join(root, "a"), filepath.Join(root, "a"), filepath.Join(root, "a")
	} // end of the same-folder case
	// The lookups.
	userConfigDir = func() (string, error) { return cb, nil }
	// Data.
	userDataDir = func() (string, error) { return db, nil }
	// State.
	userStateDir = func() (string, error) { return sb, nil }
	// The program's own folders.
	cfg, data, state := configRoot(), dataRoot(), stateRoot()
	// Create them with a file each.
	for _, d := range []string{cfg, data, state} {
		// The folder.
		if err := os.MkdirAll(d, 0o700); err != nil {
			// Stop.
			t.Fatal(err)
		} // end of the folder check
		// A file in it.
		if err := os.WriteFile(filepath.Join(d, "x.txt"), []byte("x"), 0o600); err != nil {
			// Stop.
			t.Fatal(err)
		} // end of the file check
	} // end of the loop
	// A fake Ollama that is online.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.21.2"}`))
	// The address.
	addr, err := resolve(srv.URL, "")
	// A bad address means the test is wrong.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the address check
	// The monitor with its settings in the fake folder, and a fake Linux desktop.
	mon := newMonitorWith(openSettingsStore(cfg, ""))
	// The state folder.
	mon.store.stateDir = state
	// The fake desktop.
	f := newFakeDesktop(t)
	// Use it.
	mon.denv = f.env
	// Switch the first-start check on or off.
	mon.firstRunCheck = first
	// The desktop icon helper with the same values the handler gets.
	icon := desktopIcon{env: f.env, dir: cfg, dataDir: data}
	// Create the icon so that it is part of the plan.
	if err := icon.create(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the icon check
	// Count the stops.
	var n atomic.Int32
	// Remember the real one.
	old := stopRequest
	// Count instead of stopping.
	stopRequest = func() { n.Add(1) }
	// Put it back and clear the flag at the end.
	t.Cleanup(func() { stopRequest = old; noSaveOnStop.Store(false) })
	// The handler.
	h := newWebHandlerWith(addr, time.Second, mon)
	// The token is in the System check page.
	_, _, body := get(t, h, http.MethodGet, "/systemcheck")
	// Find it.
	m := regexp.MustCompile(`name="token" value="([0-9a-f]+)"`).FindStringSubmatch(body)
	// There must be one.
	if m == nil {
		// Stop.
		t.Fatal("the System check page has no token")
	} // end of the token check
	// Hand back the rig.
	return &sysRig{h: h, mon: mon, token: m[1], cfg: cfg, data: data, state: state, stops: &n, icon: icon}
} // end of newSysRig

// TestFirstStartRedirect checks that the first start shows the report, and Continue ends it.
func TestFirstStartRedirect(t *testing.T) {
	// The first-start check is on.
	r := newSysRig(t, true, false)
	// The main page redirects to the report.
	code, hdr, _ := get(t, r.h, http.MethodGet, "/")
	// Compare.
	if code != http.StatusSeeOther || hdr.Get("Location") != "/systemcheck" {
		// Report it.
		t.Fatalf("first visit = %d %q", code, hdr.Get("Location"))
	} // end of the redirect check
	// A form from elsewhere is refused.
	if res := post(t, r.h, "/systemcheck/continue", url.Values{"token": {r.token}}, nil); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("foreign form = %d", res.StatusCode)
	} // end of the origin check
	// A wrong token is refused.
	if res := post(t, r.h, "/systemcheck/continue", url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("wrong token = %d", res.StatusCode)
	} // end of the token check
	// Continue.
	res := post(t, r.h, "/systemcheck/continue", url.Values{"token": {r.token}}, fromThisPage)
	// It goes to the monitor.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
		// Report it.
		t.Fatalf("continue = %d %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the continue check
	// The answer is kept in the settings folder.
	if !checkSeen(r.cfg) {
		// Report it.
		t.Errorf("the answer was not saved")
	} // end of the saved check
	// And the main page opens now.
	if code, _, body := get(t, r.h, http.MethodGet, "/"); code != http.StatusOK || !strings.Contains(body, "System check") {
		// Report it.
		t.Errorf("after continue = %d", code)
	} // end of the open check
} // end of TestFirstStartRedirect

// TestNoRedirectWhenOffOrCookie checks the two cases where the first start does not redirect.
func TestNoRedirectWhenOffOrCookie(t *testing.T) {
	// Switched off (the tests and a missing folder).
	r := newSysRig(t, false, false)
	// The page opens.
	if code, _, _ := get(t, r.h, http.MethodGet, "/"); code != http.StatusOK {
		// Report it.
		t.Errorf("switched off = %d", code)
	} // end of the check
	// Switched on, but the answer cannot be saved: the session note stops a loop.
	on := newSysRig(t, true, false)
	// A folder that cannot be written: the settings folder is gone.
	on.mon.store.dir = filepath.Join(t.TempDir(), "nope", "x")
	// Make a file where the folder should be, so writing fails.
	blocker := filepath.Join(t.TempDir(), "file")
	// Write it.
	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the blocker check
	// A folder below a file cannot be created.
	on.mon.store.dir = filepath.Join(blocker, "sub")
	// The continue still sets the cookie.
	res := post(t, on.h, "/systemcheck/continue", url.Values{"token": {on.token}}, fromThisPage)
	// Find the cookie.
	var got bool
	// Look.
	for _, c := range res.Cookies() {
		// The note.
		if c.Name == systemCheckCookie {
			// Found.
			got = true
		} // end of the name check
	} // end of the loop
	// It must be there.
	if !got {
		// Report it.
		t.Errorf("no session note was set")
	} // end of the cookie check
} // end of TestNoRedirectWhenOffOrCookie

// TestSystemCheckPage checks the contents of the report and the tooltips.
func TestSystemCheckPage(t *testing.T) {
	// The rig.
	r := newSysRig(t, false, false)
	// The page.
	code, _, body := get(t, r.h, http.MethodGet, "/systemcheck")
	// It opens.
	if code != http.StatusOK {
		// Stop.
		t.Fatalf("status = %d", code)
	} // end of the status check
	// The parts that must be there.
	for _, want := range []string{"This computer", "Architecture", "Operating system", "Graphics cards", "Ollama was found at", "version 0.21.2", "Against Ollama", "docs.ollama.com/gpu", "Continue to the monitor", "Uninstall this tool", "This report stays available later under System check", "You then delete the program file yourself", `role="tooltip"`} {
		// Each must be there.
		if !strings.Contains(body, want) {
			// Report it.
			t.Errorf("missing %q", want)
		} // end of the check
	} // end of the loop
	// Every tooltip id that is referred to must exist.
	for _, m := range regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1) {
		// The id.
		if !strings.Contains(body, `id="`+m[1]+`"`) {
			// Report it.
			t.Errorf("tooltip %q has no text", m[1])
		} // end of the check
	} // end of the loop
	// The main page links to it.
	if _, _, home := get(t, r.h, http.MethodGet, "/"); !strings.Contains(home, `href="/systemcheck"`) {
		// Report it.
		t.Errorf("the main page has no System check link")
	} // end of the link check
} // end of TestSystemCheckPage

// TestSystemCheckWithoutOllama checks the "Ollama only" message.
func TestSystemCheckWithoutOllama(t *testing.T) {
	// The rig first, then a handler pointing at a closed port.
	r := newSysRig(t, false, false)
	// A handler for an address where nothing listens.
	h := newWebHandlerWith(mustResolve(t, "http://"+closedAddress(t)), time.Second, r.mon)
	// The page.
	_, _, body := get(t, h, http.MethodGet, "/systemcheck")
	// The messages.
	for _, want := range []string{"Ollama was not found at", "This tool works with Ollama only", "vLLM", "No graphics card could be confirmed"} {
		// Each must be there.
		if !strings.Contains(body, want) {
			// Report it.
			t.Errorf("missing %q", want)
		} // end of the check
	} // end of the loop
} // end of TestSystemCheckWithoutOllama

// mustResolve resolves an address for a test.
func mustResolve(t *testing.T, raw string) ollamaAddress {
	// Mark this as a helper.
	t.Helper()
	// Resolve.
	a, err := resolve(raw, "")
	// A failure means the test is wrong.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the check
	// Hand it back.
	return a
} // end of mustResolve

// TestUninstallQuestion checks that the question lists the paths and removes nothing.
func TestUninstallQuestion(t *testing.T) {
	// The rig.
	r := newSysRig(t, false, false)
	// The question page.
	code, _, body := get(t, r.h, http.MethodGet, "/uninstall")
	// It opens.
	if code != http.StatusOK {
		// Stop.
		t.Fatalf("status = %d", code)
	} // end of the status check
	// The paths and words.
	for _, want := range []string{"Desktop icon", r.cfg, r.data, r.state, "OK, uninstall", "Cancel", "This cannot be undone", "Nothing is removed", "Type <code>uninstall</code> to confirm", `pattern=`} {
		// Each must be there.
		if !strings.Contains(body, want) {
			// Report it.
			t.Errorf("missing %q", want)
		} // end of the check
	} // end of the loop
	// Nothing was deleted.
	for _, d := range []string{r.cfg, r.data, r.state} {
		// Still there.
		if _, err := os.Stat(d); err != nil {
			// Report it.
			t.Errorf("%s was removed by the question page", d)
		} // end of the check
	} // end of the loop
} // end of TestUninstallQuestion

// TestUninstallConfirm checks the removal, the stop and that nothing is saved again.
func TestUninstallConfirm(t *testing.T) {
	// The rig.
	r := newSysRig(t, false, false)
	// A folder next to the program's own folders that must survive.
	other := filepath.Join(filepath.Dir(r.cfg), "SomethingElse")
	// Make it.
	if err := os.MkdirAll(other, 0o700); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the folder check
	// A foreign form is refused and removes nothing.
	if res := post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}}, nil); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("foreign form = %d", res.StatusCode)
	} // end of the origin check
	// A wrong token is refused.
	if res := post(t, r.h, "/uninstall/confirm", url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("wrong token = %d", res.StatusCode)
	} // end of the token check
	// Nothing was removed so far.
	if _, err := os.Stat(r.cfg); err != nil {
		// Report it.
		t.Fatalf("a refused form removed the folder")
	} // end of the safe check
	// The real request.
	res := post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}, "confirm": {"UNINSTALL "}}, fromThisPage)
	// Read the page.
	b, _ := io.ReadAll(res.Body)
	// The result page.
	body := string(b)
	// It says what happened and names the program file.
	for _, want := range []string{"The monitor has stopped", "removed", "delete the program file yourself", r.cfg, "Ollama and its models were not touched"} {
		// Each must be there.
		if !strings.Contains(body, want) {
			// Report it.
			t.Errorf("missing %q in the result page", want)
		} // end of the check
	} // end of the loop
	// The three folders and the icon are gone.
	for _, d := range []string{r.cfg, r.data, r.state} {
		// Gone.
		if _, err := os.Stat(d); err == nil {
			// Report it.
			t.Errorf("%s still exists", d)
		} // end of the check
	} // end of the loop
	// The desktop icon is gone.
	if r.icon.exists() {
		// Report it.
		t.Errorf("the desktop icon is still there")
	} // end of the icon check
	// The other folder survived.
	if _, err := os.Stat(other); err != nil {
		// Report it.
		t.Errorf("an unrelated folder was removed")
	} // end of the survivor check
	// The stop happens in the background shortly after.
	deadline := time.Now().Add(3 * time.Second)
	// Wait for it.
	for r.stops.Load() == 0 && time.Now().Before(deadline) {
		// A short sleep.
		time.Sleep(20 * time.Millisecond)
	} // end of the wait
	// Exactly one stop.
	if n := r.stops.Load(); n != 1 {
		// Report it.
		t.Errorf("stops = %d, want 1", n)
	} // end of the stop check
	// The stop must not write the history again.
	if !noSaveOnStop.Load() {
		// Report it.
		t.Errorf("the history save was not switched off")
	} // end of the flag check
	// Saving anything now does not re-create the folders.
	_ = r.mon.store.saveSamples([]sample{{}})
	// Still gone.
	if _, err := os.Stat(r.state); err == nil {
		// Report it.
		t.Errorf("the state folder came back")
	} // end of the re-create check
	// A second press does not stop twice.
	post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}}, fromThisPage)
	// Give it a moment.
	time.Sleep(500 * time.Millisecond)
	// Still one.
	if n := r.stops.Load(); n != 1 {
		// Report it.
		t.Errorf("stops after a second press = %d", n)
	} // end of the second-press check
} // end of TestUninstallConfirm

// TestUninstallSameFolder checks the macOS layout, where the three folders are one: one line, one removal.
func TestUninstallSameFolder(t *testing.T) {
	// The rig with one shared folder.
	r := newSysRig(t, false, true)
	// The plan has the icon and one folder.
	plan := uninstallPlan(r.icon)
	// Count the folder lines.
	n := 0
	// Look.
	for _, it := range plan {
		// A folder line.
		if it.Where == r.cfg {
			// One more.
			n++
			// It names all three.
			if !strings.Contains(it.What, "Settings") || !strings.Contains(it.What, "results") || !strings.Contains(it.What, "history") {
				// Report it.
				t.Errorf("merged name = %q", it.What)
			} // end of the names check
		} // end of the folder-line check
	} // end of the loop
	// Exactly one.
	if n != 1 {
		// Report it.
		t.Errorf("folder lines = %d, want 1", n)
	} // end of the count check
} // end of TestUninstallSameFolder

// TestGuardedRoot checks that only the program's own folder inside the standard base folder may be deleted.
func TestGuardedRoot(t *testing.T) {
	// A base folder lookup.
	look := func() (string, error) { return "/home/ann/.config", nil }
	// The good path.
	if !guardedRoot("/home/ann/.config/"+dataFolderName, look) {
		// Report it.
		t.Errorf("the program's own folder was refused")
	} // end of the good case
	// The bad paths.
	for _, p := range []string{"", "/", "/home/ann", "/home/ann/.config", "/home/ann/.config/Other", "/home/ann/.config/" + dataFolderName + "/sub", "relative/" + dataFolderName, "/home/ann/.config/../" + dataFolderName} {
		// Each is refused.
		if guardedRoot(p, look) {
			// Report it.
			t.Errorf("%q must be refused", p)
		} // end of the check
	} // end of the loop
	// No base folder known.
	if guardedRoot("/x/"+dataFolderName, func() (string, error) { return "", errors.New("none") }) {
		// Report it.
		t.Errorf("a path without a known base must be refused")
	} // end of the none case
	// The unused import guard for the context package in this file.
	var _ context.Context
} // end of TestGuardedRoot

// TestNoBackArrowOnFirstStart checks that the very first start has no way back to the monitor except Continue, and that later visits have one.
func TestNoBackArrowOnFirstStart(t *testing.T) {
	// The first-start check is on and Continue was not pressed.
	r := newSysRig(t, true, false)
	// The report and the uninstall question have no arrow.
	for _, path := range []string{"/systemcheck", "/uninstall"} {
		// The page.
		_, _, body := get(t, r.h, http.MethodGet, path)
		// No back arrow.
		if strings.Contains(body, "backcircle") {
			// Report it.
			t.Errorf("%s has a back arrow on the first start", path)
		} // end of the check
	} // end of the loop
	// Press Continue.
	post(t, r.h, "/systemcheck/continue", url.Values{"token": {r.token}}, fromThisPage)
	// Later visits have the arrow.
	for _, path := range []string{"/systemcheck", "/uninstall"} {
		// The page.
		_, _, body := get(t, r.h, http.MethodGet, path)
		// The back arrow.
		if !strings.Contains(body, "backcircle") {
			// Report it.
			t.Errorf("%s has no back arrow after Continue", path)
		} // end of the check
	} // end of the loop
} // end of TestNoBackArrowOnFirstStart

// TestUninstallNeedsTheTypedWord checks that after Continue the removal needs the word, and that a wrong word removes nothing and does not use up the one-time stop.
func TestUninstallNeedsTheTypedWord(t *testing.T) {
	// The rig, and the first-start answer given.
	r := newSysRig(t, true, false)
	// Press Continue.
	post(t, r.h, "/systemcheck/continue", url.Values{"token": {r.token}}, fromThisPage)
	// The cookie of Continue is needed too, so use the saved answer only: the file exists now.
	for _, bad := range []url.Values{{"token": {r.token}}, {"token": {r.token}, "confirm": {""}}, {"token": {r.token}, "confirm": {"uninstal"}}, {"token": {r.token}, "confirm": {"yes"}}} {
		// Send it.
		res := post(t, r.h, "/uninstall/confirm", bad, fromThisPage)
		// Read the page.
		b, _ := io.ReadAll(res.Body)
		// It asks again.
		if !strings.Contains(string(b), "The word was not") {
			// Report it.
			t.Errorf("form %v was not refused", bad)
		} // end of the refusal check
	} // end of the loop
	// Nothing was removed and nothing stopped.
	for _, d := range []string{r.cfg, r.data, r.state} {
		// Still there.
		if _, err := os.Stat(d); err != nil {
			// Report it.
			t.Fatalf("%s was removed without the word", d)
		} // end of the check
	} // end of the loop
	// No stop yet.
	time.Sleep(500 * time.Millisecond)
	// Zero.
	if n := r.stops.Load(); n != 0 {
		// Report it.
		t.Errorf("stops = %d, want 0", n)
	} // end of the stop check
	// The question page has the typed word box after Continue.
	if _, _, body := get(t, r.h, http.MethodGet, "/uninstall"); !strings.Contains(body, `name="confirm"`) {
		// Report it.
		t.Errorf("no word box after Continue")
	} // end of the box check
	// The right word, in capitals and with spaces, removes.
	post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}, "confirm": {"  UnInstall "}}, fromThisPage)
	// Gone.
	if _, err := os.Stat(r.cfg); err == nil {
		// Report it.
		t.Errorf("the right word did not remove")
	} // end of the removal check
	// Let the scheduled stop happen inside this test.
	waitForStop(t, r)
} // end of TestUninstallNeedsTheTypedWord

// TestUninstallOnFirstStartHasNoWordBox checks that before Continue the plain OK / Cancel is shown and OK works without a word.
func TestUninstallOnFirstStartHasNoWordBox(t *testing.T) {
	// The first-start check is on and Continue was not pressed.
	r := newSysRig(t, true, false)
	// The question page.
	_, _, body := get(t, r.h, http.MethodGet, "/uninstall")
	// No word box, but the OK and Cancel buttons.
	if strings.Contains(body, `name="confirm"`) || !strings.Contains(body, "OK, uninstall") || !strings.Contains(body, "Cancel") {
		// Report it.
		t.Errorf("first-start question is wrong")
	} // end of the check
	// OK works without a word.
	post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}}, fromThisPage)
	// Gone.
	if _, err := os.Stat(r.cfg); err == nil {
		// Report it.
		t.Errorf("OK without a word did not remove on the first start")
	} // end of the removal check
	// Let the scheduled stop happen inside this test.
	waitForStop(t, r)
} // end of TestUninstallOnFirstStartHasNoWordBox

// waitForStop waits until the rig has seen its one stop request, so that the stop scheduled by a test cannot fire inside the next test.
func waitForStop(t *testing.T, r *sysRig) {
	// Mark this as a helper.
	t.Helper()
	// Wait at most three seconds.
	deadline := time.Now().Add(3 * time.Second)
	// Poll.
	for r.stops.Load() == 0 && time.Now().Before(deadline) {
		// A short sleep.
		time.Sleep(20 * time.Millisecond)
	} // end of the wait
} // end of waitForStop
