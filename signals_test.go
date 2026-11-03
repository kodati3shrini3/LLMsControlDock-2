// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// context is the type the clean-up function receives.
	"context"
	// fmt builds the recorded log lines.
	"fmt"
	// os supplies the Signal type and the Interrupt value.
	"os"
	// strings searches the recorded log lines.
	"strings"
	// sync protects the recorder that several goroutines write to.
	"sync"
	// syscall names SIGTERM.
	"syscall"
	// testing is Go's built-in test framework.
	"testing"
	// time gives the tests a deadline so a mistake fails instead of hanging.
	"time"
) // end of imports

// recorder collects what the watcher does, so a test can look at it afterwards.
type recorder struct {
	// mu protects the fields, because the watcher runs in its own goroutine.
	mu sync.Mutex
	// shutdowns counts the calls of shutdown.
	shutdowns int
	// forced holds the exit codes passed to force.
	forced []int
	// lines holds the log lines.
	lines []string
	// work is what running() returns.
	work []string
	// shutdownDone is closed on the first shutdown call, so a test can wait for it.
	shutdownDone chan struct{}
	// forceDone is closed on the first force call, so a test can wait for it.
	forceDone chan struct{}
} // end of recorder

// newRecorder makes a recorder with its two wait channels.
func newRecorder() *recorder {
	// Fill the channels.
	return &recorder{shutdownDone: make(chan struct{}), forceDone: make(chan struct{})}
} // end of newRecorder

// actions turns the recorder into the actions the watcher uses.
func (r *recorder) actions() signalActions {
	// Four recording functions.
	return signalActions{
		// shutdown counts itself and releases the waiting test once.
		shutdown: func() {
			// One writer at a time.
			r.mu.Lock()
			// Release at the end.
			defer r.mu.Unlock()
			// Release the waiting test on the first call only.
			if r.shutdowns == 0 {
				// Close the wait channel.
				close(r.shutdownDone)
			} // end of the first-call check
			// Count it.
			r.shutdowns++
		}, // end of shutdown
		// force records the exit code and releases the waiting test once.
		force: func(code int) {
			// One writer at a time.
			r.mu.Lock()
			// Release at the end.
			defer r.mu.Unlock()
			// Release the waiting test on the first call only.
			if len(r.forced) == 0 {
				// Close the wait channel.
				close(r.forceDone)
			} // end of the first-call check
			// Keep the code.
			r.forced = append(r.forced, code)
		}, // end of force
		// logf keeps the formatted line.
		logf: func(format string, args ...any) {
			// One writer at a time.
			r.mu.Lock()
			// Release at the end.
			defer r.mu.Unlock()
			// Keep the line.
			r.lines = append(r.lines, fmt.Sprintf(format, args...))
		}, // end of logf
		// running hands back the pretend work list.
		running: func() []string {
			// One reader at a time.
			r.mu.Lock()
			// Release at the end.
			defer r.mu.Unlock()
			// The list.
			return r.work
		}, // end of running
	} // end of the actions
} // end of actions

// waitFor waits for a channel to close, or fails the test after two seconds.
func waitFor(t *testing.T, ch <-chan struct{}, what string) {
	// Mark this as a helper, so a failure points at the caller.
	t.Helper()
	// Either the event happens or the clock runs out.
	select {
	// The event happened.
	case <-ch:
	// Too slow: fail instead of hanging.
	case <-time.After(2 * time.Second):
		// Report what we waited for.
		t.Fatalf("timed out waiting for %s", what)
	} // end of the select
} // end of waitFor

