// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors builds fixed error messages.
	"errors"
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
	// runtime tells which operating system this is.
	"runtime"
	// strings checks name beginnings and endings.
	"strings"
) // end of imports

// dataFolderName is the program's own folder inside each of the three base folders (config, data, state).
const dataFolderName = "LLMsControlDock"

// maxMigrateBytes is the largest file that is copied from an old folder; a bigger file is never one of this program's own.
var maxMigrateBytes int64 = 100 << 20

// The three kinds of saved file, as the Linux XDG Base Directory Specification names them: configuration (what the person chose), data (what the person created) and state (what the program can reuse on a restart, such as logs and history).
const (
	// kindConfig is for settings.
	kindConfig = "config"
	// kindData is for results, saved copies, deleted models and snapshots.
	kindData = "data"
	// kindState is for the check history and the log.
	kindState = "state"
) // end of the kinds

// baseDirFor returns the base folder for one kind on one operating system, following that system's own standard; the program's own folder is added by the caller. Linux and other Unix systems follow the XDG Base Directory Specification (a variable that is empty or not an absolute path is ignored, as the specification says); Windows keeps configuration in %AppData% and data and state in %LocalAppData%; macOS keeps all three in ~/Library/Application Support. The operating system and the lookups are parameters so that a test can try every system.
func baseDirFor(goos, kind string, getenv func(string) string, home func() (string, error)) (string, error) {
	// Pick the system.
	switch goos {
	// Windows: configuration roams with the user, data and state stay on this computer.
	case "windows":
		// Data and state live in the local folder.
		name := "LocalAppData"
		// Configuration lives in the roaming folder.
		if kind == kindConfig {
			// The roaming folder.
			name = "AppData"
		} // end of the configuration check
		// Read the variable.
		dir := getenv(name)
		// Not defined.
		if dir == "" {
			// A fixed message.
			return "", errors.New("%" + name + "% is not defined")
		} // end of the variable check
		// The folder.
		return dir, nil
	// macOS: one folder for all kinds, as Apple's File System Programming Guide describes.
	case "darwin", "ios":
		// The person's home folder.
		h, err := home()
		// Not known.
		if err != nil || h == "" {
			// A fixed message.
			return "", errors.New("$HOME is not defined")
		} // end of the home check
		// The folder.
		return h + "/Library/Application Support", nil
	} // end of the system switch
	// Linux and the others: the XDG variable and its default for this kind.
	envName, rel := "XDG_CONFIG_HOME", "/.config"
	// Data.
	if kind == kindData {
		// The data variable and default.
		envName, rel = "XDG_DATA_HOME", "/.local/share"
	} // end of the data check
	// State.
	if kind == kindState {
		// The state variable and default.
		envName, rel = "XDG_STATE_HOME", "/.local/state"
	} // end of the state check
	// A variable that holds an absolute path is used as it is; anything else is ignored, as the specification says.
	if v := getenv(envName); strings.HasPrefix(v, "/") {
		// The person's choice.
		return v, nil
	} // end of the variable check
	// The default below the home folder.
	h, err := home()
	// Not known.
	if err != nil || h == "" {
		// A fixed message.
		return "", errors.New("neither $" + envName + " nor $HOME is defined")
	} // end of the home check
	// The folder.
	return h + rel, nil
} // end of baseDirFor

// osUserBaseDir asks baseDirFor about the real system for one kind.
func osUserBaseDir(kind string) (string, error) {
	// The real system, the real environment and the real home folder.
	return baseDirFor(runtime.GOOS, kind, os.Getenv, os.UserHomeDir)
} // end of osUserBaseDir

// osUserConfigDir is the real configuration base folder.
func osUserConfigDir() (string, error) {
	// Ask for the configuration kind.
	return osUserBaseDir(kindConfig)
} // end of osUserConfigDir

// osUserDataDir is the real data base folder.
func osUserDataDir() (string, error) {
	// Ask for the data kind.
	return osUserBaseDir(kindData)
} // end of osUserDataDir

// osUserStateDir is the real state base folder.
func osUserStateDir() (string, error) {
	// Ask for the state kind.
	return osUserBaseDir(kindState)
} // end of osUserStateDir

// The two lookups that are not in perfstore.go; a test replaces them so it never touches the real folders.
var (
	// userDataDir finds the base folder for data.
	userDataDir = osUserDataDir
	// userStateDir finds the base folder for state.
	userStateDir = osUserStateDir
) // end of the lookups

// rootOf adds the program's own folder to a base folder; it returns empty text when no base folder is known.
func rootOf(lookup func() (string, error)) string {
	// Ask.
	dir, err := lookup()
	// None found.
	if err != nil || dir == "" {
		// The caller keeps the data in memory and says why.
		return ""
	} // end of the lookup check
	// The program's own folder inside it.
	return filepath.Join(dir, dataFolderName)
} // end of rootOf

// configRoot is the folder of the settings and the desktop-icon choice.
func configRoot() string {
	// The configuration base.
	return rootOf(userConfigDir)
} // end of configRoot

