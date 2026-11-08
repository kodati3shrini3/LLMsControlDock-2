// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the packages this file uses.
	// embed lets the icon picture travel inside the program.
	_ "embed"
	// encoding/json reads and writes the small file that remembers the person's answer.
	"encoding/json"
	// errors builds the plain error values below.
	"errors"
	// io limits how much of a file is read.
	"io"
	// net/http provides the request handler.
	"net/http"
	// os reads files, checks folders and sets file rights.
	"os"
	// os/exec runs the best-effort "trust this launcher" command.
	"os/exec"
	// path/filepath joins folder and file names for any operating system.
	"path/filepath"
	// regexp checks that a path holds only plain characters.
	"regexp"
	// runtime tells which operating system the program runs on.
	"runtime"
	// strings trims and replaces text.
	"strings"
) // end of imports

// appIcon is the program's icon (a 256 by 256 picture), embedded from web/icon.png; the page header, the browser tab and the desktop icon all use it.
//
//go:embed web/icon.png
var appIcon []byte

// desktopChoiceFileName is the small file that remembers what the person answered ("created" or "declined").
const desktopChoiceFileName = "desktop-icon.json"

// desktopFileName is the name of the launcher on the desktop.
const desktopFileName = "LLMsControlDock.desktop"

// iconFileName is where the icon picture is kept inside the settings folder, so the launcher can point at it.
const iconFileName = "icon.png"

// safePathPattern lists the only characters allowed in the program's path when a launcher is made; other characters need quoting rules that differ between desktops, so the launcher is refused instead of risking a broken or unsafe command line.
var safePathPattern = regexp.MustCompile(`^[A-Za-z0-9/._+-]+$`)

// The two ways creating a launcher can be refused.
var (
	// errDesktopUnsupported means this system has no desktop the program knows how to place an icon on.
	errDesktopUnsupported = errors.New("this system has no desktop folder the program can use")
	// errUnusualPath means the program's own path holds characters the launcher cannot carry safely.
	errUnusualPath = errors.New("the path of the program holds characters that cannot be used in a launcher")
) // end of errors

// desktopEnv holds everything the program asks the operating system; a test replaces it.
type desktopEnv struct {
	// goos is the operating system name (linux, windows, darwin).
	goos string
	// getenv reads an environment variable.
	getenv func(string) string
	// homeDir finds the person's home folder.
	homeDir func() (string, error)
	// exePath finds the running program's own file.
	exePath func() (string, error)
	// trust runs the best-effort "trust this launcher" step on a file (it may do nothing).
	trust func(path string)
	// knownDesktop asks Windows for the Desktop folder (nil elsewhere).
	knownDesktop func() (string, error)
	// run runs a tool with extra environment variables (used for the Windows shortcut).
	run func(exe string, env []string, args ...string) error
} // end of desktopEnv

// realDesktopEnv is the environment of the running program.
func realDesktopEnv() desktopEnv {
	// The real functions.
	return desktopEnv{goos: runtime.GOOS, getenv: os.Getenv, homeDir: os.UserHomeDir, exePath: os.Executable, trust: gioTrust, knownDesktop: osKnownDesktop, run: realToolRun}
} // end of realDesktopEnv

// noDesktopEnv is an environment with no desktop at all; tests use it so a test never touches a real desktop.
func noDesktopEnv() desktopEnv {
	// Not a system with a desktop.
	return desktopEnv{goos: "none", getenv: func(string) string { return "" }, homeDir: func() (string, error) { return "", errDesktopUnsupported }, exePath: func() (string, error) { return "", errDesktopUnsupported }, trust: func(string) {}}
} // end of noDesktopEnv

// gioTrust asks GNOME to trust the launcher (the same as the right-click "Allow Launching"); it is best effort, and a failure or a missing "gio" program changes nothing.
func gioTrust(path string) {
	// Look for the program.
	gio, err := exec.LookPath("gio")
	// Without it there is nothing to do.
	if err != nil {
		// Stop here.
		return
	} // end of the lookup check
	// Run it; the answer is not needed.
	_ = exec.Command(gio, "set", path, "metadata::trusted", "true").Run()
} // end of gioTrust

