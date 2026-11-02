// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// encoding/json reads and writes the history file.
	"encoding/json"
	// errors builds plain error values.
	"errors"
	// fmt builds formatted text.
	"fmt"
	// os reads and writes the file.
	"os"
	// path/filepath joins folder and file names.
	"path/filepath"
	// sync keeps two requests from changing the history at the same moment.
	"sync"
) // end of imports

// historyFileVersion is the format number written into the file, so a future version can tell old files apart.
const historyFileVersion = 1

// maxHistoryFile is the largest history file the monitor will read (8 MiB, far more than 200 runs need).
const maxHistoryFile = 8 * 1024 * 1024

// userConfigDir finds the base folder for configuration (see baseDirFor in datafolder.go); a test replaces it so it never touches the real one.
var userConfigDir = osUserConfigDir

// historyFile is the shape of the file on disk.
type historyFile struct {
	// Version is historyFileVersion.
	Version int `json:"version"`
	// Runs holds the saved runs, oldest first.
	Runs []perfRun `json:"runs"`
} // end of historyFile

// perfStore keeps the saved test runs: in memory always, and in a file when the file can be used.
type perfStore struct {
	// mu protects everything below.
	mu sync.Mutex
	// path is the file; empty means memory only.
	path string
	// runs holds the runs, oldest first.
	runs []perfRun
	// note says why the file is not used (empty when all is well).
	note string
} // end of perfStore

// historyFolderName is the folder, inside the data folder, that holds the saved performance results.
const historyFolderName = "performanceCompare"

// oldHistoryFolderName is the name earlier versions used for that folder (with a capital P); a folder with this name is moved to the new name once.
const oldHistoryFolderName = "PerformanceCompare"

// moveOldHistoryFolder renames the folder of earlier versions (PerformanceCompare) to the current name, so saved results and copies are not left behind; it does nothing when there is no old folder or the new one exists already (that includes computers that do not tell the two names apart). The returned text is empty when all is well, or says in plain words what happened.
func moveOldHistoryFolder(historyPath string) string {
	// No file path: memory only, nothing to move.
	if historyPath == "" {
		// Nothing to do.
		return ""
	} // end of the memory check
	// The current results folder.
	newDir := filepath.Dir(historyPath)
	// Only the project's own folder is touched, never a fallback folder.
	if filepath.Base(newDir) != historyFolderName {
		// Nothing to do.
		return ""
	} // end of the name check
	// The folder of earlier versions, beside it.
	oldDir := filepath.Join(filepath.Dir(newDir), oldHistoryFolderName)
	// Is there an old folder?
	if st, err := os.Stat(oldDir); err != nil || !st.IsDir() {
		// None: leave everything as it is.
		return ""
	} // end of the old-folder check
	// The new name exists already (or is the same folder on a computer that ignores capitals): leave both alone.
	if _, err := os.Lstat(newDir); err == nil {
		// Say it only when they really are two folders.
		if os.SameFile(mustStat(oldDir), mustStat(newDir)) {
			// The same folder: nothing to say.
			return ""
		} // end of the same-folder check
		// Two folders: the person should look.
		return "Both " + oldDir + " and " + newDir + " exist; the old one was left alone. Move its files by hand if you need them."
	} // end of the new-folder check
	// Rename the folder (same disk, so this is one step).
	if err := os.Rename(oldDir, newDir); err != nil {
		// The old folder stays where it is.
		return "The results folder could not be renamed to " + newDir + " (" + err.Error() + "); the old folder was left where it is."
	} // end of the rename check
	// Done.
	return ""
} // end of moveOldHistoryFolder

// mustStat returns the file information of a path that was just found to exist; a failure gives nil, which SameFile treats as "not the same".
func mustStat(p string) os.FileInfo {
	// Look at it.
	st, err := os.Stat(p)
	// A failure.
	if err != nil {
		// Nothing to compare.
		return nil
	} // end of the check
	// The information.
	return st
} // end of mustStat

// executablePath finds the running program; a test replaces it.
var executablePath = os.Executable

// defaultHistoryPath returns the results file: in a folder named performanceCompare inside the program's data folder (each system's standard place for data, see datafolder.go); an empty text and a reason mean memory only.
func defaultHistoryPath() (string, string) {
	// The one data folder.
	root := dataRoot()
	// None found.
	if root == "" {
		// Memory only.
		return "", "No folder for the results was found, so they are kept only until the monitor stops."
	} // end of the lookup check
	// The results live in their own folder there.
	return filepath.Join(root, historyFolderName, "performance.json"), ""
} // end of defaultHistoryPath

