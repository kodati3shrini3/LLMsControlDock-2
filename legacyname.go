// Package main tells Go that this folder builds into a runnable program.
package main

// Imports: the standard library only.
import (
	// fmt builds the sentences for the log.
	"fmt"
	// os renames folders and looks at files.
	"os"
	// path/filepath joins folder and file names.
	"path/filepath"
) // end of imports

// Before version 0.31.0 the program was called OllamaControlCenter. These are the names it used on a computer; this file renames them once, so nobody loses saved data or keeps two desktop icons.
const (
	// legacyAppName is the old program name; it was also the name of the program's own folder inside the config, data and state base folders.
	legacyAppName = "OllamaControlCenter"
	// legacyDesktopFileName is the old Linux desktop launcher.
	legacyDesktopFileName = "OllamaControlCenter.desktop"
	// legacyWindowsLauncherName is the old Windows shortcut.
	legacyWindowsLauncherName = "OllamaControlCenter.lnk"
	// legacyMacLauncherName is the old macOS application bundle.
	legacyMacLauncherName = "OllamaControlCenter.app"
) // end of the old names

// renameLegacyRoot renames one old program folder to the new name, once: nothing happens when the old folder is missing or is not a plain folder (a link is never followed), and the new folder is never touched when it exists already. It returns a sentence for the log, or empty text.
func renameLegacyRoot(oldDir, newDir string) string {
	// Look at the old folder without following a link.
	st, err := os.Lstat(oldDir)
	// Missing, a link, or not a folder: nothing to do.
	if err != nil || !st.IsDir() {
		// Nothing to do.
		return ""
	} // end of the old-folder check
	// Does the new folder exist already?
	if _, err := os.Lstat(newDir); err == nil {
		// Both exist: nothing is moved, and the person is told where the old data is.
		return fmt.Sprintf("An older folder %s was found next to %s and was left untouched; saved data from before the rename to LLMsControlDock is still in it.", oldDir, newDir)
	} // end of the new-folder check
	// Rename in one step; both folders are inside the same base folder, so this is a move, not a copy.
	if err := os.Rename(oldDir, newDir); err != nil {
		// Say so; the data stays where it is.
		return fmt.Sprintf("The folder %s could not be renamed to %s (%v); the saved data was left where it is.", oldDir, newDir, err)
	} // end of the rename check
	// Done: tell the person.
	return fmt.Sprintf("The program is now called LLMsControlDock: its folder %s was renamed to %s; nothing was lost.", oldDir, newDir)
} // end of renameLegacyRoot

// migrateLegacyRoots renames the old settings, data and state folders to the new name, once; on macOS the three are the same folder and it is renamed once. It returns the sentences for the log.
func migrateLegacyRoots() []string {
	// The sentences.
	var msgs []string
	// The folders already handled (macOS has one folder for all three kinds).
	seen := map[string]bool{}
	// The three new folders.
	for _, root := range []string{configRoot(), dataRoot(), stateRoot()} {
		// An unknown folder, or one handled already: skip.
		if root == "" || seen[root] {
			// Next folder.
			continue
		} // end of the skip check
		// Remember it.
		seen[root] = true
		// The old folder sits next to the new one, inside the same base folder.
		old := filepath.Join(filepath.Dir(root), legacyAppName)
		// Rename it.
		if msg := renameLegacyRoot(old, root); msg != "" {
			// Keep the sentence.
			msgs = append(msgs, msg)
		} // end of the message check
	} // end of the folder loop
	// Hand them back.
	return msgs
} // end of migrateLegacyRoots

// legacyLauncherPath is the full path of the old launcher on the desktop ("" when there is no desktop).
func (d desktopIcon) legacyLauncherPath() string {
	// The desktop folder.
	dir, ok := d.env.desktopDir()
	// None.
	if !ok {
		// No path.
		return ""
	} // end of the desktop check
	// The old name for this system.
	name := legacyDesktopFileName
	// Windows and macOS had their own kinds.
	switch d.env.goos {
	// A shortcut.
	case "windows":
		// Its name.
		name = legacyWindowsLauncherName
	// An application bundle.
	case "darwin":
		// Its name.
		name = legacyMacLauncherName
	} // end of the system switch
	// The path.
	return filepath.Join(dir, name)
} // end of legacyLauncherPath

// legacyLauncherExists says whether the old launcher is on the desktop now.
func (d desktopIcon) legacyLauncherExists() bool {
	// Its path.
	p := d.legacyLauncherPath()
	// No desktop, no launcher.
	if p == "" {
		// Not there.
		return false
	} // end of the path check
	// A plain existence check.
	_, err := os.Lstat(p)
	// There when the check worked.
	return err == nil
} // end of legacyLauncherExists

// removeLegacyLauncher deletes the old launcher if it is there; it is best effort, because the old launcher still starts the program, so a failure does no harm.
func (d desktopIcon) removeLegacyLauncher() {
	// Its path.
	p := d.legacyLauncherPath()
	// No desktop: nothing to remove.
	if p == "" {
		// Done.
		return
	} // end of the path check
	// Delete it; the result is ignored on purpose (see above).
	_ = removeLauncher(p)
} // end of removeLegacyLauncher

// migrateLegacyLauncher replaces an old launcher by one with the new name, but only for someone who chose to have a desktop icon: when the old launcher is there and the new one is not, the new one is made (which removes the old one); when both are there, the old one is removed. It returns a sentence for the log, or empty text.
func migrateLegacyLauncher(d desktopIcon) string {
	// Without a desktop there is nothing to do.
	if !d.available() || !d.legacyLauncherExists() {
		// Nothing to do.
		return ""
	} // end of the presence check
	// Both launchers exist: the old one is a duplicate.
	if d.exists() {
		// Remove the duplicate.
		d.removeLegacyLauncher()
		// Tell the person.
		return "The desktop icon under the old name OllamaControlCenter was removed; the LLMsControlDock icon stays."
	} // end of the duplicate case
	// Only someone who chose an icon gets a new one; the old file is left alone for everyone else.
	if d.choice() != "created" {
		// Nothing to do.
		return ""
	} // end of the choice check
	// Make the new launcher (this also removes the old one).
	if err := d.create(); err != nil {
		// Say so; the old launcher still works.
		return fmt.Sprintf("The desktop icon could not be renamed to LLMsControlDock (%v); the old icon still works.", err)
	} // end of the create check
	// Done.
	return "The desktop icon was renamed to LLMsControlDock."
} // end of migrateLegacyLauncher