// desktopDir finds the person's desktop folder on the three supported systems.
func (e desktopEnv) desktopDir() (string, bool) {
	// Each system keeps its desktop in its own way.
	switch e.goos {
	// Linux: the user's folder list or "Desktop" in the home folder.
	case "linux":
		// Look there.
		return e.linuxDesktopDir()
	// Windows: the Known Folder, which follows a Desktop that was moved (for example into OneDrive).
	case "windows":
		// Not available without the lookup.
		if e.knownDesktop == nil {
			// Not supported.
			return "", false
		} // end of the lookup check
		// Ask Windows.
		dir, err := e.knownDesktop()
		// Not found.
		if err != nil || dir == "" {
			// Not supported.
			return "", false
		} // end of the result check
		// Found.
		return dir, true
	// macOS: the Desktop folder in the home folder (macOS always keeps it there).
	case "darwin":
		// The home folder.
		home, err := e.homeDir()
		// Without it nothing can be found.
		if err != nil || home == "" {
			// Not supported.
			return "", false
		} // end of the home check
		// The folder must exist.
		dir := filepath.Join(home, "Desktop")
		// Check it.
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			// Not supported.
			return "", false
		} // end of the folder check
		// Found.
		return dir, true
	// Any other system.
	default:
		// Not supported.
		return "", false
	} // end of the system switch
} // end of desktopDir

// linuxDesktopDir finds the Linux desktop folder: the one named in the user's folder list when there is one, else "Desktop" in the home folder; it must exist.
func (e desktopEnv) linuxDesktopDir() (string, bool) {
	// A graphical session must exist; a server without a screen has no desktop.
	if e.getenv("XDG_CURRENT_DESKTOP") == "" && e.getenv("DISPLAY") == "" && e.getenv("WAYLAND_DISPLAY") == "" {
		// No desktop.
		return "", false
	} // end of the session check
	// The home folder.
	home, err := e.homeDir()
	// Without it nothing can be found.
	if err != nil || home == "" {
		// Not supported.
		return "", false
	} // end of the home check
	// The default place.
	dir := filepath.Join(home, "Desktop")
	// The user's folder list may name another place.
	if f, err := os.Open(filepath.Join(home, ".config", "user-dirs.dirs")); err == nil {
		// Close it at the end.
		defer f.Close()
		// Read at most 64 KiB.
		raw, _ := io.ReadAll(io.LimitReader(f, 64*1024))
		// Look at each line.
		for _, line := range strings.Split(string(raw), "\n") {
			// The line that names the desktop folder.
			if rest, ok := strings.CutPrefix(strings.TrimSpace(line), "XDG_DESKTOP_DIR="); ok {
				// Remove the quotes and put the home folder in.
				rest = strings.ReplaceAll(strings.Trim(rest, `"`), "$HOME", home)
				// Only an absolute path is used.
				if filepath.IsAbs(rest) {
					// Use it.
					dir = filepath.Clean(rest)
				} // end of the absolute check
			} // end of the prefix check
		} // end of the line loop
	} // end of the list check
	// The folder must exist.
	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
		// Not supported.
		return "", false
	} // end of the folder check
	// Found.
	return dir, true
} // end of linuxDesktopDir

// desktopFileText builds the launcher file; exe and icon are plain paths (checked before), and Terminal=false means no window opens.
func desktopFileText(exe, icon string) string {
	// The lines of a Desktop Entry file, as a freedesktop launcher needs them.
	return "[Desktop Entry]\n" +
		// The kind of entry.
		"Type=Application\n" +
		// The version of the specification the file follows.
		"Version=1.0\n" +
		// The name shown under the icon.
		"Name=LLMsControlDock\n" +
		// The tooltip.
		"Comment=Monitor and control Ollama\n" +
		// The command: the program with the -launch option, which starts the monitor if needed and opens the page.
		"Exec=" + exe + " -launch\n" +
		// The picture.
		"Icon=" + icon + "\n" +
		// No terminal window.
		"Terminal=false\n" +
		// A menu category.
		"Categories=Utility;\n" +
		// No busy cursor while it starts.
		"StartupNotify=false\n"
} // end of desktopFileText

