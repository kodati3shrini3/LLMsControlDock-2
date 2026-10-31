// Package main tells Go that this test file belongs to the same program as appsettings.go.
package main

import ( // import lists the packages this test file uses.
	// net/http provides status codes.
	"net/http"
	// net/url builds the forms.
	"net/url"
	// os looks at the files the settings write.
	"os"
	// path/filepath joins file names.
	"path/filepath"
	// regexp finds the page token.
	"regexp"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time provides durations.
	"time"
) // end of imports

// settingsRig is a web handler wired to a settings store in a temporary folder.
type settingsRig struct {
	// h is the handler.
	h http.Handler
	// mon is the monitor with the store.
	mon *monitor
	// dir is the temporary folder.
	dir string
	// token is the page token.
	token string
} // end of settingsRig

// newSettingsRig builds the rig; run says how the program was started.
func newSettingsRig(t *testing.T, run runInfo) *settingsRig {
	// Mark this as a helper.
	t.Helper()
	// A fresh folder for the files.
	dir := t.TempDir()
	// The monitor with a store in it.
	mon := newMonitorWith(openSettingsStore(dir, ""))
	// How the program runs.
	mon.run = run
	// The default address, as the program resolves it with nothing set.
	addr, err := resolve("", "")
	// A bad address means the test is wrong.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the address check
	// The handler.
	h := newWebHandlerWith(addr, time.Second, mon)
	// The page carries the token.
	_, _, body := get(t, h, http.MethodGet, "/settings")
	// Find the token.
	m := regexp.MustCompile(`name="token" value="([0-9a-f]+)"`).FindStringSubmatch(body)
	// The page must carry one.
	if m == nil {
		// Stop.
		t.Fatal("the settings page has no token")
	} // end of the token check
	// Hand back the rig.
	return &settingsRig{h: h, mon: mon, dir: dir, token: m[1]}
} // end of newSettingsRig

// save posts the form with the given values (the token is added).
func (r *settingsRig) save(t *testing.T, v url.Values) *http.Response {
	// Mark this as a helper.
	t.Helper()
	// The token and the action.
	v.Set("token", r.token)
	// The save button.
	if v.Get("action") == "" {
		// Save.
		v.Set("action", "save")
	} // end of the action default
	// Send it as the page would.
	return post(t, r.h, "/settings", v, fromThisPage)
} // end of save

// TestSettingsProblems checks the limits and the plain messages.
func TestSettingsProblems(t *testing.T) {
	// The cases.
	cases := []struct {
		// The name, the settings and the word the message must contain ("" means all is well).
		name string
		a    appSettings
		want string
	}{
		{"empty is fine", appSettings{}, ""},
		{"good numbers", appSettings{IntervalSeconds: 30, TimeoutSeconds: 10, HistoryMinutes: 60}, ""},
		{"interval too small", appSettings{IntervalSeconds: 4}, "Check interval"},
		{"interval too large", appSettings{IntervalSeconds: 301}, "Check interval"},
		{"timeout too small", appSettings{TimeoutSeconds: -1}, "Check timeout"},
		{"timeout too large", appSettings{TimeoutSeconds: 61}, "Check timeout"},
		{"history too small", appSettings{HistoryMinutes: 4}, "Chart history"},
		{"history too large", appSettings{HistoryMinutes: 241}, "Chart history"},
		{"timeout not shorter", appSettings{IntervalSeconds: 10, TimeoutSeconds: 10}, "shorter"},
		{"bad address", appSettings{OllamaURL: "ftp://x"}, "Ollama address"},
		{"good address", appSettings{OllamaURL: "http://10.0.0.5:11434"}, ""},
	} // end of the cases
	// Run them.
	for _, c := range cases {
		// The problems.
		got := strings.Join(c.a.problems(), " | ")
		// All well.
		if c.want == "" && got != "" {
			// Report it.
			t.Errorf("%s: unexpected problems %q", c.name, got)
		} // end of the fine check
		// A problem is expected.
		if c.want != "" && !strings.Contains(got, c.want) {
			// Report it.
			t.Errorf("%s: problems %q lack %q", c.name, got, c.want)
		} // end of the problem check
	} // end of the loop
} // end of TestSettingsProblems

