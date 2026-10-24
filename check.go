// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context lets a request be cancelled or given a deadline.
	"context"
	// crypto/tls provides the certificate-verification error type.
	"crypto/tls"
	// encoding/json decodes the JSON (JavaScript Object Notation) reply.
	"encoding/json"
	// errors lets us ask what a wrapped error really is (errors.Is and errors.As).
	"errors"
	// fmt builds formatted text.
	"fmt"
	// io limits how much of a reply we read.
	"io"
	// net holds the network error types (timeouts, DNS).
	"net"
	// net/http is the built-in web client.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// syscall holds the operating-system error numbers.
	"syscall"
	// time provides durations and the stopwatch.
	"time"
) // end of imports

// defaultCheckTimeout is how long one check waits before giving up (the editable setting arrives in Step 7).
const defaultCheckTimeout = 5 * time.Second

// maxVersionReply caps how many bytes of the reply we read, so a wrong server cannot flood us.
const maxVersionReply = 64 * 1024

// windowsRefused is the number Windows uses for "connection refused" (WSAECONNREFUSED); Go does not map it to syscall.ECONNREFUSED there.
const windowsRefused = 10061

// checkResult is the outcome of one check.
type checkResult struct {
	// Online is true only when Ollama answered with a valid version.
	Online bool
	// Version is the Ollama version text, such as 0.34.4 (empty when offline).
	Version string
	// Elapsed is how long the check took.
	Elapsed time.Duration
	// Reason is a short plain-language explanation when Online is false (empty when online).
	Reason string
} // end of checkResult

// versionReply is the shape of the JSON that /api/version returns.
type versionReply struct {
	// Version is read from the "version" field of the JSON.
	Version string `json:"version"`
} // end of versionReply

// checkOllama asks base+/api/version once and reports online or offline with a reason.
func checkOllama(ctx context.Context, base *url.URL, timeout time.Duration) checkResult {
	// Start the stopwatch.
	start := time.Now()
	// Build the full address by adding the path pieces safely (JoinPath avoids doubled slashes).
	target := base.JoinPath("api", "version").String()
	// Create the request; the context allows cancelling it from outside.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	// A failure here means the address could not form a request.
	if err != nil {
		// Report it as offline, with a fixed message that never repeats the address.
		return checkResult{Elapsed: time.Since(start), Reason: "the address could not be used to build a request"}
	} // end of the request check
	// Create a client that gives up after the timeout.
	client := &http.Client{Timeout: timeout}
	// Send the request and wait for the reply.
	resp, err := client.Do(req)
	// A failure here means no reply arrived at all.
	if err != nil {
		// Turn the technical error into a plain reason.
		return checkResult{Elapsed: time.Since(start), Reason: explainError(err)}
	} // end of the send check
	// Always close the reply body when this function ends, so the connection is released.
	defer resp.Body.Close()
	// Anything other than status 200 means this is not a healthy Ollama.
	if resp.StatusCode != http.StatusOK {
		// Report the status number; it contains no secrets.
		return checkResult{Elapsed: time.Since(start), Reason: fmt.Sprintf("the server answered with status %d, not 200; it may not be Ollama", resp.StatusCode)}
	} // end of the status check
	// Prepare a place to hold the decoded JSON.
	var reply versionReply
	// Decode at most maxVersionReply bytes of the body into the struct.
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxVersionReply)).Decode(&reply); err != nil {
		// Not JSON means something else answered.
		return checkResult{Elapsed: time.Since(start), Reason: "the reply was not JSON, so it does not look like Ollama"}
	} // end of the decode check
	// An empty version means the JSON had the wrong shape.
	if reply.Version == "" {
		// Report the wrong shape.
		return checkResult{Elapsed: time.Since(start), Reason: "the reply has no version field, so it does not look like Ollama"}
	} // end of the version check
	// Everything worked: online, with the version and the time taken.
	return checkResult{Online: true, Version: reply.Version, Elapsed: time.Since(start)}
} // end of checkOllama

// explainError turns a network error into a short plain-language reason; it never prints err itself, which could hold a password.
func explainError(err error) string {
	// Declare a variable that errors.As can fill if a DNS (Domain Name System) error is inside.
	var dnsErr *net.DNSError
	// Name not found: the host name could not be translated into an address.
	if errors.As(err, &dnsErr) {
		// Report it in plain words.
		return "the host name was not found; check the spelling of the address"
	} // end of the DNS check
	// Declare a variable for the operating-system error number, if one is inside.
	var errno syscall.Errno
	// Connection refused: the machine answered but nothing listens on that port (Linux and macOS number, or the Windows number).
	if errors.Is(err, syscall.ECONNREFUSED) || (errors.As(err, &errno) && uintptr(errno) == windowsRefused) {
		// Report it in plain words.
		return "connection refused; Ollama is probably not running on that address and port"
	} // end of the refused check
	// Declare a variable for a certificate problem, if one is inside.
	var certErr *tls.CertificateVerificationError
	// Certificate problem: HTTPS (HTTP Secure) was used but the certificate is not trusted.
	if errors.As(err, &certErr) {
		// Report it in plain words.
		return "the HTTPS certificate is not trusted or does not match the host name"
	} // end of the certificate check
	// Declare a variable for any network error that can say whether it was a timeout.
	var netErr net.Error
	// Timeout: no answer within the allowed time (also covers a cancelled deadline).
	if errors.Is(err, context.DeadlineExceeded) || (errors.As(err, &netErr) && netErr.Timeout()) {
		// Report it in plain words.
		return "timed out; the machine may be off, busy, or blocked by a firewall"
	} // end of the timeout check
	// Anything else: say so honestly, without guessing.
	return "could not connect; the cause is not one of the known cases"
} // end of explainError
