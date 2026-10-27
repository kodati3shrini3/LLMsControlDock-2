// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// encoding/json reads and writes the snapshot files.
	"encoding/json"
	// errors tells "file exists" apart from other problems.
	"errors"
	// fmt builds file names and error texts.
	"fmt"
	// io limits how much of a file is read.
	"io"
	// os reads and writes the files.
	"os"
	// path/filepath builds file paths for any operating system.
	"path/filepath"
	// regexp makes a model name safe to use inside a file name.
	"regexp"
	// sort keeps the list newest first.
	"sort"
	// strings checks file name endings.
	"strings"
	// time stamps the snapshot and its file name.
	"time"
) // end of imports

// historyDirName is the folder for the history files; the .gitignore already keeps this name out of GitHub (requirement S4).
const historyDirName = "history"

// snapshotSuffix ends the name of every snapshot file taken when a model is deleted.
const snapshotSuffix = "_deleted.json"

// snapshotVersion is written into every file so a future version of the program can recognise an older layout.
const snapshotVersion = 1

// maxSnapshotFile is the biggest snapshot file that will be read; a real one is under a kilobyte.
const maxSnapshotFile = 64 * 1024

// maxSnapshotFiles is the most files looked at when listing; a folder with more is not ours.
const maxSnapshotFiles = 5000

// snapParam is one inference parameter in a snapshot, for example temperature with 0.7.
type snapParam struct {
	// Name is the parameter name.
	Name string `json:"name"`
	// Value is the value as Ollama printed it.
	Value string `json:"value"`
} // end of snapParam

// paramSnapshot is what is kept about a model at the moment it is deleted.
type paramSnapshot struct {
	// Version is snapshotVersion.
	Version int `json:"version"`
	// Model is the model name with its tag.
	Model string `json:"model"`
	// DeletedAt is the moment of deletion.
	DeletedAt time.Time `json:"deleted_at"`
	// Digest is the model's fingerprint at that moment.
	Digest string `json:"digest"`
	// Size is the size on disk in bytes.
	Size int64 `json:"size"`
	// Parameters are the inference parameters the model had; empty means none were set.
	Parameters []snapParam `json:"parameters"`
	// File is the file name the snapshot was saved under (filled in when saved or listed; not stored inside the file).
	File string `json:"-"`
} // end of paramSnapshot

// historyStore writes and reads the snapshot files in one folder.
type historyStore struct {
	// dir is the folder; empty means nothing can be saved.
	dir string
	// note explains, in plain words, why nothing can be saved (empty when all is well).
	note string
} // end of historyStore

// defaultHistoryDir picks the folder: "history" next to the program's folder (the same project folder as the performance results), or in the user's config folder when the program's place is unknown.
func defaultHistoryDir() (string, string) {
	// Next to the program, one level above a "bin" folder.
	if exe, err := executablePath(); err == nil && exe != "" {
		// The folder the program is in.
		dir := filepath.Dir(exe)
		// A program inside "bin" belongs to the project folder above it.
		if filepath.Base(dir) == "bin" {
			// Go one level up.
			dir = filepath.Dir(dir)
		} // end of the bin check
		// The history folder.
		return filepath.Join(dir, historyDirName), ""
	} // end of the program check
	// Otherwise the user's own config folder.
	dir, err := userConfigDir()
	// Nothing found.
	if err != nil || dir == "" {
		// Say so in words.
		return "", "No folder for the history was found, so no snapshots are kept."
	} // end of the lookup check
	// The history folder in the config folder.
	return filepath.Join(dir, "OllamaControlCenter", historyDirName), ""
} // end of defaultHistoryDir

// unsafeNameChars matches every character that is not safe inside a file name.
var unsafeNameChars = regexp.MustCompile(`[^A-Za-z0-9._-]`)

