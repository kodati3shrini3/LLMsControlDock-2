// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds the picture containers in memory.
	"bytes"
	// context limits how long the PowerShell call may take.
	"context"
	// encoding/binary writes the numbers of the picture containers in the byte order each format needs.
	"encoding/binary"
	// errors builds fixed error messages.
	"errors"
	// fmt builds messages.
	"fmt"
	// log reports why a tool failed (the page only says "failed").
	"log"
	// os writes and removes the launcher files.
	"os"
	// os/exec runs PowerShell.
	"os/exec"
	// path/filepath joins paths.
	"path/filepath"
	// strings builds and checks text.
	"strings"
	// time sets the limit for the tool.
	"time"
) // end of imports

// icoFileName is the Windows icon file kept in the data folder; the shortcut points at it.
const icoFileName = "icon.ico"

// The names of the launcher on each system.
const (
	// windowsLauncherName is a real Windows Shell Link.
	windowsLauncherName = "LLMsControlDock.lnk"
	// macLauncherName is an application bundle.
	macLauncherName = "LLMsControlDock.app"
) // end of the launcher names

// launcherName is the name of the launcher on the desktop of the given system.
func launcherName(goos string) string {
	// Pick by system.
	switch goos {
	// Windows.
	case "windows":
		// A shortcut file.
		return windowsLauncherName
	// macOS.
	case "darwin":
		// An application bundle.
		return macLauncherName
	// Linux and anything else: a Desktop Entry file.
	default:
		// The Linux launcher.
		return desktopFileName
	} // end of the switch
} // end of launcherName

// pngSize reads the width and height from the header of a PNG picture.
func pngSize(png []byte) (w, h uint32, err error) {
	// A PNG starts with an 8-byte signature and then the IHDR chunk, whose first two numbers are the width and the height (big-endian).
	if len(png) < 24 || !bytes.HasPrefix(png, []byte("\x89PNG\r\n\x1a\n")) || string(png[12:16]) != "IHDR" {
		// Not a PNG.
		return 0, 0, errors.New("the program icon is not a PNG picture")
	} // end of the signature check
	// The two numbers.
	return binary.BigEndian.Uint32(png[16:20]), binary.BigEndian.Uint32(png[20:24]), nil
} // end of pngSize

// pngToICO wraps a PNG picture in an ICO container (one image; PNG frames are supported from Windows Vista); a width or height of 256 is written as 0, as the format says.
func pngToICO(png []byte) ([]byte, error) {
	// The picture's size.
	w, h, err := pngSize(png)
	// A bad picture.
	if err != nil {
		// Report it.
		return nil, err
	} // end of the size check
	// An ICO frame holds at most 256 by 256 pixels.
	if w == 0 || h == 0 || w > 256 || h > 256 {
		// Refuse.
		return nil, fmt.Errorf("the program icon is %dx%d pixels; an ICO frame holds 1 to 256", w, h)
	} // end of the limit check
	// The byte that stands for a size: 0 means 256.
	size := func(v uint32) byte {
		// 256 is written as 0.
		if v == 256 {
			// Zero.
			return 0
		} // end of the 256 case
		// Otherwise the number itself.
		return byte(v)
	} // end of size
	// The container, all numbers little-endian.
	var b bytes.Buffer
	// ICONDIR: reserved 0, type 1 (icon), one image.
	binary.Write(&b, binary.LittleEndian, []uint16{0, 1, 1})
	// ICONDIRENTRY: width, height, colours 0, reserved 0.
	b.Write([]byte{size(w), size(h), 0, 0})
	// Planes 1 and 32 bits per pixel.
	binary.Write(&b, binary.LittleEndian, []uint16{1, 32})
	// The size of the image data and its offset (6 + 16 bytes of headers).
	binary.Write(&b, binary.LittleEndian, []uint32{uint32(len(png)), 22})
	// The PNG itself.
	b.Write(png)
	// Hand it back.
	return b.Bytes(), nil
} // end of pngToICO