// dataRoot is the folder of the results, the saved copies, the deleted models and the snapshots.
func dataRoot() string {
	// The data base.
	return rootOf(userDataDir)
} // end of dataRoot

// stateRoot is the folder of the check history and the log.
func stateRoot() string {
	// The state base.
	return rootOf(userStateDir)
} // end of stateRoot

// oldDataRoot returns the folder the oldest versions used for the saved data: the folder the program is in, or the folder above it when the program sits in a folder called bin; it returns empty text when the program's place is unknown.
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
	return name == "performance.json" || name == deletedFileName || strings.HasPrefix(name, "LLMsControlDock-") || strings.HasPrefix(name, legacyAppName+"-") || stampedName.MatchString(name)
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

// migrateOldData copies the three data folders (results, deleted models, snapshots) of earlier versions into the data folder, once; the sources are tried in the order given (the first one that has the folder wins), and an unknown source, or one that is the data folder itself, is skipped. It returns the sentences for the log.
func migrateOldData(newRoot string, sources ...string) []string {
	// An unknown data folder: nothing to do.
	if newRoot == "" {
		// Nothing to do.
		return nil
	} // end of the place check
	// The sentences.
	var msgs []string
	// Each place earlier versions used.
	for _, src := range sources {
		// Unknown, or the same place: skip.
		if src == "" || src == newRoot {
			// Next source.
			continue
		} // end of the source check
		// The three folders earlier versions kept there.
		for _, name := range []string{historyFolderName, deletedFolderName, historyDirName} {
			// Copy one.
			if msg := migrateFolder(filepath.Join(src, name), filepath.Join(newRoot, name)); msg != "" {
				// Keep the sentence.
				msgs = append(msgs, msg)
			} // end of the message check
		} // end of the folder loop
	} // end of the source loop
	// Hand them back.
	return msgs
} // end of migrateOldData

// migrateFile copies one file of this program from an old place to a new one, once: it does nothing when the old file is missing, is not a plain file, is too large, or the new file exists already; the old file is never changed. It returns a sentence for the log, or empty text.
func migrateFile(oldPath, newPath string) string {
	// Look at the old file.
	st, err := os.Stat(oldPath)
	// Missing, not a plain file, or too large: nothing to do.
	if err != nil || !st.Mode().IsRegular() || st.Size() > maxMigrateBytes {
		// Nothing to do.
		return ""
	} // end of the old-file check
	// The new file exists already: it is never touched.
	if _, err := os.Lstat(newPath); err == nil {
		// Nothing to do.
		return ""
	} // end of the new-file check
	// Make sure the folder exists, readable only by this user.
	if err := os.MkdirAll(filepath.Dir(newPath), 0o700); err != nil {
		// Say so; the old file stays where it is.
		return fmt.Sprintf("%s could not be copied to %s (%v); it was left where it is.", oldPath, newPath, err)
	} // end of the folder check
	// Copy to a temporary name first, so a half copy is never mistaken for the real file.
	tmp := newPath + ".copying"
	// A leftover from an earlier attempt is this program's own and is removed.
	os.Remove(tmp)
	// Copy.
	if err := copyOne(oldPath, tmp); err != nil {
		// Throw the half copy away.
		os.Remove(tmp)
		// Say so.
		return fmt.Sprintf("%s could not be copied to %s (%v); it was left where it is.", oldPath, newPath, err)
	} // end of the copy check
	// Put the finished copy in its place in one step.
	if err := os.Rename(tmp, newPath); err != nil {
		// Throw the copy away.
		os.Remove(tmp)
		// Say so.
		return fmt.Sprintf("%s could not be copied to %s (%v); it was left where it is.", oldPath, newPath, err)
	} // end of the rename check
	// Done.
	return fmt.Sprintf("Copied %s to %s; the old file was left in place and can be deleted when it is no longer needed.", oldPath, newPath)
} // end of migrateFile

// migrateOldFiles copies the two single files that earlier versions kept in the configuration folder to their proper folders: the check history to the state folder and the icon picture to the data folder. Unknown or equal folders are skipped (on macOS all three folders are the same).
func migrateOldFiles(config, data, state string) []string {
	// The sentences.
	var msgs []string
	// The check history belongs in the state folder.
	if config != "" && state != "" && config != state {
		// Copy it.
		if msg := migrateFile(filepath.Join(config, checkHistoryFileName), filepath.Join(state, checkHistoryFileName)); msg != "" {
			// Keep the sentence.
			msgs = append(msgs, msg)
		} // end of the message check
	} // end of the history check
	// The icon picture belongs in the data folder.
	if config != "" && data != "" && config != data {
		// Copy it.
		if msg := migrateFile(filepath.Join(config, iconFileName), filepath.Join(data, iconFileName)); msg != "" {
			// Keep the sentence.
			msgs = append(msgs, msg)
		} // end of the message check
	} // end of the icon check
	// Hand them back.
	return msgs
} // end of migrateOldFiles