// TestFirstSignalStopsCleanly checks that the first signal starts one clean shutdown, says so in the log, and stores the reason.
func TestFirstSignalStopsCleanly(t *testing.T) {
	// Restore the reason afterwards, so other tests see the default.
	t.Cleanup(func() { stopReason.Store("") })
	// The recorder and a channel to send signals on.
	rec := newRecorder()
	// A buffered channel, like the real one.
	sigs := make(chan os.Signal, 2)
	// Run the watcher in the background.
	done := make(chan struct{})
	// The goroutine.
	go func() { watchStopSignals(sigs, rec.actions()); close(done) }()
	// The first signal: Ctrl+C.
	sigs <- os.Interrupt
	// The shutdown must start.
	waitFor(t, rec.shutdownDone, "the clean shutdown")
	// Close the channel so the watcher ends.
	close(sigs)
	// Wait for the watcher to end.
	waitFor(t, done, "the watcher to end")
	// One lock to read the results.
	rec.mu.Lock()
	// Release at the end.
	defer rec.mu.Unlock()
	// Exactly one shutdown.
	if rec.shutdowns != 1 {
		// Report it.
		t.Fatalf("shutdown ran %d times, want 1", rec.shutdowns)
	} // end of the count check
	// No forced exit after one signal.
	if len(rec.forced) != 0 {
		// Report it.
		t.Fatalf("force was called after only one signal: %v", rec.forced)
	} // end of the force check
	// The log says what is happening and how to hurry it up.
	if len(rec.lines) == 0 || !strings.Contains(rec.lines[0], "stopping cleanly") || !strings.Contains(rec.lines[0], "again to quit at once") {
		// Report it.
		t.Fatalf("first log line = %q", rec.lines)
	} // end of the log check
	// The reason is stored for the last log line.
	if got := currentStopReason(); got != reasonSignal {
		// Report it.
		t.Fatalf("stop reason = %q, want %q", got, reasonSignal)
	} // end of the reason check
} // end of TestFirstSignalStopsCleanly

// TestSecondSignalQuitsAtOnce checks that a second signal forces an exit with code 1 and does not start a second shutdown.
func TestSecondSignalQuitsAtOnce(t *testing.T) {
	// Restore the reason afterwards.
	t.Cleanup(func() { stopReason.Store("") })
	// The recorder and the channel.
	rec := newRecorder()
	// A buffered channel.
	sigs := make(chan os.Signal, 2)
	// Run the watcher.
	done := make(chan struct{})
	// The goroutine.
	go func() { watchStopSignals(sigs, rec.actions()); close(done) }()
	// SIGTERM first, Ctrl+C second: any two signals count.
	sigs <- syscall.SIGTERM
	// Wait for the first shutdown to start.
	waitFor(t, rec.shutdownDone, "the clean shutdown")
	// The second signal.
	sigs <- os.Interrupt
	// The forced exit must follow.
	waitFor(t, rec.forceDone, "the forced exit")
	// The watcher ends by itself after forcing.
	waitFor(t, done, "the watcher to end")
	// One lock to read the results.
	rec.mu.Lock()
	// Release at the end.
	defer rec.mu.Unlock()
	// The exit code is 1 (the clean stop did not finish).
	if len(rec.forced) != 1 || rec.forced[0] != 1 {
		// Report it.
		t.Fatalf("forced = %v, want [1]", rec.forced)
	} // end of the code check
	// Still only one shutdown.
	if rec.shutdowns != 1 {
		// Report it.
		t.Fatalf("shutdown ran %d times, want 1", rec.shutdowns)
	} // end of the count check
	// The log says that nothing more is saved.
	if last := rec.lines[len(rec.lines)-1]; !strings.Contains(last, "quitting at once") || !strings.Contains(last, "nothing more is saved") {
		// Report it.
		t.Fatalf("last log line = %q", last)
	} // end of the log check
} // end of TestSecondSignalQuitsAtOnce

// TestRunningWorkIsNamed checks that work still running is named in the log when the first signal arrives.
func TestRunningWorkIsNamed(t *testing.T) {
	// Restore the reason afterwards.
	t.Cleanup(func() { stopReason.Store("") })
	// The recorder with pretend work.
	rec := newRecorder()
	// Two running pieces of work.
	rec.work = []string{"speed test of model-a", "load of model-b"}
	// A buffered channel.
	sigs := make(chan os.Signal, 2)
	// Run the watcher.
	done := make(chan struct{})
	// The goroutine.
	go func() { watchStopSignals(sigs, rec.actions()); close(done) }()
	// The signal.
	sigs <- os.Interrupt
	// Wait for the shutdown.
	waitFor(t, rec.shutdownDone, "the clean shutdown")
	// End the watcher.
	close(sigs)
	// Wait for it.
	waitFor(t, done, "the watcher to end")
	// One lock to read the results.
	rec.mu.Lock()
	// Release at the end.
	defer rec.mu.Unlock()
	// Both works are named in one line.
	joined := strings.Join(rec.lines, "\n")
	// Check both names.
	if !strings.Contains(joined, "speed test of model-a; load of model-b") {
		// Report it.
		t.Fatalf("running work not named in %q", joined)
	} // end of the name check
} // end of TestRunningWorkIsNamed

