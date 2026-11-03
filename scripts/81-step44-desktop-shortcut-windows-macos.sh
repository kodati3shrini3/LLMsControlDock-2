#!/usr/bin/env bash
# Script 81 (version 0.29.0): the desktop shortcut now also works on Windows (a real .lnk shortcut made through Windows PowerShell) and on macOS (an OllamaControlCenter.app bundle). The first-run question on the monitor page, the Settings "Desktop icon" section and the Uninstall page all cover it.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run on the wrong branch or before the earlier steps (script 80 family) are in.
[ -e syscheck.go ] && grep -q uninstallWord syscheck.go && [ "$(git branch --show-current)" != "main" ] || { echo "FAIL  run this on a new feature branch (not main), after PR #31 is merged"; exit 1; }
# Refuse to run twice.
if [ -e launchers.go ]; then
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
index cfe683b..4395f61 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.28.0"
+const appVersion = "0.29.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/desktop_other.go b/desktop_other.go
new file mode 100644
index 0000000..5e5bb64
--- /dev/null
+++ b/desktop_other.go
@@ -0,0 +1,15 @@
+//go:build !windows
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// errors builds fixed error messages.
+	"errors"
+) // end of imports
+
+// osKnownDesktop reports that the Windows Known Folders do not exist on this system.
+func osKnownDesktop() (string, error) {
+	// A fixed message.
+	return "", errors.New("Known Folders exist on Windows only")
+} // end of osKnownDesktop
diff --git a/desktop_windows.go b/desktop_windows.go
new file mode 100644
index 0000000..74bcb38
--- /dev/null
+++ b/desktop_windows.go
@@ -0,0 +1,71 @@
+//go:build windows
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// errors builds fixed error messages.
+	"errors"
+	// os checks that the folder exists.
+	"os"
+	// syscall loads the Windows libraries and holds the GUID type.
+	"syscall"
+	// unsafe reads the text Windows hands back; this is one of the two places that use it.
+	"unsafe"
+) // end of imports
+
+// The Windows library calls used to find the Desktop folder (documented by Microsoft: SHGetKnownFolderPath returns the path of a Known Folder, and CoTaskMemFree frees the text it allocated).
+var (
+	// shell32 holds SHGetKnownFolderPath.
+	shell32 = syscall.NewLazyDLL("shell32.dll")
+	// ole32 holds CoTaskMemFree.
+	ole32 = syscall.NewLazyDLL("ole32.dll")
+	// procSHGetKnownFolderPath finds a Known Folder.
+	procSHGetKnownFolderPath = shell32.NewProc("SHGetKnownFolderPath")
+	// procCoTaskMemFree frees the text.
+	procCoTaskMemFree = ole32.NewProc("CoTaskMemFree")
+) // end of the library calls
+
+// folderIDDesktop is the Known Folder ID of the Desktop, {B4BFCC3A-DB2C-424C-B029-7FE99A87C641}; it follows the person's Desktop even when Windows moved it (for example into OneDrive).
+var folderIDDesktop = syscall.GUID{Data1: 0xB4BFCC3A, Data2: 0xDB2C, Data3: 0x424C, Data4: [8]byte{0xB0, 0x29, 0x7F, 0xE9, 0x9A, 0x87, 0xC6, 0x41}}
+
+// osKnownDesktop asks Windows for the Desktop folder of the person who runs the program.
+func osKnownDesktop() (string, error) {
+	// Windows fills in a pointer to text that it allocated.
+	var p *uint16
+	// The call: the folder ID, no flags, the current person (no token), and where to put the pointer.
+	r, _, _ := procSHGetKnownFolderPath.Call(uintptr(unsafe.Pointer(&folderIDDesktop)), 0, 0, uintptr(unsafe.Pointer(&p)))
+	// The text must be freed, whatever the result.
+	if p != nil {
+		// Free it at the end.
+		defer procCoTaskMemFree.Call(uintptr(unsafe.Pointer(p)))
+	} // end of the free check
+	// A non-zero result is a failure.
+	if r != 0 || p == nil {
+		// A fixed message.
+		return "", errors.New("Windows did not report the Desktop folder")
+	} // end of the result check
+	// Read the text up to its end (at most 32,768 characters, the longest path Windows allows).
+	var chars []uint16
+	// Walk along it.
+	for i := 0; i < 32768; i++ {
+		// The next character.
+		c := *(*uint16)(unsafe.Add(unsafe.Pointer(p), i*2))
+		// The end.
+		if c == 0 {
+			// Stop.
+			break
+		} // end of the end check
+		// Keep it.
+		chars = append(chars, c)
+	} // end of the walk
+	// Make a Go string.
+	dir := syscall.UTF16ToString(chars)
+	// It must be a folder that exists.
+	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
+		// A fixed message.
+		return "", errors.New("the Desktop folder does not exist")
+	} // end of the folder check
+	// Found.
+	return dir, nil
+} // end of osKnownDesktop
diff --git a/desktopicon.go b/desktopicon.go
index 194a829..f35db73 100644
--- a/desktopicon.go
+++ b/desktopicon.go
@@ -63,12 +63,16 @@ type desktopEnv struct {
 	exePath func() (string, error)
 	// trust runs the best-effort "trust this launcher" step on a file (it may do nothing).
 	trust func(path string)
+	// knownDesktop asks Windows for the Desktop folder (nil elsewhere).
+	knownDesktop func() (string, error)
+	// run runs a tool with extra environment variables (used for the Windows shortcut).
+	run func(exe string, env []string, args ...string) error
 } // end of desktopEnv
 
 // realDesktopEnv is the environment of the running program.
 func realDesktopEnv() desktopEnv {
 	// The real functions.
-	return desktopEnv{goos: runtime.GOOS, getenv: os.Getenv, homeDir: os.UserHomeDir, exePath: os.Executable, trust: gioTrust}
+	return desktopEnv{goos: runtime.GOOS, getenv: os.Getenv, homeDir: os.UserHomeDir, exePath: os.Executable, trust: gioTrust, knownDesktop: osKnownDesktop, run: realToolRun}
 } // end of realDesktopEnv
 
 // noDesktopEnv is an environment with no desktop at all; tests use it so a test never touches a real desktop.
@@ -90,13 +94,57 @@ func gioTrust(path string) {
 	_ = exec.Command(gio, "set", path, "metadata::trusted", "true").Run()
 } // end of gioTrust
 
