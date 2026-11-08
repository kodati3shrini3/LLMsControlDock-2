// Package main tells Go that this test file belongs to the same program as desktopicon.go.
package main

import ( // import lists the packages this test file uses.
	// bytes compares the picture.
	"bytes"
	// errors checks the refusals.
	"errors"
	// net/http provides status codes.
	"net/http"
	// net/http/httptest builds the requests with their own cookies.
	"net/http/httptest"
	// net/url builds the forms.
	"net/url"
	// os looks at the files.
	"os"
	// path/filepath joins file names.
	"path/filepath"
	// regexp finds the page token.
	"regexp"
	// runtime tells which system the test runs on.
	"runtime"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time provides durations.
	"time"
) // end of imports

// fakeDesktop is a pretend Linux desktop in a temporary folder.
type fakeDesktop struct {
	// env is the environment the code sees.
	env desktopEnv
	// home is the pretend home folder.
	home string
	// desk is the pretend desktop folder.
	desk string
	// exe is the pretend program file.
	exe string
	// trusted records the files the trust step was asked about.
	trusted *[]string
} // end of fakeDesktop

// newFakeDesktop builds the pretend desktop with a Desktop folder and a program file.
func newFakeDesktop(t *testing.T) fakeDesktop {
	// Mark this as a helper.
	t.Helper()
	// The desktop icon is offered on Linux only and its paths are Unix paths, so a Windows test run has nothing to check here.
	if runtime.GOOS == "windows" {
		// Skip with the reason.
		t.Skip("the desktop icon is offered on Linux only; its paths are Unix paths")
	} // end of the Windows check
	// The pretend home, with symbolic links resolved (on macOS the temporary folder /var is really /private/var, and the program resolves links too).
	home, err := filepath.EvalSymlinks(t.TempDir())
	// A failure means the test itself is wrong.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the home check
	// Its desktop folder.
	desk := filepath.Join(home, "Desktop")
	// Make it.
	if err := os.MkdirAll(desk, 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the folder check
	// The pretend program.
	exe := filepath.Join(home, "LLMsControlDock", "bin", "LLMsControlDock")
	// Its folder.
	if err := os.MkdirAll(filepath.Dir(exe), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the program folder check
	// The file.
	if err := os.WriteFile(exe, []byte("x"), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the file check
	// The trust record.
	trusted := &[]string{}
	// The environment: Linux with a GNOME session.
	env := desktopEnv{goos: "linux", getenv: func(k string) string {
		// Only the desktop name is set.
		if k == "XDG_CURRENT_DESKTOP" {
			// A GNOME desktop.
			return "ubuntu:GNOME"
		} // end of the name check
		// Nothing else.
		return ""
	}, homeDir: func() (string, error) { return home, nil }, exePath: func() (string, error) { return exe, nil }, trust: func(p string) { *trusted = append(*trusted, p) }}
	// Hand back the pieces.
	return fakeDesktop{env: env, home: home, desk: desk, exe: exe, trusted: trusted}
} // end of newFakeDesktop

// TestDesktopDirDetection checks where a desktop is found and where not.
func TestDesktopDirDetection(t *testing.T) {
	// A normal desktop.
	f := newFakeDesktop(t)
	// Found.
	if dir, ok := f.env.desktopDir(); !ok || dir != f.desk {
		// Report it.
		t.Errorf("desktopDir = %q, %v", dir, ok)
	} // end of the found check
	// Windows is not supported yet.
	w := f.env
	// The system name.
	w.goos = "windows"
	// Not found.
	if _, ok := w.desktopDir(); ok {
		// Report it.
		t.Errorf("windows reported a desktop")
	} // end of the windows check
	// A server without a screen has no desktop.
	s := f.env
	// No session variables.
	s.getenv = func(string) string { return "" }
	// Not found.
	if _, ok := s.desktopDir(); ok {
		// Report it.
		t.Errorf("a session-less system reported a desktop")
	} // end of the session check
	// A missing folder.
	if err := os.Remove(f.desk); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the remove check
	// Not found.
	if _, ok := f.env.desktopDir(); ok {
		// Report it.
		t.Errorf("a missing Desktop folder was reported")
	} // end of the folder check
	// The user's folder list names another place.
	other := filepath.Join(f.home, "Schreibtisch")
	// Make it.
	if err := os.MkdirAll(other, 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the make check
	// Write the list.
	if err := os.MkdirAll(filepath.Join(f.home, ".config"), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the config folder check
	// The file.
	if err := os.WriteFile(filepath.Join(f.home, ".config", "user-dirs.dirs"), []byte("XDG_DOCUMENTS_DIR=\"$HOME/Documents\"\nXDG_DESKTOP_DIR=\"$HOME/Schreibtisch\"\n"), 0o644); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the list check
	// Found in the named place.
	if dir, ok := f.env.desktopDir(); !ok || dir != other {
		// Report it.
		t.Errorf("desktopDir with a folder list = %q, %v", dir, ok)
	} // end of the list result check
} // end of TestDesktopDirDetection

// TestDesktopFileText checks the launcher text.
func TestDesktopFileText(t *testing.T) {
	// Build it.
	got := desktopFileText("/opt/occ/LLMsControlDock", "/home/u/.config/LLMsControlDock/icon.png")
	// The lines it must hold.
	for _, w := range []string{"[Desktop Entry]\n", "Type=Application\n", "Name=LLMsControlDock\n", "Exec=/opt/occ/LLMsControlDock -launch\n", "Icon=/home/u/.config/LLMsControlDock/icon.png\n", "Terminal=false\n"} {
		// Look for it.
		if !strings.Contains(got, w) {
			// Report it.
			t.Errorf("launcher text lacks %q", w)
		} // end of the check
	} // end of the loop
} // end of TestDesktopFileText

// TestDesktopCreateAndRemove checks the whole life of the launcher.
func TestDesktopCreateAndRemove(t *testing.T) {
	// The pretend desktop and a settings folder.
	f := newFakeDesktop(t)
	// The settings folder.
	set := filepath.Join(f.home, ".config", "LLMsControlDock")
	// The manager.
	d := desktopIcon{env: f.env, dir: set}
	// It is available and nothing was answered yet.
	if !d.available() || d.choice() != "" || d.exists() {
		// Report it.
		t.Fatalf("start state: available %v choice %q exists %v", d.available(), d.choice(), d.exists())
	} // end of the start check
	// Create it.
	if err := d.create(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the create check
	// The launcher is there, executable, and says what it should.
	path := filepath.Join(f.desk, desktopFileName)
	// Read it.
	raw, err := os.ReadFile(path)
	// It must exist.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the read check
	// The command and the picture.
	if !strings.Contains(string(raw), "Exec="+f.exe+" -launch\n") || !strings.Contains(string(raw), "Icon="+filepath.Join(set, iconFileName)+"\n") {
		// Report it.
		t.Errorf("launcher content wrong:\n%s", raw)
	} // end of the content check
	// The executable bit.
	if info, err := os.Stat(path); err != nil || info.Mode().Perm()&0o100 == 0 {
		// Report it.
		t.Errorf("launcher is not executable: %v %v", info, err)
	} // end of the mode check
	// The picture is the embedded one.
	if pic, err := os.ReadFile(filepath.Join(set, iconFileName)); err != nil || !bytes.Equal(pic, appIcon) {
		// Report it.
		t.Errorf("icon file wrong: %v", err)
	} // end of the picture check
	// The trust step ran for the launcher.
	if len(*f.trusted) != 1 || (*f.trusted)[0] != path {
		// Report it.
		t.Errorf("trust calls %v", *f.trusted)
	} // end of the trust check
	// The answer is remembered, and the launcher exists.
	if d.choice() != "created" || !d.exists() {
		// Report it.
		t.Errorf("after create: choice %q exists %v", d.choice(), d.exists())
	} // end of the state check
	// Remove it.
	if err := d.remove(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the remove check
	// Both files are gone and the answer is "declined", so the question does not come back by itself.
	if d.exists() || d.choice() != "declined" {
		// Report it.
		t.Errorf("after remove: exists %v choice %q", d.exists(), d.choice())
	} // end of the removed check
	// The picture is gone too.
	if _, err := os.Stat(filepath.Join(set, iconFileName)); !os.IsNotExist(err) {
		// Report it.
		t.Errorf("icon file stayed: %v", err)
	} // end of the picture check
	// Removing again is not an error.
	if err := d.remove(); err != nil {
		// Report it.
		t.Errorf("second remove: %v", err)
	} // end of the second remove check
} // end of TestDesktopCreateAndRemove

// TestDesktopCreateRefusals checks the two refusals.
func TestDesktopCreateRefusals(t *testing.T) {
	// A pretend desktop whose program path holds a space.
	f := newFakeDesktop(t)
	// The settings folder.
	set := filepath.Join(f.home, ".config", "LLMsControlDock")
	// The spaced path.
	spaced := filepath.Join(f.home, "my programs")
	// Make it.
	if err := os.MkdirAll(spaced, 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the folder check
	// The file.
	if err := os.WriteFile(filepath.Join(spaced, "occ"), []byte("x"), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the file check
	// The environment with the spaced path.
	env := f.env
	// The path.
	env.exePath = func() (string, error) { return filepath.Join(spaced, "occ"), nil }
	// Refused, and nothing is written.
	d := desktopIcon{env: env, dir: set}
	// The result.
	if err := d.create(); !errors.Is(err, errUnusualPath) {
		// Report it.
		t.Errorf("spaced path: %v", err)
	} // end of the path check
	// Nothing on the desktop.
	if d.exists() {
		// Report it.
		t.Errorf("a launcher was written for an unusual path")
	} // end of the nothing check
	// No desktop at all.
	n := desktopIcon{env: noDesktopEnv(), dir: set}
	// Refused.
	if err := n.create(); !errors.Is(err, errDesktopUnsupported) {
		// Report it.
		t.Errorf("no desktop: %v", err)
	} // end of the support check
	// No settings folder: not available.
	if (desktopIcon{env: f.env, dir: ""}).available() {
		// Report it.
		t.Errorf("available without a settings folder")
	} // end of the folder check
} // end of TestDesktopCreateRefusals

// desktopRig is a web handler wired to a pretend desktop.
type desktopRig struct {
	// h is the handler.
	h http.Handler
	// f is the pretend desktop.
	f fakeDesktop
	// token is the page token.
	token string
	// mon is the monitor.
	mon *monitor
} // end of desktopRig

// newDesktopRig builds the rig.
func newDesktopRig(t *testing.T) *desktopRig {
	// Mark this as a helper.
	t.Helper()
	// The pretend desktop.
	f := newFakeDesktop(t)
	// The settings folder inside it.
	set := filepath.Join(f.home, ".config", "LLMsControlDock")
	// The monitor with a store there.
	mon := newMonitorWith(openSettingsStore(set, ""))
	// The pretend desktop.
	mon.denv = f.env
	// The default address.
	addr, err := resolve("", "")
	// A bad address means the test is wrong.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the address check
	// The handler.
	h := newWebHandlerWith(addr, time.Second, mon)
	// The token comes from the Settings page.
	_, _, body := get(t, h, http.MethodGet, "/settings")
	// Find it.
	m := regexp.MustCompile(`name="token" value="([0-9a-f]+)"`).FindStringSubmatch(body)
	// It must exist.
	if m == nil {
		// Stop.
		t.Fatal("no token on the settings page")
	} // end of the token check
	// Hand back the rig.
	return &desktopRig{h: h, f: f, token: m[1], mon: mon}
} // end of newDesktopRig

// TestDesktopBannerAndButtons checks the first-run question, the answers and the Settings section.
func TestDesktopBannerAndButtons(t *testing.T) {
	// The rig.
	r := newDesktopRig(t)
	// The main page asks.
	_, _, page := get(t, r.h, http.MethodGet, "/")
	// The words of the banner.
	for _, w := range []string{"Create a desktop icon for LLMsControlDock?", "Yes, create it", "No, don't ask again", r.f.desk, r.f.exe, "Allow Launching", `action="/desktopicon"`, `<link rel="icon"`, `class="appicon"`} {
		// Look for it.
		if !strings.Contains(page, w) {
			// Report it.
			t.Errorf("the main page lacks %q", w)
		} // end of the check
	} // end of the loop
	// A button without the token is refused.
	if res := post(t, r.h, "/desktopicon", url.Values{"action": {"create"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("no token: status %d", res.StatusCode)
	} // end of the token check
	// A foreign origin is refused.
	if res := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"create"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("cross-site: status %d", res.StatusCode)
	} // end of the origin check
	// Nothing was created by the refused requests.
	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); !os.IsNotExist(err) {
		// Report it.
		t.Errorf("a refused request created the launcher: %v", err)
	} // end of the nothing check
	// "Yes, create it", pressed on the monitor page.
	res := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"create"}, "from": {"home"}}, fromThisPage)
	// It stays on the monitor page and leaves a short-lived note.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
		// Report it.
		t.Fatalf("create: status %d location %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the create check
	// The note cookie.
	var flash *http.Cookie
	// Find it.
	for _, c := range res.Cookies() {
		// The one we look for.
		if c.Name == iconFlashCookie {
			// Keep it.
			flash = c
		} // end of the name check
	} // end of the loop
	// It must be there with the fixed word.
	if flash == nil || flash.Value != "created" {
		// Stop.
		t.Fatalf("flash cookie: %+v", flash)
	} // end of the cookie check
	// The monitor page shows the note once, and deletes the cookie.
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	// Send the cookie back.
	req.AddCookie(flash)
	// Serve.
	rec := httptest.NewRecorder()
	// Run it.
	r.h.ServeHTTP(rec, req)
	// The page text.
	home := rec.Body.String()
	// The sentence and the stay-on-home result.
	if !strings.Contains(home, "Desktop icon created. On Ubuntu") || rec.Code != http.StatusOK {
		// Report it.
		t.Errorf("the monitor page does not show the note (status %d)", rec.Code)
	} // end of the note check
	// The cookie is deleted.
	gone := false
	// Look for the deletion.
	for _, c := range rec.Result().Cookies() {
		// A deletion has a negative age.
		if c.Name == iconFlashCookie && c.MaxAge < 0 {
			// Seen.
			gone = true
		} // end of the deletion check
	} // end of the loop
	// It must be deleted.
	if !gone {
		// Report it.
		t.Errorf("the note cookie was not deleted")
	} // end of the deleted check
	// An unknown word shows nothing.
	req2 := httptest.NewRequest(http.MethodGet, "/", nil)
	// A made-up word.
	req2.AddCookie(&http.Cookie{Name: iconFlashCookie, Value: "<script>"})
	// Serve.
	rec2 := httptest.NewRecorder()
	// Run it.
	r.h.ServeHTTP(rec2, req2)
	// Nothing is echoed.
	if strings.Contains(rec2.Body.String(), "<script>") {
		// Report it.
		t.Errorf("an unknown note word was echoed")
	} // end of the echo check
	// From the Settings page the result is shown on the Settings page.
	if res2 := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"create"}}, fromThisPage); res2.Header.Get("Location") != "/settings?icon=created" {
		// Report it.
		t.Errorf("create from settings: location %q", res2.Header.Get("Location"))
	} // end of the settings check
	// The launcher is there.
	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); err != nil {
		// Report it.
		t.Errorf("launcher not created: %v", err)
	} // end of the launcher check
	// The banner is gone from the main page.
	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for LLMsControlDock?") {
		// Report it.
		t.Errorf("the banner stayed after the answer")
	} // end of the banner check
	// The Settings page shows the state, the note and the Remove button.
	_, _, set := get(t, r.h, http.MethodGet, "/settings?icon=created")
	// The words.
	for _, w := range []string{"Desktop icon created. On Ubuntu", "The icon is on your desktop", "Remove desktop icon", "Create the icon again"} {
		// Look for it.
		if !strings.Contains(set, w) {
			// Report it.
			t.Errorf("the settings page lacks %q", w)
		} // end of the check
	} // end of the loop
	// Remove it.
	res = post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"remove"}}, fromThisPage)
	// The result word.
	if res.Header.Get("Location") != "/settings?icon=removed" {
		// Report it.
		t.Errorf("remove location %q", res.Header.Get("Location"))
	} // end of the remove check
	// Gone, and the banner does not return by itself.
	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); !os.IsNotExist(err) {
		// Report it.
		t.Errorf("launcher stayed: %v", err)
	} // end of the gone check
	// The banner stays away.
	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for LLMsControlDock?") {
		// Report it.
		t.Errorf("the banner came back after a removal")
	} // end of the stay-away check
	// An unknown note key shows nothing and echoes nothing.
	if _, _, p := get(t, r.h, http.MethodGet, "/settings?icon=<script>"); strings.Contains(p, "<script>") {
		// Report it.
		t.Errorf("the icon key was echoed")
	} // end of the echo check
} // end of TestDesktopBannerAndButtons

