// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import (
	// flag reads command-line options such as -listen.
	"flag"
	// fmt writes formatted text, here into the web reply.
	"fmt"
	// log prints timestamped messages to the terminal.
	"log"
	// net/http is Go's built-in web server (standard library only, requirement T1).
	"net/http"
	// time provides durations such as the request-header timeout.
	"time"
)

// defaultListen is where the page is served unless the user chooses otherwise: this machine only (requirement S1).
const defaultListen = "127.0.0.1:8765"

// helloHandler answers one kind of request; w is where we write the reply and r describes the incoming request.
func helloHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser the reply is plain text, not a web page.
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	// Write the one-line reply; Fprintln adds a newline at the end.
	fmt.Fprintln(w, "OllamaControlCenter is running")
}

// main is where every Go program starts running.
func main() {
	// Define a -listen option: its name, its default value, and the help text shown by -h.
	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
	// Read the command line now, so the listen variable receives its value.
	flag.Parse()

	// Create a router, which decides which function answers which URL.
	mux := http.NewServeMux()
	// Route: a GET request for exactly "/" is answered by helloHandler; any other path gets a 404.
	mux.HandleFunc("GET /{$}", helloHandler)

	// Describe the web server: Addr is where to listen (the star reads the flag's value), Handler is the router,
	// and ReadHeaderTimeout drops clients that take more than 5 seconds to send their request headers.
	server := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 5 * time.Second}

	// Tell the person which address we are about to serve on.
	log.Printf("OllamaControlCenter listening on http://%s (press Ctrl+C to stop)", *listen)
	// Start serving; this call blocks (waits) until the server stops or fails, for example if the port is taken.
	err := server.ListenAndServe()
	// If we get here the server has stopped; log.Fatal prints the reason and exits with an error code.
	log.Fatal(err)
}
