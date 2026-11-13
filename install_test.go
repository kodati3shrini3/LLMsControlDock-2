// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes collects what -install prints.
	"bytes"
	// context is part of the fake tool runner's signature.
	"context"
	// encoding/json reads the install record.
	"encoding/json"
	// errors makes the fake tool runner fail.
	"errors"
	// net/http provides status codes for the fake Ollama.
	"net/http"
	// net/url parses the fake Ollama's address.
	"net/url"
	// os reads and writes the throw-away files.
	"os"
	// path/filepath builds the throw-away paths.
	"path/filepath"
	// runtime tells which system the test runs on (Unix file modes are not reported on Windows).
	"runtime"
	// strings looks for words in the output and the pages.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestInstallTargetFor checks the standard place of the installed program on each system, and the error when nothing names it.
func TestInstallTargetFor(t *testing.T) {
	// A home folder.
	home := func() (string, error) { return "/home/a", nil }
	// No home folder.
	noHome := func() (string, error) { return "", errors.New("none") }
	// Windows variables.
	env := func(name string) string { return map[string]string{"LocalAppData": `C:\Users\a\AppData\Local`}[name] }
	// Linux and macOS: ~/.local/bin.
	for _, goos := range []string{"linux", "darwin"} {
		// The place.
		got, err := installTargetFor(goos, env, home)
		// Exactly there.
		if err != nil || got != filepath.Join("/home/a", ".local", "bin", "LLMsControlDock") {
			// Report.
			t.Errorf("%s: %q %v", goos, got, err)
		} // end of the check
	} // end of the loop
	// Windows: %LocalAppData%\Programs\LLMsControlDock\LLMsControlDock.exe.
	if got, err := installTargetFor("windows", env, home); err != nil || got != filepath.Join(`C:\Users\a\AppData\Local`, "Programs", "LLMsControlDock", "LLMsControlDock.exe") {
		// Report.
		t.Errorf("windows: %q %v", got, err)
	} // end of the Windows check
	// Missing names give an error, never a guess.
	if _, err := installTargetFor("windows", func(string) string { return "" }, home); err == nil {
		// Report.
		t.Error("windows without LocalAppData gave no error")
	} // end of the Windows error check
	// No home folder on Linux.
	if _, err := installTargetFor("linux", env, noHome); err == nil {
		// Report.
		t.Error("linux without HOME gave no error")
	} // end of the Linux error check
} // end of TestInstallTargetFor

// TestPlacesBySystem checks the About page's table of places for each system, which is made from the same functions that create the folders.
func TestPlacesBySystem(t *testing.T) {
	// The expected table.
	want := []systemPlaces{
		// Settings.
		{"Settings", "~/.config/LLMsControlDock", `%AppData%\LLMsControlDock`, "~/Library/Application Support/LLMsControlDock"},
		// Data.
		{"Results, saved copies and deleted models", "~/.local/share/LLMsControlDock", `%LocalAppData%\LLMsControlDock`, "~/Library/Application Support/LLMsControlDock"},
		// State.
		{"Check history and log", "~/.local/state/LLMsControlDock", `%LocalAppData%\LLMsControlDock`, "~/Library/Application Support/LLMsControlDock"},
		// The installed program.
		{"Installed program (placed by -install)", "~/.local/bin/LLMsControlDock", `%LocalAppData%\Programs\LLMsControlDock\LLMsControlDock.exe`, "~/.local/bin/LLMsControlDock"},
	} // end of the expected table
	// The table.
	got := placesBySystem()
	// Same length.
	if len(got) != len(want) {
		// Stop.
		t.Fatalf("%d rows, want %d", len(got), len(want))
	} // end of the length check
	// Each row.
	for i := range want {
		// Equal.
		if got[i] != want[i] {
			// Report.
			t.Errorf("row %d:\n got %+v\nwant %+v", i, got[i], want[i])
		} // end of the row check
	} // end of the row loop
} // end of TestPlacesBySystem

// installRig is a throw-away home folder, program file and Ollama for one -install test.
type installRig struct {
	// home is the throw-away home folder.
	home string
	// exe is the pretend program file.
	exe string
	// target is where the copy goes.
	target string
	// ollama is the fake Ollama's address.
	ollama *url.URL
} // end of installRig

