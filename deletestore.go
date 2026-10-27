// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// encoding/json reads and writes the small file of deleted models.
	"encoding/json"
	// errors tells "file does not exist" apart from other problems.
	"errors"
	// fmt builds the error texts.
	"fmt"
	// os reads and writes the file.
	"os"
	// path/filepath builds file paths for any operating system.
	"path/filepath"
	// sort keeps the list in a steady order (newest deletion first).
	"sort"
	// sync lets several requests use the list safely.
	"sync"
	// time stamps the deletion.
	"time"
) // end of imports

// deletedFileVersion is written into the file so a future version of the program can recognise an older layout.
const deletedFileVersion = 1

// deletedFileName is the file that remembers deleted models.
const deletedFileName = "deleted-models.json"

// deletedFolderName is the folder, next to the project, that holds that file; the .gitignore keeps it out of GitHub (requirement S4).
const deletedFolderName = "deletedHistory"

// maxDeletedFile is the biggest file that will be read; a normal list is a few kilobytes.
const maxDeletedFile = 1 * 1024 * 1024

// deletedModel is what the monitor remembers about one model it deleted, so the table can show it greyed out and Restore can offer it again.
type deletedModel struct {
	// Name is the model name with its tag, for example "gemma3:4b".
	Name string `json:"name"`
	// Digest is the model's fingerprint at deletion time (shown on the restore page so a later re-download can be compared).
	Digest string `json:"digest"`
	// Size is the size on disk in bytes, so the person sees how much space was freed and how much a download will need.
	Size int64 `json:"size"`
	// DeletedAt is the moment of deletion.
	DeletedAt time.Time `json:"deleted_at"`
} // end of deletedModel

// deletedFile is the layout of the file on disk.
type deletedFile struct {
	// Version is deletedFileVersion.
	Version int `json:"version"`
	// Models is the list.
	Models []deletedModel `json:"models"`
} // end of deletedFile

// deletedStore keeps the list in memory and, when there is a path, on disk.
type deletedStore struct {
	// mu protects the list.
	mu sync.Mutex
	// path is the file; empty means the list is kept only until the monitor stops.
	path string
	// items is the list.
	items []deletedModel
	// note explains, in plain words, why the list is only kept in memory (empty when all is well).
	note string
} // end of deletedStore

// deletedPathFor puts the file in its own folder, deletedHistory, next to the performanceCompare folder (that is, in the project folder); when the results are not in a performanceCompare folder, the folder goes beside the results file instead; an empty history path gives an empty path.
func deletedPathFor(historyPath string) string {
	// No folder was found for the history, so none for this file either.
	if historyPath == "" {
		// Memory only.
		return ""
	} // end of the memory case
	// The folder of the results.
	resultsDir := filepath.Dir(historyPath)
	// A results folder named performanceCompare sits in the project folder; the new folder goes beside it.
	if filepath.Base(resultsDir) == historyFolderName {
		// Go up one level.
		resultsDir = filepath.Dir(resultsDir)
	} // end of the folder check
	// Own folder, then the file name.
	return filepath.Join(resultsDir, deletedFolderName, deletedFileName)
} // end of deletedPathFor

// moveOldDeletedFile moves the list from the place earlier versions used (next to the performance results) to the new folder, so nothing already remembered is lost; it does nothing when there is no old file or the new file exists already. The returned text is empty when all is well, or says in plain words what went wrong.
func moveOldDeletedFile(historyPath string) string {
	// No history path: nothing to move.
	if historyPath == "" {
		// Nothing to do.
		return ""
	} // end of the memory case
	// Where earlier versions kept the file.
	oldPath := filepath.Join(filepath.Dir(historyPath), deletedFileName)
	// Where it belongs now.
	newPath := deletedPathFor(historyPath)
	// The same place: nothing to move.
	if oldPath == newPath {
		// Nothing to do.
		return ""
	} // end of the same-place check
	// Is there an old file?
	if _, err := os.Stat(oldPath); err != nil {
		// None (or unreadable): leave everything as it is.
		return ""
	} // end of the old-file check
	// A new file is never overwritten.
	if _, err := os.Stat(newPath); err == nil {
		// Leave both alone.
		return ""
	} // end of the new-file check
	// The new folder, readable only by this user.
	if err := os.MkdirAll(filepath.Dir(newPath), 0o700); err != nil {
		// The old file stays where it is.
		return "The list of deleted models could not be moved to its new folder (" + err.Error() + "); the old file was left where it is."
	} // end of the folder check
	// Move the file (same disk, so this is one step).
	if err := os.Rename(oldPath, newPath); err != nil {
		// The old file stays where it is.
		return "The list of deleted models could not be moved to its new folder (" + err.Error() + "); the old file was left where it is."
	} // end of the move check
	// Done.
	return ""
} // end of moveOldDeletedFile