-// desktopDir finds the person's desktop folder: the one named in the user's folder list when there is one, else "Desktop" in the home folder; it must exist.
+// desktopDir finds the person's desktop folder on the three supported systems.
 func (e desktopEnv) desktopDir() (string, bool) {
-	// Only Linux is supported for now.
-	if e.goos != "linux" {
+	// Each system keeps its desktop in its own way.
+	switch e.goos {
+	// Linux: the user's folder list or "Desktop" in the home folder.
+	case "linux":
+		// Look there.
+		return e.linuxDesktopDir()
+	// Windows: the Known Folder, which follows a Desktop that was moved (for example into OneDrive).
+	case "windows":
+		// Not available without the lookup.
+		if e.knownDesktop == nil {
+			// Not supported.
+			return "", false
+		} // end of the lookup check
+		// Ask Windows.
+		dir, err := e.knownDesktop()
+		// Not found.
+		if err != nil || dir == "" {
+			// Not supported.
+			return "", false
+		} // end of the result check
+		// Found.
+		return dir, true
+	// macOS: the Desktop folder in the home folder (macOS always keeps it there).
+	case "darwin":
+		// The home folder.
+		home, err := e.homeDir()
+		// Without it nothing can be found.
+		if err != nil || home == "" {
+			// Not supported.
+			return "", false
+		} // end of the home check
+		// The folder must exist.
+		dir := filepath.Join(home, "Desktop")
+		// Check it.
+		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
+			// Not supported.
+			return "", false
+		} // end of the folder check
+		// Found.
+		return dir, true
+	// Any other system.
+	default:
 		// Not supported.
 		return "", false
-	} // end of the system check
+	} // end of the system switch
+} // end of desktopDir
+
+// linuxDesktopDir finds the Linux desktop folder: the one named in the user's folder list when there is one, else "Desktop" in the home folder; it must exist.
+func (e desktopEnv) linuxDesktopDir() (string, bool) {
 	// A graphical session must exist; a server without a screen has no desktop.
 	if e.getenv("XDG_CURRENT_DESKTOP") == "" && e.getenv("DISPLAY") == "" && e.getenv("WAYLAND_DISPLAY") == "" {
 		// No desktop.
@@ -138,7 +186,7 @@ func (e desktopEnv) desktopDir() (string, bool) {
 	} // end of the folder check
 	// Found.
 	return dir, true
-} // end of desktopDir
+} // end of linuxDesktopDir
 
 // desktopFileText builds the launcher file; exe and icon are plain paths (checked before), and Terminal=false means no window opens.
 func desktopFileText(exe, icon string) string {
@@ -208,7 +256,7 @@ func (d desktopIcon) desktopPath() string {
 		return ""
 	} // end of the desktop check
 	// The launcher's path.
-	return filepath.Join(dir, desktopFileName)
+	return filepath.Join(dir, launcherName(d.env.goos))
 } // end of desktopPath
 
 // exists says whether the launcher is on the desktop now.