// pngToICNS wraps a 256 by 256 PNG picture in an Apple icon container: the 'icns' header, then one 'ic08' element (256x256, PNG data); all numbers are big-endian.
func pngToICNS(png []byte) ([]byte, error) {
	// The picture's size.
	w, h, err := pngSize(png)
	// A bad picture.
	if err != nil {
		// Report it.
		return nil, err
	} // end of the size check
	// The 'ic08' element is defined for 256 by 256 pixels.
	if w != 256 || h != 256 {
		// Refuse.
		return nil, fmt.Errorf("the program icon is %dx%d pixels; the icon file needs 256x256", w, h)
	} // end of the size check
	// The container.
	var b bytes.Buffer
	// The magic and the total length (8 bytes header + 8 bytes element header + data).
	b.WriteString("icns")
	// The length.
	binary.Write(&b, binary.BigEndian, uint32(16+len(png)))
	// The element: its type and its length (including its own 8 bytes).
	b.WriteString("ic08")
	// The element length.
	binary.Write(&b, binary.BigEndian, uint32(8+len(png)))
	// The PNG.
	b.Write(png)
	// Hand it back.
	return b.Bytes(), nil
} // end of pngToICNS

// shQuote quotes text for a POSIX shell: inside single quotes nothing is special, and a single quote itself is written as '\”.
func shQuote(s string) string {
	// Wrap and escape.
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
} // end of shQuote

// macScript is the program inside the application bundle: it starts the program with -launch, which starts the monitor if needed and opens the page.
func macScript(exe string) string {
	// A shell script; exec replaces the shell by the program.
	return "#!/bin/sh\n# Starts LLMsControlDock (the monitor if needed) and opens the page in the browser.\nexec " + shQuote(exe) + " -launch\n"
} // end of macScript