// safeFilePart turns a model name into text that can sit inside a file name; it can never contain a slash, a colon or a leading dot.
func safeFilePart(name string) string {
	// Replace every odd character.
	s := unsafeNameChars.ReplaceAllString(name, "-")
	// A name made only of dots or nothing becomes a plain word.
	s = strings.TrimLeft(s, ".")
	// Empty after cleaning.
	if s == "" {
		// A fixed word.
		return "model"
	} // end of the empty check
	// Keep file names short.
	if len(s) > 80 {
		// Cut it.
		s = s[:80]
	} // end of the length check
	// Hand back.
	return s
} // end of safeFilePart

// save writes one snapshot file and returns its name; a file is never overwritten, and a second snapshot in the same second gets a number.
func (h *historyStore) save(s paramSnapshot) (string, error) {
	// No folder: nothing can be saved.
	if h.dir == "" {
		// Say why.
		if h.note != "" {
			// The stored reason.
			return "", errors.New(h.note)
		} // end of the note check
		// A fixed reason.
		return "", errors.New("there is no history folder")
	} // end of the folder check
	// The folder, readable only by this user.
	if err := os.MkdirAll(h.dir, 0o700); err != nil {
		// Fixed wording with the system reason.
		return "", fmt.Errorf("the history folder could not be created: %w", err)
	} // end of the folder check
	// Mark the file layout.
	s.Version = snapshotVersion
	// Never write a JSON null for the parameters.
	if s.Parameters == nil {
		// An empty list.
		s.Parameters = []snapParam{}
	} // end of the nil check
	// Encode with indentation so the person can read the file.
	data, err := json.MarshalIndent(s, "", "  ")
	// A bug, not a user problem.
	if err != nil {
		// Fixed wording.
		return "", fmt.Errorf("the snapshot could not be encoded: %w", err)
	} // end of the encode check
	// The first part of the name: time with its time zone offset (Z for UTC, otherwise such as +0100), then the model.
	base := s.DeletedAt.Format("2006-01-02_15-04-05Z0700") + "_" + safeFilePart(s.Model)
	// Write it under a name that is never used twice.
	return h.writeUnique("snapshot", base, snapshotSuffix, data)
} // end of save

