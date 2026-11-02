// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// encoding/json reads and writes the settings file and the saved check history.
	"encoding/json"
	// fmt builds the plain-language problem messages.
	"fmt"
	// io limits how much of a file is read.
	"io"
	// os reads, writes and removes the files.
	"os"
	// path/filepath joins folder and file names for any operating system.
	"path/filepath"
	// sync keeps two requests from changing the settings at the same moment.
	"sync"
	// time provides the durations of the settings.
	"time"
) // end of imports

// The limits of the numeric settings (requirement F10, answer 7A); a value outside them is refused with a plain message.
const (
	// minIntervalSeconds is the shortest time between two background checks.
	minIntervalSeconds = 5
	// maxIntervalSeconds is the longest time between two background checks.
	maxIntervalSeconds = 300
	// minTimeoutSeconds is the shortest time one check waits for Ollama.
	minTimeoutSeconds = 1
	// maxTimeoutSeconds is the longest time one check waits for Ollama.
	maxTimeoutSeconds = 60
	// minHistoryMinutes is the shortest chart history.
	minHistoryMinutes = 5
	// maxHistoryMinutes is the longest chart history.
	maxHistoryMinutes = 240
) // end of the limits

// settingsFileName is the file that holds the saved settings, inside the program's folder in the user's configuration folder.
const settingsFileName = "settings.json"

// checkHistoryFileName is the file that holds the saved check history (only when the person turned that on).
const checkHistoryFileName = "checkhistory.json"

// maxSettingsFile is the largest settings file the monitor will read (64 KiB; a real one is under 1 KiB).
const maxSettingsFile = 64 * 1024

// maxCheckHistoryFile is the largest check-history file the monitor will read (2 MiB; 6000 checks need about 400 KiB).
const maxCheckHistoryFile = 2 * 1024 * 1024

// appSettings holds the values the person can change on the Settings page; a zero or empty value means "not set, use the default".
type appSettings struct {
	// OllamaURL is the address of the Ollama server (used at the next start).
	OllamaURL string `json:"ollama_url,omitempty"`
	// IntervalSeconds is the time between two background checks.
	IntervalSeconds int `json:"interval_seconds,omitempty"`
	// TimeoutSeconds is how long one status check waits for Ollama.
	TimeoutSeconds int `json:"timeout_seconds,omitempty"`
	// HistoryMinutes is how much history the charts show and keep.
	HistoryMinutes int `json:"history_minutes,omitempty"`
	// AllowOthers lets other machines on the network open this page (used at the next start).
	AllowOthers bool `json:"allow_others,omitempty"`
	// SaveHistory keeps the check history in a file, so it survives a restart.
	SaveHistory bool `json:"save_history,omitempty"`
} // end of appSettings

// interval is the time between two background checks; def is used when nothing is saved.
func (a appSettings) interval(def time.Duration) time.Duration {
	// A saved value wins.
	if a.IntervalSeconds > 0 {
		// Seconds to a duration.
		return time.Duration(a.IntervalSeconds) * time.Second
	} // end of the saved case
	// Otherwise the default.
	return def
} // end of interval

// timeout is how long one status check waits; def is used when nothing is saved.
func (a appSettings) timeout(def time.Duration) time.Duration {
	// A saved value wins.
	if a.TimeoutSeconds > 0 {
		// Seconds to a duration.
		return time.Duration(a.TimeoutSeconds) * time.Second
	} // end of the saved case
	// Otherwise the default.
	return def
} // end of timeout

// window is the chart history length; the built-in 30 minutes is used when nothing is saved.
func (a appSettings) window() time.Duration {
	// A saved value wins.
	if a.HistoryMinutes > 0 {
		// Minutes to a duration.
		return time.Duration(a.HistoryMinutes) * time.Minute
	} // end of the saved case
	// Otherwise the default.
	return chartWindow
} // end of window

