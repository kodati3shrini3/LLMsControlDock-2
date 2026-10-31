// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the texts of the lines.
	"fmt"
	// sort puts the names in a fixed order, so the lines of one check always come in the same order.
	"sort"
	// sync keeps two page requests from changing the log at the same moment.
	"sync"
	// time holds the moment of each line.
	"time"
) // end of imports

// maxEvents is how many lines the log keeps in memory; older ones are dropped.
const maxEvents = 200

// shownEvents is how many of the newest lines the panel shows.
const shownEvents = 10

// eventFullLayout is how the start of the monitor is written (date, time and zone name, like every time on every page).
const eventFullLayout = "2 Jan 2006 15:04:05 MST"

// eventDayLayout is how a line of today is written: the time and the zone name.
const eventDayLayout = "15:04:05 MST"

// eventOtherDayLayout is how a line of an earlier day is written: the day, the time and the zone name.
const eventOtherDayLayout = "2 Jan 15:04:05 MST"

// eventEntry is one line of the log.
type eventEntry struct {
	// At is the moment the change was seen.
	At time.Time
	// Symbol is the small sign in front of the words; the words carry the meaning too.
	Symbol string
	// Text says what changed, in plain words.
	Text string
} // end of eventEntry

// eventRow is one line as the page draws it.
type eventRow struct {
	// Time is the moment with its zone name.
	Time string
	// Symbol is the sign in front of the words.
	Symbol string
	// Text says what changed.
	Text string
} // end of eventRow

// eventsView is the log as the page draws it.
type eventsView struct {
	// Rows are the newest lines, newest first.
	Rows []eventRow
	// Shown is how many lines are drawn.
	Shown int
	// Total is how many lines the log holds.
	Total int
	// Started is when the monitor started, with its zone name.
	Started string
} // end of eventsView

// eventLog remembers what Ollama looked like at the previous check and writes a line for each difference. It lives in memory only: it starts again when the monitor program starts, and it never holds any text of prompts or answers.
type eventLog struct {
	// mu protects every field below.
	mu sync.Mutex
	// seen is true after the first check; that check only sets the starting point.
	seen bool
	// started is the moment of the first check.
	started time.Time
	// online says whether Ollama answered at the previous check.
	online bool
	// version is the last version Ollama reported.
	version string
	// haveLists is true once the model lists were read at least once.
	haveLists bool
	// installed holds the names of the installed models at the last successful read.
	installed map[string]bool
	// loaded holds the names of the loaded models at the last successful read.
	loaded map[string]bool
	// entries are the lines, oldest first.
	entries []eventEntry
} // end of eventLog

// plural writes a count with the word in the right form, for example "1 model" and "6 models".
func plural(n int, word string) string {
	// One.
	if n == 1 {
		// Singular.
		return fmt.Sprintf("1 %s", word)
	} // end of the one check
	// Any other number.
	return fmt.Sprintf("%d %ss", n, word)
} // end of plural

// add appends one line and drops the oldest when there are too many; the caller holds the lock.
func (l *eventLog) add(at time.Time, symbol, text string) {
	// The new line.
	l.entries = append(l.entries, eventEntry{At: at, Symbol: symbol, Text: text})
	// Too many: keep the newest ones.
	if len(l.entries) > maxEvents {
		// Drop the oldest.
		l.entries = append([]eventEntry(nil), l.entries[len(l.entries)-maxEvents:]...)
	} // end of the size check
} // end of add

// names returns the keys of a set in alphabetical order.
func names(set map[string]bool) []string {
	// The list.
	out := make([]string, 0, len(set))
	// Fill it.
	for n := range set {
		// One name.
		out = append(out, n)
	} // end of the loop
	// A fixed order.
	sort.Strings(out)
	// Hand it back.
	return out
} // end of names