// writeUnique writes one file into the history folder under base + suffix, adding a number when the name is taken; a file is never overwritten, and only this user can read it. The word says what is being saved, for the error texts.
func (h *historyStore) writeUnique(what, base, suffix string, data []byte) (string, error) {
	// Try the plain name, then numbered ones.
	for n := 0; n < 100; n++ {
		// The file name.
		name := base + suffix
		// A number from the second try on.
		if n > 0 {
			// Add it.
			name = fmt.Sprintf("%s-%d%s", base, n+1, suffix)
		} // end of the number
		// Create the file, failing when it exists, so nothing is ever overwritten; only this user may read it.
		f, err := os.OpenFile(filepath.Join(h.dir, name), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		// The name is taken: try the next.
		if errors.Is(err, os.ErrExist) {
			// Next number.
			continue
		} // end of the exists check
		// Another problem.
		if err != nil {
			// Fixed wording with the system reason.
			return "", fmt.Errorf("the %s file could not be created: %w", what, err)
		} // end of the create check
		// Write the bytes.
		if _, err := f.Write(data); err != nil {
			// Close before returning.
			f.Close()
			// Fixed wording.
			return "", fmt.Errorf("the %s file could not be written: %w", what, err)
		} // end of the write check
		// Close to flush.
		if err := f.Close(); err != nil {
			// Fixed wording.
			return "", fmt.Errorf("the %s file could not be written: %w", what, err)
		} // end of the close check
		// Saved.
		return name, nil
	} // end of the loop
	// Too many files in one second.
	return "", fmt.Errorf("the %s file name was already taken", what)
} // end of writeUnique

// removedSuffix ends the name of every safety copy of removed performance results; it differs from snapshotSuffix, so the parameter history never lists these.
const removedSuffix = "_removed.json"

// saveRemoved writes the safety copy of performance results that are about to be removed and returns its file name.
func (h *historyStore) saveRemoved(r removedResults) (string, error) {
	// No folder: nothing can be saved.
	if h.dir == "" {
		// Say why.
		if h.note != "" {
			// The stored reason.
			return "", errors.New(h.note)
		} // end of the note check
		// A fixed reason.
		return "", errors.New("there is no history folder")
	} // end of the folder check
	// The folder, readable only by this user.
	if err := os.MkdirAll(h.dir, 0o700); err != nil {
		// Fixed wording with the system reason.
		return "", fmt.Errorf("the history folder could not be created: %w", err)
	} // end of the folder check
	// Encode with indentation so the person can read the file.
	data, err := json.MarshalIndent(r, "", "  ")
	// A bug, not a user problem.
	if err != nil {
		// Fixed wording.
		return "", fmt.Errorf("the copy could not be encoded: %w", err)
	} // end of the encode check
	// The name: time with its zone offset, then what was removed.
	base := r.RemovedAt.Format("2006-01-02_15-04-05Z0700") + "_performance-results_" + safeFilePart(r.Scope)
	// Write it under a name that is never used twice.
	return h.writeUnique("copy", base, removedSuffix, data)
} // end of saveRemoved

// list returns the snapshots of one model, newest first; files that are not ours, damaged, too large or from another model are skipped.
func (h *historyStore) list(model string) []paramSnapshot {
	// Nothing to read.
	if h.dir == "" {
		// An empty list.
		return nil
	} // end of the folder check
	// Read the folder.
	entries, err := os.ReadDir(h.dir)
	// A missing folder just means no history yet.
	if err != nil {
		// An empty list.
		return nil
	} // end of the read check
	// The result.
	var out []paramSnapshot
	// How many files were looked at.
	seen := 0
	// Go through the files.
	for _, e := range entries {
		// Only plain files with our ending (no folders, no links).
		if !e.Type().IsRegular() || !strings.HasSuffix(e.Name(), snapshotSuffix) {
			// Skip it.
			continue
		} // end of the type check
		// A folder with far too many files is not ours; stop.
		if seen++; seen > maxSnapshotFiles {
			// Stop.
			break
		} // end of the count check
		// Open the file.
		f, err := os.Open(filepath.Join(h.dir, e.Name()))
		// Skip what cannot be opened.
		if err != nil {
			// Next file.
			continue
		} // end of the open check
		// Read at most one byte more than the limit, to notice an oversized file.
		data, err := io.ReadAll(io.LimitReader(f, maxSnapshotFile+1))
		// Close it.
		f.Close()
		// Skip what cannot be read or is too large.
		if err != nil || len(data) > maxSnapshotFile {
			// Next file.
			continue
		} // end of the read check
		// Decode it.
		var s paramSnapshot
		// Skip damaged files and other versions.
		if err := json.Unmarshal(data, &s); err != nil || s.Version != snapshotVersion {
			// Next file.
			continue
		} // end of the decode check
		// Only this model's snapshots.
		if s.Model != model {
			// Next file.
			continue
		} // end of the model check
		// Remember the file name for display.
		s.File = e.Name()
		// Keep it.
		out = append(out, s)
	} // end of the loop
	// Newest first.
	sort.Slice(out, func(i, j int) bool { return out[i].DeletedAt.After(out[j].DeletedAt) })
	// Hand back.
	return out
} // end of list

// snapshotFrom builds a snapshot from what Ollama said about the model.
func snapshotFrom(m installedModel, info showReply, at time.Time) paramSnapshot {
	// The parameters as pairs.
	var params []snapParam
	// Convert each saved line.
	for _, p := range parseParams(info.Parameters) {
		// Keep name and value.
		params = append(params, snapParam{Name: p.Name, Value: p.Value})
	} // end of the loop
	// Hand back.
	return paramSnapshot{Model: m.Name, DeletedAt: at, Digest: m.Digest, Size: m.Size, Parameters: params}
} // end of snapshotFrom
