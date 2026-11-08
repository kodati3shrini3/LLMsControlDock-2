// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this test uses.
	// bytes compares picture data.
	"bytes"
	// encoding/binary reads the numbers of the picture containers.
	"encoding/binary"
	// errors builds the failure of a tool.
	"errors"
	// os makes and reads files.
	"os"
	// os/exec runs the macOS starting script for real.
	"os/exec"
	// path/filepath joins paths.
	"path/filepath"
	// runtime tells which system the test runs on.
	"runtime"
	// strings searches texts.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// toolCall records one call of the fake tool runner.
type toolCall struct {
	// exe is the tool.
	exe string
	// env is the extra environment.
	env []string
	// args are the arguments.
	args []string
} // end of toolCall

// launcherRig is a pretend Windows or macOS computer inside a temporary folder.
type launcherRig struct {
	// d is the desktop icon helper.
	d desktopIcon
	// desk is the desktop folder.
	desk string
	// exe is the program file.
	exe string
	// data is the data folder.
	data string
	// cfg is the settings folder.
	cfg string
	// calls records the tool calls.
	calls *[]toolCall
} // end of launcherRig

// newLauncherRig builds the rig for the given system name; the program sits in a folder whose name has a space and an apostrophe, which a careless launcher would break on.
func newLauncherRig(t *testing.T, goos string, makeLink bool) *launcherRig {
	// Mark this as a helper.
	t.Helper()
	// The pretend home, with links resolved.
	home, err := filepath.EvalSymlinks(t.TempDir())
	// A failure means the test is wrong.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the home check
	// The desktop.
	desk := filepath.Join(home, "Desktop")
	// Make it.
	if err := os.MkdirAll(desk, 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the desktop check
	// The program folder with an awkward name.
	progDir := filepath.Join(home, "O'Brien apps")
	// Make it.
	if err := os.MkdirAll(progDir, 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the folder check
	// The program file.
	exe := filepath.Join(progDir, "occ")
	// Write it.
	if err := os.WriteFile(exe, []byte("x"), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the file check
	// The calls.
	calls := &[]toolCall{}
	// The environment.
	env := desktopEnv{goos: goos, getenv: func(string) string { return "" }, homeDir: func() (string, error) { return home, nil }, exePath: func() (string, error) { return exe, nil }, trust: func(string) {}}
	// The Windows lookups.
	env.knownDesktop = func() (string, error) { return desk, nil }
	// The fake tool: it records the call and, like PowerShell would, writes the shortcut file.
	env.run = func(tool string, extra []string, args ...string) error {
		// Record it.
		*calls = append(*calls, toolCall{tool, extra, args})
		// Write the shortcut file the way the real tool would.
		if makeLink {
			// Find the link path in the environment.
			for _, e := range extra {
				// The variable.
				if v, ok := strings.CutPrefix(e, "OCC_LINK="); ok {
					// Create it.
					return os.WriteFile(v, []byte("lnk"), 0o644)
				} // end of the variable check
			} // end of the loop
		} // end of the link case
		// Nothing written.
		return nil
	} // end of the fake tool
	// The folders of the program.
	cfg, data := filepath.Join(home, "cfg"), filepath.Join(home, "data")
	// The helper.
	return &launcherRig{d: desktopIcon{env: env, dir: cfg, dataDir: data}, desk: desk, exe: exe, data: data, cfg: cfg, calls: calls}
} // end of newLauncherRig

// TestPngToICO checks the ICO container byte by byte.
func TestPngToICO(t *testing.T) {
	// The program's own picture is 256 by 256.
	ico, err := pngToICO(appIcon)
	// It must work.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the error check
	// ICONDIR: reserved 0, type 1, count 1.
	if binary.LittleEndian.Uint16(ico[0:]) != 0 || binary.LittleEndian.Uint16(ico[2:]) != 1 || binary.LittleEndian.Uint16(ico[4:]) != 1 {
		// Report it.
		t.Errorf("bad ICONDIR % x", ico[:6])
	} // end of the header check
	// ICONDIRENTRY: 256 is written as 0, no colours, reserved 0, 1 plane, 32 bits.
	if ico[6] != 0 || ico[7] != 0 || ico[8] != 0 || ico[9] != 0 || binary.LittleEndian.Uint16(ico[10:]) != 1 || binary.LittleEndian.Uint16(ico[12:]) != 32 {
		// Report it.
		t.Errorf("bad ICONDIRENTRY % x", ico[6:22])
	} // end of the entry check
	// The size and the offset.
	if int(binary.LittleEndian.Uint32(ico[14:])) != len(appIcon) || binary.LittleEndian.Uint32(ico[18:]) != 22 {
		// Report it.
		t.Errorf("bad size or offset")
	} // end of the size check
	// The picture follows unchanged.
	if !bytes.Equal(ico[22:], appIcon) {
		// Report it.
		t.Errorf("the PNG data was changed")
	} // end of the data check
	// A text is not a picture.
	if _, err := pngToICO([]byte("not a png at all, really not")); err == nil {
		// Report it.
		t.Errorf("a non-PNG was accepted")
	} // end of the refusal check
	// A picture that is too large for an ICO frame.
	big := append([]byte{}, appIcon...)
	// Make the width 512.
	binary.BigEndian.PutUint32(big[16:], 512)
	// Refused.
	if _, err := pngToICO(big); err == nil {
		// Report it.
		t.Errorf("a 512-pixel picture was accepted")
	} // end of the large check
} // end of TestPngToICO

// TestPngToICNS checks the Apple icon container.
func TestPngToICNS(t *testing.T) {
	// Make it.
	icns, err := pngToICNS(appIcon)
	// It must work.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the error check
	// The magic and the total length (big-endian).
	if string(icns[:4]) != "icns" || int(binary.BigEndian.Uint32(icns[4:])) != len(icns) {
		// Report it.
		t.Errorf("bad header % x", icns[:8])
	} // end of the header check
	// The element: type and length.
	if string(icns[8:12]) != "ic08" || int(binary.BigEndian.Uint32(icns[12:])) != len(icns)-8 {
		// Report it.
		t.Errorf("bad element % x", icns[8:16])
	} // end of the element check
	// The picture follows unchanged.
	if !bytes.Equal(icns[16:], appIcon) {
		// Report it.
		t.Errorf("the PNG data was changed")
	} // end of the data check
	// Another size is refused.
	small := append([]byte{}, appIcon...)
	// Make the width 128.
	binary.BigEndian.PutUint32(small[16:], 128)
	// Refused.
	if _, err := pngToICNS(small); err == nil {
		// Report it.
		t.Errorf("a 128-pixel picture was accepted")
	} // end of the size check
} // end of TestPngToICNS

// TestShQuoteAndScript checks the quoting of the macOS starting script.
func TestShQuoteAndScript(t *testing.T) {
	// A path with a space and an apostrophe.
	got := macScript("/Users/O'Brien/My App/occ")
	// The expected line.
	if !strings.Contains(got, `exec '/Users/O'\''Brien/My App/occ' -launch`) || !strings.HasPrefix(got, "#!/bin/sh\n") {
		// Report it.
		t.Errorf("script = %q", got)
	} // end of the check
} // end of TestShQuoteAndScript

// TestCreateWindowsShortcut checks the Windows shortcut: the call, the icon file, the answer, and that no path is pasted into the script.
func TestCreateWindowsShortcut(t *testing.T) {
	// The rig.
	r := newLauncherRig(t, "windows", true)
	// Create it.
	if err := r.d.create(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the create check
	// One tool call.
	if len(*r.calls) != 1 {
		// Stop.
		t.Fatalf("tool calls = %d", len(*r.calls))
	} // end of the call count
	// The call.
	c := (*r.calls)[0]
	// The arguments: no profile, no questions, and the fixed script.
	if strings.Join(c.args[:3], " ") != "-NoProfile -NonInteractive -Command" || c.args[3] != winShortcutScript {
		// Report it.
		t.Errorf("args = %q", c.args)
	} // end of the argument check
	// The script holds no path.
	if strings.Contains(winShortcutScript, r.exe) || strings.Contains(winShortcutScript, r.desk) {
		// Report it.
		t.Errorf("a path was pasted into the script")
	} // end of the injection check
	// The paths travel in the environment, with the awkward name intact.
	want := []string{"OCC_LINK=" + filepath.Join(r.desk, windowsLauncherName), "OCC_EXE=" + r.exe, "OCC_WORKDIR=" + filepath.Dir(r.exe), "OCC_ICON=" + filepath.Join(r.data, icoFileName) + ",0"}
	// Compare.
	if strings.Join(c.env, "|") != strings.Join(want, "|") {
		// Report it.
		t.Errorf("env = %q\nwant %q", c.env, want)
	} // end of the environment check
	// The script asks for -launch and a minimised window.
	if !strings.Contains(winShortcutScript, "'-launch'") || !strings.Contains(winShortcutScript, "WindowStyle=7") {
		// Report it.
		t.Errorf("the script lacks -launch or the minimised window")
	} // end of the script check
	// The icon file is a valid ICO.
	ico, err := os.ReadFile(filepath.Join(r.data, icoFileName))
	// It must exist.
	if err != nil || len(ico) < 22 || binary.LittleEndian.Uint16(ico[2:]) != 1 {
		// Report it.
		t.Errorf("icon file: %v", err)
	} // end of the icon check
	// The answer is remembered, and the shortcut counts as existing.
	if r.d.choice() != "created" || !r.d.exists() {
		// Report it.
		t.Errorf("choice %q exists %v", r.d.choice(), r.d.exists())
	} // end of the answer check
	// A Windows launcher is never compared as text.
	if stale, _, _ := r.d.staleness(); stale {
		// Report it.
		t.Errorf("a Windows shortcut was reported stale")
	} // end of the stale check
	// Removing deletes the shortcut and the icon file.
	if err := r.d.removeFiles(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the remove check
	// Both gone.
	if r.d.exists() {
		// Report it.
		t.Errorf("the shortcut is still there")
	} // end of the gone check
	// The icon file too.
	if _, err := os.Stat(filepath.Join(r.data, icoFileName)); err == nil {
		// Report it.
		t.Errorf("the icon file is still there")
	} // end of the icon gone check
} // end of TestCreateWindowsShortcut

// TestCreateWindowsFailures checks that a failing or silent tool is reported and not remembered as success.
func TestCreateWindowsFailures(t *testing.T) {
	// The tool fails.
	r := newLauncherRig(t, "windows", true)
	// A failing tool.
	r.d.env.run = func(string, []string, ...string) error { return errors.New("blocked") }
	// It must fail.
	if err := r.d.create(); err == nil || r.d.choice() != "" {
		// Report it.
		t.Errorf("failing tool: err=%v choice=%q", err, r.d.choice())
	} // end of the failure check
	// The tool succeeds but writes nothing.
	q := newLauncherRig(t, "windows", false)
	// It must fail.
	if err := q.d.create(); err == nil || q.d.choice() != "" {
		// Report it.
		t.Errorf("silent tool: err=%v choice=%q", err, q.d.choice())
	} // end of the silent check
	// No way to run tools.
	n := newLauncherRig(t, "windows", true)
	// None.
	n.d.env.run = nil
	// Not supported.
	if err := n.d.create(); !errors.Is(err, errDesktopUnsupported) {
		// Report it.
		t.Errorf("no runner: %v", err)
	} // end of the no-runner check
} // end of TestCreateWindowsFailures

// TestCreateMacBundle checks the application bundle and that a second creation replaces it.
func TestCreateMacBundle(t *testing.T) {
	// The rig.
	r := newLauncherRig(t, "darwin", false)
	// Create it twice: the second time replaces the first.
	for i := 0; i < 2; i++ {
		// Create.
		if err := r.d.create(); err != nil {
			// Stop.
			t.Fatal(err)
		} // end of the create check
	} // end of the loop
	// The bundle.
	app := filepath.Join(r.desk, macLauncherName)
	// The property list.
	plist, err := os.ReadFile(filepath.Join(app, "Contents", "Info.plist"))
	// It must exist.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the read check
	// The keys.
	for _, want := range []string{"<key>CFBundleExecutable</key><string>LLMsControlDock</string>", "<key>CFBundlePackageType</key><string>APPL</string>", "<key>CFBundleIconFile</key><string>icon</string>", "<string>" + appVersion + "</string>", "com.termgate.llmscontroldock"} {
		// Each must be there.
		if !strings.Contains(string(plist), want) {
			// Report it.
			t.Errorf("Info.plist lacks %q", want)
		} // end of the check
	} // end of the loop
	// The script holds the quoted program path.
	script, err := os.ReadFile(filepath.Join(app, "Contents", "MacOS", "LLMsControlDock"))
	// It must exist.
	if err != nil || string(script) != macScript(r.exe) {
		// Report it.
		t.Errorf("script: %v %q", err, script)
	} // end of the script check
	// The icon.
	if icns, err := os.ReadFile(filepath.Join(app, "Contents", "Resources", "icon.icns")); err != nil || string(icns[:4]) != "icns" {
		// Report it.
		t.Errorf("icon: %v", err)
	} // end of the icon check
	// The script is executable (Windows has no such bit).
	if st, err := os.Stat(filepath.Join(app, "Contents", "MacOS", "LLMsControlDock")); err != nil || (modesApply() && st.Mode().Perm() != 0o755) {
		// Report it.
		t.Errorf("script mode: %v %v", st, err)
	} // end of the mode check
	// The answer is remembered and the bundle counts as existing.
	if r.d.choice() != "created" || !r.d.exists() {
		// Report it.
		t.Errorf("choice %q exists %v", r.d.choice(), r.d.exists())
	} // end of the answer check
	// Removing deletes the whole bundle.
	if err := r.d.removeFiles(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the remove check
	// Gone.
	if r.d.exists() {
		// Report it.
		t.Errorf("the bundle is still there")
	} // end of the gone check
	// The desktop folder itself stays.
	if _, err := os.Stat(r.desk); err != nil {
		// Report it.
		t.Errorf("the desktop folder was removed")
	} // end of the desktop check
} // end of TestCreateMacBundle

// TestMacScriptRuns runs the starting script for real with a program path that has a space and an apostrophe, and checks that the program receives -launch.
func TestMacScriptRuns(t *testing.T) {
	// The script needs a POSIX shell.
	if runtime.GOOS == "windows" {
		// Skip with the reason.
		t.Skip("the starting script is a POSIX shell script")
	} // end of the system check
	// The rig.
	r := newLauncherRig(t, "darwin", false)
	// Where the fake program writes what it received.
	out := filepath.Join(filepath.Dir(r.exe), "got.txt")
	// The fake program.
	if err := os.WriteFile(r.exe, []byte("#!/bin/sh\necho \"$@\" > "+shQuote(out)+"\n"), 0o755); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// Create the bundle.
	if err := r.d.create(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the create check
	// Run its script.
	if err := exec.Command(filepath.Join(r.desk, macLauncherName, "Contents", "MacOS", "LLMsControlDock")).Run(); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the run check
	// What the program received.
	got, err := os.ReadFile(out)
	// It must be exactly -launch.
	if err != nil || strings.TrimSpace(string(got)) != "-launch" {
		// Report it.
		t.Errorf("program received %q (%v)", got, err)
	} // end of the check
} // end of TestMacScriptRuns

// TestDesktopDirWindowsAndMac checks where each system's desktop is found.
func TestDesktopDirWindowsAndMac(t *testing.T) {
	// Windows: the Known Folder lookup decides.
	w := newLauncherRig(t, "windows", false)
	// Found.
	if dir, ok := w.d.env.desktopDir(); !ok || dir != w.desk {
		// Report it.
		t.Errorf("windows desktop = %q %v", dir, ok)
	} // end of the found check
	// A failing lookup means no desktop.
	w.d.env.knownDesktop = func() (string, error) { return "", errors.New("no") }
	// Not found.
	if _, ok := w.d.env.desktopDir(); ok {
		// Report it.
		t.Errorf("a failing lookup gave a desktop")
	} // end of the not-found check
	// macOS: Desktop in the home folder.
	m := newLauncherRig(t, "darwin", false)
	// Found.
	if dir, ok := m.d.env.desktopDir(); !ok || dir != m.desk {
		// Report it.
		t.Errorf("mac desktop = %q %v", dir, ok)
	} // end of the found check
	// Without the folder there is no desktop.
	if err := os.RemoveAll(m.desk); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the remove check
	// Not found.
	if _, ok := m.d.env.desktopDir(); ok {
		// Report it.
		t.Errorf("a missing Desktop folder gave a desktop")
	} // end of the missing check
	// Another system.
	o := newLauncherRig(t, "plan9", false)
	// Not found.
	if _, ok := o.d.env.desktopDir(); ok {
		// Report it.
		t.Errorf("an unknown system gave a desktop")
	} // end of the other check
} // end of TestDesktopDirWindowsAndMac

// TestIconWordsPerSystem checks that the Ubuntu hint stays on Linux.
func TestIconWordsPerSystem(t *testing.T) {
	// Linux keeps the hint.
	if !strings.Contains(iconNoteFor("created", "linux"), "Allow Launching") || !strings.Contains(desktopHint("linux"), "Allow Launching") {
		// Report it.
		t.Errorf("the Linux hint is missing")
	} // end of the Linux check
	// The others have none.
	for _, goos := range []string{"windows", "darwin"} {
		// The note and the hint.
		if strings.Contains(iconNoteFor("created", goos), "Ubuntu") || desktopHint(goos) != "" || iconNoteFor("created", goos) == "" {
			// Report it.
			t.Errorf("%s: note %q hint %q", goos, iconNoteFor("created", goos), desktopHint(goos))
		} // end of the check
	} // end of the loop
	// Other words are unchanged.
	if iconNoteFor("removed", "windows") != iconNotes["removed"] || iconNoteFor("bogus", "linux") != "" {
		// Report it.
		t.Errorf("other words changed")
	} // end of the other-words check
} // end of TestIconWordsPerSystem
