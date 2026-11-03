// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the packages this file uses.
	// errors recognises the "port already in use" error inside a longer error.
	"errors"
	// fmt builds the message texts.
	"fmt"
	// io reads a limited part of an answer.
	"io"
	// net splits the listen address and holds the port.
	"net"
	// net/http asks the program on the port who it is.
	"net/http"
	// strconv turns the port into a number and back.
	"strconv"
	// strings looks for the program's name in an answer.
	"strings"
	// syscall holds the operating system's error numbers.
	"syscall"
	// time limits the question.
	"time"
) // end of imports

// isAddrInUse says whether an error means "another program already uses this port". Linux and macOS give EADDRINUSE; Windows gives its own number 10048 (WSAEADDRINUSE), which Go does not map to EADDRINUSE.
func isAddrInUse(err error) bool {
	// Either number counts; the Windows number means nothing on the other systems, so it never matches there by mistake.
	return errors.Is(err, syscall.EADDRINUSE) || errors.Is(err, syscall.Errno(10048))
} // end of isAddrInUse

// probeIsOurs asks whatever answers at the address whether it is an OllamaControlCenter monitor: its read-only About page always answers and names the program. A test replaces it.
var probeIsOurs = func(url string) bool {
	// A short time limit: this runs while the program is leaving anyway.
	c := &http.Client{Timeout: 2 * time.Second}
	// Ask for the About page.
	res, err := c.Get(url + "about")
	// No answer, so it is not a web page of ours.
	if err != nil {
		// Not ours, as far as we can tell.
		return false
	} // end of the error check
	// Close the body at the end.
	defer res.Body.Close()
	// Only a normal page can be ours.
	if res.StatusCode != http.StatusOK {
		// Not ours.
		return false
	} // end of the status check
	// Read the first 64 KB; the name is in the page title.
	body, _ := io.ReadAll(io.LimitReader(res.Body, 64*1024))
	// Ours when the page names the program.
	return strings.Contains(string(body), "OllamaControlCenter")
} // end of probeIsOurs

// nextPortAddress suggests the same address with the next port number, or the empty text when the address cannot be read.
func nextPortAddress(listen string) string {
	// Split host and port.
	host, port, err := net.SplitHostPort(listen)
	// An unreadable address.
	if err != nil {
		// No suggestion.
		return ""
	} // end of the split check
	// The port as a number.
	n, err := strconv.Atoi(port)
	// Not a number, or the last port.
	if err != nil || n < 1 || n >= 65535 {
		// No suggestion.
		return ""
	} // end of the number check
	// A listen address of ":8765" (all addresses) would give ":8766"; keep the same host part.
	return net.JoinHostPort(host, strconv.Itoa(n+1))
} // end of nextPortAddress

// listenFailureMessage explains in plain words why the program could not take its port and what to do; it never contains a password or anything private, only the listen address.
func listenFailureMessage(listen string, err error) string {
	// Another reason than a busy port: say it as it is.
	if !isAddrInUse(err) {
		// The real reason follows.
		return fmt.Sprintf("OllamaControlCenter cannot listen on %s: %v", listen, err)
	} // end of the other-reason case
	// The address a browser on this computer opens.
	url := launchURL(listen)
	// The next free-looking port, when one can be named.
	next := nextPortAddress(listen)
	// The hint for a second copy.
	hint := ""
	// Name the option when we can.
	if next != "" {
		// The option to use.
		hint = fmt.Sprintf(" To run a second copy on purpose, start it on another port, for example: -listen %s", next)
	} // end of the hint
	// Is the program on that port one of ours?
	if probeIsOurs(url) {
		// Say so, and say what to do.
		return fmt.Sprintf("OllamaControlCenter is already running and answers at %s. Open that address in your browser. To stop it, use its Stop button, or press Ctrl+C in the window where it runs.%s", url, hint)
	} // end of the ours case
	// The option for another port, when one can be named.
	other := ""
	// Name the option when we can.
	if next != "" {
		// The option to use.
		other = fmt.Sprintf(" For example: -listen %s", next)
	} // end of the option
	// Something else uses the port.
	return fmt.Sprintf("Port %s is already used by another program, which is not OllamaControlCenter. Stop that program, or start this one on another port.%s", listen[strings.LastIndex(listen, ":")+1:], other)
} // end of listenFailureMessage