// newInstallRig makes a throw-away home with no folders yet, a pretend program file, a fake Ollama and no real tools or desktop.
func newInstallRig(t *testing.T) installRig {
	// Mark this as a helper.
	t.Helper()
	// The throw-away home.
	home := t.TempDir()
	// The program's folders follow this home.
	t.Setenv("HOME", home)
	// No XDG overrides.
	for _, n := range []string{"XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"} {
		// Cleared for this test.
		t.Setenv(n, "")
	} // end of the loop
	// The three base folders point into the throw-away home (the test suite points the settings elsewhere by default), and back at the end.
	oldCfg, oldData, oldState := userConfigDir, userDataDir, userStateDir
	// Restore.
	t.Cleanup(func() { userConfigDir, userDataDir, userStateDir = oldCfg, oldData, oldState })
	// Settings.
	userConfigDir = func() (string, error) { return filepath.Join(home, ".config"), nil }
	// Data.
	userDataDir = func() (string, error) { return filepath.Join(home, ".local", "share"), nil }
	// State.
	userStateDir = func() (string, error) { return filepath.Join(home, ".local", "state"), nil }
	// The pretend program file, somewhere else.
	exe := filepath.Join(t.TempDir(), "LLMsControlDock")
	// Some bytes.
	if err := os.WriteFile(exe, []byte("pretend program"), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// The copy goes into the home folder's ~/.local/bin.
	target := filepath.Join(home, ".local", "bin", "LLMsControlDock")
	// Point -install there, and back at the end.
	old := installTarget
	// Restore.
	t.Cleanup(func() { installTarget = old })
	// The test place.
	installTarget = func() (string, error) { return target, nil }
	// No real tool runs during the System check.
	oldProbe := probeRun
	// Restore.
	t.Cleanup(func() { probeRun = oldProbe })
	// Every tool "fails", so the report says "not reported".
	probeRun = func(ctx context.Context, name string, args ...string) (string, error) {
		return "", errors.New("no tools in tests")
	}
	// A fake Ollama that answers.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Its address.
	u, _ := url.Parse(srv.URL)
	// The rig.
	return installRig{home: home, exe: exe, target: target, ollama: u}
} // end of newInstallRig

// run runs -install with an answer and returns the exit code and what it printed.
func (r installRig) run(answer string) (int, string) {
	// The output.
	var out bytes.Buffer
	// Run it with no desktop.
	code := runInstall(installEnv{in: strings.NewReader(answer), out: &out, ollama: r.ollama, exe: func() (string, error) { return r.exe, nil }, desktop: noDesktopEnv()})
	// Both.
	return code, out.String()
} // end of run

// TestRunInstall checks the whole -install mode: the System check and the plan are shown, a "no" changes nothing, a "yes" makes the folders, copies the program and remembers it, and a second run shows both versions before replacing.
func TestRunInstall(t *testing.T) {
	// The rig.
	r := newInstallRig(t)
	// Say no.
	code, out := r.run("no\n")
	// Refused, with the check and the plan shown first.
	if code != 1 || !strings.Contains(out, "System check") || !strings.Contains(out, "This installation will:") || !strings.Contains(out, "Nothing was changed") {
		// Report.
		t.Fatalf("no: code %d, output:\n%s", code, out)
	} // end of the refusal check
	// Nothing was made.
	for _, p := range []string{configRoot(), dataRoot(), stateRoot(), r.target} {
		// Must not exist.
		if _, err := os.Stat(p); err == nil {
			// Report.
			t.Errorf("%s exists after a no", p)
		} // end of the exists check
	} // end of the loop
	// Say yes.
	code, out = r.run("yes\n")
	// Installed.
	if code != 0 || !strings.Contains(out, "Installed.") {
		// Stop.
		t.Fatalf("yes: code %d, output:\n%s", code, out)
	} // end of the success check
	// The three folders exist, for the person only.
	for _, p := range []string{configRoot(), dataRoot(), stateRoot()} {
		// Look.
		info, err := os.Stat(p)
		// A folder; on Unix with mode 0700 (Windows does not report Unix modes, so only the folder is checked there).
		if err != nil || !info.IsDir() || (runtime.GOOS != "windows" && info.Mode().Perm() != 0o700) {
			// Report.
			t.Errorf("%s: %v %v", p, info, err)
		} // end of the folder check
	} // end of the loop
	// The copy has the same bytes and is runnable.
	got, err := os.ReadFile(r.target)
	// Same bytes.
	if err != nil || string(got) != "pretend program" {
		// Report.
		t.Errorf("copy: %q %v", got, err)
	} // end of the bytes check
	// Runnable.
	if info, err := os.Stat(r.target); err != nil || (runtime.GOOS != "windows" && info.Mode().Perm()&0o100 == 0) {
		// Report.
		t.Errorf("the copy is not runnable: %v %v", info, err)
	} // end of the mode check
	// The record names the copy, the version and its fingerprint.
	raw, _ := os.ReadFile(filepath.Join(stateRoot(), installRecordFileName))
	// Decode it.
	var rec installRecord
	// It must decode and match.
	if json.Unmarshal(raw, &rec) != nil || rec.Path != r.target || rec.Version != appVersion || rec.SHA256 != fileSHA256(r.target) {
		// Report.
		t.Errorf("record: %s", raw)
	} // end of the record check
	// Uninstall may now remove exactly this copy.
	if p, ok := installedCopy(stateRoot()); !ok || p != r.target {
		// Report.
		t.Errorf("installedCopy: %q %v", p, ok)
	} // end of the installed check
	// The desktop icon was skipped and said so (no desktop in tests).
	if !strings.Contains(out, "Desktop icon skipped") {
		// Report.
		t.Error("the missing desktop was not reported")
	} // end of the icon check
	// A second run says the folders exist already, in plain words.
	if _, out2 := r.run("no\n"); !strings.Contains(out2, "Settings folder exists already, kept: "+configRoot()) || strings.Contains(out2, "Keep (") {
		// Report.
		t.Errorf("second run folder lines:\n%s", out2)
	} // end of the folder wording check
	// A second run shows both versions before replacing.
	code, out = r.run("no\n")
	// The plan names the installed version.
	if code != 1 || !strings.Contains(out, "Replace the installed program (version "+appVersion+") with version "+appVersion) {
		// Report.
		t.Errorf("second run plan:\n%s", out)
	} // end of the second-run check
} // end of TestRunInstall

// TestUninstallRemovesOnlyTheInstalledCopy checks that Uninstall lists and removes the copy -install placed, and leaves a changed copy alone.
func TestUninstallRemovesOnlyTheInstalledCopy(t *testing.T) {
	// The rig.
	r := newInstallRig(t)
	// Install.
	if code, out := r.run("yes\n"); code != 0 {
		// Stop.
		t.Fatalf("install failed:\n%s", out)
	} // end of the install check
	// The plan of the uninstall, with no desktop.
	plan := uninstallPlan(desktopIcon{env: noDesktopEnv()})
	// Find the program item.
	var item *uninstallItem
	// Look through the plan.
	for i := range plan {
		// The program item.
		if plan[i].Where == r.target {
			// Found.
			item = &plan[i]
		} // end of the match
	} // end of the search
	// It must be listed.
	if item == nil {
		// Stop.
		t.Fatalf("the installed copy is not in the uninstall plan: %+v", plan)
	} // end of the listed check
	// Remove it.
	if err := item.remove(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the remove check
	// It is gone; the running program file is untouched.
	if _, err := os.Stat(r.target); err == nil {
		// Report.
		t.Error("the installed copy is still there")
	} // end of the gone check
	// The running program file stays.
	if _, err := os.Stat(r.exe); err != nil {
		// Report.
		t.Error("the running program file was touched")
	} // end of the untouched check
	// Install again, then change the copy: a changed file is never removed.
	if code, out := r.run("yes\n"); code != 0 {
		// Stop.
		t.Fatalf("second install failed:\n%s", out)
	} // end of the second install check
	// Change the copy.
	if err := os.WriteFile(r.target, []byte("someone else's file"), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the change
	// No longer listed.
	for _, it := range uninstallPlan(desktopIcon{env: noDesktopEnv()}) {
		// The program must not be in the plan.
		if it.Where == r.target {
			// Report.
			t.Error("a changed copy is listed for removal")
		} // end of the match
	} // end of the loop
} // end of TestUninstallRemovesOnlyTheInstalledCopy

// TestAboutShowsThePlaces checks the About page's card of places: this computer's three folders with their state, the installed program's place, and the table for each system.
func TestAboutShowsThePlaces(t *testing.T) {
	// The rig gives a throw-away home, so the folders do not exist yet.
	r := newInstallRig(t)
	// The page.
	rig := newThemeRig(t)
	// Fetch it.
	_, _, body := get(t, rig.h, http.MethodGet, "/about")
	// The card and its parts.
	for _, want := range []string{`id="places"`, "Where this program keeps its files", "<code>" + configRoot() + "</code>", "<code>" + dataRoot() + "</code>", "<code>" + stateRoot() + "</code>", "<code>" + r.target + "</code>", "not installed", "not yet: made when you press Continue", "<code>~/.local/bin/LLMsControlDock</code>", `<code>%LocalAppData%\Programs\LLMsControlDock\LLMsControlDock.exe</code>`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the About page lacks %q", want)
		} // end of the look
	} // end of the loop
} // end of TestAboutShowsThePlaces

// TestJoinReportLines checks that a report row reads naturally on one line: a space after a colon, "; " between other lines.
func TestJoinReportLines(t *testing.T) {
	// The cases.
	for _, c := range []struct {
		// The lines and the wanted text.
		lines []string
		want  string
	}{
		// The graphics card row of the DGX.
		{[]string{"1 found:", "NVIDIA GB10, compute capability 12.1"}, "1 found: NVIDIA GB10, compute capability 12.1"},
		// Two plain lines.
		{[]string{"a", "b"}, "a; b"},
		// One line.
		{[]string{"only"}, "only"},
		// Nothing.
		{nil, ""},
	} {
		// Join.
		if got := joinReportLines(c.lines); got != c.want {
			// Report.
			t.Errorf("joinReportLines(%q) = %q, want %q", c.lines, got, c.want)
		} // end of the check
	} // end of the loop
} // end of TestJoinReportLines
