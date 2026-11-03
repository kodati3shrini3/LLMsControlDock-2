// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the packages this file uses.
	// errors builds a plain error.
	"errors"
	// net opens a real port twice.
	"net"
	// net/http runs fake programs on a port.
	"net/http"
	// net/http/httptest runs them.
	"net/http/httptest"
	// strings checks the messages.
	"strings"
	// syscall gives the Windows error number.
	"syscall"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestRealSecondListenIsAddrInUse checks the recognition on the real operating system: taking a port twice must be recognised.
func TestRealSecondListenIsAddrInUse(t *testing.T) {
	// Take a free port.
	first, err := net.Listen("tcp", "127.0.0.1:0")
	// It must work.
	if err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the check
	// Release it at the end.
	defer first.Close()
	// Take the same one again.
	_, err = net.Listen("tcp", first.Addr().String())
	// It must fail, and be recognised.
	if err == nil || !isAddrInUse(err) {
		// Report it.
		t.Fatalf("err = %v, want address in use", err)
	} // end of the check
} // end of TestRealSecondListenIsAddrInUse

// TestAddrInUseRecognition checks the cases that a real port cannot give on this system, including the Windows number.
func TestAddrInUseRecognition(t *testing.T) {
	// Cases.
	for name, tc := range map[string]struct {
		err  error
		want bool
	}{
		"linux number":      {syscall.EADDRINUSE, true},
		"windows number":    {syscall.Errno(10048), true},
		"wrapped":           {&net.OpError{Op: "listen", Err: syscall.EADDRINUSE}, true},
		"permission denied": {syscall.EACCES, false},
		"plain":             {errors.New("boom"), false},
		"nil":               {nil, false},
	} {
		// One sub-test per case.
		t.Run(name, func(t *testing.T) {
			// Check.
			if got := isAddrInUse(tc.err); got != tc.want {
				// Report it.
				t.Errorf("isAddrInUse = %v, want %v", got, tc.want)
			} // end of the check
		})
	} // end of the loop
} // end of TestAddrInUseRecognition

// TestNextPortAddress checks the suggested other port.
func TestNextPortAddress(t *testing.T) {
	// Cases.
	for in, want := range map[string]string{
		"127.0.0.1:8765":  "127.0.0.1:8766",
		"0.0.0.0:8765":    "0.0.0.0:8766",
		":8765":           ":8766",
		"[::1]:8765":      "[::1]:8766",
		"127.0.0.1:65535": "",
		"nonsense":        "",
		"127.0.0.1:abc":   "",
	} {
		// Check.
		if got := nextPortAddress(in); got != want {
			// Report it.
			t.Errorf("nextPortAddress(%q) = %q, want %q", in, got, want)
		} // end of the check
	} // end of the loop
} // end of TestNextPortAddress

// TestFailureMessages checks the three messages: our own monitor on the port, another program, and another reason.
func TestFailureMessages(t *testing.T) {
	// Put the probe back at the end.
	old := probeIsOurs
	// Restore.
	t.Cleanup(func() { probeIsOurs = old })
	// Our own monitor is there.
	probeIsOurs = func(string) bool { return true }
	// The message.
	m := listenFailureMessage("127.0.0.1:8765", syscall.EADDRINUSE)
	// It names the address, says how to stop it, and offers another port.
	for _, want := range []string{"already running", "http://127.0.0.1:8765/", "Stop button", "Ctrl+C", "-listen 127.0.0.1:8766"} {
		// Check each.
		if !strings.Contains(m, want) {
			// Report it.
			t.Errorf("own-monitor message lacks %q: %s", want, m)
		} // end of the check
	} // end of the loop
	// Another program is there.
	probeIsOurs = func(string) bool { return false }
	// The message.
	m = listenFailureMessage("127.0.0.1:8765", syscall.EADDRINUSE)
	// It says another program, with the port, and offers another port.
	for _, want := range []string{"Port 8765", "another program", "not OllamaControlCenter", "For example: -listen 127.0.0.1:8766"} {
		// Check each.
		if !strings.Contains(m, want) {
			// Report it.
			t.Errorf("other-program message lacks %q: %s", want, m)
		} // end of the check
	} // end of the loop
	// The other-program message does not talk about a second copy.
	if strings.Contains(m, "second copy") {
		// Report it.
		t.Errorf("other-program message mentions a second copy: %s", m)
	} // end of the wording check
	// Another reason: no claim about a busy port, and the real reason is kept.
	m = listenFailureMessage("127.0.0.1:80", syscall.EACCES)
	// The text.
	if strings.Contains(m, "already") || !strings.Contains(m, "cannot listen on 127.0.0.1:80") || !strings.Contains(m, syscall.EACCES.Error()) {
		// Report it.
		t.Errorf("other-reason message: %s", m)
	} // end of the check
} // end of TestFailureMessages

// TestProbeIsOurs checks the real probe against fake programs: a page that names OllamaControlCenter, a page that does not, an error page, and nothing at all.
func TestProbeIsOurs(t *testing.T) {
	// A program that looks like ours.
	ours := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Only the About page.
		if r.URL.Path != "/about" {
			// Anything else is not found.
			http.NotFound(w, r)
			// Done.
			return
		} // end of the path check
		// The title names the program.
		w.Write([]byte("<title>About - OllamaControlCenter</title>"))
	}))
	// Stop it at the end.
	defer ours.Close()
	// Another web program.
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("<title>Something else</title>")) }))
	// Stop it at the end.
	defer other.Close()
	// A program that always fails.
	broken := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "OllamaControlCenter", 500) }))
	// Stop it at the end.
	defer broken.Close()
	// The cases.
	if !probeIsOurs(ours.URL + "/") {
		// Report it.
		t.Error("our page was not recognised")
	} // end of the ours check
	// Not ours.
	if probeIsOurs(other.URL + "/") {
		// Report it.
		t.Error("another page was taken for ours")
	} // end of the other check
	// An error page is not ours even if it names the program.
	if probeIsOurs(broken.URL + "/") {
		// Report it.
		t.Error("an error page was taken for ours")
	} // end of the broken check
	// Nothing answering.
	if probeIsOurs("http://127.0.0.1:1/") {
		// Report it.
		t.Error("nothing was taken for ours")
	} // end of the nothing check
} // end of TestProbeIsOurs
