// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// crypto/rand makes the page token from random numbers that a program cannot predict.
	"crypto/rand"
	// crypto/subtle compares two texts in constant time, so the time taken cannot give the token away.
	"crypto/subtle"
	// encoding/hex writes the random bytes as readable letters and digits.
	"encoding/hex"
	// net splits "host:port" addresses.
	"net"
	// net/http provides requests and status codes.
	"net/http"
	// strings makes host names lower case before they are compared.
	"strings"
) // end of imports

// mustToken makes the page token: 16 random bytes written as 32 letters and digits (the name starts with "must" because it stops the program if it fails, like template.Must).
func mustToken() string {
	// 16 random bytes are 128 bits, far too many to guess.
	b := make([]byte, 16)
	// Fill them from the operating system's random source.
	if _, err := rand.Read(b); err != nil {
		// Without randomness the page cannot be made safe, so stop at start-up.
		panic("cannot create the page token: " + err.Error())
	} // end of the random check
	// Write the bytes as 32 letters and digits.
	return hex.EncodeToString(b)
} // end of mustToken

// tokenValid says whether the token sent with a form is the page token; an empty token is never valid.
func tokenValid(want, got string) bool {
	// An empty page token would match an empty form value, so refuse it first.
	if want == "" {
		// Never valid.
		return false
	} // end of the empty check
	// Compare in constant time; the result is 1 when the texts are equal.
	return subtle.ConstantTimeCompare([]byte(want), []byte(got)) == 1
} // end of tokenValid

// sameOrigin says whether a request was sent by a form on this very page (requirement S2: only the monitor's own page may change anything).
func sameOrigin(r *http.Request) bool {
	// Modern browsers always say where a request came from; only "same-origin" is accepted.
	if site := r.Header.Get("Sec-Fetch-Site"); site != "" {
		// Compare with the one accepted value.
		return site == "same-origin"
	} // end of the Sec-Fetch-Site check
	// Older browsers send an Origin header with form posts; it must name this very address.
	if origin := r.Header.Get("Origin"); origin != "" {
		// "null" and every other address are refused because they do not match.
		return origin == "http://"+r.Host
	} // end of the Origin check
	// Neither header: the request did not come from a browser page (a script or curl, for example), so refuse it.
	return false
} // end of sameOrigin

// allowedHosts lists the Host header values that count as "this computer, this port" for the given listen address.
func allowedHosts(listen string) map[string]bool {
	// The address exactly as it was given to -listen is always allowed.
	set := map[string]bool{strings.ToLower(listen): true}
	// Split it into host and port; if that fails, only the exact text is allowed.
	_, port, err := net.SplitHostPort(listen)
	// A failure means no port can be added to the names below.
	if err != nil {
		// Return what we have.
		return set
	} // end of the split check
	// The three names a browser on this computer uses for itself.
	for _, host := range []string{"127.0.0.1", "localhost", "[::1]"} {
		// The name with the port.
		set[host+":"+port] = true
		// Browsers leave the port out when it is the default web port, 80.
		if port == "80" {
			// The name alone.
			set[host] = true
		} // end of the port-80 check
	} // end of the name loop
	// Hand back the list.
	return set
} // end of allowedHosts

// hostGuard refuses every request whose Host header is not one of this computer's own names, which stops DNS rebinding (a web page elsewhere tricking the browser into talking to this monitor).
func hostGuard(next http.Handler, listen string) http.Handler {
	// Work out the allowed names once.
	allowed := allowedHosts(listen)
	// Return a handler that checks the Host header and then calls the wrapped one.
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Host names are not case sensitive, so compare in lower case.
		if !allowed[strings.ToLower(r.Host)] {
			// Never cache a refusal.
			w.Header().Set("Cache-Control", "no-store")
			// Refuse with a plain message.
			http.Error(w, "unexpected Host header", http.StatusForbidden)
			// Stop here.
			return
		} // end of the host check
		// The name is fine; hand the request on.
		next.ServeHTTP(w, r)
	}) // end of the wrapper
} // end of hostGuard
