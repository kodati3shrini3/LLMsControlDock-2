#!/usr/bin/env bash
# Script 72 (version 0.23.0): the desktop icon. On first run, on a Linux system with a desktop, the monitor page asks once: Create a desktop icon? (Yes, create it / No, don't ask again). The icon launches the monitor in the background when it is not running and opens the page in your browser (new option -launch). The Settings page can create or remove the icon. The program also gets its own icon (page header and browser tab).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/desktop-icon" ] || { echo "FAIL  not on feature/desktop-icon"; exit 1; }
# Script 70c (Settings page) must be applied and merged already.
[ -e settingspage.go ] || { echo "FAIL  the Settings page (scripts 70 to 70c) is not in this branch"; exit 1; }
# Refuse to run twice.
if [ -e desktopicon.go ]; then
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
index 8203ac5..05e6252 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.22.0"
+const appVersion = "0.23.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/desktopicon.go b/desktopicon.go
new file mode 100644
index 0000000..12524e2
--- /dev/null
+++ b/desktopicon.go
@@ -0,0 +1,423 @@
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the packages this file uses.
+	// embed lets the icon picture travel inside the program.
+	_ "embed"
+	// encoding/json reads and writes the small file that remembers the person's answer.
+	"encoding/json"
+	// errors builds the plain error values below.
+	"errors"
+	// io limits how much of a file is read.
+	"io"
+	// net/http provides the request handler.
+	"net/http"
+	// os reads files, checks folders and sets file rights.
+	"os"
+	// os/exec runs the best-effort "trust this launcher" command.
+	"os/exec"
+	// path/filepath joins folder and file names for any operating system.
+	"path/filepath"
+	// regexp checks that a path holds only plain characters.
+	"regexp"
+	// runtime tells which operating system the program runs on.
+	"runtime"
+	// strings trims and replaces text.
+	"strings"
+) // end of imports
+
+// appIcon is the program's icon (a 256 by 256 picture), embedded from web/icon.png; the page header, the browser tab and the desktop icon all use it.
+//
+//go:embed web/icon.png
+var appIcon []byte
+
+// desktopChoiceFileName is the small file that remembers what the person answered ("created" or "declined").
+const desktopChoiceFileName = "desktop-icon.json"
+
+// desktopFileName is the name of the launcher on the desktop.
+const desktopFileName = "OllamaControlCenter.desktop"
+
+// iconFileName is where the icon picture is kept inside the settings folder, so the launcher can point at it.
+const iconFileName = "icon.png"
+
+// safePathPattern lists the only characters allowed in the program's path when a launcher is made; other characters need quoting rules that differ between desktops, so the launcher is refused instead of risking a broken or unsafe command line.
+var safePathPattern = regexp.MustCompile(`^[A-Za-z0-9/._+-]+$`)
+
+// The two ways creating a launcher can be refused.
+var (
+	// errDesktopUnsupported means this system has no desktop the program knows how to place an icon on.
+	errDesktopUnsupported = errors.New("this system has no desktop folder the program can use")
+	// errUnusualPath means the program's own path holds characters the launcher cannot carry safely.
+	errUnusualPath = errors.New("the path of the program holds characters that cannot be used in a launcher")
+) // end of errors
+
+// desktopEnv holds everything the program asks the operating system; a test replaces it.
+type desktopEnv struct {
+	// goos is the operating system name (linux, windows, darwin).
+	goos string
+	// getenv reads an environment variable.
+	getenv func(string) string
+	// homeDir finds the person's home folder.
+	homeDir func() (string, error)
+	// exePath finds the running program's own file.
+	exePath func() (string, error)
+	// trust runs the best-effort "trust this launcher" step on a file (it may do nothing).
+	trust func(path string)
+} // end of desktopEnv
+
+// realDesktopEnv is the environment of the running program.
+func realDesktopEnv() desktopEnv {
+	// The real functions.
+	return desktopEnv{goos: runtime.GOOS, getenv: os.Getenv, homeDir: os.UserHomeDir, exePath: os.Executable, trust: gioTrust}
+} // end of realDesktopEnv
+
+// noDesktopEnv is an environment with no desktop at all; tests use it so a test never touches a real desktop.
+func noDesktopEnv() desktopEnv {
+	// Not a system with a desktop.
+	return desktopEnv{goos: "none", getenv: func(string) string { return "" }, homeDir: func() (string, error) { return "", errDesktopUnsupported }, exePath: func() (string, error) { return "", errDesktopUnsupported }, trust: func(string) {}}
+} // end of noDesktopEnv
+
+// gioTrust asks GNOME to trust the launcher (the same as the right-click "Allow Launching"); it is best effort, and a failure or a missing "gio" program changes nothing.
+func gioTrust(path string) {
+	// Look for the program.
+	gio, err := exec.LookPath("gio")
+	// Without it there is nothing to do.
+	if err != nil {
+		// Stop here.
+		return
+	} // end of the lookup check
+	// Run it; the answer is not needed.
+	_ = exec.Command(gio, "set", path, "metadata::trusted", "true").Run()
+} // end of gioTrust
+
+// desktopDir finds the person's desktop folder: the one named in the user's folder list when there is one, else "Desktop" in the home folder; it must exist.
+func (e desktopEnv) desktopDir() (string, bool) {
+	// Only Linux is supported for now.
+	if e.goos != "linux" {
+		// Not supported.
+		return "", false
+	} // end of the system check
+	// A graphical session must exist; a server without a screen has no desktop.
+	if e.getenv("XDG_CURRENT_DESKTOP") == "" && e.getenv("DISPLAY") == "" && e.getenv("WAYLAND_DISPLAY") == "" {
+		// No desktop.
+		return "", false
+	} // end of the session check
+	// The home folder.
+	home, err := e.homeDir()
+	// Without it nothing can be found.
+	if err != nil || home == "" {
+		// Not supported.
+		return "", false
+	} // end of the home check
+	// The default place.
+	dir := filepath.Join(home, "Desktop")
+	// The user's folder list may name another place.
+	if f, err := os.Open(filepath.Join(home, ".config", "user-dirs.dirs")); err == nil {
+		// Close it at the end.
+		defer f.Close()
+		// Read at most 64 KiB.
+		raw, _ := io.ReadAll(io.LimitReader(f, 64*1024))
+		// Look at each line.
+		for _, line := range strings.Split(string(raw), "\n") {
+			// The line that names the desktop folder.
+			if rest, ok := strings.CutPrefix(strings.TrimSpace(line), "XDG_DESKTOP_DIR="); ok {
+				// Remove the quotes and put the home folder in.
+				rest = strings.ReplaceAll(strings.Trim(rest, `"`), "$HOME", home)
+				// Only an absolute path is used.
+				if filepath.IsAbs(rest) {
+					// Use it.
+					dir = filepath.Clean(rest)
+				} // end of the absolute check
+			} // end of the prefix check
+		} // end of the line loop
+	} // end of the list check
+	// The folder must exist.
+	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
+		// Not supported.
+		return "", false
+	} // end of the folder check
+	// Found.
+	return dir, true
+} // end of desktopDir
+
+// desktopFileText builds the launcher file; exe and icon are plain paths (checked before), and Terminal=false means no window opens.
+func desktopFileText(exe, icon string) string {
+	// The lines of a Desktop Entry file, as a freedesktop launcher needs them.
+	return "[Desktop Entry]\n" +
+		// The kind of entry.
+		"Type=Application\n" +
+		// The version of the specification the file follows.
+		"Version=1.0\n" +
+		// The name shown under the icon.
+		"Name=OllamaControlCenter\n" +
+		// The tooltip.
+		"Comment=Monitor and control Ollama\n" +
+		// The command: the program with the -launch option, which starts the monitor if needed and opens the page.
+		"Exec=" + exe + " -launch\n" +
+		// The picture.
+		"Icon=" + icon + "\n" +
+		// No terminal window.
+		"Terminal=false\n" +
+		// A menu category.
+		"Categories=Utility;\n" +
+		// No busy cursor while it starts.
+		"StartupNotify=false\n"
+} // end of desktopFileText
+
+// desktopIcon manages the launcher on the desktop and remembers the person's answer.
+type desktopIcon struct {
+	// env is the operating system as seen by the program.
+	env desktopEnv
+	// dir is the settings folder (empty means no folder: nothing can be kept).
+	dir string
+} // end of desktopIcon
+
+// available says whether this system can have a launcher (a desktop exists and the settings folder is known).
+func (d desktopIcon) available() bool {
+	// Without a settings folder the icon picture cannot be kept.
+	if d.dir == "" {
+		// Not available.
+		return false
+	} // end of the folder check
+	// A desktop folder must exist.
+	_, ok := d.env.desktopDir()
+	// The answer.
+	return ok
+} // end of available
+
+// desktopPath is the full path of the launcher file on the desktop ("" when there is no desktop).
+func (d desktopIcon) desktopPath() string {
+	// The desktop folder.
+	dir, ok := d.env.desktopDir()
+	// None.
+	if !ok {
+		// No path.
+		return ""
+	} // end of the desktop check
+	// The launcher's path.
+	return filepath.Join(dir, desktopFileName)
+} // end of desktopPath
+
+// exists says whether the launcher is on the desktop now.
+func (d desktopIcon) exists() bool {
+	// Its path.
+	p := d.desktopPath()
+	// No desktop, no launcher.
+	if p == "" {
+		// Not there.
+		return false
+	} // end of the path check
+	// A plain file check.
+	_, err := os.Stat(p)
+	// There when the check worked.
+	return err == nil
+} // end of exists
+
+// choice returns what the person answered before: "created", "declined" or "" (not asked yet).
+func (d desktopIcon) choice() string {
+	// No folder, no answer.
+	if d.dir == "" {
+		// Not asked.
+		return ""
+	} // end of the folder check
+	// Open the file.
+	f, err := os.Open(filepath.Join(d.dir, desktopChoiceFileName))
+	// A missing file means not asked yet.
+	if err != nil {
+		// Not asked.
+		return ""
+	} // end of the open check
+	// Close it at the end.
+	defer f.Close()
+	// The content: one word.
+	var c struct {
+		// Choice is the word.
+		Choice string `json:"choice"`
+	} // end of the content shape
+	// Read at most 1 KiB.
+	if err := json.NewDecoder(io.LimitReader(f, 1024)).Decode(&c); err != nil {
+		// A damaged file counts as not asked.
+		return ""
+	} // end of the decode check
+	// Only the two known words count.
+	if c.Choice == "created" || c.Choice == "declined" {
+		// A known word.
+		return c.Choice
+	} // end of the word check
+	// Not asked.
+	return ""
+} // end of choice
+
+// remember writes the person's answer.
+func (d desktopIcon) remember(word string) error {
+	// Nowhere to write.
+	if d.dir == "" {
+		// Nothing to keep; not an error the person can fix.
+		return nil
+	} // end of the folder check
+	// Encode the word.
+	data, err := json.Marshal(map[string]string{"choice": word})
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the encode check
+	// Write it the safe way (a private file).
+	return writeFile(d.dir, desktopChoiceFileName, append(data, '\n'))
+} // end of remember
+
+// decline remembers "no, do not ask again".
+func (d desktopIcon) decline() error {
+	// Keep the answer.
+	return d.remember("declined")
+} // end of decline
+
+// create writes the icon picture next to the settings and the launcher on the desktop, then remembers the answer.
+func (d desktopIcon) create() error {
+	// A desktop must exist.
+	dir, ok := d.env.desktopDir()
+	// Refuse without one.
+	if !ok || d.dir == "" {
+		// Not supported.
+		return errDesktopUnsupported
+	} // end of the support check
+	// The program's own file.
+	exe, err := d.env.exePath()
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the program check
+	// The path as the system sees it.
+	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
+		// Use the real file.
+		exe = resolved
+	} // end of the link check
+	// Only plain characters are allowed.
+	if !safePathPattern.MatchString(exe) {
+		// Refuse.
+		return errUnusualPath
+	} // end of the path check
+	// Where the picture goes.
+	icon := filepath.Join(d.dir, iconFileName)
+	// The picture's path must be plain too.
+	if !safePathPattern.MatchString(icon) {
+		// Refuse.
+		return errUnusualPath
+	} // end of the icon path check
+	// Write the picture.
+	if err := writeFile(d.dir, iconFileName, appIcon); err != nil {
+		// Report it.
+		return err
+	} // end of the picture check
+	// The launcher's path.
+	target := filepath.Join(dir, desktopFileName)
+	// Write it the safe way; the file is then made executable, as desktops require for a launcher.
+	if err := writeFile(dir, desktopFileName, []byte(desktopFileText(exe, icon))); err != nil {
+		// Report it.
+		return err
+	} // end of the launcher check
+	// A launcher needs the executable bit to start from the desktop.
+	if err := os.Chmod(target, 0o755); err != nil {
+		// Report it.
+		return err
+	} // end of the chmod check
+	// Ask the desktop to trust it (best effort).
+	d.env.trust(target)
+	// Remember the answer.
+	return d.remember("created")
+} // end of create
+
+// remove deletes the launcher and the picture, and remembers "declined" so the question does not return by itself.
+func (d desktopIcon) remove() error {
+	// The launcher.
+	if p := d.desktopPath(); p != "" {
+		// Delete it; a missing file is fine.
+		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
+			// Report it.
+			return err
+		} // end of the delete check
+	} // end of the launcher case
+	// The picture.
+	if d.dir != "" {
+		// Delete it; a missing file is fine.
+		if err := os.Remove(filepath.Join(d.dir, iconFileName)); err != nil && !os.IsNotExist(err) {
+			// Report it.
+			return err
+		} // end of the delete check
+	} // end of the picture case
+	// Keep the answer.
+	return d.remember("declined")
+} // end of remove
+
+// iconResultWords turns a result into the fixed word used in the address of the Settings page (so no free text is ever echoed); okWord is the word for success.
+func iconResultWords(okWord string, err error) string {
+	// Success.
+	if err == nil {
+		// The word.
+		return okWord
+	} // end of the success case
+	// The two known refusals.
+	if errors.Is(err, errDesktopUnsupported) {
+		// The word.
+		return "unsupported"
+	} // end of the unsupported case
+	// The path case.
+	if errors.Is(err, errUnusualPath) {
+		// The word.
+		return "unusualpath"
+	} // end of the path case
+	// Anything else.
+	return "failed"
+} // end of iconResultWords
+
+// desktopHandler answers the three buttons: create, decline and remove (the page token and the same-origin check protect it like every other button).
+func desktopHandler(token string, d desktopIcon) http.HandlerFunc {
+	// The handler.
+	return func(w http.ResponseWriter, r *http.Request) {
+		// A form is small.
+		r.Body = http.MaxBytesReader(w, r.Body, 1024)
+		// It must come from this page.
+		if !sameOrigin(r) {
+			// Refuse.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the origin check
+		// Read the form.
+		if err := r.ParseForm(); err != nil {
+			// Refuse.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return
+		} // end of the form check
+		// The token must match.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the token check
+		// Which button.
+		switch r.PostFormValue("action") {
+		// Create the launcher.
+		case "create":
+			// Do it and show the result on the Settings page.
+			http.Redirect(w, r, "/settings?icon="+iconResultWords("created", d.create()), http.StatusSeeOther)
+		// Do not ask again.
+		case "decline":
+			// Keep the answer, then go back to the monitor.
+			_ = d.decline()
+			// The monitor page.
+			http.Redirect(w, r, "/", http.StatusSeeOther)
+		// Remove the launcher.
+		case "remove":
+			// Do it and show the result on the Settings page.
+			http.Redirect(w, r, "/settings?icon="+iconResultWords("removed", d.remove()), http.StatusSeeOther)
+		// Anything else.
+		default:
+			// Refuse.
+			http.Error(w, "unknown action", http.StatusBadRequest)
+		} // end of the action switch
+	} // end of the handler
+} // end of desktopHandler
diff --git a/desktopicon_test.go b/desktopicon_test.go
new file mode 100644
index 0000000..e3c8fdf
--- /dev/null
+++ b/desktopicon_test.go
@@ -0,0 +1,450 @@
+// Package main tells Go that this test file belongs to the same program as desktopicon.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// bytes compares the picture.
+	"bytes"
+	// errors checks the refusals.
+	"errors"
+	// net/http provides status codes.
+	"net/http"
+	// net/url builds the forms.
+	"net/url"
+	// os looks at the files.
+	"os"
+	// path/filepath joins file names.
+	"path/filepath"
+	// regexp finds the page token.
+	"regexp"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time provides durations.
+	"time"
+) // end of imports
+
+// fakeDesktop is a pretend Linux desktop in a temporary folder.
+type fakeDesktop struct {
+	// env is the environment the code sees.
+	env desktopEnv
+	// home is the pretend home folder.
+	home string
+	// desk is the pretend desktop folder.
+	desk string
+	// exe is the pretend program file.
+	exe string
+	// trusted records the files the trust step was asked about.
+	trusted *[]string
+} // end of fakeDesktop
+
+// newFakeDesktop builds the pretend desktop with a Desktop folder and a program file.
+func newFakeDesktop(t *testing.T) fakeDesktop {
+	// Mark this as a helper.
+	t.Helper()
+	// The pretend home.
+	home := t.TempDir()
+	// Its desktop folder.
+	desk := filepath.Join(home, "Desktop")
+	// Make it.
+	if err := os.MkdirAll(desk, 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the folder check
+	// The pretend program.
+	exe := filepath.Join(home, "OllamaControlCenter", "bin", "OllamaControlCenter")
+	// Its folder.
+	if err := os.MkdirAll(filepath.Dir(exe), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the program folder check
+	// The file.
+	if err := os.WriteFile(exe, []byte("x"), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the file check
+	// The trust record.
+	trusted := &[]string{}
+	// The environment: Linux with a GNOME session.
+	env := desktopEnv{goos: "linux", getenv: func(k string) string {
+		// Only the desktop name is set.
+		if k == "XDG_CURRENT_DESKTOP" {
+			// A GNOME desktop.
+			return "ubuntu:GNOME"
+		} // end of the name check
+		// Nothing else.
+		return ""
+	}, homeDir: func() (string, error) { return home, nil }, exePath: func() (string, error) { return exe, nil }, trust: func(p string) { *trusted = append(*trusted, p) }}
+	// Hand back the pieces.
+	return fakeDesktop{env: env, home: home, desk: desk, exe: exe, trusted: trusted}
+} // end of newFakeDesktop
+
+// TestDesktopDirDetection checks where a desktop is found and where not.
+func TestDesktopDirDetection(t *testing.T) {
+	// A normal desktop.
+	f := newFakeDesktop(t)
+	// Found.
+	if dir, ok := f.env.desktopDir(); !ok || dir != f.desk {
+		// Report it.
+		t.Errorf("desktopDir = %q, %v", dir, ok)
+	} // end of the found check
+	// Windows is not supported yet.
+	w := f.env
+	// The system name.
+	w.goos = "windows"
+	// Not found.
+	if _, ok := w.desktopDir(); ok {
+		// Report it.
+		t.Errorf("windows reported a desktop")
+	} // end of the windows check
+	// A server without a screen has no desktop.
+	s := f.env
+	// No session variables.
+	s.getenv = func(string) string { return "" }
+	// Not found.
+	if _, ok := s.desktopDir(); ok {
+		// Report it.
+		t.Errorf("a session-less system reported a desktop")
+	} // end of the session check
+	// A missing folder.
+	if err := os.Remove(f.desk); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the remove check
+	// Not found.
+	if _, ok := f.env.desktopDir(); ok {
+		// Report it.
+		t.Errorf("a missing Desktop folder was reported")
+	} // end of the folder check
+	// The user's folder list names another place.
+	other := filepath.Join(f.home, "Schreibtisch")
+	// Make it.
+	if err := os.MkdirAll(other, 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the make check
+	// Write the list.
+	if err := os.MkdirAll(filepath.Join(f.home, ".config"), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the config folder check
+	// The file.
+	if err := os.WriteFile(filepath.Join(f.home, ".config", "user-dirs.dirs"), []byte("XDG_DOCUMENTS_DIR=\"$HOME/Documents\"\nXDG_DESKTOP_DIR=\"$HOME/Schreibtisch\"\n"), 0o644); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the list check
+	// Found in the named place.
+	if dir, ok := f.env.desktopDir(); !ok || dir != other {
+		// Report it.
+		t.Errorf("desktopDir with a folder list = %q, %v", dir, ok)
+	} // end of the list result check
+} // end of TestDesktopDirDetection
+
+// TestDesktopFileText checks the launcher text.
+func TestDesktopFileText(t *testing.T) {
+	// Build it.
+	got := desktopFileText("/opt/occ/OllamaControlCenter", "/home/u/.config/OllamaControlCenter/icon.png")
+	// The lines it must hold.
+	for _, w := range []string{"[Desktop Entry]\n", "Type=Application\n", "Name=OllamaControlCenter\n", "Exec=/opt/occ/OllamaControlCenter -launch\n", "Icon=/home/u/.config/OllamaControlCenter/icon.png\n", "Terminal=false\n"} {
+		// Look for it.
+		if !strings.Contains(got, w) {
+			// Report it.
+			t.Errorf("launcher text lacks %q", w)
+		} // end of the check
+	} // end of the loop
+} // end of TestDesktopFileText
+
+// TestDesktopCreateAndRemove checks the whole life of the launcher.
+func TestDesktopCreateAndRemove(t *testing.T) {
+	// The pretend desktop and a settings folder.
+	f := newFakeDesktop(t)
+	// The settings folder.
+	set := filepath.Join(f.home, ".config", "OllamaControlCenter")
+	// The manager.
+	d := desktopIcon{env: f.env, dir: set}
+	// It is available and nothing was answered yet.
+	if !d.available() || d.choice() != "" || d.exists() {
+		// Report it.
+		t.Fatalf("start state: available %v choice %q exists %v", d.available(), d.choice(), d.exists())
+	} // end of the start check
+	// Create it.
+	if err := d.create(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the create check
+	// The launcher is there, executable, and says what it should.
+	path := filepath.Join(f.desk, desktopFileName)
+	// Read it.
+	raw, err := os.ReadFile(path)
+	// It must exist.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the read check
+	// The command and the picture.
+	if !strings.Contains(string(raw), "Exec="+f.exe+" -launch\n") || !strings.Contains(string(raw), "Icon="+filepath.Join(set, iconFileName)+"\n") {
+		// Report it.
+		t.Errorf("launcher content wrong:\n%s", raw)
+	} // end of the content check
+	// The executable bit.
+	if info, err := os.Stat(path); err != nil || info.Mode().Perm()&0o100 == 0 {
+		// Report it.
+		t.Errorf("launcher is not executable: %v %v", info, err)
+	} // end of the mode check
+	// The picture is the embedded one.
+	if pic, err := os.ReadFile(filepath.Join(set, iconFileName)); err != nil || !bytes.Equal(pic, appIcon) {
+		// Report it.
+		t.Errorf("icon file wrong: %v", err)
+	} // end of the picture check
+	// The trust step ran for the launcher.
+	if len(*f.trusted) != 1 || (*f.trusted)[0] != path {
+		// Report it.
+		t.Errorf("trust calls %v", *f.trusted)
+	} // end of the trust check
+	// The answer is remembered, and the launcher exists.
+	if d.choice() != "created" || !d.exists() {
+		// Report it.
+		t.Errorf("after create: choice %q exists %v", d.choice(), d.exists())
+	} // end of the state check
+	// Remove it.
+	if err := d.remove(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the remove check
+	// Both files are gone and the answer is "declined", so the question does not come back by itself.
+	if d.exists() || d.choice() != "declined" {
+		// Report it.
+		t.Errorf("after remove: exists %v choice %q", d.exists(), d.choice())
+	} // end of the removed check
+	// The picture is gone too.
+	if _, err := os.Stat(filepath.Join(set, iconFileName)); !os.IsNotExist(err) {
+		// Report it.
+		t.Errorf("icon file stayed: %v", err)
+	} // end of the picture check
+	// Removing again is not an error.
+	if err := d.remove(); err != nil {
+		// Report it.
+		t.Errorf("second remove: %v", err)
+	} // end of the second remove check
+} // end of TestDesktopCreateAndRemove
+
+// TestDesktopCreateRefusals checks the two refusals.
+func TestDesktopCreateRefusals(t *testing.T) {
+	// A pretend desktop whose program path holds a space.
+	f := newFakeDesktop(t)
+	// The settings folder.
+	set := filepath.Join(f.home, ".config", "OllamaControlCenter")
+	// The spaced path.
+	spaced := filepath.Join(f.home, "my programs")
+	// Make it.
+	if err := os.MkdirAll(spaced, 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the folder check
+	// The file.
+	if err := os.WriteFile(filepath.Join(spaced, "occ"), []byte("x"), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the file check
+	// The environment with the spaced path.
+	env := f.env
+	// The path.
+	env.exePath = func() (string, error) { return filepath.Join(spaced, "occ"), nil }
+	// Refused, and nothing is written.
+	d := desktopIcon{env: env, dir: set}
+	// The result.
+	if err := d.create(); !errors.Is(err, errUnusualPath) {
+		// Report it.
+		t.Errorf("spaced path: %v", err)
+	} // end of the path check
+	// Nothing on the desktop.
+	if d.exists() {
+		// Report it.
+		t.Errorf("a launcher was written for an unusual path")
+	} // end of the nothing check
+	// No desktop at all.
+	n := desktopIcon{env: noDesktopEnv(), dir: set}
+	// Refused.
+	if err := n.create(); !errors.Is(err, errDesktopUnsupported) {
+		// Report it.
+		t.Errorf("no desktop: %v", err)
+	} // end of the support check
+	// No settings folder: not available.
+	if (desktopIcon{env: f.env, dir: ""}).available() {
+		// Report it.
+		t.Errorf("available without a settings folder")
+	} // end of the folder check
+} // end of TestDesktopCreateRefusals
+
+// desktopRig is a web handler wired to a pretend desktop.
+type desktopRig struct {
+	// h is the handler.
+	h http.Handler
+	// f is the pretend desktop.
+	f fakeDesktop
+	// token is the page token.
+	token string
+	// mon is the monitor.
+	mon *monitor
+} // end of desktopRig
+
+// newDesktopRig builds the rig.
+func newDesktopRig(t *testing.T) *desktopRig {
+	// Mark this as a helper.
+	t.Helper()
+	// The pretend desktop.
+	f := newFakeDesktop(t)
+	// The settings folder inside it.
+	set := filepath.Join(f.home, ".config", "OllamaControlCenter")
+	// The monitor with a store there.
+	mon := newMonitorWith(openSettingsStore(set, ""))
+	// The pretend desktop.
+	mon.denv = f.env
+	// The default address.
+	addr, err := resolve("", "")
+	// A bad address means the test is wrong.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the address check
+	// The handler.
+	h := newWebHandlerWith(addr, time.Second, mon)
+	// The token comes from the Settings page.
+	_, _, body := get(t, h, http.MethodGet, "/settings")
+	// Find it.
+	m := regexp.MustCompile(`name="token" value="([0-9a-f]+)"`).FindStringSubmatch(body)
+	// It must exist.
+	if m == nil {
+		// Stop.
+		t.Fatal("no token on the settings page")
+	} // end of the token check
+	// Hand back the rig.
+	return &desktopRig{h: h, f: f, token: m[1], mon: mon}
+} // end of newDesktopRig
+
+// TestDesktopBannerAndButtons checks the first-run question, the answers and the Settings section.
+func TestDesktopBannerAndButtons(t *testing.T) {
+	// The rig.
+	r := newDesktopRig(t)
+	// The main page asks.
+	_, _, page := get(t, r.h, http.MethodGet, "/")
+	// The words of the banner.
+	for _, w := range []string{"Create a desktop icon for OllamaControlCenter?", "Yes, create it", "No, don't ask again", r.f.desk, r.f.exe, "Allow Launching", `action="/desktopicon"`, `<link rel="icon"`, `class="appicon"`} {
+		// Look for it.
+		if !strings.Contains(page, w) {
+			// Report it.
+			t.Errorf("the main page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// A button without the token is refused.
+	if res := post(t, r.h, "/desktopicon", url.Values{"action": {"create"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("no token: status %d", res.StatusCode)
+	} // end of the token check
+	// A foreign origin is refused.
+	if res := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"create"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("cross-site: status %d", res.StatusCode)
+	} // end of the origin check
+	// Nothing was created by the refused requests.
+	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); !os.IsNotExist(err) {
+		// Report it.
+		t.Errorf("a refused request created the launcher: %v", err)
+	} // end of the nothing check
+	// "Yes, create it".
+	res := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"create"}}, fromThisPage)
+	// It goes to the Settings page with the fixed word.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/settings?icon=created" {
+		// Report it.
+		t.Fatalf("create: status %d location %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the create check
+	// The launcher is there.
+	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); err != nil {
+		// Report it.
+		t.Errorf("launcher not created: %v", err)
+	} // end of the launcher check
+	// The banner is gone from the main page.
+	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for OllamaControlCenter?") {
+		// Report it.
+		t.Errorf("the banner stayed after the answer")
+	} // end of the banner check
+	// The Settings page shows the state, the note and the Remove button.
+	_, _, set := get(t, r.h, http.MethodGet, "/settings?icon=created")
+	// The words.
+	for _, w := range []string{"Desktop icon created. On Ubuntu", "The icon is on your desktop", "Remove desktop icon", "Create the icon again"} {
+		// Look for it.
+		if !strings.Contains(set, w) {
+			// Report it.
+			t.Errorf("the settings page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// Remove it.
+	res = post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"remove"}}, fromThisPage)
+	// The result word.
+	if res.Header.Get("Location") != "/settings?icon=removed" {
+		// Report it.
+		t.Errorf("remove location %q", res.Header.Get("Location"))
+	} // end of the remove check
+	// Gone, and the banner does not return by itself.
+	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); !os.IsNotExist(err) {
+		// Report it.
+		t.Errorf("launcher stayed: %v", err)
+	} // end of the gone check
+	// The banner stays away.
+	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for OllamaControlCenter?") {
+		// Report it.
+		t.Errorf("the banner came back after a removal")
+	} // end of the stay-away check
+	// An unknown note key shows nothing and echoes nothing.
+	if _, _, p := get(t, r.h, http.MethodGet, "/settings?icon=<script>"); strings.Contains(p, "<script>") {
+		// Report it.
+		t.Errorf("the icon key was echoed")
+	} // end of the echo check
+} // end of TestDesktopBannerAndButtons
+
+// TestDesktopDeclineAndNoDesktop checks "No, don't ask again" and that systems without a desktop see nothing.
+func TestDesktopDeclineAndNoDesktop(t *testing.T) {
+	// The rig.
+	r := newDesktopRig(t)
+	// "No, don't ask again".
+	res := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"decline"}}, fromThisPage)
+	// Back to the monitor.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
+		// Report it.
+		t.Errorf("decline: status %d location %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the decline check
+	// No launcher and no banner.
+	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); !os.IsNotExist(err) {
+		// Report it.
+		t.Errorf("decline created the launcher: %v", err)
+	} // end of the launcher check
+	// The banner is gone, and a new run (a new store) still remembers.
+	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for OllamaControlCenter?") {
+		// Report it.
+		t.Errorf("the banner stayed after No")
+	} // end of the banner check
+	// The Settings page still offers to create it.
+	if _, _, p := get(t, r.h, http.MethodGet, "/settings"); !strings.Contains(p, "Create desktop icon") {
+		// Report it.
+		t.Errorf("the settings page does not offer the icon after No")
+	} // end of the offer check
+	// A system without a desktop shows neither the banner nor the section.
+	plain := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
+	// Its main page.
+	if _, _, p := get(t, plain.h, http.MethodGet, "/"); strings.Contains(p, "desktop icon") {
+		// Report it.
+		t.Errorf("a system without a desktop shows the banner")
+	} // end of the main page check
+	// Its Settings page.
+	if _, _, p := get(t, plain.h, http.MethodGet, "/settings"); strings.Contains(p, "Desktop icon") {
+		// Report it.
+		t.Errorf("a system without a desktop shows the icon section")
+	} // end of the settings check
+	// The icon picture is served as a PNG.
+	code, hdr, body := get(t, r.h, http.MethodGet, "/icon.png")
+	// The checks.
+	if code != http.StatusOK || hdr.Get("Content-Type") != "image/png" || !strings.HasPrefix(body, "\x89PNG") {
+		// Report it.
+		t.Errorf("icon route: %d %q", code, hdr.Get("Content-Type"))
+	} // end of the icon check
+} // end of TestDesktopDeclineAndNoDesktop
diff --git a/launch.go b/launch.go
new file mode 100644
index 0000000..a4b496a
--- /dev/null
+++ b/launch.go
@@ -0,0 +1,183 @@
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the packages this file uses.
+	// fmt builds the plain error messages.
+	"fmt"
+	// net/http asks the monitor whether it already answers.
+	"net/http"
+	// os reads the program's own arguments and opens the log file.
+	"os"
+	// os/exec starts the monitor and the browser.
+	"os/exec"
+	// path/filepath joins the log file's path.
+	"path/filepath"
+	// runtime tells which operating system the program runs on.
+	"runtime"
+	// time provides the waiting times.
+	"time"
+) // end of imports
+
+// maxLogFile is the size at which the monitor's log file is started again (1 MiB).
+const maxLogFile = 1 << 20
+
+// launcher holds the three actions of "-launch"; a test replaces them.
+type launcher struct {
+	// probe says whether the monitor already answers at the address.
+	probe func(url string) bool
+	// start starts the monitor in the background.
+	start func() error
+	// open opens the page in the browser.
+	open func(url string) error
+	// wait is how long to wait for a freshly started monitor.
+	wait time.Duration
+	// poll is the time between two looks.
+	poll time.Duration
+} // end of launcher
+
+// run does what a double-click on the desktop icon does: open the page, starting the monitor first when it is not running.
+func (l launcher) run(url string) error {
+	// Already running: only open the page.
+	if l.probe(url) {
+		// Open it.
+		return l.open(url)
+	} // end of the running case
+	// Start the monitor.
+	if err := l.start(); err != nil {
+		// Report it.
+		return fmt.Errorf("the monitor could not be started: %w", err)
+	} // end of the start check
+	// The moment to give up.
+	deadline := time.Now().Add(l.wait)
+	// Look until it answers or the time is over.
+	for time.Now().Before(deadline) {
+		// It answers.
+		if l.probe(url) {
+			// Open the page.
+			return l.open(url)
+		} // end of the answer check
+		// Wait a little.
+		time.Sleep(l.poll)
+	} // end of the waiting loop
+	// It did not answer in time.
+	return fmt.Errorf("the monitor did not answer within %v; see the log file", l.wait)
+} // end of run
+
+// httpProbe asks the page once; any answer with status 200 means the monitor runs.
+func httpProbe(url string) bool {
+	// A short time limit.
+	c := &http.Client{Timeout: 2 * time.Second}
+	// Ask.
+	res, err := c.Get(url)
+	// No answer.
+	if err != nil {
+		// Not running.
+		return false
+	} // end of the error check
+	// Close the body at the end.
+	defer res.Body.Close()
+	// Running when the page answers.
+	return res.StatusCode == http.StatusOK
+} // end of httpProbe
+
+// openBrowser opens the address in the person's default browser, with the command each system provides.
+func openBrowser(url string) error {
+	// The command for this system.
+	switch runtime.GOOS {
+	// Windows.
+	case "windows":
+		// The documented way to open an address.
+		return exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
+	// macOS.
+	case "darwin":
+		// The "open" command.
+		return exec.Command("open", url).Start()
+	// Linux and the others.
+	default:
+		// The freedesktop command.
+		return exec.Command("xdg-open", url).Start()
+	} // end of the system switch
+} // end of openBrowser
+
+// childArgs are this program's own arguments without -launch, so the background copy runs as a normal monitor with the same options.
+func childArgs(args []string) []string {
+	// The result.
+	var out []string
+	// Walk the arguments.
+	for _, a := range args {
+		// Drop the launch switch in its two spellings.
+		if a == "-launch" || a == "--launch" {
+			// Skip it.
+			continue
+		} // end of the switch check
+		// Keep the rest.
+		out = append(out, a)
+	} // end of the loop
+	// Hand them back.
+	return out
+} // end of childArgs
+
+// startMonitor starts a copy of this program in the background, without a window, with its messages written to a log file in the settings folder.
+func startMonitor(logDir string) error {
+	// The program's own file.
+	exe, err := os.Executable()
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the program check
+	// The log file; without a folder the messages are dropped.
+	sink := os.DevNull
+	// With a folder, a real file.
+	if logDir != "" {
+		// Make the folder, private to the owner.
+		if err := os.MkdirAll(logDir, 0o700); err != nil {
+			// Report it.
+			return err
+		} // end of the folder check
+		// The file.
+		sink = filepath.Join(logDir, "OllamaControlCenter.log")
+		// A file that grew too big is started again.
+		if info, err := os.Stat(sink); err == nil && info.Size() > maxLogFile {
+			// Remove it.
+			_ = os.Remove(sink)
+		} // end of the size check
+	} // end of the log case
+	// Open it for appending, private to the owner.
+	f, err := os.OpenFile(sink, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the open check
+	// The log file belongs to the child now; this copy lets go of it at the end.
+	defer f.Close()
+	// The command: this program again, without -launch.
+	cmd := exec.Command(exe, childArgs(os.Args[1:])...)
+	// Its messages go to the log.
+	cmd.Stdout, cmd.Stderr = f, f
+	// Detach it from this process, so closing the launcher does not stop the monitor (the way depends on the system).
+	detach(cmd)
+	// Start it, without waiting.
+	if err := cmd.Start(); err != nil {
+		// Report it.
+		return err
+	} // end of the start check
+	// Let go of it.
+	return cmd.Process.Release()
+} // end of startMonitor
+
+// runLaunch is the -launch option: returns the exit code (0 = the page was opened).
+func runLaunch(url, logDir string) int {
+	// The real actions.
+	l := launcher{probe: httpProbe, start: func() error { return startMonitor(logDir) }, open: openBrowser, wait: 15 * time.Second, poll: 300 * time.Millisecond}
+	// Do it.
+	if err := l.run(url); err != nil {
+		// Tell the terminal (a double-click has none, but a person who ran it by hand sees it).
+		fmt.Fprintln(os.Stderr, "launch:", err)
+		// Failure.
+		return 1
+	} // end of the error check
+	// Success.
+	return 0
+} // end of runLaunch
diff --git a/launch_test.go b/launch_test.go
new file mode 100644
index 0000000..06dff37
--- /dev/null
+++ b/launch_test.go
@@ -0,0 +1,132 @@
+// Package main tells Go that this test file belongs to the same program as launch.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// errors builds the pretend failures.
+	"errors"
+	// net/http provides the status codes and the handler type.
+	"net/http"
+	// httptest provides the pretend server.
+	"net/http/httptest"
+	// reflect compares the argument lists.
+	"reflect"
+	// strings searches the messages.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time provides durations.
+	"time"
+) // end of imports
+
+// TestLauncherRunning checks that a running monitor is not started again: the page is just opened.
+func TestLauncherRunning(t *testing.T) {
+	// The record of what happened.
+	var started, opened int
+	// A launcher whose monitor already answers.
+	l := launcher{probe: func(string) bool { return true }, start: func() error { started++; return nil }, open: func(string) error { opened++; return nil }, wait: time.Second, poll: time.Millisecond}
+	// Run it.
+	if err := l.run("http://127.0.0.1:8765/"); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the run check
+	// Only the page was opened.
+	if started != 0 || opened != 1 {
+		// Report it.
+		t.Errorf("started %d opened %d", started, opened)
+	} // end of the count check
+} // end of TestLauncherRunning
+
+// TestLauncherStarts checks that a monitor that is not running is started, waited for, and then the page is opened.
+func TestLauncherStarts(t *testing.T) {
+	// The record.
+	var started, opened, probes int
+	// A launcher whose monitor answers on the third look.
+	l := launcher{probe: func(string) bool { probes++; return started > 0 && probes >= 3 }, start: func() error { started++; return nil }, open: func(string) error { opened++; return nil }, wait: 2 * time.Second, poll: time.Millisecond}
+	// Run it.
+	if err := l.run("http://127.0.0.1:8765/"); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the run check
+	// Started once, opened once.
+	if started != 1 || opened != 1 {
+		// Report it.
+		t.Errorf("started %d opened %d", started, opened)
+	} // end of the count check
+} // end of TestLauncherStarts
+
+// TestLauncherFailures checks the two failure paths: the start fails, or the monitor never answers.
+func TestLauncherFailures(t *testing.T) {
+	// The record.
+	opened := 0
+	// The start fails.
+	l := launcher{probe: func(string) bool { return false }, start: func() error { return errors.New("boom") }, open: func(string) error { opened++; return nil }, wait: 50 * time.Millisecond, poll: time.Millisecond}
+	// The error says what happened.
+	if err := l.run("u"); err == nil || !strings.Contains(err.Error(), "could not be started") {
+		// Report it.
+		t.Errorf("start failure: %v", err)
+	} // end of the start check
+	// The monitor never answers.
+	l.start = func() error { return nil }
+	// The error says so.
+	if err := l.run("u"); err == nil || !strings.Contains(err.Error(), "did not answer") {
+		// Report it.
+		t.Errorf("timeout: %v", err)
+	} // end of the timeout check
+	// The page was never opened.
+	if opened != 0 {
+		// Report it.
+		t.Errorf("the page was opened %d times after a failure", opened)
+	} // end of the open check
+} // end of TestLauncherFailures
+
+// TestHttpProbe checks the probe against a pretend monitor.
+func TestHttpProbe(t *testing.T) {
+	// A server that answers 200.
+	ok := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
+	// Stop it at the end.
+	defer ok.Close()
+	// It is running.
+	if !httpProbe(ok.URL + "/") {
+		// Report it.
+		t.Errorf("a running server was not seen")
+	} // end of the running check
+	// A server that answers 500 is not a healthy monitor.
+	bad := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(500) }))
+	// Stop it at the end.
+	defer bad.Close()
+	// Not running.
+	if httpProbe(bad.URL + "/") {
+		// Report it.
+		t.Errorf("a failing server counted as running")
+	} // end of the failing check
+	// A closed server.
+	url := ok.URL + "/"
+	// Close it.
+	ok.Close()
+	// Not running.
+	if httpProbe(url) {
+		// Report it.
+		t.Errorf("a closed server counted as running")
+	} // end of the closed check
+} // end of TestHttpProbe
+
+// TestChildArgsAndLaunchURL checks the argument filter and the address builder.
+func TestChildArgsAndLaunchURL(t *testing.T) {
+	// The filter drops only the launch switch.
+	got := childArgs([]string{"-launch", "-ollama-url", "http://x:1", "--launch", "-listen", "127.0.0.1:9"})
+	// What must remain.
+	want := []string{"-ollama-url", "http://x:1", "-listen", "127.0.0.1:9"}
+	// Compare.
+	if !reflect.DeepEqual(got, want) {
+		// Report it.
+		t.Errorf("childArgs = %v", got)
+	} // end of the compare
+	// The address a browser on this computer opens, for every kind of listen address.
+	for in, out := range map[string]string{"127.0.0.1:8765": "http://127.0.0.1:8765/", "0.0.0.0:8765": "http://127.0.0.1:8765/", "[::1]:9000": "http://127.0.0.1:9000/"} {
+		// Compare.
+		if got := launchURL(in); got != out {
+			// Report it.
+			t.Errorf("launchURL(%q) = %q want %q", in, got, out)
+		} // end of the compare
+	} // end of the loop
+} // end of TestChildArgsAndLaunchURL
diff --git a/launch_unix.go b/launch_unix.go
new file mode 100644
index 0000000..549bf4e
--- /dev/null
+++ b/launch_unix.go
@@ -0,0 +1,17 @@
+//go:build !windows
+
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the packages this file uses.
+	// os/exec holds the command that is detached.
+	"os/exec"
+	// syscall holds the process settings of Linux and macOS.
+	"syscall"
+) // end of imports
+
+// detach makes the command a session of its own, so it keeps running when the launcher ends.
+func detach(cmd *exec.Cmd) {
+	// A new session.
+	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
+} // end of detach
diff --git a/launch_windows.go b/launch_windows.go
new file mode 100644
index 0000000..76c1903
--- /dev/null
+++ b/launch_windows.go
@@ -0,0 +1,17 @@
+//go:build windows
+
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the packages this file uses.
+	// os/exec holds the command that is detached.
+	"os/exec"
+	// syscall holds the process settings of Windows.
+	"syscall"
+) // end of imports
+
+// detach makes the command a new process group without a window, so it keeps running when the launcher ends (not yet tried on Windows).
+func detach(cmd *exec.Cmd) {
+	// A new group (0x200) and no window (0x08000000).
+	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: 0x00000200 | 0x08000000}
+} // end of detach
diff --git a/main.go b/main.go
index 75a5a19..f9706dd 100644
--- a/main.go
+++ b/main.go
@@ -16,6 +16,8 @@ import ( // import lists the standard-library packages this file uses.
 	"net/http"
 	// os reads environment variables and ends the program with an exit code.
 	"os"
+	// strings cuts the port out of the listen address.
+	"strings"
 	// time provides durations such as the request-header timeout.
 	"time"
 ) // end of imports