// TestSettingsStoreRoundTrip checks that saved settings survive a restart, with private file rights, and that the defaults remove the file.
func TestSettingsStoreRoundTrip(t *testing.T) {
	// A folder.
	dir := t.TempDir()
	// The store.
	s := openSettingsStore(dir, "")
	// Save some values.
	want := appSettings{OllamaURL: "http://10.0.0.5:11434", IntervalSeconds: 30, TimeoutSeconds: 10, HistoryMinutes: 60, AllowOthers: true, SaveHistory: true}
	// Put them.
	if err := s.put(want); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the put check
	// A new store reads them back (a restart).
	if got := openSettingsStore(dir, "").get(); got != want {
		// Report it.
		t.Errorf("after restart got %+v want %+v", got, want)
	} // end of the read check
	// The file is private to the owner.
	info, err := os.Stat(filepath.Join(dir, settingsFileName))
	// It must exist.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the stat check
	// Owner only (not on Windows, where the bits mean little).
	if info.Mode().Perm()&0o077 != 0 {
		// Report it.
		t.Errorf("settings file mode %v is readable by others", info.Mode().Perm())
	} // end of the mode check
	// The defaults remove the file.
	if err := s.put(appSettings{}); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the reset check
	// Gone.
	if _, err := os.Stat(filepath.Join(dir, settingsFileName)); !os.IsNotExist(err) {
		// Report it.
		t.Errorf("settings file still there after the defaults: %v", err)
	} // end of the gone check
} // end of TestSettingsStoreRoundTrip

// TestSettingsStoreIgnoresBadFiles checks that damaged or out-of-range files are ignored with a note.
func TestSettingsStoreIgnoresBadFiles(t *testing.T) {
	// The bad contents.
	for name, text := range map[string]string{"not json": "{{{", "out of range": `{"interval_seconds": 1}`, "bad address": `{"ollama_url": "ftp://x"}`} {
		// A folder.
		dir := t.TempDir()
		// Write the file.
		if err := os.WriteFile(filepath.Join(dir, settingsFileName), []byte(text), 0o600); err != nil {
			// Stop.
			t.Fatal(err)
		} // end of the write check
		// Open it.
		s := openSettingsStore(dir, "")
		// The defaults are used.
		if s.get() != (appSettings{}) {
			// Report it.
			t.Errorf("%s: bad file was used: %+v", name, s.get())
		} // end of the defaults check
		// A note says why.
		if s.noteText() == "" {
			// Report it.
			t.Errorf("%s: no note about the ignored file", name)
		} // end of the note check
	} // end of the loop
} // end of TestSettingsStoreIgnoresBadFiles

