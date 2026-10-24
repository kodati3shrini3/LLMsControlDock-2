// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// flag reads command-line options such as -listen.
	"flag"
	// fmt writes formatted text, here into the web reply.
	"fmt"
	// log prints timestamped messages to the terminal.
	"log"
	// net/http is Go's built-in web server (standard library only, requirement T1).
	"net/http"
	// os reads environment variables.
	"os"
	// time provides durations such as the request-header timeout.
	"time"
) // end of imports

// defaultListen is where the page is served unless the user chooses otherwise: this machine only (requirement S1).
const defaultListen = "127.0.0.1:8765"

// helloHandler answers one kind of request; w is where we write the reply and r describes the incoming request.
func helloHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser the reply is plain text, not a web page.
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	// Write the one-line reply; Fprintln adds a newline at the end.
	fmt.Fprintln(w, "OllamaControlCenter is running")
} // end of helloHandler

// main is where every Go program starts running.
func main() {
	// Define a -listen option: its name, its default value, and the help text shown by -h.
	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
	// Define an -ollama-url option; empty means "not given", so the environment variable or the default is used.
	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the OCC_OLLAMA_URL environment variable (default http://127.0.0.1:11434)")
	// Read the command line now, so the variables above receive their values.
	flag.Parse()

	// Choose the Ollama address by precedence: option, then environment variable, then default.
	addr, err := resolve(*ollamaFlag, os.Getenv(envOllamaURL))
	// If the address is unusable, stop with a clear message and a failure exit code.
	if err != nil {
		// log.Fatalf prints the message and exits with code 1.
		log.Fatalf("%v", err)
	} // end of the address check
	// Print the address (any password shown as xxxxx) and which layer supplied it.
	log.Printf("Ollama address: %s (from %s)", addr.URL.Redacted(), addr.Source)

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
	err = server.ListenAndServe()
	// If we get here the server has stopped; log.Fatal prints the reason and exits with an error code.
	log.Fatal(err)
} // end of main
