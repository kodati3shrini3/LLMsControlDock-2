// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the messages.
	"fmt"
	// io copies a file.
	"io"
	// os reads and writes the folders and files.
	"os"
	// path/filepath joins the folder and file names.
	"path/filepath"
	// regexp recognises the file names this program writes.
	"regexp"
	// strings checks name beginnings and endings.
	"strings"
) // end of imports

// dataFolderName is the folder, inside the person's configuration folder, that holds everything the program saves (settings, results, deleted models, snapshots, saved copies).
const dataFolderName = "OllamaControlCenter"

// maxMigrateBytes is the largest file that is copied from an old folder; a bigger file is never one of this program's own.
var maxMigrateBytes int64 = 100 << 20

// dataRoot returns the one folder where all saved data lives on every operating system: OllamaControlCenter inside the configuration folder (Linux: ~/.config, Windows: %AppData%, macOS: ~/Library/Application Support); it returns empty text when no configuration folder is known.
func dataRoot() string {
	// Ask Go for the configuration folder (a test replaces userConfigDir).
	dir, err := userConfigDir()
	// None found.
	if err != nil || dir == "" {
		// The caller keeps the data in memory and says why.
		return ""
	} // end of the lookup check
	// The program's own folder inside it.
	return filepath.Join(dir, dataFolderName)
} // end of dataRoot

// oldDataRoot returns the folder earlier versions used for the saved data: the folder the program is in, or the folder above it when the program sits in a folder called bin; it returns empty text when the program's place is unknown.
func oldDataRoot() string {
	// Where is the running program?
	exe, err := executablePath()
	// Unknown.
	if err != nil || exe == "" {
		// Nothing to look at.
		return ""
	} // end of the program check
	// The folder that holds it.
	dir := filepath.Dir(exe)
	// A program inside bin belongs to the project folder above it.
	if filepath.Base(dir) == "bin" {
		// Go one level up.
		dir = filepath.Dir(dir)
	} // end of the bin check
	// The old data folder.
	return dir
} // end of oldDataRoot

// stampedName matches the names this program gives to the files it saves with a date: 2026-11-02_17-54-00...
var stampedName = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}`)

// looksOurs says whether a file name is one this program writes (and so may be copied): the results file, the deleted-models file, a dated snapshot, or a saved copy of a download; and only the kinds of file it writes.
func looksOurs(name string) bool {
	// Only these kinds of file are ever written.
	ext := strings.ToLower(filepath.Ext(name))
	// Anything else is somebody else's file.
	if ext != ".json" && ext != ".csv" && ext != ".pdf" {
		// Not ours.
		return false
	} // end of the kind check
	// The two fixed names, the saved copies and the dated files.
	return name == "performance.json" || name == deletedFileName || strings.HasPrefix(name, "OllamaControlCenter-") || stampedName.MatchString(name)
} // end of looksOurs

// copyOne copies one file into a new file that only this user can read; an existing file is never overwritten.
func copyOne(src, dst string) error {
	// Open the source.
	in, err := os.Open(src)
	// Not readable.
	if err != nil {
		// Give up with the reason.
		return err
	} // end of the open check
	// Close it at the end.
	defer in.Close()
	// Create the target; O_EXCL refuses an existing file.
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	// Cannot create.
	if err != nil {
		// Give up with the reason.
		return err
	} // end of the create check
	// Copy the bytes.
	if _, err := io.Copy(out, in); err != nil {
		// Close and give up.
		out.Close()
		// The reason.
		return err
	} // end of the copy check
	// Closing is where a full disk shows up.
	return out.Close()
} // end of copyOne

// migrateFolder copies this program's own files from an old folder into the new one, once: it does nothing when the old folder is missing, holds none of this program's files, or the new folder exists already; the old folder is never changed. It returns a sentence for the log, or empty text.
func migrateFolder(oldDir, newDir string) string {
	// Is there an old folder?
	if st, err := os.Stat(oldDir); err != nil || !st.IsDir() {
		// None: nothing to do.
		return ""
	} // end of the old-folder check
	// The new folder exists already: it is never touched, and this also makes the copy happen only once.
	if _, err := os.Lstat(newDir); err == nil {
		// Nothing to do.
		return ""
	} // end of the new-folder check
	// What is in the old folder.
	entries, err := os.ReadDir(oldDir)
	// Unreadable: leave it.
	if err != nil {
		// Nothing to do.
		return ""
	} // end of the read check
	// The files to copy.
	var names []string
	// Look at each entry.
	for _, e := range entries {
		// Only plain files of this program's kind, of a sensible size.
		if info, err := e.Info(); err == nil && e.Type().IsRegular() && looksOurs(e.Name()) && info.Size() <= maxMigrateBytes {
			// Keep it.
			names = append(names, e.Name())
		} // end of the file check
	} // end of the entry loop
	// None of this program's files: the folder belongs to somebody else.
	if len(names) == 0 {
		// Nothing to do.
		return ""
	} // end of the empty check
	// Make sure the parent folder exists.
	if err := os.MkdirAll(filepath.Dir(newDir), 0o700); err != nil {
		// Say so; the old data stays where it is.
		return fmt.Sprintf("Saved data could not be copied from %s (%v); it was left where it is.", oldDir, err)
	} // end of the parent check
	// Copy into a temporary folder first, so a half copy is never mistaken for the real one.
	tmp := newDir + ".copying"
	// A leftover from an earlier attempt is this program's own and is removed.
	os.RemoveAll(tmp)
	// Make it, readable only by this user.
	if err := os.Mkdir(tmp, 0o700); err != nil {
		// Say so.
		return fmt.Sprintf("Saved data could not be copied from %s (%v); it was left where it is.", oldDir, err)
	} // end of the temporary-folder check
	// Copy each file.
	for _, n := range names {
		// One file.
		if err := copyOne(filepath.Join(oldDir, n), filepath.Join(tmp, n)); err != nil {
			// Throw the half copy away.
			os.RemoveAll(tmp)
			// Say so.
			return fmt.Sprintf("Saved data could not be copied from %s (%v); it was left where it is.", oldDir, err)
		} // end of the copy check
	} // end of the copy loop
	// Put the finished copy in its place in one step.
	if err := os.Rename(tmp, newDir); err != nil {
		// Throw the copy away.
		os.RemoveAll(tmp)
		// Say so.
		return fmt.Sprintf("Saved data could not be copied from %s (%v); it was left where it is.", oldDir, err)
	} // end of the rename check
	// Done: tell the person where things are now.
	return fmt.Sprintf("Copied %d saved file(s) from %s to %s; the old folder was left in place and can be deleted when it is no longer needed.", len(names), oldDir, newDir)
} // end of migrateFolder

// migrateOldData copies the three folders of earlier versions (results, deleted models, snapshots) from the old place to the new one; it returns the sentences for the log.
func migrateOldData(oldRoot, newRoot string) []string {
	// Unknown places, or the same place: nothing to do.
	if oldRoot == "" || newRoot == "" || oldRoot == newRoot {
		// Nothing to do.
		return nil
	} // end of the place check
	// The sentences.
	var msgs []string
	// The three folders earlier versions kept next to the program.
	for _, name := range []string{historyFolderName, deletedFolderName, historyDirName} {
		// Copy one.
		if msg := migrateFolder(filepath.Join(oldRoot, name), filepath.Join(newRoot, name)); msg != "" {
			// Keep the sentence.
			msgs = append(msgs, msg)
		} // end of the message check
	} // end of the folder loop
	// Hand them back.
	return msgs
} // end of migrateOldData