// TestDesktopDeclineAndNoDesktop checks "No, don't ask again" and that systems without a desktop see nothing.
func TestDesktopDeclineAndNoDesktop(t *testing.T) {
	// The rig.
	r := newDesktopRig(t)
	// "No, don't ask again".
	res := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"decline"}}, fromThisPage)
	// Back to the monitor.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
		// Report it.
		t.Errorf("decline: status %d location %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the decline check
	// No launcher and no banner.
	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); !os.IsNotExist(err) {
		// Report it.
		t.Errorf("decline created the launcher: %v", err)
	} // end of the launcher check
	// The banner is gone, and a new run (a new store) still remembers.
	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for LLMsControlDock?") {
		// Report it.
		t.Errorf("the banner stayed after No")
	} // end of the banner check
	// The Settings page still offers to create it.
	if _, _, p := get(t, r.h, http.MethodGet, "/settings"); !strings.Contains(p, "Create desktop icon") {
		// Report it.
		t.Errorf("the settings page does not offer the icon after No")
	} // end of the offer check
	// A system without a desktop shows neither the banner nor the section.
	plain := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
	// Its main page.
	if _, _, p := get(t, plain.h, http.MethodGet, "/"); strings.Contains(p, "desktop icon") {
		// Report it.
		t.Errorf("a system without a desktop shows the banner")
	} // end of the main page check
	// Its Settings page.
	if _, _, p := get(t, plain.h, http.MethodGet, "/settings"); strings.Contains(p, "Desktop icon") {
		// Report it.
		t.Errorf("a system without a desktop shows the icon section")
	} // end of the settings check
	// The icon picture is served as a PNG.
	code, hdr, body := get(t, r.h, http.MethodGet, "/icon.png")
	// The checks.
	if code != http.StatusOK || hdr.Get("Content-Type") != "image/png" || !strings.HasPrefix(body, "\x89PNG") {
		// Report it.
		t.Errorf("icon route: %d %q", code, hdr.Get("Content-Type"))
	} // end of the icon check
} // end of TestDesktopDeclineAndNoDesktop