// TestSettingsPageSaves checks the whole path: the page, a good save, a refused save, and the defaults.
func TestSettingsPageSaves(t *testing.T) {
	// The rig: the program runs on this computer only.
	r := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
	// The page shows all six settings and the warning.
	_, _, body := get(t, r.h, http.MethodGet, "/settings")
	// The things it must say.
	for _, w := range []string{"Ollama address", "Check interval (seconds)", "Check timeout (seconds)", "Chart history (minutes)", "Let other machines open this page", "Save check history to a file", "no password", `name="interval"`} {
		// Look for it.
		if !strings.Contains(body, w) {
			// Report it.
			t.Errorf("the settings page lacks %q", w)
		} // end of the check
	} // end of the loop
	// A good save: interval 30, timeout 8, history 60.
	res := r.save(t, url.Values{"ollama_url": {""}, "interval": {"30"}, "timeout": {"8"}, "history": {"60"}, "others": {"no"}, "savehistory": {"no"}})
	// It redirects back to the page.
	if res.StatusCode != http.StatusSeeOther || !strings.Contains(res.Header.Get("Location"), "/settings?saved=saved") {
		// Report it.
		t.Fatalf("good save: status %d location %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the redirect check
	// The store holds the values, and they apply at once.
	if got := r.mon.store.get(); got.IntervalSeconds != 30 || got.TimeoutSeconds != 8 || got.HistoryMinutes != 60 {
		// Report it.
		t.Errorf("saved values wrong: %+v", got)
	} // end of the value check
	// The timeout in force is the saved one.
	if r.mon.timeoutOr(time.Second) != 8*time.Second {
		// Report it.
		t.Errorf("timeout in force %v", r.mon.timeoutOr(time.Second))
	} // end of the timeout check
	// Values equal to the defaults are stored as not set.
	r.save(t, url.Values{"interval": {"10"}, "timeout": {"5"}, "history": {"30"}, "others": {"no"}, "savehistory": {"no"}})
	// Nothing is stored, so no file stays.
	if got := r.mon.store.get(); got != (appSettings{}) {
		// Report it.
		t.Errorf("defaults were stored as values: %+v", got)
	} // end of the default check
	// A refused save: interval out of range, text instead of a number, and nothing changes.
	r.save(t, url.Values{"interval": {"30"}, "timeout": {"8"}, "history": {"60"}, "others": {"no"}, "savehistory": {"no"}})
	// Now the bad form.
	res = r.save(t, url.Values{"interval": {"2"}, "timeout": {"abc"}, "history": {"60"}, "others": {"no"}, "savehistory": {"no"}})
	// It is refused with 422.
	if res.StatusCode != http.StatusUnprocessableEntity {
		// Report it.
		t.Errorf("bad save status %d", res.StatusCode)
	} // end of the status check
	// The body names both problems and keeps what was typed.
	text := bodyOf(res)
	// The messages.
	for _, w := range []string{"Check interval: use a whole number from 5 to 300", "Check timeout: use a whole number", `value="2"`} {
		// Look for it.
		if !strings.Contains(text, w) {
			// Report it.
			t.Errorf("refused page lacks %q", w)
		} // end of the check
	} // end of the loop
	// The earlier values stay.
	if got := r.mon.store.get(); got.IntervalSeconds != 30 {
		// Report it.
		t.Errorf("a refused save changed the settings: %+v", got)
	} // end of the unchanged check
	// A timeout that is not shorter than the interval, with the interval at its default, is refused.
	res = r.save(t, url.Values{"interval": {"10"}, "timeout": {"10"}, "history": {"30"}, "others": {"no"}, "savehistory": {"no"}})
	// Refused.
	if res.StatusCode != http.StatusUnprocessableEntity {
		// Report it.
		t.Errorf("overlap status %d", res.StatusCode)
	} // end of the overlap check
	// Save something first, so "Back to defaults" has something to change.
	r.save(t, url.Values{"interval": {"30"}, "timeout": {"8"}, "history": {"60"}, "others": {"no"}, "savehistory": {"no"}})
	// Back to the defaults only fills the form; it saves nothing.
	res = r.save(t, url.Values{"action": {"defaults"}})
	// The page is shown again (no redirect).
	if res.StatusCode != http.StatusOK {
		// Report it.
		t.Errorf("defaults: status %d", res.StatusCode)
	} // end of the status check
	// The page says nothing is saved yet and offers Cancel.
	page := bodyOf(res)
	// The words.
	for _, w := range []string{"Nothing is saved yet", ">Cancel</a>", `name="interval" type="number" inputmode="numeric" min="5" max="300" step="1" aria-label="Check interval (seconds)" value="10"`} {
		// Look for it.
		if !strings.Contains(page, w) {
			// Report it.
			t.Errorf("the defaults page lacks %q", w)
		} // end of the check
	} // end of the loop
	// The saved values are untouched until Save is pressed.
	if got := r.mon.store.get(); got.IntervalSeconds != 30 || got.HistoryMinutes != 60 {
		// Report it.
		t.Errorf("Back to defaults changed the saved settings: %+v", got)
	} // end of the untouched check
	// Pressing Save with the default values clears the saved settings.
	r.save(t, url.Values{"interval": {"10"}, "timeout": {"5"}, "history": {"30"}, "others": {"no"}, "savehistory": {"no"}})
	// Now everything is cleared.
	if got := r.mon.store.get(); got != (appSettings{}) {
		// Report it.
		t.Errorf("saving the defaults left values: %+v", got)
	} // end of the cleared check
} // end of TestSettingsPageSaves

// TestSettingsPageSecurity checks that a save needs the token and a same-origin request.
func TestSettingsPageSecurity(t *testing.T) {
	// The rig.
	r := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
	// The form.
	form := url.Values{"interval": {"30"}, "action": {"save"}}
	// No token.
	if res := post(t, r.h, "/settings", form, fromThisPage); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("no token: status %d", res.StatusCode)
	} // end of the token check
	// A good token but a foreign origin.
	form.Set("token", r.token)
	// Send it.
	if res := post(t, r.h, "/settings", form, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("cross-site: status %d", res.StatusCode)
	} // end of the origin check
	// Nothing was saved.
	if got := r.mon.store.get(); got != (appSettings{}) {
		// Report it.
		t.Errorf("a refused request saved %+v", got)
	} // end of the unchanged check
} // end of TestSettingsPageSecurity

// TestSettingsPageRestartNotes checks the notes for values that wait for a restart or are overridden.
func TestSettingsPageRestartNotes(t *testing.T) {
	// The program runs on this computer only, from the default.
	r := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
	// Save a new address and allow other machines.
	r.save(t, url.Values{"ollama_url": {"http://10.0.0.5:11434"}, "interval": {"10"}, "timeout": {"5"}, "history": {"30"}, "others": {"yes"}, "savehistory": {"no"}})
	// The page says both wait for a restart.
	_, _, body := get(t, r.h, http.MethodGet, "/settings?saved=saved")
	// The words.
	for _, w := range []string{"saved: http://10.0.0.5:11434 (used after a restart)", "saved: Yes (used after a restart)", "used the next time the monitor starts"} {
		// Look for it.
		if !strings.Contains(body, w) {
			// Report it.
			t.Errorf("the page lacks %q", w)
		} // end of the check
	} // end of the loop
	// With -listen given, the saved choice is overridden and says so.
	r2 := newSettingsRig(t, runInfo{Listen: "127.0.0.1:9000", ListenSource: sourceFlag})
	// Allow others.
	r2.save(t, url.Values{"interval": {"10"}, "timeout": {"5"}, "history": {"30"}, "others": {"yes"}, "savehistory": {"no"}})
	// The page.
	_, _, body2 := get(t, r2.h, http.MethodGet, "/settings")
	// The words.
	if !strings.Contains(body2, "-listen overrides this") {
		// Report it.
		t.Errorf("the page does not say that -listen overrides the saved choice")
	} // end of the override check
} // end of TestSettingsPageRestartNotes

// TestCheckHistoryFile checks that the history file is written, read after a restart, cut to the window, and deleted when switched off.
func TestCheckHistoryFile(t *testing.T) {
	// A folder and a store.
	dir := t.TempDir()
	// The store.
	s := openSettingsStore(dir, "")
	// Now.
	now := time.Now()
	// Three checks: one too old, two inside, one in the future.
	items := []sample{{At: now.Add(-3 * time.Hour), Online: true, Ms: 1}, {At: now.Add(-10 * time.Minute), Online: true, Ms: 2}, {At: now.Add(-time.Minute), Online: false, Ms: 3}, {At: now.Add(time.Hour), Online: true, Ms: 4}}
	// Write them.
	if err := s.saveSamples(items); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// Read them back with a 30-minute window.
	got := s.loadSamples(30*time.Minute, now)
	// Only the two inside the window.
	if len(got) != 2 || got[0].Ms != 2 || got[1].Ms != 3 {
		// Report it.
		t.Errorf("loaded %+v", got)
	} // end of the window check
	// A damaged file gives nothing.
	if err := os.WriteFile(filepath.Join(dir, checkHistoryFileName), []byte("nope"), 0o600); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the damage check
	// Nothing comes back.
	if got := s.loadSamples(30*time.Minute, now); got != nil {
		// Report it.
		t.Errorf("a damaged file gave %+v", got)
	} // end of the nothing check
	// Write it again, then switch the history off: the file is deleted.
	if err := s.saveSamples(items); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the rewrite check
	// Save settings with the history off.
	if err := s.put(appSettings{IntervalSeconds: 30}); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the put check
	// The history file is gone.
	if _, err := os.Stat(filepath.Join(dir, checkHistoryFileName)); !os.IsNotExist(err) {
		// Report it.
		t.Errorf("history file stayed after the history was switched off: %v", err)
	} // end of the gone check
} // end of TestCheckHistoryFile

// TestMonitorWritesHistoryWhenOn checks that record writes the file every saveHistoryEvery checks only while the setting is on.
func TestMonitorWritesHistoryWhenOn(t *testing.T) {
	// A folder and a monitor with the history on.
	dir := t.TempDir()
	// The store.
	s := openSettingsStore(dir, "")
	// Switch it on.
	if err := s.put(appSettings{SaveHistory: true}); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the put check
	// The monitor.
	m := newMonitorWith(s)
	// One short of the write.
	for i := 0; i < saveHistoryEvery-1; i++ {
		// A check.
		m.record(checkResult{Online: true}, time.Now())
	} // end of the loop
	// No file yet.
	if _, err := os.Stat(filepath.Join(dir, checkHistoryFileName)); !os.IsNotExist(err) {
		// Report it.
		t.Errorf("history file written too early: %v", err)
	} // end of the early check
	// The check that triggers the write.
	m.record(checkResult{Online: true}, time.Now())
	// The file exists.
	if _, err := os.Stat(filepath.Join(dir, checkHistoryFileName)); err != nil {
		// Report it.
		t.Errorf("history file not written: %v", err)
	} // end of the file check
	// With the setting off nothing is written.
	off := t.TempDir()
	// The monitor.
	m2 := newMonitorWith(openSettingsStore(off, ""))
	// Many checks.
	for i := 0; i < saveHistoryEvery*2; i++ {
		// A check.
		m2.record(checkResult{Online: true}, time.Now())
	} // end of the loop
	// No file.
	if _, err := os.Stat(filepath.Join(off, checkHistoryFileName)); !os.IsNotExist(err) {
		// Report it.
		t.Errorf("history written while switched off: %v", err)
	} // end of the off check
} // end of TestMonitorWritesHistoryWhenOn

// TestHistoryCeilingFollowsTheSettings checks that a long window at a short interval keeps more than 400 checks, never more than the hard ceiling.
func TestHistoryCeilingFollowsTheSettings(t *testing.T) {
	// A history with a 240-minute window and a 5-second interval.
	h := &sampleHistory{}
	// Set the limits.
	h.setLimits(240*time.Minute, 5*time.Second)
	// Now.
	now := time.Now()
	// More checks than the old ceiling, fewer than the new one.
	for i := 0; i < 1000; i++ {
		// One check, 5 seconds apart, ending now.
		h.add(sample{At: now.Add(-time.Duration(1000-i) * 5 * time.Second), Online: true, Ms: int64(i)})
	} // end of the loop
	// All kept.
	if n := len(h.all()); n != 1000 {
		// Report it.
		t.Errorf("kept %d checks, want 1000", n)
	} // end of the keep check
	// The ceiling for the largest settings is the hard one at most.
	if _, ceil := h.limits(); ceil > hardMaxSamples || ceil < 1000 {
		// Report it.
		t.Errorf("ceiling %d", ceil)
	} // end of the ceiling check
} // end of TestHistoryCeilingFollowsTheSettings

// TestChartsUseTheWindow checks that the charts speak of the chosen window and block size.
func TestChartsUseTheWindow(t *testing.T) {
	// Now.
	now := time.Now()
	// A 60-minute window has blocks of one minute.
	v := buildChartsFor([]sample{{At: now.Add(-time.Minute), Online: true, Ms: 10}}, now, true, false, 60*time.Minute, 20*time.Second)
	// The window text.
	if v.WindowText != "60 minutes" || v.EverySeconds != 20 {
		// Report it.
		t.Errorf("window %q every %d", v.WindowText, v.EverySeconds)
	} // end of the text check
	// The block size in the text alternative.
	if !strings.Contains(v.StateAlt, "blocks of 1 minute") {
		// Report it.
		t.Errorf("state text %q", v.StateAlt)
	} // end of the block check
	// The span words.
	for in, want := range map[time.Duration]string{30 * time.Second: "30 seconds", time.Second: "1 second", time.Minute: "1 minute", 4 * time.Minute: "4 minutes", 90 * time.Second: "90 seconds"} {
		// Compare.
		if got := spanWords(in); got != want {
			// Report it.
			t.Errorf("spanWords(%v) = %q want %q", in, got, want)
		} // end of the compare
	} // end of the loop
} // end of TestChartsUseTheWindow

// TestResolveWithSaved checks the order: option, environment variable, saved setting, default.
func TestResolveWithSaved(t *testing.T) {
	// The cases.
	cases := []struct {
		// The three layers and the expected source.
		flag, env, saved, want string
	}{
		{"", "", "", sourceDefault},
		{"", "", "http://10.0.0.5:11434", sourceSaved},
		{"", "http://10.0.0.6:11434", "http://10.0.0.5:11434", sourceEnv},
		{"http://10.0.0.7:11434", "http://10.0.0.6:11434", "http://10.0.0.5:11434", sourceFlag},
	} // end of the cases
	// Run them.
	for _, c := range cases {
		// Resolve.
		a, err := resolveWithSaved(c.flag, c.env, c.saved)
		// It must work.
		if err != nil || a.Source != c.want {
			// Report it.
			t.Errorf("%+v: source %q err %v", c, a.Source, err)
		} // end of the check
	} // end of the loop
} // end of TestResolveWithSaved

// TestChooseListen checks the order: option, saved choice, default.
func TestChooseListen(t *testing.T) {
	// The option wins.
	if a, s := chooseListen("127.0.0.1:9", true, true); a != "127.0.0.1:9" || s != sourceFlag {
		// Report it.
		t.Errorf("option: %q %q", a, s)
	} // end of the option check
	// The saved choice opens the page.
	if a, s := chooseListen(defaultListen, false, true); a != openListen || s != sourceSaved {
		// Report it.
		t.Errorf("saved: %q %q", a, s)
	} // end of the saved check
	// The default.
	if a, s := chooseListen(defaultListen, false, false); a != defaultListen || s != sourceDefault {
		// Report it.
		t.Errorf("default: %q %q", a, s)
	} // end of the default check
} // end of TestChooseListen

// TestLanHostGuard checks the Host rules for a page that is open to the network.
func TestLanHostGuard(t *testing.T) {
	// Open and closed listen addresses.
	for listen, want := range map[string]bool{"0.0.0.0:8765": true, "192.168.1.5:8765": true, "127.0.0.1:8765": false, "localhost:8765": false, "[::1]:8765": false} {
		// Compare.
		if got := lanListen(listen); got != want {
			// Report it.
			t.Errorf("lanListen(%q) = %v", listen, got)
		} // end of the compare
	} // end of the loop
	// The Host headers.
	for host, want := range map[string]bool{"192.168.1.20:8765": true, "localhost:8765": true, "[fe80::1]:8765": true, "evil.example:8765": false, "192.168.1.20:9999": false, "evil.example": false} {
		// Compare.
		if got := lanHostOK(host, "8765"); got != want {
			// Report it.
			t.Errorf("lanHostOK(%q) = %v", host, got)
		} // end of the compare
	} // end of the loop
	// This computer's own name is accepted.
	if name, err := os.Hostname(); err == nil && name != "" && !lanHostOK(name+":8765", "8765") {
		// Report it.
		t.Errorf("own host name %q refused", name)
	} // end of the name check
} // end of TestLanHostGuard

// TestSettingsLinkAndArrow checks that the main page links to the Settings page and that the Settings page has the back arrow.
func TestSettingsLinkAndArrow(t *testing.T) {
	// The rig.
	r := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
	// The main page.
	_, _, main := get(t, r.h, http.MethodGet, "/")
	// The link, its tooltip and its words.
	for _, w := range []string{`href="/settings"`, `id="tipsettings"`, "Settings</a>"} {
		// Look for it.
		if !strings.Contains(main, w) {
			// Report it.
			t.Errorf("the main page lacks %q", w)
		} // end of the check
	} // end of the loop
	// The Settings page.
	_, _, page := get(t, r.h, http.MethodGet, "/settings")
	// The arrow, before the heading.
	if i, j := strings.Index(page, `class="tipbox backtop"`), strings.Index(page, "<h1"); i < 0 || j < 0 || i > j {
		// Report it.
		t.Errorf("the Settings page has no back arrow at the top (%d, %d)", i, j)
	} // end of the arrow check
	// The button at the bottom is the same as on the other pages.
	if !strings.Contains(page, `<a class="btn-plain" href="/">Back to the monitor</a>`) {
		// Report it.
		t.Errorf("the Settings page lacks the Back to the monitor button")
	} // end of the button check
	// A page never caches, because it shows live values.
	if _, h, _ := get(t, r.h, http.MethodGet, "/settings"); h.Get("Cache-Control") != "no-store" {
		// Report it.
		t.Errorf("Cache-Control %q", h.Get("Cache-Control"))
	} // end of the cache check
	// An unknown saved word shows no note.
	if _, _, p := get(t, r.h, http.MethodGet, "/settings?saved=<script>"); strings.Contains(p, "<script>") {
		// Report it.
		t.Errorf("the saved word was echoed")
	} // end of the echo check
} // end of TestSettingsLinkAndArrow