// TestWatcherEndsWhenChannelCloses checks that closing the channel ends the watcher without any action.
func TestWatcherEndsWhenChannelCloses(t *testing.T) {
	// The recorder and the channel.
	rec := newRecorder()
	// A channel nobody sends on.
	sigs := make(chan os.Signal, 2)
	// Run the watcher.
	done := make(chan struct{})
	// The goroutine.
	go func() { watchStopSignals(sigs, rec.actions()); close(done) }()
	// Close it at once.
	close(sigs)
	// The watcher must end.
	waitFor(t, done, "the watcher to end")
	// One lock to read the results.
	rec.mu.Lock()
	// Release at the end.
	defer rec.mu.Unlock()
	// Nothing happened.
	if rec.shutdowns != 0 || len(rec.forced) != 0 || len(rec.lines) != 0 {
		// Report it.
		t.Fatalf("unexpected actions: shutdowns=%d forced=%v lines=%q", rec.shutdowns, rec.forced, rec.lines)
	} // end of the nothing check
} // end of TestWatcherEndsWhenChannelCloses

// TestStopNowRunsCleanupBeforeStop checks the order: the clean-up of running work first, the shutdown after it.
func TestStopNowRunsCleanupBeforeStop(t *testing.T) {
	// Remember the real stop function and put it back afterwards.
	old := stopRequest
	// Restore at the end.
	t.Cleanup(func() { stopRequest = old })
	// The order in which things happen.
	var order []string
	// A mutex, because the clean-up runs in this goroutine but be safe.
	var mu sync.Mutex
	// A stop that only records itself.
	stopRequest = func() { mu.Lock(); order = append(order, "stop"); mu.Unlock() }
	// Register work whose clean-up records itself.
	end := activeWork.begin("pretend work", func(ctx context.Context) { mu.Lock(); order = append(order, "cleanup"); mu.Unlock() })
	// Forget the work at the end of the test.
	t.Cleanup(end)
	// Do the clean stop.
	stopNow()
	// Read the order.
	mu.Lock()
	// Release at the end.
	defer mu.Unlock()
	// Clean-up first, then stop.
	if len(order) != 2 || order[0] != "cleanup" || order[1] != "stop" {
		// Report it.
		t.Fatalf("order = %v, want [cleanup stop]", order)
	} // end of the order check
} // end of TestStopNowRunsCleanupBeforeStop

// TestOnceStopRunsOnce checks that asking for the stop twice (Ctrl+C and the Stop button) runs it only once.
func TestOnceStopRunsOnce(t *testing.T) {
	// A counter.
	n := 0
	// The wrapped function.
	f := onceStop(func() { n++ })
	// Ask three times.
	f()
	// Second ask.
	f()
	// Third ask.
	f()
	// Only the first one counted.
	if n != 1 {
		// Report it.
		t.Fatalf("stop ran %d times, want 1", n)
	} // end of the count check
} // end of TestOnceStopRunsOnce

// TestDefaultStopReasonIsThePage checks that without a signal the reason is the Stop button on the page.
func TestDefaultStopReasonIsThePage(t *testing.T) {
	// Make sure nothing is stored.
	stopReason.Store("")
	// The default.
	if got := currentStopReason(); got != reasonPage {
		// Report it.
		t.Fatalf("default reason = %q, want %q", got, reasonPage)
	} // end of the default check
} // end of TestDefaultStopReasonIsThePage