// observe compares what Ollama reports now with what it reported at the previous check, and writes a line for each difference. listsOK is false when the model lists could not be read, and then no model line is written.
func (l *eventLog) observe(now time.Time, online bool, version, reason string, listsOK bool, installed []installedModel, loaded []loadedModel) {
	// One at a time.
	l.mu.Lock()
	// Release at the end.
	defer l.mu.Unlock()
	// The sets of names now, and the sizes of the loaded models for the lines.
	instNow, loadNow, loadSize := map[string]bool{}, map[string]bool{}, map[string]int64{}
	// Fill them only when the lists were read.
	if listsOK {
		// The installed names.
		for _, m := range installed {
			// One name.
			instNow[m.Name] = true
		} // end of the installed loop
		// The loaded names and sizes.
		for _, m := range loaded {
			// One name.
			loadNow[m.Name] = true
			// Its size.
			loadSize[m.Name] = m.Size
		} // end of the loaded loop
	} // end of the lists check
	// The first check only sets the starting point and writes the first line.
	if !l.seen {
		// Remember it.
		l.seen, l.started, l.online = true, now, online
		// The line depends on what is known.
		switch {
		// Offline at the start.
		case !online:
			// Say so, with the reason.
			l.add(now, "●", "Monitor started: Ollama offline ("+reason+")")
		// Online and the lists were read.
		case listsOK:
			// The loaded part.
			state := "none loaded"
			// Some are loaded.
			if len(loadNow) > 0 {
				// Count them.
				state = fmt.Sprintf("%d loaded", len(loadNow))
			} // end of the loaded check
			// Say it.
			l.add(now, "●", fmt.Sprintf("Monitor started: Ollama online, %s installed, %s", plural(len(instNow), "model"), state))
		// Online, lists not read.
		default:
			// Say so.
			l.add(now, "●", "Monitor started: Ollama online")
		} // end of the line choice
		// Keep the version.
		if online {
			// The version.
			l.version = version
		} // end of the version check
		// Keep the starting lists.
		if listsOK {
			// Remember them.
			l.installed, l.loaded, l.haveLists = instNow, loadNow, true
		} // end of the lists check
		// Nothing more to compare.
		return
	} // end of the first check
	// Ollama went offline or came back.
	if online != l.online {
		// It came back.
		if online {
			// Say so, with the version.
			l.add(now, "✔", "Ollama is back online (version "+version+")")
		} else { // it went away
			// Say so, with the reason.
			l.add(now, "✖", "Ollama went offline: "+reason)
		} // end of the direction check
	} // end of the online check
	// Remember the state.
	l.online = online
	// An online Ollama may have been updated.
	if online && version != "" {
		// A different version than the last one seen.
		if l.version != "" && l.version != version {
			// Say so.
			l.add(now, "↻", "Ollama updated from "+l.version+" to "+version)
		} // end of the version check
		// Remember it.
		l.version = version
	} // end of the version block
	// Model lines only when the lists were read now and before.
	if listsOK {
		// A starting point exists.
		if l.haveLists {
			// Loaded and unloaded models, in name order.
			for _, n := range names(loadNow) {
				// A model that was not loaded before.
				if !l.loaded[n] {
					// The size, when Ollama reports one.
					size := ""
					// A size is known.
					if loadSize[n] > 0 {
						// Write it.
						size = " (" + formatSize(loadSize[n]) + ")"
					} // end of the size check
					// Say so.
					l.add(now, "▲", "Model loaded: "+n+size)
				} // end of the new check
			} // end of the loaded loop
			// Models that are not loaded any more.
			for _, n := range names(l.loaded) {
				// Gone from the list.
				if !loadNow[n] {
					// Say so.
					l.add(now, "▼", "Model unloaded: "+n)
				} // end of the gone check
			} // end of the unloaded loop
			// Installed models.
			for _, n := range names(instNow) {
				// A model that was not there before.
				if !l.installed[n] {
					// Say so.
					l.add(now, "＋", "Model installed: "+n)
				} // end of the new check
			} // end of the installed loop
			// Removed models.
			for _, n := range names(l.installed) {
				// Gone from the list.
				if !instNow[n] {
					// Say so.
					l.add(now, "－", "Model removed: "+n)
				} // end of the gone check
			} // end of the removed loop
		} // end of the starting point check
		// Remember the lists for the next check.
		l.installed, l.loaded, l.haveLists = instNow, loadNow, true
	} // end of the lists block
} // end of observe

// eventTime writes the moment of a line: the time of today with its zone name, or the day too for an earlier day.
func eventTime(at, now time.Time) string {
	// The same calendar day in the zone of the line.
	if at.Year() == now.In(at.Location()).Year() && at.YearDay() == now.In(at.Location()).YearDay() {
		// The time only.
		return at.Format(eventDayLayout)
	} // end of the day check
	// The day and the time.
	return at.Format(eventOtherDayLayout)
} // end of eventTime

// view copies the newest lines for the page, newest first.
func (l *eventLog) view(now time.Time) eventsView {
	// One at a time.
	l.mu.Lock()
	// Release at the end.
	defer l.mu.Unlock()
	// The view.
	v := eventsView{Total: len(l.entries)}
	// When the monitor started.
	if l.seen {
		// With its zone name.
		v.Started = l.started.Format(eventFullLayout)
	} // end of the started check
	// From the newest to older ones, at most the shown number.
	for i := len(l.entries) - 1; i >= 0 && len(v.Rows) < shownEvents; i-- {
		// One line.
		e := l.entries[i]
		// Add it.
		v.Rows = append(v.Rows, eventRow{Time: eventTime(e.At, now), Symbol: e.Symbol, Text: e.Text})
	} // end of the loop
	// How many are drawn.
	v.Shown = len(v.Rows)
	// Hand it back.
	return v
} // end of view