// desktopIcon manages the launcher on the desktop and remembers the person's answer.
type desktopIcon struct {
	// env is the operating system as seen by the program.
	env desktopEnv
	// dir is the settings folder (empty means no folder: nothing can be kept); the person's answer is kept there.
	dir string
	// dataDir is the data folder, where the icon picture is kept; empty means the same folder as dir.
	dataDir string
} // end of desktopIcon

// iconDir returns the folder of the icon picture: the data folder when one is set, else the settings folder.
func (d desktopIcon) iconDir() string {
	// A data folder was set.
	if d.dataDir != "" {
		// Use it.
		return d.dataDir
	} // end of the data check
	// Otherwise the settings folder.
	return d.dir
} // end of iconDir

// available says whether this system can have a launcher (a desktop exists and the settings folder is known).
func (d desktopIcon) available() bool {
	// Without a settings folder the icon picture cannot be kept.
	if d.dir == "" {
		// Not available.
		return false
	} // end of the folder check
	// A desktop folder must exist.
	_, ok := d.env.desktopDir()
	// The answer.
	return ok
} // end of available

// desktopPath is the full path of the launcher file on the desktop ("" when there is no desktop).
func (d desktopIcon) desktopPath() string {
	// The desktop folder.
	dir, ok := d.env.desktopDir()
	// None.
	if !ok {
		// No path.
		return ""
	} // end of the desktop check
	// The launcher's path.
	return filepath.Join(dir, launcherName(d.env.goos))
} // end of desktopPath

// exists says whether the launcher is on the desktop now.
func (d desktopIcon) exists() bool {
	// Its path.
	p := d.desktopPath()
	// No desktop, no launcher.
	if p == "" {
		// Not there.
		return false
	} // end of the path check
	// A plain file check.
	_, err := os.Stat(p)
	// There when the check worked.
	return err == nil
} // end of exists

// choice returns what the person answered before: "created", "declined" or "" (not asked yet).
func (d desktopIcon) choice() string {
	// No folder, no answer.
	if d.dir == "" {
		// Not asked.
		return ""
	} // end of the folder check
	// Open the file.
	f, err := os.Open(filepath.Join(d.dir, desktopChoiceFileName))
	// A missing file means not asked yet.
	if err != nil {
		// Not asked.
		return ""
	} // end of the open check
	// Close it at the end.
	defer f.Close()
	// The content: one word.
	var c struct {
		// Choice is the word.
		Choice string `json:"choice"`
	} // end of the content shape
	// Read at most 1 KiB.
	if err := json.NewDecoder(io.LimitReader(f, 1024)).Decode(&c); err != nil {
		// A damaged file counts as not asked.
		return ""
	} // end of the decode check
	// Only the two known words count.
	if c.Choice == "created" || c.Choice == "declined" {
		// A known word.
		return c.Choice
	} // end of the word check
	// Not asked.
	return ""
} // end of choice

// remember writes the person's answer.
func (d desktopIcon) remember(word string) error {
	// Nowhere to write.
	if d.dir == "" {
		// Nothing to keep; not an error the person can fix.
		return nil
	} // end of the folder check
	// Encode the word.
	data, err := json.Marshal(map[string]string{"choice": word})
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the encode check
	// Write it the safe way (a private file).
	return writeFile(d.dir, desktopChoiceFileName, append(data, '\n'))
} // end of remember

// decline remembers "no, do not ask again".
func (d desktopIcon) decline() error {
	// Keep the answer.
	return d.remember("declined")
} // end of decline

// launcherPaths returns the program path and the picture path a launcher should hold now, both checked to be plain; it returns an error when the program's place is unknown or holds unusual characters.
func (d desktopIcon) launcherPaths() (string, string, error) {
	// The program's own file.
	exe, err := d.env.exePath()
	// Report a failure.
	if err != nil {
		// Report it.
		return "", "", err
	} // end of the program check
	// The path as the system sees it.
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		// Use the real file.
		exe = resolved
	} // end of the link check
	// Only plain characters are allowed.
	if !safePathPattern.MatchString(exe) {
		// Refuse.
		return "", "", errUnusualPath
	} // end of the path check
	// Where the picture goes.
	icon := filepath.Join(d.iconDir(), iconFileName)
	// The picture's path must be plain too.
	if !safePathPattern.MatchString(icon) {
		// Refuse.
		return "", "", errUnusualPath
	} // end of the icon path check
	// Both are fine.
	return exe, icon, nil
} // end of launcherPaths