// openPerfStore opens the history at the given path (an empty path means memory only); a file that cannot be read is left untouched and the store stays in memory.
func openPerfStore(path, note string) *perfStore {
	// The store starts empty.
	s := &perfStore{path: path, note: note}
	// Memory only: nothing to read.
	if path == "" {
		// Done.
		return s
	} // end of the memory case
	// Look at the file.
	info, err := os.Stat(path)
	// No file yet is normal.
	if errors.Is(err, os.ErrNotExist) {
		// Start empty.
		return s
	} // end of the missing-file case
	// Some other problem with the file.
	if err != nil {
		// Keep the file untouched.
		s.path, s.note = "", "The history file could not be opened ("+err.Error()+"), so results are kept only until the monitor stops."
		// Done.
		return s
	} // end of the stat check
	// A file that is far too large is not ours.
	if info.Size() > maxHistoryFile {
		// Keep the file untouched.
		s.path, s.note = "", "The history file is unusually large, so it was left alone and results are kept only until the monitor stops."
		// Done.
		return s
	} // end of the size check
	// Read it.
	data, err := os.ReadFile(path)
	// A read problem.
	if err != nil {
		// Keep the file untouched.
		s.path, s.note = "", "The history file could not be read ("+err.Error()+"), so results are kept only until the monitor stops."
		// Done.
		return s
	} // end of the read check
	// Decode it.
	var h historyFile
	// A damaged or foreign file.
	if err := json.Unmarshal(data, &h); err != nil || h.Version != historyFileVersion {
		// Keep the file untouched, so nothing is lost.
		s.path, s.note = "", "The history file is damaged or from another version, so it was left alone and results are kept only until the monitor stops."
		// Done.
		return s
	} // end of the decode check
	// Use the saved runs.
	s.runs = h.Runs
	// Done.
	return s
} // end of openPerfStore

// writeLocked writes the file (the caller holds the lock): a temporary file in the same folder, then a rename, so a crash never leaves half a file.
func (s *perfStore) writeLocked() error {
	// Memory only: nothing to write.
	if s.path == "" {
		// Not an error.
		return nil
	} // end of the memory case
	// The folder, private to the person.
	dir := filepath.Dir(s.path)
	// Create it when missing.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		// Say why.
		return fmt.Errorf("the history folder could not be created: %w", err)
	} // end of the folder check
	// Encode the runs (an empty list is written as an empty list, not null).
	runs := s.runs
	// Avoid null.
	if runs == nil {
		// Empty list.
		runs = []perfRun{}
	} // end of the nil check
	// The file text.
	data, err := json.MarshalIndent(historyFile{Version: historyFileVersion, Runs: runs}, "", "  ")
	// Cannot happen with these types.
	if err != nil {
		// Say why.
		return fmt.Errorf("the history could not be encoded: %w", err)
	} // end of the encode check
	// A temporary file next to the real one.
	tmp, err := os.CreateTemp(dir, "performance-*.tmp")
	// Could not create it.
	if err != nil {
		// Say why.
		return fmt.Errorf("the history file could not be written: %w", err)
	} // end of the create check
	// Remove the temporary file if anything below fails (after a successful rename it no longer exists).
	defer os.Remove(tmp.Name())
	// Only the person may read it.
	if err := tmp.Chmod(0o600); err != nil {
		// Close and report.
		tmp.Close()
		// Say why.
		return fmt.Errorf("the history file could not be protected: %w", err)
	} // end of the chmod check
	// Write the text.
	if _, err := tmp.Write(data); err != nil {
		// Close and report.
		tmp.Close()
		// Say why.
		return fmt.Errorf("the history file could not be written: %w", err)
	} // end of the write check
	// Close it so everything reaches the disk.
	if err := tmp.Close(); err != nil {
		// Say why.
		return fmt.Errorf("the history file could not be written: %w", err)
	} // end of the close check
	// Replace the real file in one step.
	if err := os.Rename(tmp.Name(), s.path); err != nil {
		// Say why.
		return fmt.Errorf("the history file could not be replaced: %w", err)
	} // end of the rename check
	// Saved.
	return nil
} // end of writeLocked

// add appends one run, drops the oldest beyond the limit, and saves; the run is kept in memory even when the file cannot be written.
func (s *perfStore) add(r perfRun) error {
	// One change at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Append.
	s.runs = append(s.runs, r)
	// Drop the oldest ones beyond the limit.
	if len(s.runs) > maxHistoryRuns {
		// Keep the newest.
		s.runs = append([]perfRun(nil), s.runs[len(s.runs)-maxHistoryRuns:]...)
	} // end of the limit check
	// Save.
	return s.writeLocked()
} // end of add

// forModel returns the runs of one model and kind, newest first.
func (s *perfStore) forModel(model, kind string) []perfRun {
	// One reader at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// The result.
	var out []perfRun
	// Walk from the newest to the oldest.
	for i := len(s.runs) - 1; i >= 0; i-- {
		// A match.
		if s.runs[i].Model == model && s.runs[i].Kind == kind {
			// Keep it.
			out = append(out, s.runs[i])
		} // end of the match check
	} // end of the loop
	// Hand them back.
	return out
} // end of forModel

// count says how many runs are saved in all.
func (s *perfStore) count() int {
	// One reader at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// The number.
	return len(s.runs)
} // end of count

// where describes where the history lives, for the page.
func (s *perfStore) where() (path, note string) {
	// One reader at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Both values.
	return s.path, s.note
} // end of where

// clear removes every saved run and saves the empty history.
func (s *perfStore) clear() error {
	// One change at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Forget everything.
	s.runs = nil
	// Save.
	return s.writeLocked()
} // end of clear