// problems lists, in plain words, everything that is wrong with the values (an empty list means all is well).
func (a appSettings) problems() []string {
	// The list to fill.
	var out []string
	// The address, when given, must be usable.
	if a.OllamaURL != "" {
		// Reuse the same check as the command line and the environment variable.
		if _, err := parseOllamaURL(a.OllamaURL); err != nil {
			// Say what is wrong.
			out = append(out, "Ollama address: "+err.Error())
		} // end of the address check
	} // end of the address case
	// The interval, when given, must be inside its limits.
	if a.IntervalSeconds != 0 && (a.IntervalSeconds < minIntervalSeconds || a.IntervalSeconds > maxIntervalSeconds) {
		// Say the allowed range.
		out = append(out, fmt.Sprintf("Check interval: use a whole number from %d to %d seconds.", minIntervalSeconds, maxIntervalSeconds))
	} // end of the interval check
	// The timeout, when given, must be inside its limits.
	if a.TimeoutSeconds != 0 && (a.TimeoutSeconds < minTimeoutSeconds || a.TimeoutSeconds > maxTimeoutSeconds) {
		// Say the allowed range.
		out = append(out, fmt.Sprintf("Check timeout: use a whole number from %d to %d seconds.", minTimeoutSeconds, maxTimeoutSeconds))
	} // end of the timeout check
	// The history, when given, must be inside its limits.
	if a.HistoryMinutes != 0 && (a.HistoryMinutes < minHistoryMinutes || a.HistoryMinutes > maxHistoryMinutes) {
		// Say the allowed range.
		out = append(out, fmt.Sprintf("Chart history: use a whole number from %d to %d minutes.", minHistoryMinutes, maxHistoryMinutes))
	} // end of the history check
	// The timeout must be shorter than the interval, or two checks would overlap.
	if a.IntervalSeconds != 0 && a.TimeoutSeconds != 0 && a.TimeoutSeconds >= a.IntervalSeconds {
		// Say so.
		out = append(out, "Check timeout: it must be shorter than the check interval.")
	} // end of the overlap check
	// Hand back the list.
	return out
} // end of problems

// settingsStore keeps the settings: in memory always, and in a file when a folder is known.
type settingsStore struct {
	// mu protects everything below.
	mu sync.Mutex
	// dir is the configuration folder (the settings); empty means memory only.
	dir string
	// stateDir is the state folder (the check history); empty means the same folder as dir.
	stateDir string
	// cur is the current settings.
	cur appSettings
	// note says why the file is not used or was ignored (empty when all is well).
	note string
} // end of settingsStore

// settingsFolder finds the configuration folder of the settings file (each system's standard place, see datafolder.go); the second value is a plain note when none was found.
func settingsFolder() (string, string) {
	// The program's own folder inside the configuration base (a test replaces userConfigDir).
	dir := configRoot()
	// No folder: memory only.
	if dir == "" {
		// Say so.
		return "", "No folder for the settings was found, so they are kept only until the monitor stops."
	} // end of the lookup check
	// The folder.
	return dir, ""
} // end of settingsFolder

// stateFolder returns the folder of the check history: the state folder when one is set, else the settings folder; empty means memory only.
func (s *settingsStore) stateFolder() string {
	// A state folder was set.
	if s.stateDir != "" {
		// Use it.
		return s.stateDir
	} // end of the state check
	// Otherwise the settings folder.
	return s.dir
} // end of stateFolder

// openSettingsStore reads the settings file when there is one; a damaged or out-of-range file is ignored with a note, never trusted.
func openSettingsStore(dir, note string) *settingsStore {
	// Start with the defaults.
	s := &settingsStore{dir: dir, note: note}
	// No folder, nothing to read.
	if dir == "" {
		// Memory only.
		return s
	} // end of the memory case
	// Open the file.
	f, err := os.Open(filepath.Join(dir, settingsFileName))
	// A missing file is normal: nothing saved yet.
	if err != nil {
		// Defaults.
		return s
	} // end of the open check
	// Close it at the end.
	defer f.Close()
	// Read at most the limit, so a huge file cannot fill memory.
	var a appSettings
	// Decode the JSON.
	if err := json.NewDecoder(io.LimitReader(f, maxSettingsFile)).Decode(&a); err != nil {
		// Ignore the file and say why.
		s.note = "The saved settings file could not be read, so the defaults are used."
		// Defaults.
		return s
	} // end of the decode check
	// A value outside its limits is refused as a whole.
	if len(a.problems()) > 0 {
		// Ignore the file and say why.
		s.note = "The saved settings file holds a value outside its limits, so the defaults are used."
		// Defaults.
		return s
	} // end of the limits check
	// The file is good.
	s.cur = a
	// Hand back the store.
	return s
} // end of openSettingsStore

// get returns a copy of the current settings.
func (s *settingsStore) get() appSettings {
	// One at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// The copy.
	return s.cur
} // end of get

// noteText returns the plain note about the file (empty when all is well).
func (s *settingsStore) noteText() string {
	// One at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// The note.
	return s.note
} // end of noteText