// macInfoPlist is the property list that makes the folder an application bundle (Apple's standard keys).
func macInfoPlist() string {
	// The XML property list; every value is a fixed text of this program.
	return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>LLMsControlDock</string>
	<key>CFBundleDisplayName</key><string>LLMsControlDock</string>
	<key>CFBundleIdentifier</key><string>com.termgate.llmscontroldock</string>
	<key>CFBundleExecutable</key><string>LLMsControlDock</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleIconFile</key><string>icon</string>
	<key>CFBundleShortVersionString</key><string>` + appVersion + `</string>
	<key>CFBundleVersion</key><string>` + appVersion + `</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
`
} // end of macInfoPlist

// winShortcutScript makes the shortcut; the paths arrive in environment variables, so no path is ever pasted into the script and a path with spaces or quotes cannot change what it does.
const winShortcutScript = `$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:OCC_LINK);` +
	`$s.TargetPath=$env:OCC_EXE;$s.Arguments='-launch';$s.WorkingDirectory=$env:OCC_WORKDIR;` +
	`$s.IconLocation=$env:OCC_ICON;$s.Description='Monitor and control Ollama';$s.WindowStyle=7;$s.Save()`

// realToolRun runs a tool with extra environment variables and waits at most twenty seconds; a failure carries what the tool printed (it goes to the log, never to the page).
func realToolRun(exe string, env []string, args ...string) error {
	// Never wait long.
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	// Release the timer at the end.
	defer cancel()
	// The command.
	cmd := exec.CommandContext(ctx, exe, args...)
	// The program's environment plus the extra variables.
	cmd.Env = append(os.Environ(), env...)
	// Run it.
	out, err := cmd.CombinedOutput()
	// A failure.
	if err != nil {
		// Say why in the log.
		log.Printf("desktop shortcut tool failed: %v: %s", err, strings.TrimSpace(string(out)))
		// Report it.
		return err
	} // end of the failure check
	// Done.
	return nil
} // end of realToolRun

// resolvedExe returns the running program's own file with links resolved, refusing text that cannot be a normal path.
func (d desktopIcon) resolvedExe() (string, error) {
	// The program's own file.
	exe, err := d.env.exePath()
	// Report a failure.
	if err != nil {
		// Report it.
		return "", err
	} // end of the program check
	// The real file.
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		// Use it.
		exe = resolved
	} // end of the link check
	// It must be an absolute path without control characters.
	if !filepath.IsAbs(exe) || strings.ContainsAny(exe, "\x00\r\n") {
		// Refuse.
		return "", errUnusualPath
	} // end of the path check
	// Fine.
	return exe, nil
} // end of resolvedExe

// createWindows writes the icon file and makes the shortcut with Windows PowerShell (the Windows Script Host shortcut object), then remembers the answer.
func (d desktopIcon) createWindows(dir string) error {
	// The program.
	exe, err := d.resolvedExe()
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the program check
	// The icon file made from the program's picture.
	ico, err := pngToICO(appIcon)
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the icon check
	// Write it where the shortcut can find it.
	if err := writeFile(d.iconDir(), icoFileName, ico); err != nil {
		// Report it.
		return err
	} // end of the write check
	// Where the shortcut goes.
	link := filepath.Join(dir, windowsLauncherName)
	// Without a way to run tools there is nothing more to do.
	if d.env.run == nil {
		// Not supported.
		return errDesktopUnsupported
	} // end of the tool check
	// Make it; the icon location is the file and the number of the picture inside it.
	if err := d.env.run(powershellPath(), []string{"OCC_LINK=" + link, "OCC_EXE=" + exe, "OCC_WORKDIR=" + filepath.Dir(exe), "OCC_ICON=" + filepath.Join(d.iconDir(), icoFileName) + ",0"}, "-NoProfile", "-NonInteractive", "-Command", winShortcutScript); err != nil {
		// Report it.
		return err
	} // end of the tool check
	// The tool can succeed without writing the file (for example when a security program blocks it); check.
	if _, err := os.Stat(link); err != nil {
		// Report it.
		return errors.New("the shortcut file was not created")
	} // end of the file check
	// Remember the answer.
	return d.remember("created")
} // end of createWindows

// createMac writes the application bundle on the desktop: Info.plist, the starting script and the icon, then remembers the answer.
func (d desktopIcon) createMac(dir string) error {
	// The program.
	exe, err := d.resolvedExe()
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the program check
	// The icon container.
	icns, err := pngToICNS(appIcon)
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the icon check
	// The bundle's folder.
	app := filepath.Join(dir, macLauncherName)
	// Start fresh: an older bundle of ours is replaced (the name is fixed, so nothing else can be removed).
	if err := os.RemoveAll(app); err != nil {
		// Report it.
		return err
	} // end of the clean-up check
	// The two folders inside.
	for _, sub := range []string{"Contents/MacOS", "Contents/Resources"} {
		// Make one.
		if err := os.MkdirAll(filepath.Join(app, filepath.FromSlash(sub)), 0o755); err != nil {
			// Report it.
			return err
		} // end of the folder check
	} // end of the folder loop
	// The files: the property list, the icon and the starting script (which needs the executable bit).
	for _, f := range []struct {
		// path is relative to the bundle.
		path string
		// data is the content.
		data []byte
		// mode is the file mode.
		mode os.FileMode
	}{
		// The property list.
		{"Contents/Info.plist", []byte(macInfoPlist()), 0o644},
		// The icon.
		{"Contents/Resources/icon.icns", icns, 0o644},
		// The script; it is named like CFBundleExecutable.
		{"Contents/MacOS/LLMsControlDock", []byte(macScript(exe)), 0o755},
	} { // end of the file list
		// Write it.
		if err := os.WriteFile(filepath.Join(app, filepath.FromSlash(f.path)), f.data, f.mode); err != nil {
			// Report it.
			return err
		} // end of the write check
		// The mode is set again, because the umask may have removed the executable bit.
		if err := os.Chmod(filepath.Join(app, filepath.FromSlash(f.path)), f.mode); err != nil {
			// Report it.
			return err
		} // end of the chmod check
	} // end of the file loop
	// Remember the answer.
	return d.remember("created")
} // end of createMac

// removeLauncher deletes the launcher on the desktop; a missing one is fine, and a bundle is removed only when it carries the program's own name.
func removeLauncher(path string) error {
	// A bundle is a folder.
	if base := filepath.Base(path); base == macLauncherName || base == legacyMacLauncherName {
		// Delete it with everything in it.
		return os.RemoveAll(path)
	} // end of the bundle case
	// A file; a missing one is fine.
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		// Report it.
		return err
	} // end of the delete check
	// Done.
	return nil
} // end of removeLauncher