// openDeletedStore reads the file if there is one; a missing file is normal (nothing deleted yet), a damaged one is left alone and the list is kept in memory only.
func openDeletedStore(path string) *deletedStore {
	// Start with an empty list.
	s := &deletedStore{path: path}
	// No path: memory only.
	if path == "" {
		// Nothing to read.
		return s
	} // end of the memory case
	// Look at the file first.
	info, err := os.Stat(path)
	// A missing file just means nothing was deleted yet.
	if errors.Is(err, os.ErrNotExist) {
		// Keep the path so the first deletion creates the file.
		return s
	} // end of the missing-file case
	// Another problem with the file.
	if err != nil {
		// Do not touch the file; keep the list in memory.
		s.path, s.note = "", "The list of deleted models could not be opened, so it is kept only until the monitor stops."
		// Hand back.
		return s
	} // end of the stat check
	// An absurdly big file is not ours.
	if info.Size() > maxDeletedFile {
		// Leave it alone.
		s.path, s.note = "", "The file of deleted models is unusually large, so it was left alone and the list is kept only until the monitor stops."
		// Hand back.
		return s
	} // end of the size check
	// Read it.
	data, err := os.ReadFile(path)
	// A read failure.
	if err != nil {
		// Leave it alone.
		s.path, s.note = "", "The list of deleted models could not be read, so it is kept only until the monitor stops."
		// Hand back.
		return s
	} // end of the read check
	// Decode it.
	var f deletedFile
	// A damaged file or another version is left alone.
	if err := json.Unmarshal(data, &f); err != nil || f.Version != deletedFileVersion {
		// Leave it alone.
		s.path, s.note = "", "The file of deleted models is damaged or from another version, so it was left alone and the list is kept only until the monitor stops."
		// Hand back.
		return s
	} // end of the decode check
	// Use what was read.
	s.items = f.Models
	// Hand back.
	return s
} // end of openDeletedStore

// writeLocked saves the list; the caller holds the lock. It writes a temporary file and renames it, so a crash never leaves half a file.
func (s *deletedStore) writeLocked() error {
	// Memory only: nothing to write.
	if s.path == "" {
		// Fine.
		return nil
	} // end of the memory case
	// The folder of the file.
	dir := filepath.Dir(s.path)
	// Create it if needed, readable only by this user.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		// Fixed wording with the system reason.
		return fmt.Errorf("the folder for the deleted-models list could not be created: %w", err)
	} // end of the folder check
	// Never write a JSON null.
	list := s.items
	// An empty list becomes an empty array.
	if list == nil {
		// Empty array.
		list = []deletedModel{}
	} // end of the nil check
	// Encode with indentation so the person can read the file.
	data, err := json.MarshalIndent(deletedFile{Version: deletedFileVersion, Models: list}, "", "  ")
	// A bug, not a user problem.
	if err != nil {
		// Fixed wording.
		return fmt.Errorf("the deleted-models list could not be encoded: %w", err)
	} // end of the encode check
	// Temporary file in the same folder, so the rename stays on one disk.
	tmp, err := os.CreateTemp(dir, "deleted-*.tmp")
	// A create failure.
	if err != nil {
		// Fixed wording.
		return fmt.Errorf("the deleted-models list could not be written: %w", err)
	} // end of the create check
	// Remove the temporary file if anything below fails.
	defer os.Remove(tmp.Name())
	// Only this user may read it.
	if err := tmp.Chmod(0o600); err != nil {
		// Close before returning.
		tmp.Close()
		// Fixed wording.
		return fmt.Errorf("the deleted-models list could not be protected: %w", err)
	} // end of the chmod check
	// Write the bytes.
	if _, err := tmp.Write(data); err != nil {
		// Close before returning.
		tmp.Close()
		// Fixed wording.
		return fmt.Errorf("the deleted-models list could not be written: %w", err)
	} // end of the write check
	// Close to flush.
	if err := tmp.Close(); err != nil {
		// Fixed wording.
		return fmt.Errorf("the deleted-models list could not be written: %w", err)
	} // end of the close check
	// Replace the old file in one step.
	if err := os.Rename(tmp.Name(), s.path); err != nil {
		// Fixed wording.
		return fmt.Errorf("the deleted-models list could not be replaced: %w", err)
	} // end of the rename check
	// Saved.
	return nil
} // end of writeLocked

// add remembers one deleted model (a second deletion of the same name replaces the first).
func (s *deletedStore) add(m deletedModel) error {
	// One request at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Keep every other model.
	kept := make([]deletedModel, 0, len(s.items)+1)
	// Go through the list.
	for _, it := range s.items {
		// Drop an older entry with the same name.
		if it.Name != m.Name {
			// Keep it.
			kept = append(kept, it)
		} // end of the name check
	} // end of the loop
	// Add the new one.
	s.items = append(kept, m)
	// Save.
	return s.writeLocked()
} // end of add

// forget removes one name from the list (after a restore, or when the person no longer wants to see it).
func (s *deletedStore) forget(name string) error {
	// One request at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Keep every other model.
	kept := make([]deletedModel, 0, len(s.items))
	// Go through the list.
	for _, it := range s.items {
		// Keep all but the named one.
		if it.Name != name {
			// Keep it.
			kept = append(kept, it)
		} // end of the name check
	} // end of the loop
	// Use the shorter list.
	s.items = kept
	// Save.
	return s.writeLocked()
} // end of forget

// find returns the remembered model with this name.
func (s *deletedStore) find(name string) (deletedModel, bool) {
	// One request at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Look at every entry.
	for _, it := range s.items {
		// A match.
		if it.Name == name {
			// Found.
			return it, true
		} // end of the name check
	} // end of the loop
	// Not remembered.
	return deletedModel{}, false
} // end of find

// list returns a copy, newest deletion first.
func (s *deletedStore) list() []deletedModel {
	// One request at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Copy, so the caller cannot change the store.
	out := append([]deletedModel(nil), s.items...)
	// Newest first.
	sort.Slice(out, func(i, j int) bool { return out[i].DeletedAt.After(out[j].DeletedAt) })
	// Hand back.
	return out
} // end of list