@@ -58,6 +60,14 @@ func chooseListen(flagValue string, flagGiven, allowOthers bool) (string, string
 	return defaultListen, sourceDefault
 } // end of chooseListen
 
+// launchURL turns a listen address (host:port) into the address a browser on this computer opens.
+func launchURL(listen string) string {
+	// The port is the part after the last colon.
+	port := listen[strings.LastIndex(listen, ":")+1:]
+	// Always this computer.
+	return "http://127.0.0.1:" + port + "/"
+} // end of launchURL
+
 // formatCheck turns one check result into the single status line the -check option prints.
 func formatCheck(res checkResult) string {
 	// A successful check says ONLINE, the version and the time taken.
@@ -103,6 +113,8 @@ func main() {
 	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
 	// Define an -ollama-url option; empty means "not given", so the environment variable or the default is used.
 	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the OCC_OLLAMA_URL environment variable (default http://127.0.0.1:11434)")
+	// Define a -launch switch: what a double-click on the desktop icon runs; it opens the page and starts the monitor first when it is not running.
+	launchFlag := flag.Bool("launch", false, "open the monitor page in the browser, starting the monitor in the background first when it is not running (this is what the desktop icon runs)")
 	// Define a -check switch: false unless given on the command line.
 	checkFlag := flag.Bool("check", false, "check Ollama once, print one status line, and exit (0 = online, 1 = offline)")
 	// Define a -models switch: false unless given on the command line.
@@ -115,7 +127,7 @@ func main() {
 	// The one-shot modes cannot be combined; ask the person to choose one.
 	modes := 0
 	// Count the modes that were given.
-	for _, on := range []bool{*checkFlag, *modelsFlag, *linksFlag} {
+	for _, on := range []bool{*checkFlag, *modelsFlag, *linksFlag, *launchFlag} {
 		// One more mode.
 		if on {
 			// Count it.
@@ -125,7 +137,7 @@ func main() {
 	// More than one is not allowed.
 	if modes > 1 {
 		// log.Fatal prints the message and exits with code 1.
-		log.Fatal("use only one of -check, -models and -check-links")
+		log.Fatal("use only one of -check, -models, -check-links and -launch")
 	} // end of the combination check
 
 	// In -check-links mode, no Ollama is needed: open the reference addresses, print the result and leave.
@@ -178,7 +190,16 @@ func main() {
 	// Describe the web server: Addr is where to listen (the star reads the flag's value), Handler is the web interface from web.go wrapped in the Host-name check from guard.go,
 	// and ReadHeaderTimeout drops clients that take more than 5 seconds to send their request headers.
 	// The monitor holds the counters and the history of checks; it asks Ollama in the background every sampleEvery, so the charts have no gaps while the page is closed.
+	// In -launch mode, open the page (starting the monitor first when needed) and leave.
+	if *launchFlag {
+		// The address the page is served on, by the same precedence as below.
+		la, _ := chooseListen(*listen, listenGiven(), store.get().AllowOthers)
+		// Run it and leave with its exit code.
+		os.Exit(runLaunch(launchURL(la), store.dir))
+	} // end of the launch mode
 	mon := newMonitorWith(store)
+	// The real desktop, so the first-run banner and the Settings buttons can place the icon.
+	mon.denv = realDesktopEnv()
 	// The listen address: the -listen option if it was given, else "other machines allowed" from the settings, else this computer only.
 	listenAddr, listenSource := chooseListen(*listen, listenGiven(), store.get().AllowOthers)
 	// Tell the Settings page how the program was started.
diff --git a/monitor.go b/monitor.go
index 5e0cf34..9fd71af 100644
--- a/monitor.go
+++ b/monitor.go
@@ -161,6 +161,8 @@ type monitor struct {
 	background atomic.Bool
 	// store holds the saved settings (interval, timeout, history length, history file).
 	store *settingsStore
+	// denv is the operating system as seen by the desktop icon code; main sets the real one, and it stays "no desktop" in tests.
+	denv desktopEnv
 	// run says how the program was started (listen address and where it came from); main sets it once before serving.
 	run runInfo
 	// unsaved counts the checks since the history file was last written.
@@ -187,7 +189,7 @@ func newMonitor() *monitor {
 // newMonitorWith builds a monitor that reads its settings from the given store.
 func newMonitorWith(store *settingsStore) *monitor {
 	// Empty counters and an empty history, and the settings.
-	return &monitor{health: &apiHealth{}, hist: &sampleHistory{}, store: store}
+	return &monitor{health: &apiHealth{}, hist: &sampleHistory{}, store: store, denv: noDesktopEnv()}
 } // end of newMonitorWith
 
 // timeoutOr is how long one status check waits: the saved value, or def.
diff --git a/settingspage.go b/settingspage.go
index d432e9b..aa15d6d 100644
--- a/settingspage.go
+++ b/settingspage.go
@@ -71,8 +71,30 @@ type settingsPage struct {
 	Note string
 	// Folder is the folder of the files (empty when none was found).
 	Folder string
+	// IconAvailable is true when this system can have a desktop icon; the section is hidden otherwise.
+	IconAvailable bool
+	// IconExists is true when the launcher is on the desktop now.
+	IconExists bool
+	// IconPath is the launcher's full path.
+	IconPath string
+	// IconNote is the plain sentence about what just happened (empty when nothing did).
+	IconNote string
 } // end of settingsPage
 
+// iconNotes are the sentences shown after a desktop icon button; the address carries only the key, so no free text is ever echoed.
+var iconNotes = map[string]string{
+	// Created.
+	"created": "Desktop icon created. On Ubuntu you may have to right-click it once and choose Allow Launching.",
+	// Removed.
+	"removed": "Desktop icon removed.",
+	// No desktop.
+	"unsupported": "This system has no desktop folder the program can use, so no icon was made.",
+	// A path with unusual characters.
+	"unusualpath": "The path of the program holds characters that cannot be used in a launcher (use letters, digits and . _ + - / only), so no icon was made. Move the program to a plainer folder and try again.",
+	// Anything else.
+	"failed": "The desktop icon could not be created or removed. Check that the folders are writable.",
+} // end of iconNotes
+
 // yesNo writes a flag as the words used in the form.
 func yesNo(on bool) string {
 	// Yes.
@@ -226,7 +248,13 @@ func settingsHandlers(addr ollamaAddress, mon *monitor, token string) (http.Hand
 		// The lines and the restart flag.
 		rows, restart := buildSettingsRows(cfg, addr, mon.run, typed)
 		// Everything the template needs.
-		data := settingsPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder}
+		desk := desktopIcon{env: mon.denv, dir: mon.store.dir}
+		// The icon section's facts.
+		iconAvail, iconExists, iconPath := desk.available(), desk.exists(), desk.desktopPath()
+		// The note after a button; unknown keys show nothing.
+		iconNote := iconNotes[r.URL.Query().Get("icon")]
+		// Everything the template needs.
+		data := settingsPage{IconAvailable: iconAvail, IconExists: iconExists, IconPath: iconPath, IconNote: iconNote, Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder}
 		// Build the page in memory first, so a template error gives a clean 500.
 		var buf bytes.Buffer
 		// Fill the template.
diff --git a/web.go b/web.go
index 563d703..9d3c47a 100644
--- a/web.go
+++ b/web.go
@@ -87,6 +87,10 @@ type pageData struct {
 	NumbersOpen bool
 	// DetailsClosed is true when the person folded the monitoring details (API health and Event log) away; a cookie remembers it.
 	DetailsClosed bool
+	// DesktopBanner is true when the first-run question about a desktop icon is shown.
+	DesktopBanner bool
+	// DesktopDir and DesktopExe are the folder and the program the question names.
+	DesktopDir, DesktopExe string
 	// DetailsTip is the help bubble of the twistie "Monitoring details".
 	DetailsTip tipView
 	// KeyOpen is true when the person opened the key to the symbols (the address then ends in ?key=open); the page does not update by itself meanwhile.
@@ -144,6 +148,17 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	mux.HandleFunc("POST /theme", themeHandler(token))
 	// Route: a POST request for "/textsize" saves the chosen text size in a cookie (the checks are in size.go).
 	mux.HandleFunc("POST /textsize", sizeHandler(token))
+	// The desktop icon: the launcher, and the answer to the first-run question.
+	desktop := desktopIcon{env: mon.denv, dir: mon.store.dir}
+	// Route: a POST request for "/desktopicon" creates or removes the launcher, or records "no".
+	mux.HandleFunc("POST /desktopicon", desktopHandler(token, desktop))
+	// Route: a GET request for "/icon.png" sends the program's icon (the page header, the browser tab and the desktop icon use it).
+	mux.HandleFunc("GET /icon.png", func(w http.ResponseWriter, r *http.Request) {
+		// Tell the browser this is a PNG image.
+		w.Header().Set("Content-Type", "image/png")
+		// Send it.
+		w.Write(appIcon)
+	}) // end of the icon route
 	// Route: a GET request for "/about" shows the read-only About page (see about.go).
 	mux.HandleFunc("GET /about", aboutHandler())
 	// Make the two Settings handlers: the first shows the page, the second saves the form (see settingspage.go).
@@ -306,6 +321,15 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 			// When this page was made.
 			UpdatedAt: time.Now().Format("15:04:05 MST"),
 		} // end of the data
+		// The first-run question: only where a desktop exists and the person has not answered yet.
+		if desktop.available() && desktop.choice() == "" {
+			// Show it, naming the folder and the program.
+			data.DesktopBanner = true
+			// The folder.
+			data.DesktopDir, _ = desktop.env.desktopDir()
+			// The program.
+			data.DesktopExe, _ = desktop.env.exePath()
+		} // end of the banner check
 		// The lists that the event log compares; they stay empty when Ollama cannot be read.
 		var evInstalled []installedModel
 		// The loaded models, the same way.
diff --git a/web/app.css b/web/app.css
index b769b61..95dcb2a 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2321,3 +2321,37 @@ html[data-size="medium"] svg[width="22"] {
     overflow-wrap: anywhere;
   } /* end of rule */
 } /* end of media rule */
+
+/* The program's icon beside the main heading. */
+.brandrow {
+  /* Icon and heading side by side. */
+  display: flex;
+  /* Level with each other. */
+  align-items: center;
+  /* Space between them. */
+  gap: 0.7rem;
+} /* end of rule */
+
+/* The heading inside the icon row needs no extra space above it. */
+.brandrow h1 {
+  /* Keep the row compact. */
+  margin: 0;
+} /* end of rule */
+
+/* The icon picture. */
+.appicon {
+  /* A little rounding matches the picture's own corners. */
+  border-radius: 10px;
+  /* Never stretched. */
+  flex: none;
+} /* end of rule */
+
+/* The question of the desktop icon: the picture and the words level with each other. */
+.iconquestion {
+  /* Side by side. */
+  display: flex;
+  /* Level with each other. */
+  align-items: center;
+  /* Space between them. */
+  gap: 0.7rem;
+} /* end of rule */
diff --git a/web/icon.png b/web/icon.png
new file mode 100644
index 0000000000000000000000000000000000000000..619b55047223a9625ffa370d5945728ff50502a7
GIT binary patch
literal 8267
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
K@?Oa@{Qm&t9tWTR

literal 0
HcmV?d00001

diff --git a/web/index.html b/web/index.html
index 4cc393f..660247a 100644
--- a/web/index.html
+++ b/web/index.html
@@ -13,17 +13,43 @@
 <title>OllamaControlCenter</title>
 {{/* Load our own stylesheet; the safety policy allows only styles from this same address. */}}
 <link rel="stylesheet" href="/app.css">
+{{/* The program's icon on the browser tab. */}}
+<link rel="icon" type="image/png" href="/icon.png">
 {{/* While the page is being watched it reloads itself; Pause removes this line. It needs no script. */}}
 {{/* No automatic update while the key is open, so it does not vanish while it is being read. */}}
 {{if and (not .Paused) (not .KeyOpen) (not .NumbersOpen)}}<meta http-equiv="refresh" content="{{.RefreshSeconds}}">{{end}}
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
+{{/* The first-run question: only on a system with a desktop, and only until the person has answered. */}}
+{{if .DesktopBanner}}
+<section class="panel" role="region" aria-label="Desktop icon">
+{{/* The question. */}}
+<p class="iconquestion"><img class="appicon" src="/icon.png" width="40" height="40" alt=""> <strong>Create a desktop icon for OllamaControlCenter?</strong></p>
+{{/* What it does and where it goes. */}}
+<p class="muted">One click on it starts the monitor (if it is not running) and opens this page in your browser. It is created in <code>{{.DesktopDir}}</code> and points to <code>{{.DesktopExe}}</code>. On Ubuntu you may have to right-click the icon once and choose <strong>Allow Launching</strong>. You can remove it later on the Settings page.</p>
+{{/* The two answers: one small form with the page token. */}}
+<form method="post" action="/desktopicon">
+{{/* The page token proves the form comes from this page. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The buttons. */}}
+<p><button type="submit" name="action" value="create" class="btn-plain">Yes, create it</button> <button type="submit" name="action" value="decline" class="btn-plain">No, don't ask again</button></p>
+{{/* End of the form. */}}
+</form>
+{{/* End of the question box. */}}
+</section>
+{{end}}
 {{/* The page header. */}}
 <header class="headrow">
 {{/* The title block on the left. */}}
 <div>
+{{/* The icon and the main heading, side by side. */}}
+<div class="brandrow">
+{{/* The program's icon; it is decoration, so its text alternative is empty. */}}
+<img class="appicon" src="/icon.png" width="44" height="44" alt="">
 {{/* The main heading. */}}
 <h1>OllamaControlCenter</h1>
+{{/* End of the icon and heading. */}}
+</div>
 {{/* A quiet line under the title: who is behind the program, with a link that opens in a new window. */}}
 <p class="brandline">by <a href="{{.HeaderURL}}" target="_blank" rel="noopener noreferrer">{{.CompanyName}}<span class="sr-only"> (opens in a new window)</span></a> &middot; {{.CompanyAILine}}</p>
 {{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}
diff --git a/web/settings.html b/web/settings.html
index 9450757..3d1d920 100644
--- a/web/settings.html
+++ b/web/settings.html
@@ -67,6 +67,23 @@
 <p><button type="submit" name="action" value="save" class="btn-plain">Save settings</button> <button type="submit" name="action" value="defaults" class="btn-plain">Back to defaults</button> <a class="btn-plain" href="/settings">Cancel</a></p>
 {{/* End of the form. */}}
 </form>
+{{/* The desktop icon: only on a system that has a desktop. It has its own small form, so it never mixes with the settings form above. */}}
+{{if or .IconAvailable .IconNote}}
+<h2>Desktop icon</h2>
+{{/* What happened after a button. */}}
+{{if .IconNote}}<p class="muted" role="status">{{.IconNote}}</p>{{end}}
+{{/* The state and the buttons. */}}
+{{if .IconAvailable}}
+<p class="muted">{{if .IconExists}}The icon is on your desktop: <code>{{.IconPath}}</code>.{{else}}There is no icon on your desktop now.{{end}} One click on it starts the monitor (if it is not running) and opens the page in your browser. If you move the program, create the icon again.</p>
+<form method="post" action="/desktopicon">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The buttons. */}}
+<p><button type="submit" name="action" value="create" class="btn-plain">{{if .IconExists}}Create the icon again{{else}}Create desktop icon{{end}}</button>{{if .IconExists}} <button type="submit" name="action" value="remove" class="btn-plain">Remove desktop icon</button>{{end}}</p>
+{{/* End of the form. */}}
+</form>
+{{end}}
+{{end}}
 {{/* A plain way back besides the arrow: the same button as on the other pages. */}}
 <p><a class="btn-plain" href="/">Back to the monitor</a></p>
 {{/* End of the box. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
f325c9c5d627bc43f5578c3aae994956a26980e97dd781018f71cae01a9eb49a  desktopicon.go
fc1b2afbd7de41f6284f173e364fc6a3a82f72456064b2003379cf72db782971  desktopicon_test.go
f388c386615e9c84b4b050a02225232da22bfc5022ed114616a8f4d8fca3678d  launch.go
6016e684441dd008508fd6437bf28350d9ca39bb1449f9bf88a4aedb06006c3c  launch_test.go
bb871cbf4dcd94a792685770b973ecdf0ba04ea80b2805da29032f91ce2bb53c  launch_unix.go
622fd454912965467eae4b4f88385946e095fa364583d5cb6bd125498a71ee42  launch_windows.go
64d2f12b3c49cc0a3a232bc9b5f3bed802c7016b897a07b9bfd51a059d8f109e  web/icon.png
9c7154e3dd24fdf94b7165c64b96857bb1b7b93c50abab7ff9d428388e9dfe8d  main.go
7e0cc8a81df4a4160221c5aa11e294ed6c0257d116ec340cd2ac8c75d2afdb54  monitor.go
08e2bda02ea045b63f4056d06fc208cee0bd90233633ab55951e6548bd91a5c9  web.go
cd62196fb64b8b5d13909bd8b3fa0cd5b8ca01e0398049707cee899cbaa05fb9  settingspage.go
a087c689a9d7ae9bece7d07ddb13a83015c0e2a1ec4b920ab3e97a87d975e767  web/settings.html
e775c39c8b3246b6ef248e4ea64f9aa0f23e0c87a66e20c2415ba0dc909c4180  web/index.html
21ad0d6cbbcfb1e291480d6fb529389b0df415050ec096e850bcb1550035e05a  web/app.css
a7070812fa5ab09df0ceac87d911a8d190f8fd1318be2044d407caf2f0ee9341  about.go
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
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
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
# Tell the person how to use the new command.
echo "NEXT  start ./bin/OllamaControlCenter, open http://127.0.0.1:8765/ and look for the question Create a desktop icon for OllamaControlCenter?"
# List the changed files; nothing is committed yet.
git status --short