// staleness says whether the launcher on the desktop differs from what the program would write now (for example after an upgrade moved the picture, or after the program was moved); it returns the picture path the launcher holds and the one it should hold. A missing or unreadable launcher is not stale, because there is nothing to refresh.
func (d desktopIcon) staleness() (bool, string, string) {
	// Only the Linux launcher is a text file that can be compared.
	if d.env.goos != "linux" {
		// Not checked.
		return false, "", ""
	} // end of the system check
	// No launcher, nothing to refresh.
	p := d.desktopPath()
	// No desktop.
	if p == "" {
		// Not stale.
		return false, "", ""
	} // end of the path check
	// Open the launcher.
	f, err := os.Open(p)
	// Missing: not stale.
	if err != nil {
		// Not stale.
		return false, "", ""
	} // end of the open check
	// Close it at the end.
	defer f.Close()
	// Read at most 8 KiB; a real launcher is far smaller.
	have, err := io.ReadAll(io.LimitReader(f, 8192))
	// Unreadable: not stale.
	if err != nil {
		// Not stale.
		return false, "", ""
	} // end of the read check
	// What the program would write now.
	exe, icon, err := d.launcherPaths()
	// Without plain paths nothing can be compared.
	if err != nil {
		// Not stale.
		return false, "", ""
	} // end of the paths check
	// The same text: current.
	if string(have) == desktopFileText(exe, icon) {
		// Not stale.
		return false, icon, icon
	} // end of the compare
	// The picture path the launcher holds now.
	old := ""
	// Look at each line.
	for _, line := range strings.Split(string(have), "\n") {
		// The picture line.
		if strings.HasPrefix(line, "Icon=") {
			// Keep the path.
			old = strings.TrimPrefix(line, "Icon=")
		} // end of the picture line
	} // end of the line loop
	// Stale.
	return true, old, icon
} // end of staleness

// create writes the icon picture next to the data and the launcher on the desktop, then remembers the answer; a launcher of the same program under its old name (before version 0.31.0) is removed afterwards, so the desktop never shows two icons.
func (d desktopIcon) create() error {
	// Make the launcher under the current name.
	if err := d.createCurrent(); err != nil {
		// Report the failure; the old launcher, if any, is left alone.
		return err
	} // end of the create check
	// The new launcher is there: remove the old one (best effort; it still starts the program, so a failure is harmless).
	d.removeLegacyLauncher()
	// Done.
	return nil
} // end of create

// createCurrent writes the icon picture and the launcher under the current name, then remembers the answer.
func (d desktopIcon) createCurrent() error {
	// A desktop must exist.
	dir, ok := d.env.desktopDir()
	// Refuse without one.
	if !ok || d.dir == "" {
		// Not supported.
		return errDesktopUnsupported
	} // end of the support check
	// Windows and macOS have their own kinds of launcher.
	switch d.env.goos {
	// A real shortcut.
	case "windows":
		// Make it.
		return d.createWindows(dir)
	// An application bundle.
	case "darwin":
		// Make it.
		return d.createMac(dir)
	} // end of the system switch
	// The paths the launcher should hold.
	exe, icon, err := d.launcherPaths()
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the paths check
	// Write the picture.
	if err := writeFile(d.iconDir(), iconFileName, appIcon); err != nil {
		// Report it.
		return err
	} // end of the picture check
	// The launcher's path.
	target := filepath.Join(dir, desktopFileName)
	// Write it the safe way; the file is then made executable, as desktops require for a launcher.
	if err := writeFile(dir, desktopFileName, []byte(desktopFileText(exe, icon))); err != nil {
		// Report it.
		return err
	} // end of the launcher check
	// A launcher needs the executable bit to start from the desktop.
	if err := os.Chmod(target, 0o755); err != nil {
		// Report it.
		return err
	} // end of the chmod check
	// Ask the desktop to trust it (best effort).
	d.env.trust(target)
	// Remember the answer.
	return d.remember("created")
} // end of createCurrent