// writeFile writes data next to its final name and then renames it, so a crash never leaves half a file; only the owner can read it.
func writeFile(dir, name string, data []byte) error {
	// Make the folder, private to the owner.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		// Report it.
		return err
	} // end of the folder check
	// A temporary file in the same folder, so the rename stays on one disk.
	tmp, err := os.CreateTemp(dir, name+".tmp*")
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the create check
	// Write the data.
	if _, err := tmp.Write(data); err != nil {
		// Clean up.
		tmp.Close()
		// Remove the temporary file.
		os.Remove(tmp.Name())
		// Report it.
		return err
	} // end of the write check
	// Close it, which also reports a late write failure.
	if err := tmp.Close(); err != nil {
		// Remove the temporary file.
		os.Remove(tmp.Name())
		// Report it.
		return err
	} // end of the close check
	// Only the owner may read it.
	if err := os.Chmod(tmp.Name(), 0o600); err != nil {
		// Remove the temporary file.
		os.Remove(tmp.Name())
		// Report it.
		return err
	} // end of the chmod check
	// Swap it into place.
	if err := os.Rename(tmp.Name(), filepath.Join(dir, name)); err != nil {
		// Remove the temporary file.
		os.Remove(tmp.Name())
		// Report it.
		return err
	} // end of the rename check
	// Done.
	return nil
} // end of writeFile

// put replaces the settings; the file is written first, and the settings change in memory only when the write worked (or when there is no folder). Turning the history off removes the saved history file.
func (s *settingsStore) put(a appSettings) error {
	// One at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// With a folder, save the file.
	if s.dir != "" {
		// An all-default setting removes the file instead of writing an empty one.
		if a == (appSettings{}) {
			// Remove it; a missing file is fine.
			if err := os.Remove(filepath.Join(s.dir, settingsFileName)); err != nil && !os.IsNotExist(err) {
				// Report it.
				return err
			} // end of the remove check
		} else { // the other case
			// Encode with indentation, so a person can read the file.
			data, err := json.MarshalIndent(a, "", "  ")
			// Report a failure.
			if err != nil {
				// Report it.
				return err
			} // end of the encode check
			// Write it.
			if err := writeFile(s.dir, settingsFileName, append(data, '\n')); err != nil {
				// Report it.
				return err
			} // end of the write check
		} // end of the file case
	} // end of the folder case
	// Without the history setting no history file may stay behind.
	if sf := s.stateFolder(); sf != "" && !a.SaveHistory {
		// Remove it; a missing file is fine.
		if err := os.Remove(filepath.Join(sf, checkHistoryFileName)); err != nil && !os.IsNotExist(err) {
			// Report it.
			return err
		} // end of the remove check
	} // end of the history removal
	// Keep the new values.
	s.cur = a
	// A successful save clears an old note about an ignored file.
	s.note = ""
	// Done.
	return nil
} // end of put

// checkHistoryFile is the shape of the saved check history.
type checkHistoryFile struct {
	// Version is the format number.
	Version int `json:"version"`
	// Samples holds the checks, oldest first.
	Samples []sample `json:"samples"`
} // end of checkHistoryFile

// saveSamples writes the check history to its file; it does nothing without a folder.
func (s *settingsStore) saveSamples(items []sample) error {
	// Without a folder there is nowhere to write.
	if s.stateFolder() == "" {
		// Nothing to do.
		return nil
	} // end of the memory case
	// Encode.
	data, err := json.Marshal(checkHistoryFile{Version: 1, Samples: items})
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the encode check
	// Write it.
	return writeFile(s.stateFolder(), checkHistoryFileName, data)
} // end of saveSamples

// loadSamples reads the saved check history and keeps the checks inside the window; a missing or damaged file gives nothing.
func (s *settingsStore) loadSamples(window time.Duration, now time.Time) []sample {
	// Without a folder there is nothing to read.
	if s.stateFolder() == "" {
		// Nothing.
		return nil
	} // end of the memory case
	// Open the file.
	f, err := os.Open(filepath.Join(s.stateFolder(), checkHistoryFileName))
	// A missing file is normal.
	if err != nil {
		// Nothing.
		return nil
	} // end of the open check
	// Close it at the end.
	defer f.Close()
	// Decode at most the limit.
	var h checkHistoryFile
	// A damaged file gives nothing.
	if err := json.NewDecoder(io.LimitReader(f, maxCheckHistoryFile)).Decode(&h); err != nil || h.Version != 1 {
		// Nothing.
		return nil
	} // end of the decode check
	// Keep the checks that are inside the window and not in the future.
	var out []sample
	// Walk them.
	for _, it := range h.Samples {
		// Inside the window and not later than now.
		if !it.At.Before(now.Add(-window)) && !it.At.After(now) {
			// Keep it.
			out = append(out, it)
		} // end of the window check
	} // end of the loop
	// Hand back the checks.
	return out
} // end of loadSamples