@@ -317,6 +365,11 @@ func (d desktopIcon) launcherPaths() (string, string, error) {
 
 // staleness says whether the launcher on the desktop differs from what the program would write now (for example after an upgrade moved the picture, or after the program was moved); it returns the picture path the launcher holds and the one it should hold. A missing or unreadable launcher is not stale, because there is nothing to refresh.
 func (d desktopIcon) staleness() (bool, string, string) {
+	// Only the Linux launcher is a text file that can be compared.
+	if d.env.goos != "linux" {
+		// Not checked.
+		return false, "", ""
+	} // end of the system check
 	// No launcher, nothing to refresh.
 	p := d.desktopPath()
 	// No desktop.
@@ -375,6 +428,17 @@ func (d desktopIcon) create() error {
 		// Not supported.
 		return errDesktopUnsupported
 	} // end of the support check
+	// Windows and macOS have their own kinds of launcher.
+	switch d.env.goos {
+	// A real shortcut.
+	case "windows":
+		// Make it.
+		return d.createWindows(dir)
+	// An application bundle.
+	case "darwin":
+		// Make it.
+		return d.createMac(dir)
+	} // end of the system switch
 	// The paths the launcher should hold.
 	exe, icon, err := d.launcherPaths()
 	// Report a failure.
@@ -409,19 +473,22 @@ func (d desktopIcon) create() error {
 func (d desktopIcon) removeFiles() error {
 	// The launcher.
 	if p := d.desktopPath(); p != "" {
-		// Delete it; a missing file is fine.
-		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
+		// Delete it; a missing one is fine.
+		if err := removeLauncher(p); err != nil {
 			// Report it.
 			return err
 		} // end of the delete check
 	} // end of the launcher case
-	// The picture.
+	// The pictures: the PNG of the Linux launcher and the ICO of the Windows shortcut.
 	if d.iconDir() != "" {
-		// Delete it; a missing file is fine.
-		if err := os.Remove(filepath.Join(d.iconDir(), iconFileName)); err != nil && !os.IsNotExist(err) {
-			// Report it.
-			return err
-		} // end of the delete check
+		// Both names; a missing file is fine.
+		for _, name := range []string{iconFileName, icoFileName} {
+			// Delete one.
+			if err := os.Remove(filepath.Join(d.iconDir(), name)); err != nil && !os.IsNotExist(err) {
+				// Report it.
+				return err
+			} // end of the delete check
+		} // end of the picture loop
 	} // end of the picture case
 	// Done.
 	return nil
diff --git a/launchers.go b/launchers.go
new file mode 100644
index 0000000..3cfec47
--- /dev/null
+++ b/launchers.go
@@ -0,0 +1,342 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds the picture containers in memory.
+	"bytes"
+	// context limits how long the PowerShell call may take.
+	"context"
+	// encoding/binary writes the numbers of the picture containers in the byte order each format needs.
+	"encoding/binary"
+	// errors builds fixed error messages.
+	"errors"
+	// fmt builds messages.
+	"fmt"
+	// log reports why a tool failed (the page only says "failed").
+	"log"
+	// os writes and removes the launcher files.
+	"os"
+	// os/exec runs PowerShell.
+	"os/exec"
+	// path/filepath joins paths.
+	"path/filepath"
+	// strings builds and checks text.
+	"strings"
+	// time sets the limit for the tool.
+	"time"
+) // end of imports
+
+// icoFileName is the Windows icon file kept in the data folder; the shortcut points at it.
+const icoFileName = "icon.ico"
+
+// The names of the launcher on each system.
+const (
+	// windowsLauncherName is a real Windows Shell Link.
+	windowsLauncherName = "OllamaControlCenter.lnk"
+	// macLauncherName is an application bundle.
+	macLauncherName = "OllamaControlCenter.app"
+) // end of the launcher names
+
+// launcherName is the name of the launcher on the desktop of the given system.
+func launcherName(goos string) string {
+	// Pick by system.
+	switch goos {
+	// Windows.
+	case "windows":
+		// A shortcut file.
+		return windowsLauncherName
+	// macOS.
+	case "darwin":
+		// An application bundle.
+		return macLauncherName
+	// Linux and anything else: a Desktop Entry file.
+	default:
+		// The Linux launcher.
+		return desktopFileName
+	} // end of the switch
+} // end of launcherName
+
+// pngSize reads the width and height from the header of a PNG picture.
+func pngSize(png []byte) (w, h uint32, err error) {
+	// A PNG starts with an 8-byte signature and then the IHDR chunk, whose first two numbers are the width and the height (big-endian).
+	if len(png) < 24 || !bytes.HasPrefix(png, []byte("\x89PNG\r\n\x1a\n")) || string(png[12:16]) != "IHDR" {
+		// Not a PNG.
+		return 0, 0, errors.New("the program icon is not a PNG picture")
+	} // end of the signature check
+	// The two numbers.
+	return binary.BigEndian.Uint32(png[16:20]), binary.BigEndian.Uint32(png[20:24]), nil
+} // end of pngSize
+
+// pngToICO wraps a PNG picture in an ICO container (one image; PNG frames are supported from Windows Vista); a width or height of 256 is written as 0, as the format says.
+func pngToICO(png []byte) ([]byte, error) {
+	// The picture's size.
+	w, h, err := pngSize(png)
+	// A bad picture.
+	if err != nil {
+		// Report it.
+		return nil, err
+	} // end of the size check
+	// An ICO frame holds at most 256 by 256 pixels.
+	if w == 0 || h == 0 || w > 256 || h > 256 {
+		// Refuse.
+		return nil, fmt.Errorf("the program icon is %dx%d pixels; an ICO frame holds 1 to 256", w, h)
+	} // end of the limit check
+	// The byte that stands for a size: 0 means 256.
+	size := func(v uint32) byte {
+		// 256 is written as 0.
+		if v == 256 {
+			// Zero.
+			return 0
+		} // end of the 256 case
+		// Otherwise the number itself.
+		return byte(v)
+	} // end of size
+	// The container, all numbers little-endian.
+	var b bytes.Buffer
+	// ICONDIR: reserved 0, type 1 (icon), one image.
+	binary.Write(&b, binary.LittleEndian, []uint16{0, 1, 1})
+	// ICONDIRENTRY: width, height, colours 0, reserved 0.
+	b.Write([]byte{size(w), size(h), 0, 0})
+	// Planes 1 and 32 bits per pixel.
+	binary.Write(&b, binary.LittleEndian, []uint16{1, 32})
+	// The size of the image data and its offset (6 + 16 bytes of headers).
+	binary.Write(&b, binary.LittleEndian, []uint32{uint32(len(png)), 22})
+	// The PNG itself.
+	b.Write(png)
+	// Hand it back.
+	return b.Bytes(), nil
+} // end of pngToICO
+
+// pngToICNS wraps a 256 by 256 PNG picture in an Apple icon container: the 'icns' header, then one 'ic08' element (256x256, PNG data); all numbers are big-endian.
+func pngToICNS(png []byte) ([]byte, error) {
+	// The picture's size.
+	w, h, err := pngSize(png)
+	// A bad picture.
+	if err != nil {
+		// Report it.
+		return nil, err
+	} // end of the size check
+	// The 'ic08' element is defined for 256 by 256 pixels.
+	if w != 256 || h != 256 {
+		// Refuse.
+		return nil, fmt.Errorf("the program icon is %dx%d pixels; the icon file needs 256x256", w, h)
+	} // end of the size check
+	// The container.
+	var b bytes.Buffer
+	// The magic and the total length (8 bytes header + 8 bytes element header + data).
+	b.WriteString("icns")
+	// The length.
+	binary.Write(&b, binary.BigEndian, uint32(16+len(png)))
+	// The element: its type and its length (including its own 8 bytes).
+	b.WriteString("ic08")
+	// The element length.
+	binary.Write(&b, binary.BigEndian, uint32(8+len(png)))
+	// The PNG.
+	b.Write(png)
+	// Hand it back.
+	return b.Bytes(), nil
+} // end of pngToICNS
+
+// shQuote quotes text for a POSIX shell: inside single quotes nothing is special, and a single quote itself is written as '\”.
+func shQuote(s string) string {
+	// Wrap and escape.
+	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
+} // end of shQuote
+
+// macScript is the program inside the application bundle: it starts the program with -launch, which starts the monitor if needed and opens the page.
+func macScript(exe string) string {
+	// A shell script; exec replaces the shell by the program.
+	return "#!/bin/sh\n# Starts OllamaControlCenter (the monitor if needed) and opens the page in the browser.\nexec " + shQuote(exe) + " -launch\n"
+} // end of macScript
+
+// macInfoPlist is the property list that makes the folder an application bundle (Apple's standard keys).
+func macInfoPlist() string {
+	// The XML property list; every value is a fixed text of this program.
+	return `<?xml version="1.0" encoding="UTF-8"?>
+<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
+<plist version="1.0">
+<dict>
+	<key>CFBundleName</key><string>OllamaControlCenter</string>
+	<key>CFBundleDisplayName</key><string>OllamaControlCenter</string>
+	<key>CFBundleIdentifier</key><string>com.termgate.ollamacontrolcenter</string>
+	<key>CFBundleExecutable</key><string>OllamaControlCenter</string>
+	<key>CFBundlePackageType</key><string>APPL</string>
+	<key>CFBundleIconFile</key><string>icon</string>
+	<key>CFBundleShortVersionString</key><string>` + appVersion + `</string>
+	<key>CFBundleVersion</key><string>` + appVersion + `</string>
+	<key>LSUIElement</key><true/>
+</dict>
+</plist>
+`
+} // end of macInfoPlist
+
+// winShortcutScript makes the shortcut; the paths arrive in environment variables, so no path is ever pasted into the script and a path with spaces or quotes cannot change what it does.
+const winShortcutScript = `$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:OCC_LINK);` +
+	`$s.TargetPath=$env:OCC_EXE;$s.Arguments='-launch';$s.WorkingDirectory=$env:OCC_WORKDIR;` +
+	`$s.IconLocation=$env:OCC_ICON;$s.Description='Monitor and control Ollama';$s.WindowStyle=7;$s.Save()`
+
+// realToolRun runs a tool with extra environment variables and waits at most twenty seconds; a failure carries what the tool printed (it goes to the log, never to the page).
+func realToolRun(exe string, env []string, args ...string) error {
+	// Never wait long.
+	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
+	// Release the timer at the end.
+	defer cancel()
+	// The command.
+	cmd := exec.CommandContext(ctx, exe, args...)
+	// The program's environment plus the extra variables.
+	cmd.Env = append(os.Environ(), env...)
+	// Run it.
+	out, err := cmd.CombinedOutput()
+	// A failure.
+	if err != nil {
+		// Say why in the log.
+		log.Printf("desktop shortcut tool failed: %v: %s", err, strings.TrimSpace(string(out)))
+		// Report it.
+		return err
+	} // end of the failure check
+	// Done.
+	return nil
+} // end of realToolRun
+
+// resolvedExe returns the running program's own file with links resolved, refusing text that cannot be a normal path.
+func (d desktopIcon) resolvedExe() (string, error) {
+	// The program's own file.
+	exe, err := d.env.exePath()
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return "", err
+	} // end of the program check
+	// The real file.
+	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
+		// Use it.
+		exe = resolved
+	} // end of the link check
+	// It must be an absolute path without control characters.
+	if !filepath.IsAbs(exe) || strings.ContainsAny(exe, "\x00\r\n") {
+		// Refuse.
+		return "", errUnusualPath
+	} // end of the path check
+	// Fine.
+	return exe, nil
+} // end of resolvedExe
+
+// createWindows writes the icon file and makes the shortcut with Windows PowerShell (the Windows Script Host shortcut object), then remembers the answer.
+func (d desktopIcon) createWindows(dir string) error {
+	// The program.
+	exe, err := d.resolvedExe()
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the program check
+	// The icon file made from the program's picture.
+	ico, err := pngToICO(appIcon)
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the icon check
+	// Write it where the shortcut can find it.
+	if err := writeFile(d.iconDir(), icoFileName, ico); err != nil {
+		// Report it.
+		return err
+	} // end of the write check
+	// Where the shortcut goes.
+	link := filepath.Join(dir, windowsLauncherName)
+	// Without a way to run tools there is nothing more to do.
+	if d.env.run == nil {
+		// Not supported.
+		return errDesktopUnsupported
+	} // end of the tool check
+	// Make it; the icon location is the file and the number of the picture inside it.
+	if err := d.env.run(powershellPath(), []string{"OCC_LINK=" + link, "OCC_EXE=" + exe, "OCC_WORKDIR=" + filepath.Dir(exe), "OCC_ICON=" + filepath.Join(d.iconDir(), icoFileName) + ",0"}, "-NoProfile", "-NonInteractive", "-Command", winShortcutScript); err != nil {
+		// Report it.
+		return err
+	} // end of the tool check
+	// The tool can succeed without writing the file (for example when a security program blocks it); check.
+	if _, err := os.Stat(link); err != nil {
+		// Report it.
+		return errors.New("the shortcut file was not created")
+	} // end of the file check
+	// Remember the answer.
+	return d.remember("created")
+} // end of createWindows
+
+// createMac writes the application bundle on the desktop: Info.plist, the starting script and the icon, then remembers the answer.
+func (d desktopIcon) createMac(dir string) error {
+	// The program.
+	exe, err := d.resolvedExe()
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the program check
+	// The icon container.
+	icns, err := pngToICNS(appIcon)
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the icon check
+	// The bundle's folder.
+	app := filepath.Join(dir, macLauncherName)
+	// Start fresh: an older bundle of ours is replaced (the name is fixed, so nothing else can be removed).
+	if err := os.RemoveAll(app); err != nil {
+		// Report it.
+		return err
+	} // end of the clean-up check
+	// The two folders inside.
+	for _, sub := range []string{"Contents/MacOS", "Contents/Resources"} {
+		// Make one.
+		if err := os.MkdirAll(filepath.Join(app, filepath.FromSlash(sub)), 0o755); err != nil {
+			// Report it.
+			return err
+		} // end of the folder check
+	} // end of the folder loop
+	// The files: the property list, the icon and the starting script (which needs the executable bit).
+	for _, f := range []struct {
+		// path is relative to the bundle.
+		path string
+		// data is the content.
+		data []byte
+		// mode is the file mode.
+		mode os.FileMode
+	}{
+		// The property list.
+		{"Contents/Info.plist", []byte(macInfoPlist()), 0o644},
+		// The icon.
+		{"Contents/Resources/icon.icns", icns, 0o644},
+		// The script; it is named like CFBundleExecutable.
+		{"Contents/MacOS/OllamaControlCenter", []byte(macScript(exe)), 0o755},
+	} { // end of the file list
+		// Write it.
+		if err := os.WriteFile(filepath.Join(app, filepath.FromSlash(f.path)), f.data, f.mode); err != nil {
+			// Report it.
+			return err
+		} // end of the write check
+		// The mode is set again, because the umask may have removed the executable bit.
+		if err := os.Chmod(filepath.Join(app, filepath.FromSlash(f.path)), f.mode); err != nil {
+			// Report it.
+			return err
+		} // end of the chmod check
+	} // end of the file loop
+	// Remember the answer.
+	return d.remember("created")
+} // end of createMac
+
+// removeLauncher deletes the launcher on the desktop; a missing one is fine, and a bundle is removed only when it carries the program's own name.
+func removeLauncher(path string) error {
+	// A bundle is a folder.
+	if filepath.Base(path) == macLauncherName {
+		// Delete it with everything in it.
+		return os.RemoveAll(path)
+	} // end of the bundle case
+	// A file; a missing one is fine.
+	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
+		// Report it.
+		return err
+	} // end of the delete check
+	// Done.
+	return nil
+} // end of removeLauncher
diff --git a/launchers_test.go b/launchers_test.go
new file mode 100644
index 0000000..479087c
--- /dev/null
+++ b/launchers_test.go
@@ -0,0 +1,470 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this test uses.
+	// bytes compares picture data.
+	"bytes"
+	// encoding/binary reads the numbers of the picture containers.
+	"encoding/binary"
+	// errors builds the failure of a tool.
+	"errors"
+	// os makes and reads files.
+	"os"
+	// os/exec runs the macOS starting script for real.
+	"os/exec"
+	// path/filepath joins paths.
+	"path/filepath"
+	// runtime tells which system the test runs on.
+	"runtime"
+	// strings searches texts.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// toolCall records one call of the fake tool runner.
+type toolCall struct {
+	// exe is the tool.
+	exe string
+	// env is the extra environment.
+	env []string
+	// args are the arguments.
+	args []string
+} // end of toolCall
+
+// launcherRig is a pretend Windows or macOS computer inside a temporary folder.
+type launcherRig struct {
+	// d is the desktop icon helper.
+	d desktopIcon
+	// desk is the desktop folder.
+	desk string
+	// exe is the program file.
+	exe string
+	// data is the data folder.
+	data string
+	// cfg is the settings folder.
+	cfg string
+	// calls records the tool calls.
+	calls *[]toolCall
+} // end of launcherRig
+
+// newLauncherRig builds the rig for the given system name; the program sits in a folder whose name has a space and an apostrophe, which a careless launcher would break on.
+func newLauncherRig(t *testing.T, goos string, makeLink bool) *launcherRig {
+	// Mark this as a helper.
+	t.Helper()
+	// The pretend home, with links resolved.
+	home, err := filepath.EvalSymlinks(t.TempDir())
+	// A failure means the test is wrong.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the home check
+	// The desktop.
+	desk := filepath.Join(home, "Desktop")
+	// Make it.
+	if err := os.MkdirAll(desk, 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the desktop check
+	// The program folder with an awkward name.
+	progDir := filepath.Join(home, "O'Brien apps")
+	// Make it.
+	if err := os.MkdirAll(progDir, 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the folder check
+	// The program file.
+	exe := filepath.Join(progDir, "occ")
+	// Write it.
+	if err := os.WriteFile(exe, []byte("x"), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the file check
+	// The calls.
+	calls := &[]toolCall{}
+	// The environment.
+	env := desktopEnv{goos: goos, getenv: func(string) string { return "" }, homeDir: func() (string, error) { return home, nil }, exePath: func() (string, error) { return exe, nil }, trust: func(string) {}}
+	// The Windows lookups.
+	env.knownDesktop = func() (string, error) { return desk, nil }
+	// The fake tool: it records the call and, like PowerShell would, writes the shortcut file.
+	env.run = func(tool string, extra []string, args ...string) error {
+		// Record it.
+		*calls = append(*calls, toolCall{tool, extra, args})
+		// Write the shortcut file the way the real tool would.
+		if makeLink {
+			// Find the link path in the environment.
+			for _, e := range extra {
+				// The variable.
+				if v, ok := strings.CutPrefix(e, "OCC_LINK="); ok {
+					// Create it.
+					return os.WriteFile(v, []byte("lnk"), 0o644)
+				} // end of the variable check
+			} // end of the loop
+		} // end of the link case
+		// Nothing written.
+		return nil
+	} // end of the fake tool
+	// The folders of the program.
+	cfg, data := filepath.Join(home, "cfg"), filepath.Join(home, "data")
+	// The helper.
+	return &launcherRig{d: desktopIcon{env: env, dir: cfg, dataDir: data}, desk: desk, exe: exe, data: data, cfg: cfg, calls: calls}
+} // end of newLauncherRig
+
+// TestPngToICO checks the ICO container byte by byte.
+func TestPngToICO(t *testing.T) {
+	// The program's own picture is 256 by 256.
+	ico, err := pngToICO(appIcon)
+	// It must work.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the error check
+	// ICONDIR: reserved 0, type 1, count 1.
+	if binary.LittleEndian.Uint16(ico[0:]) != 0 || binary.LittleEndian.Uint16(ico[2:]) != 1 || binary.LittleEndian.Uint16(ico[4:]) != 1 {
+		// Report it.
+		t.Errorf("bad ICONDIR % x", ico[:6])
+	} // end of the header check
+	// ICONDIRENTRY: 256 is written as 0, no colours, reserved 0, 1 plane, 32 bits.
+	if ico[6] != 0 || ico[7] != 0 || ico[8] != 0 || ico[9] != 0 || binary.LittleEndian.Uint16(ico[10:]) != 1 || binary.LittleEndian.Uint16(ico[12:]) != 32 {
+		// Report it.
+		t.Errorf("bad ICONDIRENTRY % x", ico[6:22])
+	} // end of the entry check
+	// The size and the offset.
+	if int(binary.LittleEndian.Uint32(ico[14:])) != len(appIcon) || binary.LittleEndian.Uint32(ico[18:]) != 22 {
+		// Report it.
+		t.Errorf("bad size or offset")
+	} // end of the size check
+	// The picture follows unchanged.
+	if !bytes.Equal(ico[22:], appIcon) {
+		// Report it.
+		t.Errorf("the PNG data was changed")
+	} // end of the data check
+	// A text is not a picture.
+	if _, err := pngToICO([]byte("not a png at all, really not")); err == nil {
+		// Report it.
+		t.Errorf("a non-PNG was accepted")
+	} // end of the refusal check
+	// A picture that is too large for an ICO frame.
+	big := append([]byte{}, appIcon...)
+	// Make the width 512.
+	binary.BigEndian.PutUint32(big[16:], 512)
+	// Refused.
+	if _, err := pngToICO(big); err == nil {
+		// Report it.
+		t.Errorf("a 512-pixel picture was accepted")
+	} // end of the large check
+} // end of TestPngToICO
+
+// TestPngToICNS checks the Apple icon container.
+func TestPngToICNS(t *testing.T) {
+	// Make it.
+	icns, err := pngToICNS(appIcon)
+	// It must work.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the error check
+	// The magic and the total length (big-endian).
+	if string(icns[:4]) != "icns" || int(binary.BigEndian.Uint32(icns[4:])) != len(icns) {
+		// Report it.
+		t.Errorf("bad header % x", icns[:8])
+	} // end of the header check
+	// The element: type and length.
+	if string(icns[8:12]) != "ic08" || int(binary.BigEndian.Uint32(icns[12:])) != len(icns)-8 {
+		// Report it.
+		t.Errorf("bad element % x", icns[8:16])
+	} // end of the element check
+	// The picture follows unchanged.
+	if !bytes.Equal(icns[16:], appIcon) {
+		// Report it.
+		t.Errorf("the PNG data was changed")
+	} // end of the data check
+	// Another size is refused.
+	small := append([]byte{}, appIcon...)
+	// Make the width 128.
+	binary.BigEndian.PutUint32(small[16:], 128)
+	// Refused.
+	if _, err := pngToICNS(small); err == nil {
+		// Report it.
+		t.Errorf("a 128-pixel picture was accepted")
+	} // end of the size check
+} // end of TestPngToICNS
+
+// TestShQuoteAndScript checks the quoting of the macOS starting script.
+func TestShQuoteAndScript(t *testing.T) {
+	// A path with a space and an apostrophe.
+	got := macScript("/Users/O'Brien/My App/occ")
+	// The expected line.
+	if !strings.Contains(got, `exec '/Users/O'\''Brien/My App/occ' -launch`) || !strings.HasPrefix(got, "#!/bin/sh\n") {
+		// Report it.
+		t.Errorf("script = %q", got)
+	} // end of the check
+} // end of TestShQuoteAndScript
+
+// TestCreateWindowsShortcut checks the Windows shortcut: the call, the icon file, the answer, and that no path is pasted into the script.
+func TestCreateWindowsShortcut(t *testing.T) {
+	// The rig.
+	r := newLauncherRig(t, "windows", true)
+	// Create it.
+	if err := r.d.create(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the create check
+	// One tool call.
+	if len(*r.calls) != 1 {
+		// Stop.
+		t.Fatalf("tool calls = %d", len(*r.calls))
+	} // end of the call count
+	// The call.
+	c := (*r.calls)[0]
+	// The arguments: no profile, no questions, and the fixed script.
+	if strings.Join(c.args[:3], " ") != "-NoProfile -NonInteractive -Command" || c.args[3] != winShortcutScript {
+		// Report it.
+		t.Errorf("args = %q", c.args)
+	} // end of the argument check
+	// The script holds no path.
+	if strings.Contains(winShortcutScript, r.exe) || strings.Contains(winShortcutScript, r.desk) {
+		// Report it.
+		t.Errorf("a path was pasted into the script")
+	} // end of the injection check
+	// The paths travel in the environment, with the awkward name intact.
+	want := []string{"OCC_LINK=" + filepath.Join(r.desk, windowsLauncherName), "OCC_EXE=" + r.exe, "OCC_WORKDIR=" + filepath.Dir(r.exe), "OCC_ICON=" + filepath.Join(r.data, icoFileName) + ",0"}
+	// Compare.
+	if strings.Join(c.env, "|") != strings.Join(want, "|") {
+		// Report it.
+		t.Errorf("env = %q\nwant %q", c.env, want)
+	} // end of the environment check
+	// The script asks for -launch and a minimised window.
+	if !strings.Contains(winShortcutScript, "'-launch'") || !strings.Contains(winShortcutScript, "WindowStyle=7") {
+		// Report it.
+		t.Errorf("the script lacks -launch or the minimised window")
+	} // end of the script check
+	// The icon file is a valid ICO.
+	ico, err := os.ReadFile(filepath.Join(r.data, icoFileName))
+	// It must exist.
+	if err != nil || len(ico) < 22 || binary.LittleEndian.Uint16(ico[2:]) != 1 {
+		// Report it.
+		t.Errorf("icon file: %v", err)
+	} // end of the icon check
+	// The answer is remembered, and the shortcut counts as existing.
+	if r.d.choice() != "created" || !r.d.exists() {
+		// Report it.
+		t.Errorf("choice %q exists %v", r.d.choice(), r.d.exists())
+	} // end of the answer check
+	// A Windows launcher is never compared as text.
+	if stale, _, _ := r.d.staleness(); stale {
+		// Report it.
+		t.Errorf("a Windows shortcut was reported stale")
+	} // end of the stale check
+	// Removing deletes the shortcut and the icon file.
+	if err := r.d.removeFiles(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the remove check
+	// Both gone.
+	if r.d.exists() {
+		// Report it.
+		t.Errorf("the shortcut is still there")
+	} // end of the gone check
+	// The icon file too.
+	if _, err := os.Stat(filepath.Join(r.data, icoFileName)); err == nil {
+		// Report it.
+		t.Errorf("the icon file is still there")
+	} // end of the icon gone check
+} // end of TestCreateWindowsShortcut
+
+// TestCreateWindowsFailures checks that a failing or silent tool is reported and not remembered as success.
+func TestCreateWindowsFailures(t *testing.T) {
+	// The tool fails.
+	r := newLauncherRig(t, "windows", true)
+	// A failing tool.
+	r.d.env.run = func(string, []string, ...string) error { return errors.New("blocked") }
+	// It must fail.
+	if err := r.d.create(); err == nil || r.d.choice() != "" {
+		// Report it.
+		t.Errorf("failing tool: err=%v choice=%q", err, r.d.choice())
+	} // end of the failure check
+	// The tool succeeds but writes nothing.
+	q := newLauncherRig(t, "windows", false)
+	// It must fail.
+	if err := q.d.create(); err == nil || q.d.choice() != "" {
+		// Report it.
+		t.Errorf("silent tool: err=%v choice=%q", err, q.d.choice())
+	} // end of the silent check
+	// No way to run tools.
+	n := newLauncherRig(t, "windows", true)
+	// None.
+	n.d.env.run = nil
+	// Not supported.
+	if err := n.d.create(); !errors.Is(err, errDesktopUnsupported) {
+		// Report it.
+		t.Errorf("no runner: %v", err)
+	} // end of the no-runner check
+} // end of TestCreateWindowsFailures
+
+// TestCreateMacBundle checks the application bundle and that a second creation replaces it.
+func TestCreateMacBundle(t *testing.T) {
+	// The rig.
+	r := newLauncherRig(t, "darwin", false)
+	// Create it twice: the second time replaces the first.
+	for i := 0; i < 2; i++ {
+		// Create.
+		if err := r.d.create(); err != nil {
+			// Stop.
+			t.Fatal(err)
+		} // end of the create check
+	} // end of the loop
+	// The bundle.
+	app := filepath.Join(r.desk, macLauncherName)
+	// The property list.
+	plist, err := os.ReadFile(filepath.Join(app, "Contents", "Info.plist"))
+	// It must exist.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the read check
+	// The keys.
+	for _, want := range []string{"<key>CFBundleExecutable</key><string>OllamaControlCenter</string>", "<key>CFBundlePackageType</key><string>APPL</string>", "<key>CFBundleIconFile</key><string>icon</string>", "<string>" + appVersion + "</string>", "com.termgate.ollamacontrolcenter"} {
+		// Each must be there.
+		if !strings.Contains(string(plist), want) {
+			// Report it.
+			t.Errorf("Info.plist lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The script holds the quoted program path.
+	script, err := os.ReadFile(filepath.Join(app, "Contents", "MacOS", "OllamaControlCenter"))
+	// It must exist.
+	if err != nil || string(script) != macScript(r.exe) {
+		// Report it.
+		t.Errorf("script: %v %q", err, script)
+	} // end of the script check
+	// The icon.
+	if icns, err := os.ReadFile(filepath.Join(app, "Contents", "Resources", "icon.icns")); err != nil || string(icns[:4]) != "icns" {
+		// Report it.
+		t.Errorf("icon: %v", err)
+	} // end of the icon check
+	// The script is executable (Windows has no such bit).
+	if st, err := os.Stat(filepath.Join(app, "Contents", "MacOS", "OllamaControlCenter")); err != nil || (modesApply() && st.Mode().Perm() != 0o755) {
+		// Report it.
+		t.Errorf("script mode: %v %v", st, err)
+	} // end of the mode check
+	// The answer is remembered and the bundle counts as existing.
+	if r.d.choice() != "created" || !r.d.exists() {
+		// Report it.
+		t.Errorf("choice %q exists %v", r.d.choice(), r.d.exists())
+	} // end of the answer check
+	// Removing deletes the whole bundle.
+	if err := r.d.removeFiles(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the remove check
+	// Gone.
+	if r.d.exists() {
+		// Report it.
+		t.Errorf("the bundle is still there")
+	} // end of the gone check
+	// The desktop folder itself stays.
+	if _, err := os.Stat(r.desk); err != nil {
+		// Report it.
+		t.Errorf("the desktop folder was removed")
+	} // end of the desktop check
+} // end of TestCreateMacBundle
+
+// TestMacScriptRuns runs the starting script for real with a program path that has a space and an apostrophe, and checks that the program receives -launch.
+func TestMacScriptRuns(t *testing.T) {
+	// The script needs a POSIX shell.
+	if runtime.GOOS == "windows" {
+		// Skip with the reason.
+		t.Skip("the starting script is a POSIX shell script")
+	} // end of the system check
+	// The rig.
+	r := newLauncherRig(t, "darwin", false)
+	// Where the fake program writes what it received.
+	out := filepath.Join(filepath.Dir(r.exe), "got.txt")
+	// The fake program.
+	if err := os.WriteFile(r.exe, []byte("#!/bin/sh\necho \"$@\" > "+shQuote(out)+"\n"), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// Create the bundle.
+	if err := r.d.create(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the create check
+	// Run its script.
+	if err := exec.Command(filepath.Join(r.desk, macLauncherName, "Contents", "MacOS", "OllamaControlCenter")).Run(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the run check
+	// What the program received.
+	got, err := os.ReadFile(out)
+	// It must be exactly -launch.
+	if err != nil || strings.TrimSpace(string(got)) != "-launch" {
+		// Report it.
+		t.Errorf("program received %q (%v)", got, err)
+	} // end of the check
+} // end of TestMacScriptRuns
+
+// TestDesktopDirWindowsAndMac checks where each system's desktop is found.
+func TestDesktopDirWindowsAndMac(t *testing.T) {
+	// Windows: the Known Folder lookup decides.
+	w := newLauncherRig(t, "windows", false)
+	// Found.
+	if dir, ok := w.d.env.desktopDir(); !ok || dir != w.desk {
+		// Report it.
+		t.Errorf("windows desktop = %q %v", dir, ok)
+	} // end of the found check
+	// A failing lookup means no desktop.
+	w.d.env.knownDesktop = func() (string, error) { return "", errors.New("no") }
+	// Not found.
+	if _, ok := w.d.env.desktopDir(); ok {
+		// Report it.
+		t.Errorf("a failing lookup gave a desktop")
+	} // end of the not-found check
+	// macOS: Desktop in the home folder.
+	m := newLauncherRig(t, "darwin", false)
+	// Found.
+	if dir, ok := m.d.env.desktopDir(); !ok || dir != m.desk {
+		// Report it.
+		t.Errorf("mac desktop = %q %v", dir, ok)
+	} // end of the found check
+	// Without the folder there is no desktop.
+	if err := os.RemoveAll(m.desk); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the remove check
+	// Not found.
+	if _, ok := m.d.env.desktopDir(); ok {
+		// Report it.
+		t.Errorf("a missing Desktop folder gave a desktop")
+	} // end of the missing check
+	// Another system.
+	o := newLauncherRig(t, "plan9", false)
+	// Not found.
+	if _, ok := o.d.env.desktopDir(); ok {
+		// Report it.
+		t.Errorf("an unknown system gave a desktop")
+	} // end of the other check
+} // end of TestDesktopDirWindowsAndMac
+
+// TestIconWordsPerSystem checks that the Ubuntu hint stays on Linux.
+func TestIconWordsPerSystem(t *testing.T) {
+	// Linux keeps the hint.
+	if !strings.Contains(iconNoteFor("created", "linux"), "Allow Launching") || !strings.Contains(desktopHint("linux"), "Allow Launching") {
+		// Report it.
+		t.Errorf("the Linux hint is missing")
+	} // end of the Linux check
+	// The others have none.
+	for _, goos := range []string{"windows", "darwin"} {
+		// The note and the hint.
+		if strings.Contains(iconNoteFor("created", goos), "Ubuntu") || desktopHint(goos) != "" || iconNoteFor("created", goos) == "" {
+			// Report it.
+			t.Errorf("%s: note %q hint %q", goos, iconNoteFor("created", goos), desktopHint(goos))
+		} // end of the check
+	} // end of the loop
+	// Other words are unchanged.
+	if iconNoteFor("removed", "windows") != iconNotes["removed"] || iconNoteFor("bogus", "linux") != "" {
+		// Report it.
+		t.Errorf("other words changed")
+	} // end of the other-words check
+} // end of TestIconWordsPerSystem
diff --git a/settingspage.go b/settingspage.go
index 0d4d2d9..c19e7b2 100644
--- a/settingspage.go
+++ b/settingspage.go
@@ -105,6 +105,28 @@ var iconNotes = map[string]string{
 	"failed": "The desktop icon could not be created or removed. Check that the folders are writable.",
 } // end of iconNotes
 
+// iconNoteFor returns the sentence for a result word; the Ubuntu hint about "Allow Launching" belongs to Linux only.
+func iconNoteFor(word, goos string) string {
+	// Only the "created" sentence differs.
+	if word == "created" && goos != "linux" {
+		// Without the Linux hint.
+		return "Desktop icon created."
+	} // end of the created case
+	// The fixed sentence, or nothing for an unknown word.
+	return iconNotes[word]
+} // end of iconNoteFor
+
+// desktopHint is the extra sentence of the first-run question: on Ubuntu the launcher must be allowed once; the other systems need no hint.
+func desktopHint(goos string) string {
+	// Linux only.
+	if goos == "linux" {
+		// The hint.
+		return "On Ubuntu you may have to right-click the icon once and choose Allow Launching."
+	} // end of the Linux case
+	// None.
+	return ""
+} // end of desktopHint
+
 // yesNo writes a flag as the words used in the form.
 func yesNo(on bool) string {
 	// Yes.
@@ -276,7 +298,7 @@ func settingsHandlers(addr ollamaAddress, mon *monitor, token string) (http.Hand
 		// Whether the launcher is out of date, and the two picture paths.
 		iconStale, iconOld, iconNew := desk.staleness()
 		// The note after a button; unknown keys show nothing.
-		iconNote := iconNotes[r.URL.Query().Get("icon")]
+		iconNote := iconNoteFor(r.URL.Query().Get("icon"), mon.denv.goos)
 		// Everything the template needs.
 		data := settingsPage{IconAvailable: iconAvail, IconExists: iconExists, IconPath: iconPath, IconNote: iconNote, IconStale: iconStale && iconAvail, IconOld: iconOld, IconNew: iconNew, Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder, DataFolder: dataFolder, StateFolder: stateFolder}
 		// Build the page in memory first, so a template error gives a clean 500.
diff --git a/web.go b/web.go
index 3b5b7a7..70fb98c 100644
--- a/web.go
+++ b/web.go
@@ -93,6 +93,8 @@ type pageData struct {
 	DesktopBanner bool
 	// DesktopDir and DesktopExe are the folder and the program the question names.
 	DesktopDir, DesktopExe string
+	// DesktopHint is the extra sentence for this system (empty on most).
+	DesktopHint string
 	// DetailsTip is the help bubble of the twistie "Monitoring details".
 	DetailsTip tipView
 	// KeyOpen is true when the person opened the key to the symbols (the address then ends in ?key=open); the page does not update by itself meanwhile.
@@ -352,7 +354,7 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 		// The result of the icon button, shown once: read the short-lived note and delete it, so the automatic reload does not show it again.
 		if c, err := r.Cookie(iconFlashCookie); err == nil {
 			// Only the known words show a sentence.
-			data.IconNote = iconNotes[c.Value]
+			data.IconNote = iconNoteFor(c.Value, desktop.env.goos)
 			// Delete the note.
 			http.SetCookie(w, &http.Cookie{Name: iconFlashCookie, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
 		} // end of the note check
@@ -364,6 +366,8 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 			data.DesktopDir, _ = desktop.env.desktopDir()
 			// The program.
 			data.DesktopExe, _ = desktop.env.exePath()
+			// The hint that belongs to this system.
+			data.DesktopHint = desktopHint(desktop.env.goos)
 		} // end of the banner check
 		// The lists that the event log compares; they stay empty when Ollama cannot be read.
 		var evInstalled []installedModel
diff --git a/web/index.html b/web/index.html
index d4f5103..561a51e 100644
--- a/web/index.html
+++ b/web/index.html
@@ -28,7 +28,7 @@
 {{/* The question. */}}
 <p class="iconquestion"><img class="appicon" src="/icon.png" width="40" height="40" alt=""> <strong>Create a desktop icon for OllamaControlCenter?</strong></p>
 {{/* What it does and where it goes. */}}
-<p class="muted">One click on it starts the monitor (if it is not running) and opens this page in your browser. It is created in <code>{{.DesktopDir}}</code> and points to <code>{{.DesktopExe}}</code>. On Ubuntu you may have to right-click the icon once and choose <strong>Allow Launching</strong>. You can remove it later on the Settings page.</p>
+<p class="muted">One click on it starts the monitor (if it is not running) and opens this page in your browser. It is created in <code>{{.DesktopDir}}</code> and points to <code>{{.DesktopExe}}</code>. {{.DesktopHint}} You can remove it later on the Settings page.</p>
 {{/* The two answers: one small form with the page token. */}}
 <form method="post" action="/desktopicon">
 {{/* The page token proves the form comes from this page. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
06a06317dfefa71abc146bb8cee06eac8243173a72da332cbc18347bb9dc8eb3  about.go
95e6ae7ed861b1eafdab8c36167ab91b6ae3ae53d5fc4057ead68b2296ddf6ca  desktop_other.go
dacde02f13cbdbfaa2e87db01467aaf11798c64d8b8dd59b774a886aa2a1c286  desktop_windows.go
0d9c20cb79b59f163f919ecbce45524b3541ac5f441f174e4b8d3d60e5e252ee  desktopicon.go
7df069c6dc819305e533298d31ead6d87874eb58fd029eed5bfcf62da3979ce7  launchers.go
9e4e4b997ef2486c452850a8aa51362b9f7cf60426fb3804390f1f5036b14944  launchers_test.go
fc15e2863706dff698e40b12758e04a40eb0a919ee9e94954ff2c57bd4314fbd  settingspage.go
2d99b19bbfb0397ee6e3d8c416b5383043c32c009055f4f10b90b15671bd210a  web.go
772211e3084d10c6ad0c487ea499b85117ba6827000fe3c23ca6679adf1849e0  web/index.html
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
for target in windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Build for one target and throw the file away.
  GOOS="${target%/*}" GOARCH="${target#*/}" CGO_ENABLED=0 go build -trimpath -o /dev/null . || { echo "FAIL  build for $target"; exit 1; }
  # Report it.
  echo "PASS  compiles for $target"
done
# Stop only the old monitor program by exact name (a pattern match could stop this very script).
pgrep -x OllamaControlCenter | xargs -r kill || true
# Give it a moment to exit.
sleep 1
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# Tell the person what to look at.
echo "NEXT  start ./bin/OllamaControlCenter and open http://127.0.0.1:8765/ ; on Linux nothing changes; the Windows and macOS shortcuts are tested on those systems; then commit, push and merge"
# List the changed files; nothing is committed yet.
git status --short
