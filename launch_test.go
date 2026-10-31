// Package main tells Go that this test file belongs to the same program as launch.go.
package main

import ( // import lists the packages this test file uses.
	// errors builds the pretend failures.
	"errors"
	// net/http provides the status codes and the handler type.
	"net/http"
	// httptest provides the pretend server.
	"net/http/httptest"
	// reflect compares the argument lists.
	"reflect"
	// strings searches the messages.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time provides durations.
	"time"
) // end of imports

// TestLauncherRunning checks that a running monitor is not started again: the page is just opened.
func TestLauncherRunning(t *testing.T) {
	// The record of what happened.
	var started, opened int
	// A launcher whose monitor already answers.
	l := launcher{probe: func(string) bool { return true }, start: func() error { started++; return nil }, open: func(string) error { opened++; return nil }, wait: time.Second, poll: time.Millisecond}
	// Run it.
	if err := l.run("http://127.0.0.1:8765/"); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the run check
	// Only the page was opened.
	if started != 0 || opened != 1 {
		// Report it.
		t.Errorf("started %d opened %d", started, opened)
	} // end of the count check
} // end of TestLauncherRunning

// TestLauncherStarts checks that a monitor that is not running is started, waited for, and then the page is opened.
func TestLauncherStarts(t *testing.T) {
	// The record.
	var started, opened, probes int
	// A launcher whose monitor answers on the third look.
	l := launcher{probe: func(string) bool { probes++; return started > 0 && probes >= 3 }, start: func() error { started++; return nil }, open: func(string) error { opened++; return nil }, wait: 2 * time.Second, poll: time.Millisecond}
	// Run it.
	if err := l.run("http://127.0.0.1:8765/"); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the run check
	// Started once, opened once.
	if started != 1 || opened != 1 {
		// Report it.
		t.Errorf("started %d opened %d", started, opened)
	} // end of the count check
} // end of TestLauncherStarts

// TestLauncherFailures checks the two failure paths: the start fails, or the monitor never answers.
func TestLauncherFailures(t *testing.T) {
	// The record.
	opened := 0
	// The start fails.
	l := launcher{probe: func(string) bool { return false }, start: func() error { return errors.New("boom") }, open: func(string) error { opened++; return nil }, wait: 50 * time.Millisecond, poll: time.Millisecond}
	// The error says what happened.
	if err := l.run("u"); err == nil || !strings.Contains(err.Error(), "could not be started") {
		// Report it.
		t.Errorf("start failure: %v", err)
	} // end of the start check
	// The monitor never answers.
	l.start = func() error { return nil }
	// The error says so.
	if err := l.run("u"); err == nil || !strings.Contains(err.Error(), "did not answer") {
		// Report it.
		t.Errorf("timeout: %v", err)
	} // end of the timeout check
	// The page was never opened.
	if opened != 0 {
		// Report it.
		t.Errorf("the page was opened %d times after a failure", opened)
	} // end of the open check
} // end of TestLauncherFailures

// TestHttpProbe checks the probe against a pretend monitor.
func TestHttpProbe(t *testing.T) {
	// A server that answers 200.
	ok := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	// Stop it at the end.
	defer ok.Close()
	// It is running.
	if !httpProbe(ok.URL + "/") {
		// Report it.
		t.Errorf("a running server was not seen")
	} // end of the running check
	// A server that answers 500 is not a healthy monitor.
	bad := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(500) }))
	// Stop it at the end.
	defer bad.Close()
	// Not running.
	if httpProbe(bad.URL + "/") {
		// Report it.
		t.Errorf("a failing server counted as running")
	} // end of the failing check
	// A closed server.
	url := ok.URL + "/"
	// Close it.
	ok.Close()
	// Not running.
	if httpProbe(url) {
		// Report it.
		t.Errorf("a closed server counted as running")
	} // end of the closed check
} // end of TestHttpProbe

// TestChildArgsAndLaunchURL checks the argument filter and the address builder.
func TestChildArgsAndLaunchURL(t *testing.T) {
	// The filter drops only the launch switch.
	got := childArgs([]string{"-launch", "-ollama-url", "http://x:1", "--launch", "-listen", "127.0.0.1:9"})
	// What must remain.
	want := []string{"-ollama-url", "http://x:1", "-listen", "127.0.0.1:9"}
	// Compare.
	if !reflect.DeepEqual(got, want) {
		// Report it.
		t.Errorf("childArgs = %v", got)
	} // end of the compare
	// The address a browser on this computer opens, for every kind of listen address.
	for in, out := range map[string]string{"127.0.0.1:8765": "http://127.0.0.1:8765/", "0.0.0.0:8765": "http://127.0.0.1:8765/", "[::1]:9000": "http://127.0.0.1:9000/"} {
		// Compare.
		if got := launchURL(in); got != out {
			// Report it.
			t.Errorf("launchURL(%q) = %q want %q", in, got, out)
		} // end of the compare
	} // end of the loop
} // end of TestChildArgsAndLaunchURL
