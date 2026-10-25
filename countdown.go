// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// net/http provides requests and status codes.
	"net/http"
	// time provides durations.
	"time"
) // end of imports

// countdownJS is the small script that makes the timers tick, stored inside the executable at build time (requirement T3).
//
//go:embed web/countdown.js
var countdownJS []byte

// contentSecurityPolicyWithScript is the policy for the message pages that show a ticking timer: the same as the main page plus scripts from this same address only (no inline scripts, no other sites).
const contentSecurityPolicyWithScript = "default-src 'none'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"

// countdownHandler sends the script file.
func countdownHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser this is JavaScript.
	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	// Send it.
	w.Write(countdownJS)
} // end of countdownHandler

// remainingSeconds is the time left in whole seconds for the ticking timer; 0 means "no countdown" (no time reported, already past, or a model set to stay loaded).
func remainingSeconds(now, expires time.Time, ok bool) int {
	// No usable time.
	if !ok {
		// No countdown.
		return 0
	} // end of the no-time case
	// How long is left.
	left := expires.Sub(now)
	// Past, or so far away that the model is set to stay loaded.
	if left <= 0 || left > 30*24*time.Hour {
		// No countdown.
		return 0
	} // end of the range check
	// Round to whole seconds.
	return int(left.Round(time.Second).Seconds())
} // end of remainingSeconds
