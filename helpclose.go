// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// net/http provides requests and status codes.
	"net/http"
) // end of imports

// helpCloseJS is the small script behind the collapse buttons of the Help page, stored inside the executable at build time.
//
//go:embed web/helpclose.js
var helpCloseJS []byte

// helpCloseHandler sends the script file.
func helpCloseHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser this is JavaScript.
	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	// Send it.
	w.Write(helpCloseJS)
} // end of helpCloseHandler
