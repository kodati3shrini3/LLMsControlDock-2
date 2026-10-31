// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context stops the background checks when the program ends.
	"context"
	// net/url holds the Ollama address.
	"net/url"
	// sync protects the history from two writers at once.
	"sync"
	// sync/atomic holds the flag that says a background check is running.
	"sync/atomic"
	// time gives the moments and the interval.
	"time"
) // end of imports

// sampleEvery is how often the background check asks Ollama whether it answers.
const sampleEvery = 10 * time.Second

// chartWindow is how much history the charts show and keep.
const chartWindow = 30 * time.Minute

// maxSamples is the most checks kept in memory, whatever the interval, so memory use has a ceiling.
const maxSamples = 400

// sample is one check of Ollama: when it was made, whether Ollama answered, and how long the answer took.
type sample struct {
	// At is the moment of the check.
	At time.Time
	// Online is true when Ollama answered correctly.
	Online bool
	// Ms is the time the check took, in milliseconds.
	Ms int64
} // end of sample

// sampleHistory keeps the newest checks in memory only; it holds no text of prompts or answers.
type sampleHistory struct {
	// mu protects the list below.
	mu sync.Mutex
	// items are the checks, oldest first.
	items []sample
} // end of sampleHistory

// add keeps one more check and forgets the ones that are too old or beyond the ceiling.
func (h *sampleHistory) add(s sample) {
	// One writer at a time.
	h.mu.Lock()
	// Release at the end.
	defer h.mu.Unlock()
	// Add the new check at the end.
	h.items = append(h.items, s)
	// Anything older than the window plus a minute of slack is no longer shown, so it goes.
	cut := s.At.Add(-(chartWindow + time.Minute))
	// Count the old ones at the front.
	drop := 0
	// The list is oldest first, so stop at the first one that is recent enough.
	for drop < len(h.items) && h.items[drop].At.Before(cut) {
		// One more to drop.
		drop++
	} // end of the loop
	// The ceiling: drop the oldest when there are too many.
	if over := len(h.items) - drop - maxSamples; over > 0 {
		// Drop those too.
		drop += over
	} // end of the ceiling check
	// Forget them, copying so the old memory can be released.
	if drop > 0 {
		// The kept part.
		h.items = append([]sample(nil), h.items[drop:]...)
	} // end of the drop
} // end of add

// since returns a copy of the checks made at or after the given moment, oldest first.
func (h *sampleHistory) since(from time.Time) []sample {
	// One reader at a time.
	h.mu.Lock()
	// Release at the end.
	defer h.mu.Unlock()
	// The copy.
	var out []sample
	// Pick the recent ones.
	for _, s := range h.items {
		// Recent enough.
		if !s.At.Before(from) {
			// Keep it.
			out = append(out, s)
		} // end of the age check
	} // end of the loop
	// Hand them back.
	return out
} // end of since

// monitor holds what the page shows about Ollama's health: the counters and the history of checks.
type monitor struct {
	// health counts the failed checks (the API health box).
	health *apiHealth
	// hist keeps the checks for the charts.
	hist *sampleHistory
	// background is true while a background check runs; the page then does not count its own checks.
	background atomic.Bool
} // end of monitor

// newMonitor builds an empty monitor.
func newMonitor() *monitor {
	// Empty counters and an empty history.
	return &monitor{health: &apiHealth{}, hist: &sampleHistory{}}
} // end of newMonitor

// record counts one check in the counters and in the history.
func (m *monitor) record(res checkResult, now time.Time) {
	// The counters of the API health box.
	m.health.record(res.Online, now)
	// The history for the charts.
	m.hist.add(sample{At: now, Online: res.Online, Ms: res.Elapsed.Milliseconds()})
} // end of record

// pageCheck is called by the page for its own check: it counts the check only when no background check runs, and returns the counters.
func (m *monitor) pageCheck(res checkResult, now time.Time) healthView {
	// With a background check the page only reads.
	if m.background.Load() {
		// Read the counters.
		return m.health.view()
	} // end of the background check
	// Without one the page's own check is the only measurement.
	m.record(res, now)
	// Read the counters.
	return m.health.view()
} // end of pageCheck

// start switches the background check on: one check now, then one every interval, until the context ends.
func (m *monitor) start(ctx context.Context, base *url.URL, timeout, every time.Duration) {
	// From now on the page does not count its own checks.
	m.background.Store(true)
	// The loop runs on its own.
	go func() {
		// One check straight away, so the charts start at once.
		m.record(checkOllama(ctx, base, timeout), time.Now())
		// The clock for the next ones.
		tick := time.NewTicker(every)
		// Stop the clock at the end.
		defer tick.Stop()
		// Wait for each tick or the end.
		for {
			// Which came first.
			select {
			// The program is ending.
			case <-ctx.Done():
				// Leave the loop.
				return
			// Time for the next check.
			case <-tick.C:
				// Check and remember.
				m.record(checkOllama(ctx, base, timeout), time.Now())
			} // end of the select
		} // end of the loop
	}() // end of the goroutine
} // end of start
