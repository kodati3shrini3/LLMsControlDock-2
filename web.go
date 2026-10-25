// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes provides a buffer so the page is built completely before anything is sent.
	"bytes"
	// embed lets files be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// html/template builds HTML and escapes every inserted value, so untrusted text cannot become markup.
	"html/template"
	// log prints messages to the terminal.
	"log"
	// net/http is Go's built-in web server.
	"net/http"
	// time provides durations.
	"time"
) // end of imports

// indexTemplateText is the page template, stored inside the executable at build time (requirements T3 and T4).
//
//go:embed web/index.html
var indexTemplateText string

// appCSS is the stylesheet, stored inside the executable at build time.
//
//go:embed web/app.css
var appCSS []byte

// contentSecurityPolicy tells the browser what the page may load: only our own stylesheet, no scripts, no frames, no forms.
const contentSecurityPolicy = "default-src 'none'; style-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

// pageData is everything the page template can show.
type pageData struct {
	// Address is the Ollama address with any password hidden.
	Address string
	// AddressSource names the layer that supplied the address.
	AddressSource string
	// Online is true when Ollama answered with a valid version.
	Online bool
	// Version is the Ollama version text.
	Version string
	// ElapsedMs is how long the check took, in milliseconds.
	ElapsedMs int64
	// Reason explains why Ollama is offline.
	Reason string
} // end of pageData

// secureHeaders wraps a handler so every reply, including errors, carries the same safety headers.
func secureHeaders(next http.Handler) http.Handler {
	// Return a handler that sets the headers and then calls the wrapped one.
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Limit what the page may load.
		w.Header().Set("Content-Security-Policy", contentSecurityPolicy)
		// Stop the browser from guessing a different content type.
		w.Header().Set("X-Content-Type-Options", "nosniff")
		// Forbid showing the page inside a frame (older browsers read this header).
		w.Header().Set("X-Frame-Options", "DENY")
		// Never send the page address to other sites.
		w.Header().Set("Referrer-Policy", "no-referrer")
		// A status page must never come from a cache.
		w.Header().Set("Cache-Control", "no-store")
		// Hand the request on.
		next.ServeHTTP(w, r)
	}) // end of the wrapper
} // end of secureHeaders

// newWebHandler builds the whole web interface: the page at "/" and the stylesheet at "/app.css".
func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
	page := template.Must(template.New("index").Parse(indexTemplateText))
	// Create a router for the two routes.
	mux := http.NewServeMux()
	// Route: a GET request for exactly "/" shows the page; other paths get 404 and other methods get 405 from the router.
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		// Ask Ollama once; the request's own context cancels the check if the browser goes away.
		res := checkOllama(r.Context(), addr.URL, timeout)
		// Fill in what the template shows.
		data := pageData{
			// The address with any password replaced by xxxxx.
			Address: addr.URL.Redacted(),
			// Which layer supplied it.
			AddressSource: addr.Source,
			// Online or offline.
			Online: res.Online,
			// The version, if online.
			Version: res.Version,
			// The time taken.
			ElapsedMs: res.Elapsed.Milliseconds(),
			// The reason, if offline.
			Reason: res.Reason,
		} // end of the data
		// Build the whole page in memory first, so a template error produces a clean 500 and not a half page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the finished page.
		w.Write(buf.Bytes())
	}) // end of the page route
	// Route: a GET request for "/app.css" sends the embedded stylesheet.
	mux.HandleFunc("GET /app.css", func(w http.ResponseWriter, r *http.Request) {
		// Tell the browser this is a stylesheet.
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		// Send it.
		w.Write(appCSS)
	}) // end of the stylesheet route
	// Wrap the router so every reply carries the safety headers.
	return secureHeaders(mux)
} // end of newWebHandler
