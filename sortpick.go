// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// net/http provides requests and status codes.
	"net/http"
) // end of imports

// sortPickJS is the small script behind the Sort by choice of the Find LLM page, stored inside the executable at build time.
//
//go:embed web/sortpick.js
var sortPickJS []byte

// sortPickHandler sends the script file.
func sortPickHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser this is JavaScript.
	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	// Send it.
	w.Write(sortPickJS)
} // end of sortPickHandler
