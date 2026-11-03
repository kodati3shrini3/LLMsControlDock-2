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
	// window is how long checks are kept; zero means the built-in chartWindow.
	window time.Duration
	// every is the time between checks; zero means the built-in sampleEvery. It sizes the ceiling.
	every time.Duration
} // end of sampleHistory

// hardMaxSamples is the largest number of checks ever kept, whatever the settings (240 minutes at 5 seconds is 2880).
const hardMaxSamples = 6000

// setLimits tells the history how long to keep checks and how often they come (both from the settings).
func (h *sampleHistory) setLimits(window, every time.Duration) {
	// One at a time.
	h.mu.Lock()
	// Release at the end.
	defer h.mu.Unlock()
	// Keep them.
	h.window, h.every = window, every
} // end of setLimits

// limits returns the window and the ceiling in use; the caller holds the lock.
func (h *sampleHistory) limits() (time.Duration, int) {
	// The window, or the built-in one.
	w := h.window
	// Zero means not set.
	if w <= 0 {
		// The built-in window.
		w = chartWindow
	} // end of the window default
	// The interval, or the built-in one.
	e := h.every
	// Zero means not set.
	if e <= 0 {
		// The built-in interval.
		e = sampleEvery
	} // end of the interval default
	// The checks that fit the window, plus a minute of slack; never fewer than the original ceiling.
	n := int(w/e) + 60
	// The original ceiling is the floor.
	if n < maxSamples {
		// Use it.
		n = maxSamples
	} // end of the floor
	// The hard ceiling.
	if n > hardMaxSamples {
		// Use it.
		n = hardMaxSamples
	} // end of the hard ceiling
	// Hand back both.
	return w, n
} // end of limits

// all returns a copy of every kept check, oldest first.
func (h *sampleHistory) all() []sample {
	// One at a time.
	h.mu.Lock()
	// Release at the end.
	defer h.mu.Unlock()
	// A copy, so the caller cannot change the list.
	return append([]sample(nil), h.items...)
} // end of all

// add keeps one more check and forgets the ones that are too old or beyond the ceiling.
func (h *sampleHistory) add(s sample) {
	// One writer at a time.
	h.mu.Lock()
	// Release at the end.
	defer h.mu.Unlock()
	// Add the new check at the end.
	h.items = append(h.items, s)
	// Anything older than the window plus a minute of slack is no longer shown, so it goes.
	w, ceiling := h.limits()
	// Checks older than the window plus a minute are dropped.
	cut := s.At.Add(-(w + time.Minute))
	// Count the old ones at the front.
	drop := 0
	// The list is oldest first, so stop at the first one that is recent enough.
	for drop < len(h.items) && h.items[drop].At.Before(cut) {
		// One more to drop.
		drop++
	} // end of the loop
	// The ceiling: drop the oldest when there are too many.
	if over := len(h.items) - drop - ceiling; over > 0 {
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
	// firstRunCheck is true in the real program: the first start shows the System check before the monitor.
	firstRunCheck bool
	// health counts the failed checks (the API health box).
	health *apiHealth
	// hist keeps the checks for the charts.
	hist *sampleHistory
	// background is true while a background check runs; the page then does not count its own checks.
	background atomic.Bool
	// store holds the saved settings (interval, timeout, history length, history file).
	store *settingsStore
	// denv is the operating system as seen by the desktop icon code; main sets the real one, and it stays "no desktop" in tests.
	denv desktopEnv
	// run says how the program was started (listen address and where it came from); main sets it once before serving.
	run runInfo
	// unsaved counts the checks since the history file was last written.
	unsaved atomic.Int32
} // end of monitor

// runInfo holds facts about the running program that the Settings page shows next to the saved values.
type runInfo struct {
	// Listen is the address the page is served on, as host:port.
	Listen string
	// ListenSource says which layer chose it: the command-line option, the saved setting or the default.
	ListenSource string
} // end of runInfo

// saveHistoryEvery is how many checks pass between two writes of the history file (12 checks of 10 seconds are 2 minutes).
const saveHistoryEvery = 12

// newMonitor builds an empty monitor.
func newMonitor() *monitor {
	// Empty counters and an empty history.
	return newMonitorWith(openSettingsStore("", ""))
} // end of newMonitor

// newMonitorWith builds a monitor that reads its settings from the given store.
func newMonitorWith(store *settingsStore) *monitor {
	// Empty counters and an empty history, and the settings.
	return &monitor{health: &apiHealth{}, hist: &sampleHistory{}, store: store, denv: noDesktopEnv()}
} // end of newMonitorWith

// timeoutOr is how long one status check waits: the saved value, or def.
func (m *monitor) timeoutOr(def time.Duration) time.Duration {
	// Ask the settings.
	return m.store.get().timeout(def)
} // end of timeoutOr

// record counts one check in the counters and in the history.
func (m *monitor) record(res checkResult, now time.Time) {
	// The counters of the API health box.
	m.health.record(res.Online, now)
	// The settings in force now.
	cfg := m.store.get()
	// The history keeps as long as the settings say.
	m.hist.setLimits(cfg.window(), cfg.interval(sampleEvery))
	// The history for the charts.
	m.hist.add(sample{At: now, Online: res.Online, Ms: res.Elapsed.Milliseconds()})
	// When the person asked for the history file, write it every few checks.
	if cfg.SaveHistory && m.unsaved.Add(1) >= saveHistoryEvery {
		// Start counting again.
		m.unsaved.Store(0)
		// A failed write is not fatal: the history stays in memory.
		_ = m.store.saveSamples(m.hist.all())
	} // end of the save check
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
	// With the history file switched on, take back the checks of before the restart.
	if cfg := m.store.get(); cfg.SaveHistory {
		// Apply the limits first, so old checks are pruned correctly.
		m.hist.setLimits(cfg.window(), cfg.interval(every))
		// Add what the file holds.
		for _, it := range m.store.loadSamples(cfg.window(), time.Now()) {
			// One at a time, oldest first.
			m.hist.add(it)
		} // end of the loop
	} // end of the history restore
	// The loop runs on its own.
	go func() {
		// One check right away, with the timeout in force now.
		m.record(checkOllama(ctx, base, m.timeoutOr(timeout)), time.Now())
		// Then wait, check, wait, check; the interval is read again every round, so a saved change applies at once.
		for {
			// Wait for the interval, or for the end of the program.
			select {
			// The program ends.
			case <-ctx.Done():
				// Leave the loop.
				return
			// The interval has passed.
			case <-time.After(m.store.get().interval(every)):
				// Check, with the timeout in force now.
				m.record(checkOllama(ctx, base, m.timeoutOr(timeout)), time.Now())
			} // end of the select
		} // end of the loop
	}() // end of the goroutine
} // end of start
