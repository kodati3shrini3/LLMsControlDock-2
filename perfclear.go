// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the speed text.
	"fmt"
	// path/filepath joins the history folder and the file name.
	"path/filepath"
	// sort keeps the rows in a steady order.
	"sort"
	// time stamps the copy of removed results.
	"time"
) // end of imports

// perfSummary is one line of the "what you lose" table: what is saved for one model.
type perfSummary struct {
	// Model is the model name.
	Model string
	// Tests is how many saved test results the model has.
	Tests int
	// First is the time of the oldest test, with the year and the time zone.
	First string
	// Latest is the time of the newest test, with the year and the time zone.
	Latest string
	// Speed is the newest test's speed in words.
	Speed string
	// This is true for the model whose page the person came from.
	This bool
} // end of perfSummary

// perfTimeText shows a test time in the computer's own time zone, with the year and the zone name.
func perfTimeText(t time.Time) string {
	// Local time, day, month, year, clock, zone.
	return t.Local().Format("2 Jan 2006 15:04 MST")
} // end of perfTimeText

// perfSpeedText says in words how fast a run was: tokens per second for a chat model, the embedding time for an embedding model.
func perfSpeedText(r perfRun) string {
	// A chat model.
	if r.AnswerSpeed > 0 {
		// Tokens per second.
		return fmtSpeed(r.AnswerSpeed)
	} // end of the chat check
	// An embedding model.
	if r.Kind == "embedding" && r.WarmTotalSec > 0 {
		// The time one embedding took.
		return fmt.Sprintf("%s per embedding", fmtSecs(r.WarmTotalSec))
	} // end of the embedding check
	// Nothing to show.
	return "not available"
} // end of perfSpeedText

// summaries describes the saved results per model; with a model name it describes only that model; "this" marks the model the person came from.
func (s *perfStore) summaries(only, this string) []perfSummary {
	// One reader at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// One entry per model, with its newest and oldest run.
	type acc struct {
		// n counts the runs.
		n int
		// first is the oldest run.
		first perfRun
		// last is the newest run.
		last perfRun
	} // end of acc
	// The entries by model name.
	by := map[string]*acc{}
	// Go through all runs.
	for _, r := range s.runs {
		// Only the wanted model, when one is given.
		if only != "" && r.Model != only {
			// Skip it.
			continue
		} // end of the model check
		// The entry of this model.
		a := by[r.Model]
		// The first run of a model starts its entry.
		if a == nil {
			// Create it.
			a = &acc{first: r, last: r}
			// Keep it.
			by[r.Model] = a
		} // end of the new entry
		// Count it.
		a.n++
		// An older run.
		if r.Time.Before(a.first.Time) {
			// It becomes the first.
			a.first = r
		} // end of the older check
		// A newer run (or the same moment, later in the file).
		if !r.Time.Before(a.last.Time) {
			// It becomes the last.
			a.last = r
		} // end of the newer check
	} // end of the loop
	// The result.
	var out []perfSummary
	// Build the lines.
	for model, a := range by {
		// One line.
		out = append(out, perfSummary{Model: model, Tests: a.n, First: perfTimeText(a.first.Time), Latest: perfTimeText(a.last.Time), Speed: perfSpeedText(a.last), This: model == this})
	} // end of the loop
	// A steady order: the model of this page first, then by name.
	sort.Slice(out, func(i, j int) bool {
		// This model first.
		if out[i].This != out[j].This {
			// The marked one goes up.
			return out[i].This
		} // end of the marked check
		// Then by name.
		return out[i].Model < out[j].Model
	}) // end of the sort
	// Hand back.
	return out
} // end of summaries

// all returns a copy of every saved run, oldest first.
func (s *perfStore) all() []perfRun {
	// One reader at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// A copy, so the caller cannot change the store.
	return append([]perfRun(nil), s.runs...)
} // end of all

// runsOf returns a copy of the saved runs of one model, oldest first.
func (s *perfStore) runsOf(model string) []perfRun {
	// One reader at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// The result.
	var out []perfRun
	// Go through all runs.
	for _, r := range s.runs {
		// A match.
		if r.Model == model {
			// Keep it.
			out = append(out, r)
		} // end of the match check
	} // end of the loop
	// Hand back.
	return out
} // end of runsOf

// countModel says how many saved runs one model has.
func (s *perfStore) countModel(model string) int {
	// One reader at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Count the matches.
	n := 0
	// Go through all runs.
	for _, r := range s.runs {
		// A match.
		if r.Model == model {
			// Count it.
			n++
		} // end of the match check
	} // end of the loop
	// The number.
	return n
} // end of countModel

// inCompare says whether the model is in the list that "Compare tested models" shows now.
func (s *perfStore) inCompare(model string) bool {
	// The newest run of each model with the current prompt.
	runs, _ := s.latestRuns(perfPromptVersion)
	// Look for the model.
	for _, r := range runs {
		// A match.
		if r.Model == model {
			// It is in the list.
			return true
		} // end of the match check
	} // end of the loop
	// Not in the list.
	return false
} // end of inCompare

// removeModel removes every saved run of one model, saves the rest, and says how many were removed.
func (s *perfStore) removeModel(model string) (int, error) {
	// One change at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// The runs that stay.
	var keep []perfRun
	// Go through all runs.
	for _, r := range s.runs {
		// Keep the other models' runs.
		if r.Model != model {
			// Keep it.
			keep = append(keep, r)
		} // end of the model check
	} // end of the loop
	// How many go away.
	removed := len(s.runs) - len(keep)
	// Replace the list.
	s.runs = keep
	// Save.
	return removed, s.writeLocked()
} // end of removeModel

// removedResults is what is written to the safety copy when saved results are removed.
type removedResults struct {
	// Version is snapshotVersion, so a future version of the program can recognise the layout.
	Version int `json:"version"`
	// RemovedAt is the moment of removal.
	RemovedAt time.Time `json:"removed_at"`
	// Scope is "all models" or the model name.
	Scope string `json:"scope"`
	// Runs are the removed results.
	Runs []perfRun `json:"runs"`
} // end of removedResults

// removalPlan tells, before anything is removed, whether a safety copy can be kept; the bool is true when it cannot.
func removalPlan(h *historyStore) (string, bool) {
	// No folder: nothing can be copied.
	if h.dir == "" {
		// The stored reason, or a fixed one.
		if h.note != "" {
			// Say why.
			return h.note + " These results would be gone for good.", true
		} // end of the note check
		// A fixed reason.
		return "There is no history folder, so these results would be gone for good.", true
	} // end of the folder check
	// All is well.
	return "A copy of these results is saved first, in " + h.dir + ", so they can still be looked at by hand (numbers only).", false
} // end of removalPlan

// keepCopy saves the safety copy of results that are about to be removed; it returns the full path of the copy, or the reason there is none.
func keepCopy(h *historyStore, scope string, runs []perfRun, at time.Time) (string, string) {
	// Nothing to copy.
	if len(runs) == 0 {
		// No copy, no problem.
		return "", ""
	} // end of the empty check
	// The label in the file name and in the file.
	label := scope
	// An empty scope means all models.
	if label == "" {
		// The words.
		label = "all models"
	} // end of the label check
	// Save it.
	name, err := h.saveRemoved(removedResults{Version: snapshotVersion, RemovedAt: at, Scope: label, Runs: runs})
	// A failure is reported, not hidden.
	if err != nil {
		// The reason in words.
		return "", err.Error()
	} // end of the save check
	// The full path.
	return filepath.Join(h.dir, name), ""
} // end of keepCopy