// TestDesktopStaleness checks when the launcher counts as out of date.
func TestDesktopStaleness(t *testing.T) {
	// The pretend desktop and the two folders.
	f := newFakeDesktop(t)
	// The settings folder.
	set := filepath.Join(f.home, ".config", "LLMsControlDock")
	// The data folder, where the picture lives now.
	data := filepath.Join(f.home, ".local", "share", "LLMsControlDock")
	// The manager.
	d := desktopIcon{env: f.env, dir: set, dataDir: data}
	// No launcher: nothing to refresh.
	if stale, _, _ := d.staleness(); stale {
		// Report it.
		t.Error("a missing launcher was called stale")
	} // end of the missing check
	// Create it: now it is current.
	if err := d.create(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the create check
	// Current.
	if stale, _, _ := d.staleness(); stale {
		// Report it.
		t.Error("a fresh launcher was called stale")
	} // end of the current check
	// Path of the launcher.
	path := filepath.Join(f.desk, desktopFileName)
	// An old launcher: the picture is in the old place (as version 0.25.0 wrote it).
	oldIcon := filepath.Join(set, iconFileName)
	// Write it.
	if err := os.WriteFile(path, []byte(desktopFileText(f.exe, oldIcon)), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// Stale, with both paths named.
	stale, got, want := d.staleness()
	// Compare.
	if !stale || got != oldIcon || want != filepath.Join(data, iconFileName) {
		// Report it.
		t.Errorf("old icon: stale %v, old %q, new %q", stale, got, want)
	} // end of the old-icon check
	// A launcher for another copy of the program.
	if err := os.WriteFile(path, []byte(desktopFileText(filepath.Join(f.home, "elsewhere", "occ"), filepath.Join(data, iconFileName))), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// Stale, with the same picture path.
	stale, got, want = d.staleness()
	// Compare.
	if !stale || got != want {
		// Report it.
		t.Errorf("old program: stale %v, old %q, new %q", stale, got, want)
	} // end of the old-program check
	// Updating makes it current again.
	if err := d.create(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the update check
	// Current.
	if stale, _, _ := d.staleness(); stale {
		// Report it.
		t.Error("still stale after the update")
	} // end of the after check
} // end of TestDesktopStaleness

// TestDesktopStaleWarningOnPage checks the warning and the "Update the icon" button on the Settings page, and that the button fixes it.
func TestDesktopStaleWarningOnPage(t *testing.T) {
	// The rig.
	r := newDesktopRig(t)
	// A current launcher first.
	d := desktopIcon{env: r.f.env, dir: r.mon.store.dir, dataDir: dataRoot()}
	// Create it.
	if err := d.create(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the create check
	// The page: no warning.
	_, _, body := get(t, r.h, http.MethodGet, "/settings")
	// No warning, the usual button.
	if strings.Contains(body, "out of date") || strings.Contains(body, "Update the icon") || !strings.Contains(body, "Create the icon again") {
		// Report it.
		t.Error("a current launcher shows a warning")
	} // end of the current check
	// Make the launcher old.
	old := filepath.Join(r.mon.store.dir, iconFileName)
	// Write it.
	if err := os.WriteFile(filepath.Join(r.f.desk, desktopFileName), []byte(desktopFileText(r.f.exe, old)), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// The page: the warning and the button.
	_, _, body = get(t, r.h, http.MethodGet, "/settings")
	// Both must show, with the old path named.
	if !strings.Contains(body, "out of date") || !strings.Contains(body, "Update the icon") || !strings.Contains(body, old) {
		// Report it.
		t.Errorf("no warning for an old launcher")
	} // end of the stale check
	// Press the button (the action is "create").
	form := url.Values{"token": {r.token}, "action": {"create"}}
	// Send it.
	if resp := post(t, r.h, "/desktopicon", form, fromThisPage); resp.StatusCode != http.StatusSeeOther {
		// Report it.
		t.Errorf("update status = %d", resp.StatusCode)
	} // end of the post check
	// The page again: no warning.
	_, _, body = get(t, r.h, http.MethodGet, "/settings")
	// Gone.
	if strings.Contains(body, "out of date") {
		// Report it.
		t.Error("the warning stayed after the update")
	} // end of the fixed check
} // end of TestDesktopStaleWarningOnPage
