// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// sync keeps two page requests from changing the counters at the same moment.
	"sync"
	// time holds the moment of the last good check.
	"time"
) // end of imports

// healthTimeLayout is how the moment of the last successful check is written; it always carries the time zone name, as every time on every page does.
const healthTimeLayout = "2 Jan 2006 15:04:05 MST"

// healthNever is shown when no check has succeeded since the monitor started.
const healthNever = "none since this monitor started"

// apiHealth counts the checks of Ollama's API (the check that asks for its version). It lives in memory only: it starts again from zero when the monitor program starts, and it never stores any text of prompts or answers.
type apiHealth struct {
	// mu protects the counters below.
	mu sync.Mutex
	// failedRow is the number of failed checks since the last successful one.
	failedRow int
	// failedTotal is the number of failed checks since the monitor started.
	failedTotal int
	// lastOK is the moment of the last successful check (zero when there was none).
	lastOK time.Time
} // end of apiHealth

// healthView is what the page shows.
type healthView struct {
	// FailedRow is the number of failed checks in a row.
	FailedRow int
	// FailedTotal is the number of failed checks in total since the monitor started.
	FailedTotal int
	// LastOK is the last successful check, with its time zone, or healthNever.
	LastOK string
} // end of healthView

// record counts one check made at the given moment and returns what the page shows afterwards.
func (h *apiHealth) record(online bool, now time.Time) healthView {
	// One request at a time.
	h.mu.Lock()
	// Release at the end.
	defer h.mu.Unlock()
	// A good check ends the run of failures and remembers the moment.
	if online {
		// The run of failures is over.
		h.failedRow = 0
		// Remember when.
		h.lastOK = now
	} else {
		// One more failure in a row.
		h.failedRow++
		// One more in total.
		h.failedTotal++
	} // end of the online check
	// The text for the last good check.
	last := healthNever
	// There was one.
	if !h.lastOK.IsZero() {
		// Write it with its time zone.
		last = h.lastOK.Format(healthTimeLayout)
	} // end of the last-check text
	// What the page shows.
	return healthView{FailedRow: h.failedRow, FailedTotal: h.failedTotal, LastOK: last}
} // end of record