// removeFiles deletes the launcher and the picture and remembers nothing (the uninstall uses this, because remembering would re-create the settings folder).
func (d desktopIcon) removeFiles() error {
	// The launcher.
	if p := d.desktopPath(); p != "" {
		// Delete it; a missing one is fine.
		if err := removeLauncher(p); err != nil {
			// Report it.
			return err
		} // end of the delete check
	} // end of the launcher case
	// A launcher left from before the rename goes too.
	d.removeLegacyLauncher()
	// The pictures: the PNG of the Linux launcher and the ICO of the Windows shortcut.
	if d.iconDir() != "" {
		// Both names; a missing file is fine.
		for _, name := range []string{iconFileName, icoFileName} {
			// Delete one.
			if err := os.Remove(filepath.Join(d.iconDir(), name)); err != nil && !os.IsNotExist(err) {
				// Report it.
				return err
			} // end of the delete check
		} // end of the picture loop
	} // end of the picture case
	// Done.
	return nil
} // end of removeFiles

// remove deletes the launcher and the picture, and remembers "declined" so the question does not return by itself.
func (d desktopIcon) remove() error {
	// Delete the files.
	if err := d.removeFiles(); err != nil {
		// Report it.
		return err
	} // end of the delete check
	// Keep the answer.
	return d.remember("declined")
} // end of remove

// iconResultWords turns a result into the fixed word used in the address of the Settings page (so no free text is ever echoed); okWord is the word for success.
func iconResultWords(okWord string, err error) string {
	// Success.
	if err == nil {
		// The word.
		return okWord
	} // end of the success case
	// The two known refusals.
	if errors.Is(err, errDesktopUnsupported) {
		// The word.
		return "unsupported"
	} // end of the unsupported case
	// The path case.
	if errors.Is(err, errUnusualPath) {
		// The word.
		return "unusualpath"
	} // end of the path case
	// Anything else.
	return "failed"
} // end of iconResultWords

// iconFlashCookie holds, for a moment, the result of the icon button pressed on the monitor page; the page shows it once and deletes it.
const iconFlashCookie = "occ_icon"

// desktopHandler answers the three buttons: create, decline and remove (the page token and the same-origin check protect it like every other button).
func desktopHandler(token string, d desktopIcon) http.HandlerFunc {
	// The handler.
	return func(w http.ResponseWriter, r *http.Request) {
		// A form is small.
		r.Body = http.MaxBytesReader(w, r.Body, 1024)
		// It must come from this page.
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return
		} // end of the origin check
		// Read the form.
		if err := r.ParseForm(); err != nil {
			// Refuse.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the form check
		// The token must match.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return
		} // end of the token check
		// Which button.
		switch r.PostFormValue("action") {
		// Create the launcher.
		case "create":
			// Do it.
			word := iconResultWords("created", d.create())
			// From the question on the monitor page: stay on that page and show the result there, once.
			if r.PostFormValue("from") == "home" {
				// A short-lived note, read once by the monitor page.
				http.SetCookie(w, &http.Cookie{Name: iconFlashCookie, Value: word, Path: "/", MaxAge: 120, HttpOnly: true, SameSite: http.SameSiteStrictMode})
				// Back to the monitor page.
				http.Redirect(w, r, "/", http.StatusSeeOther)
				// Stop here.
				return
			} // end of the home case
			// From the Settings page: show the result there.
			http.Redirect(w, r, "/settings?icon="+word, http.StatusSeeOther)
		// Do not ask again.
		case "decline":
			// Keep the answer, then go back to the monitor.
			_ = d.decline()
			// The monitor page.
			http.Redirect(w, r, "/", http.StatusSeeOther)
		// Remove the launcher.
		case "remove":
			// Do it and show the result on the Settings page.
			http.Redirect(w, r, "/settings?icon="+iconResultWords("removed", d.remove()), http.StatusSeeOther)
		// Anything else.
		default:
			// Refuse.
			http.Error(w, "unknown action", http.StatusBadRequest)
		} // end of the action switch
	} // end of the handler
} // end of desktopHandler
