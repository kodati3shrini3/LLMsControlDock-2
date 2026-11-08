// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// encoding/json writes and reads the saved copy.
	"encoding/json"
	// errors makes the "no copy" answer.
	"errors"
	// log reports a copy that could not be saved; the search itself carries on.
	"log"
	// os creates the folder and the file.
	"os"
	// path/filepath builds the file's place inside the data folder.
	"path/filepath"
	// sync lets only one search save at a time.
	"sync"
	// time carries the moment the list was read.
	"time"
) // end of imports

// libraryCopyFolder and libraryCopyName say where the saved copy of the library list lives, inside the program's data folder.
const (
	// libraryCopyFolder is the sub-folder of the data folder.
	libraryCopyFolder = "findLibrary"
	// libraryCopyName is the file inside it.
	libraryCopyName = "library-list.json"
) // end of the names

// errNoCopy is the answer when no copy has been saved yet, or the data folder is unknown.
var errNoCopy = errors.New("no saved copy of the library list exists yet")

// libraryCopy is what is saved: the moment the list was read from ollama.com and the list itself.
type libraryCopy struct {
	// ReadAt is when the list was read from the public website.
	ReadAt time.Time `json:"read_at"`
	// Models are the models of the list.
	Models []siteModel `json:"models"`
} // end of libraryCopy

// copyState remembers which reading was saved last, so the same reading is not written again and again.
var copyState struct {
	// mu lets one search at a time touch the state.
	mu sync.Mutex
	// savedAt is the moment of the reading saved last.
	savedAt time.Time
} // end of copyState

// libraryCopyPath is the place of the saved copy; empty when the data folder is unknown.
func libraryCopyPath() string {
	// The data folder.
	root := dataRoot()
	// Unknown: nothing can be saved or read.
	if root == "" {
		// No place.
		return ""
	} // end of the folder check
	// The file inside the program's own sub-folder.
	return filepath.Join(root, libraryCopyFolder, libraryCopyName)
} // end of libraryCopyPath

// saveLibraryCopy keeps the list that was just read, so Find LLM can show it, dated, when ollama.com cannot be reached later; it writes only when this reading is new, and it never stops a search: a failure is only logged.
func saveLibraryCopy(models []siteModel, at time.Time) {
	// One at a time.
	copyState.mu.Lock()
	// Let go at the end.
	defer copyState.mu.Unlock()
	// The same reading was saved already.
	if at.Equal(copyState.savedAt) {
		// Nothing to do.
		return
	} // end of the repeat check
	// Where to write.
	path := libraryCopyPath()
	// No data folder: the copy stays out; say so once in the log.
	if path == "" {
		// Log it.
		log.Printf("Find LLM: no data folder is known, so the library list is not saved for offline use")
		// Stop.
		return
	} // end of the folder check
	// The text to save.
	body, err := json.Marshal(libraryCopy{ReadAt: at, Models: models})
	// Not expected for plain text and numbers.
	if err != nil {
		// Log it.
		log.Printf("Find LLM: the library list could not be prepared for saving: %v", err)
		// Stop.
		return
	} // end of the encode check
	// The folder, private to the person running the program.
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		// Log it.
		log.Printf("Find LLM: the folder for the saved library list could not be made: %v", err)
		// Stop.
		return
	} // end of the folder check
	// Write to a temporary file first, so a power cut never leaves half a copy.
	tmp, err := os.CreateTemp(filepath.Dir(path), "library-*.tmp")
	// A failure.
	if err != nil {
		// Log it.
		log.Printf("Find LLM: the saved library list could not be started: %v", err)
		// Stop.
		return
	} // end of the temp check
	// Remove the temporary file if something below fails.
	defer os.Remove(tmp.Name())
	// Write it.
	if _, err := tmp.Write(body); err != nil {
		// Close it.
		tmp.Close()
		// Log it.
		log.Printf("Find LLM: the saved library list could not be written: %v", err)
		// Stop.
		return
	} // end of the write check
	// Finish the file.
	if err := tmp.Close(); err != nil {
		// Log it.
		log.Printf("Find LLM: the saved library list could not be finished: %v", err)
		// Stop.
		return
	} // end of the close check
	// Private to this person.
	if err := os.Chmod(tmp.Name(), 0o600); err != nil {
		// Not fatal on systems without file modes (Windows): carry on.
		log.Printf("Find LLM: the saved library list could not be made private: %v", err)
	} // end of the mode check
	// Put it in place in one step.
	if err := os.Rename(tmp.Name(), path); err != nil {
		// Log it.
		log.Printf("Find LLM: the saved library list could not be put in place: %v", err)
		// Stop.
		return
	} // end of the rename check
	// Remember this reading.
	copyState.savedAt = at
} // end of saveLibraryCopy

// loadLibraryCopy reads the saved copy and the moment its list was read; it says errNoCopy when there is none, and an error when the file is damaged, so a damaged copy is never shown.
func loadLibraryCopy() ([]siteModel, time.Time, error) {
	// Where it should be.
	path := libraryCopyPath()
	// Unknown folder.
	if path == "" {
		// None.
		return nil, time.Time{}, errNoCopy
	} // end of the folder check
	// Read the file.
	body, err := os.ReadFile(path)
	// Not there.
	if errors.Is(err, os.ErrNotExist) {
		// None yet.
		return nil, time.Time{}, errNoCopy
	} // end of the missing check
	// Another failure.
	if err != nil {
		// Report it.
		return nil, time.Time{}, err
	} // end of the read check
	// Decode it.
	var c libraryCopy
	// A damaged file.
	if err := json.Unmarshal(body, &c); err != nil {
		// Report it.
		return nil, time.Time{}, err
	} // end of the decode check
	// An empty list or no date cannot be shown honestly.
	if len(c.Models) == 0 || c.ReadAt.IsZero() {
		// Treat it as no copy.
		return nil, time.Time{}, errNoCopy
	} // end of the content check
	// The copy.
	return c.Models, c.ReadAt, nil
} // end of loadLibraryCopy
