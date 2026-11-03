#!/usr/bin/env bash
# Script 74 (clean stop on Ctrl+C and on a termination request, version 0.29.1): until now only the Stop button stopped the program cleanly; Ctrl+C or "kill" ended it on the spot, so the last few minutes of check history were lost and the work in progress was not tidied up. Now the first Ctrl+C (or SIGTERM, which "kill", "docker stop" and a service manager send) undoes what running work changed, writes the check history when that is switched on, closes the web page and exits with code 0; a second Ctrl+C quits at once. It adds signals.go and signals_test.go and changes main.go (two small edits) and about.go (version 0.29.1). go.mod is NOT touched.
# Run it from the project folder, on a feature branch (never on main): cd ~/OllamaControlCenter && git checkout -b fix/clean-ctrl-c && bash scripts/74-step47-clean-ctrl-c.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two files this script changes, BEFORE the change (the version made from main after pull request 34).
EXPECT_ABOUT_BEFORE="612b64095709d68435d0559568441bb015a27ba4e488a7d9213aa0c90967eb0f"
# The expected sha256 of main.go BEFORE the change.
EXPECT_MAIN_BEFORE="5231b2054440e45dd95ad6057632f4f37ef499d0432853ca815d05cc0864d9a8"
# The expected sha256 of the four files AFTER the change.
EXPECT_ABOUT_AFTER="d3984838cb6901cf819677bc1dab8f86f6f71fc78509664d449faa7205a1f11d"
# The expected sha256 of main.go AFTER the change.
EXPECT_MAIN_AFTER="6d8e3a2c376ad4b724f4a5a0f098ec1d88d87423e0ff1665152e6ba4d9d9059f"
# The expected sha256 of the new signals.go.
EXPECT_SIGNALS_AFTER="0c44d2dbcd8a6434f233df37624bab5283b8415a4a77d3d748fcd7607718492d"
# The expected sha256 of the new signals_test.go.
EXPECT_SIGNALS_TEST_AFTER="47229c4a50fd45d68a7b4edf883b88351e9367f9e5ba04185b7e828e97e03bd6"

# Count of passed and failed checks, for the summary at the end.
PASS=0
# Count of failed checks.
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be OllamaControlCenter: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the OllamaControlCenter folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; run: git checkout -b fix/clean-ctrl-c"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Refuse to run twice: the new file already exists when the change was applied before.
[ ! -e signals.go ] || fail "signals.go already exists: this script was already applied on this branch"
# Report it.
pass "signals.go does not exist yet (script not applied before)"

# The files must be exactly the ones the change was made against; otherwise the patch could land in the wrong place.
[ "$(sha256sum about.go | cut -d' ' -f1)" = "$EXPECT_ABOUT_BEFORE" ] || fail "about.go is not the expected version (sha256 differs); tell Claude which commit you are on"
# Same for main.go.
[ "$(sha256sum main.go | cut -d' ' -f1)" = "$EXPECT_MAIN_BEFORE" ] || fail "main.go is not the expected version (sha256 differs); tell Claude which commit you are on"
# Report it.
pass "about.go and main.go are the expected versions before the change"

# A temporary file for the patch, removed when the script ends (also on an error).
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_74_END'
diff --git a/about.go b/about.go
index cadf14e..528f6f9 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.29.0"
+const appVersion = "0.29.1"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/main.go b/main.go
index 3f08ef2..9219a8e 100644
--- a/main.go
+++ b/main.go
@@ -222,8 +222,8 @@ func main() {
 	log.Printf("OllamaControlCenter listening on http://%s (from %s; press Ctrl+C to stop)", listenAddr, listenSource)
 	// Closed when the shutdown that the Stop button started has finished.
 	stopped := make(chan struct{})
-	// The Stop button's last step: shut the web server down, waiting at most 5 seconds for requests that are still running.
-	stopRequest = func() {
+	// The last step of every stop (the Stop button, Ctrl+C, a termination request): shut the web server down, waiting at most 5 seconds for requests that are still running; onceStop makes it run only the first time it is asked.
+	stopRequest = onceStop(func() {
 		// In the background, so the request that asked for it can finish.
 		go func() {
 			// A time limit for the polite shutdown.
@@ -243,15 +243,17 @@ func main() {
 			// Tell main that it can leave.
 			close(stopped)
 		}() // end of the goroutine
-	} // end of stopRequest
+	}) // end of stopRequest
+	// From here on Ctrl+C and a termination request (SIGTERM) stop the program as cleanly as the Stop button does; the first one asks politely, a second one quits at once.
+	startStopSignals()
 	// Start serving; this call blocks (waits) until the server stops or fails, for example if the port is taken.
 	err = server.ListenAndServe()
 	// A shutdown asked for by the Stop button is a normal end, not an error.
 	if errors.Is(err, http.ErrServerClosed) {
 		// Wait until the shutdown has finished.
 		<-stopped
-		// Say why the program ends.
-		log.Printf("OllamaControlCenter stopped from its page")
+		// Say why the program ends: from its page, or by Ctrl+C or a termination request.
+		log.Printf("OllamaControlCenter stopped %s", currentStopReason())
 		// Leave with the success code.
 		return
 	} // end of the normal stop
diff --git a/signals.go b/signals.go
new file mode 100644
index 0000000..700dfcd
--- /dev/null
+++ b/signals.go
@@ -0,0 +1,125 @@
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context gives the clean-up of running work a time limit.
+	"context"
+	// log prints timestamped messages to the terminal.
+	"log"
+	// os supplies the Interrupt signal and the immediate exit.
+	"os"
+	// os/signal delivers Ctrl+C and the termination request to a channel (the official Go package for this).
+	"os/signal"
+	// strings joins the descriptions of running work into one line.
+	"strings"
+	// sync makes sure the shutdown runs only once, however many things ask for it.
+	"sync"
+	// sync/atomic holds the reason for stopping so main can read it safely from another goroutine.
+	"sync/atomic"
+	// syscall names SIGTERM; Go defines that name on Windows too.
+	"syscall"
+) // end of imports
+
+// reasonPage is the stop reason when the person pressed Stop on the page (the default).
+const reasonPage = "from its page"
+
+// reasonSignal is the stop reason when Ctrl+C or a termination request arrived.
+const reasonSignal = "by Ctrl+C or a termination request"
+
+// stopReason holds the reason for stopping as text, so the last log line can say why the program ended.
+var stopReason atomic.Value
+
+// currentStopReason returns the reason for stopping; the page is the default when nothing else was stored.
+func currentStopReason() string {
+	// Read the stored value; it is empty (nil) until a signal arrives.
+	if s, ok := stopReason.Load().(string); ok && s != "" {
+		// A stored reason wins.
+		return s
+	} // end of the stored check
+	// Nothing stored: the Stop button on the page.
+	return reasonPage
+} // end of currentStopReason
+
+// onceStop wraps a stop function so that it runs only the first time it is called (a second Ctrl+C or the Stop button after it must not shut down twice).
+func onceStop(f func()) func() {
+	// The guard that lets the first call through and turns the others away.
+	var once sync.Once
+	// The wrapped function.
+	return func() {
+		// Run f one time only.
+		once.Do(f)
+	} // end of the wrapper
+} // end of onceStop
+
+// stopNow is the clean stop for a signal: it undoes what running work changed (within the time limit), then shuts the program down the same way the Stop button does.
+func stopNow() {
+	// The same time limit the Stop button uses for the clean-up.
+	ctx, cancel := context.WithTimeout(context.Background(), stopCleanupLimit)
+	// Undo what running work changed, for example unload a model a test loaded.
+	activeWork.runCleanups(ctx)
+	// Release the timer.
+	cancel()
+	// Save the history if the person turned that on, close the web server, and let main leave.
+	stopRequest()
+} // end of stopNow
+
+// signalActions are the things the signal watcher does; tests replace them with recorders.
+type signalActions struct {
+	// shutdown stops the program cleanly; it runs in its own goroutine so a second signal can still be read.
+	shutdown func()
+	// force ends the program at once with the given exit code.
+	force func(code int)
+	// logf writes one line to the log.
+	logf func(format string, args ...any)
+	// running returns the descriptions of the work that is running right now.
+	running func() []string
+} // end of signalActions
+
+// realSignalActions wires the watcher to the real program.
+func realSignalActions() signalActions {
+	// The real parts.
+	return signalActions{shutdown: stopNow, force: os.Exit, logf: log.Printf, running: activeWork.texts}
+} // end of realSignalActions
+
+// watchStopSignals reads signals until the channel closes: the first one starts the clean stop, the second one quits at once.
+func watchStopSignals(sigs <-chan os.Signal, act signalActions) {
+	// True until the first signal has been handled.
+	first := true
+	// Wait for each signal in turn; the loop ends when the channel is closed.
+	for sig := range sigs {
+		// The first signal asks for a clean stop.
+		if first {
+			// From now on a signal means "quit at once".
+			first = false
+			// Remember why we stop, so the last log line can say it.
+			stopReason.Store(reasonSignal)
+			// Tell the person what is happening and how to hurry it up.
+			act.logf("OllamaControlCenter received %v: stopping cleanly (press Ctrl+C again to quit at once)", sig)
+			// Work that is still running is cut short; say which.
+			if work := act.running(); len(work) > 0 {
+				// One line naming the work.
+				act.logf("work still running will be stopped: %s", strings.Join(work, "; "))
+			} // end of the running-work check
+			// Run the clean stop in the background, so this loop keeps listening.
+			go act.shutdown()
+			// Wait for the next signal.
+			continue
+		} // end of the first-signal case
+		// A second signal: the person does not want to wait.
+		act.logf("OllamaControlCenter received %v again: quitting at once; nothing more is saved", sig)
+		// Leave with a failure code, because the clean stop did not finish.
+		act.force(1)
+		// Stop reading signals.
+		return
+	} // end of the signal loop
+} // end of watchStopSignals
+
+// startStopSignals asks the operating system to deliver Ctrl+C (os.Interrupt) and the termination request (SIGTERM) to the watcher.
+func startStopSignals() {
+	// A buffer of 2, because the signal package never waits for a slow reader and would drop a signal otherwise.
+	sigs := make(chan os.Signal, 2)
+	// os.Interrupt is Ctrl+C on every system; SIGTERM is what "kill", "docker stop" and a service manager send (on Windows it also stands for the console closing).
+	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
+	// Watch in the background for as long as the program runs.
+	go watchStopSignals(sigs, realSignalActions())
+} // end of startStopSignals
diff --git a/signals_test.go b/signals_test.go
new file mode 100644
index 0000000..863c681
--- /dev/null
+++ b/signals_test.go
@@ -0,0 +1,321 @@
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context is the type the clean-up function receives.
+	"context"
+	// fmt builds the recorded log lines.
+	"fmt"
+	// os supplies the Signal type and the Interrupt value.
+	"os"
+	// strings searches the recorded log lines.
+	"strings"
+	// sync protects the recorder that several goroutines write to.
+	"sync"
+	// syscall names SIGTERM.
+	"syscall"
+	// testing is Go's built-in test framework.
+	"testing"
+	// time gives the tests a deadline so a mistake fails instead of hanging.
+	"time"
+) // end of imports
+
+// recorder collects what the watcher does, so a test can look at it afterwards.
+type recorder struct {
+	// mu protects the fields, because the watcher runs in its own goroutine.
+	mu sync.Mutex
+	// shutdowns counts the calls of shutdown.
+	shutdowns int
+	// forced holds the exit codes passed to force.
+	forced []int
+	// lines holds the log lines.
+	lines []string
+	// work is what running() returns.
+	work []string
+	// shutdownDone is closed on the first shutdown call, so a test can wait for it.
+	shutdownDone chan struct{}
+	// forceDone is closed on the first force call, so a test can wait for it.
+	forceDone chan struct{}
+} // end of recorder
+
+// newRecorder makes a recorder with its two wait channels.
+func newRecorder() *recorder {
+	// Fill the channels.
+	return &recorder{shutdownDone: make(chan struct{}), forceDone: make(chan struct{})}
+} // end of newRecorder
+
+// actions turns the recorder into the actions the watcher uses.
+func (r *recorder) actions() signalActions {
+	// Four recording functions.
+	return signalActions{
+		// shutdown counts itself and releases the waiting test once.
+		shutdown: func() {
+			// One writer at a time.
+			r.mu.Lock()
+			// Release at the end.
+			defer r.mu.Unlock()
+			// Release the waiting test on the first call only.
+			if r.shutdowns == 0 {
+				// Close the wait channel.
+				close(r.shutdownDone)
+			} // end of the first-call check
+			// Count it.
+			r.shutdowns++
+		}, // end of shutdown
+		// force records the exit code and releases the waiting test once.
+		force: func(code int) {
+			// One writer at a time.
+			r.mu.Lock()
+			// Release at the end.
+			defer r.mu.Unlock()
+			// Release the waiting test on the first call only.
+			if len(r.forced) == 0 {
+				// Close the wait channel.
+				close(r.forceDone)
+			} // end of the first-call check
+			// Keep the code.
+			r.forced = append(r.forced, code)
+		}, // end of force
+		// logf keeps the formatted line.
+		logf: func(format string, args ...any) {
+			// One writer at a time.
+			r.mu.Lock()
+			// Release at the end.
+			defer r.mu.Unlock()
+			// Keep the line.
+			r.lines = append(r.lines, fmt.Sprintf(format, args...))
+		}, // end of logf
+		// running hands back the pretend work list.
+		running: func() []string {
+			// One reader at a time.
+			r.mu.Lock()
+			// Release at the end.
+			defer r.mu.Unlock()
+			// The list.
+			return r.work
+		}, // end of running
+	} // end of the actions
+} // end of actions
+
+// waitFor waits for a channel to close, or fails the test after two seconds.
+func waitFor(t *testing.T, ch <-chan struct{}, what string) {
+	// Mark this as a helper, so a failure points at the caller.
+	t.Helper()
+	// Either the event happens or the clock runs out.
+	select {
+	// The event happened.
+	case <-ch:
+	// Too slow: fail instead of hanging.
+	case <-time.After(2 * time.Second):
+		// Report what we waited for.
+		t.Fatalf("timed out waiting for %s", what)
+	} // end of the select
+} // end of waitFor
+
+// TestFirstSignalStopsCleanly checks that the first signal starts one clean shutdown, says so in the log, and stores the reason.
+func TestFirstSignalStopsCleanly(t *testing.T) {
+	// Restore the reason afterwards, so other tests see the default.
+	t.Cleanup(func() { stopReason.Store("") })
+	// The recorder and a channel to send signals on.
+	rec := newRecorder()
+	// A buffered channel, like the real one.
+	sigs := make(chan os.Signal, 2)
+	// Run the watcher in the background.
+	done := make(chan struct{})
+	// The goroutine.
+	go func() { watchStopSignals(sigs, rec.actions()); close(done) }()
+	// The first signal: Ctrl+C.
+	sigs <- os.Interrupt
+	// The shutdown must start.
+	waitFor(t, rec.shutdownDone, "the clean shutdown")
+	// Close the channel so the watcher ends.
+	close(sigs)
+	// Wait for the watcher to end.
+	waitFor(t, done, "the watcher to end")
+	// One lock to read the results.
+	rec.mu.Lock()
+	// Release at the end.
+	defer rec.mu.Unlock()
+	// Exactly one shutdown.
+	if rec.shutdowns != 1 {
+		// Report it.
+		t.Fatalf("shutdown ran %d times, want 1", rec.shutdowns)
+	} // end of the count check
+	// No forced exit after one signal.
+	if len(rec.forced) != 0 {
+		// Report it.
+		t.Fatalf("force was called after only one signal: %v", rec.forced)
+	} // end of the force check
+	// The log says what is happening and how to hurry it up.
+	if len(rec.lines) == 0 || !strings.Contains(rec.lines[0], "stopping cleanly") || !strings.Contains(rec.lines[0], "again to quit at once") {
+		// Report it.
+		t.Fatalf("first log line = %q", rec.lines)
+	} // end of the log check
+	// The reason is stored for the last log line.
+	if got := currentStopReason(); got != reasonSignal {
+		// Report it.
+		t.Fatalf("stop reason = %q, want %q", got, reasonSignal)
+	} // end of the reason check
+} // end of TestFirstSignalStopsCleanly
+
+// TestSecondSignalQuitsAtOnce checks that a second signal forces an exit with code 1 and does not start a second shutdown.
+func TestSecondSignalQuitsAtOnce(t *testing.T) {
+	// Restore the reason afterwards.
+	t.Cleanup(func() { stopReason.Store("") })
+	// The recorder and the channel.
+	rec := newRecorder()
+	// A buffered channel.
+	sigs := make(chan os.Signal, 2)
+	// Run the watcher.
+	done := make(chan struct{})
+	// The goroutine.
+	go func() { watchStopSignals(sigs, rec.actions()); close(done) }()
+	// SIGTERM first, Ctrl+C second: any two signals count.
+	sigs <- syscall.SIGTERM
+	// Wait for the first shutdown to start.
+	waitFor(t, rec.shutdownDone, "the clean shutdown")
+	// The second signal.
+	sigs <- os.Interrupt
+	// The forced exit must follow.
+	waitFor(t, rec.forceDone, "the forced exit")
+	// The watcher ends by itself after forcing.
+	waitFor(t, done, "the watcher to end")
+	// One lock to read the results.
+	rec.mu.Lock()
+	// Release at the end.
+	defer rec.mu.Unlock()
+	// The exit code is 1 (the clean stop did not finish).
+	if len(rec.forced) != 1 || rec.forced[0] != 1 {
+		// Report it.
+		t.Fatalf("forced = %v, want [1]", rec.forced)
+	} // end of the code check
+	// Still only one shutdown.
+	if rec.shutdowns != 1 {
+		// Report it.
+		t.Fatalf("shutdown ran %d times, want 1", rec.shutdowns)
+	} // end of the count check
+	// The log says that nothing more is saved.
+	if last := rec.lines[len(rec.lines)-1]; !strings.Contains(last, "quitting at once") || !strings.Contains(last, "nothing more is saved") {
+		// Report it.
+		t.Fatalf("last log line = %q", last)
+	} // end of the log check
+} // end of TestSecondSignalQuitsAtOnce
+
+// TestRunningWorkIsNamed checks that work still running is named in the log when the first signal arrives.
+func TestRunningWorkIsNamed(t *testing.T) {
+	// Restore the reason afterwards.
+	t.Cleanup(func() { stopReason.Store("") })
+	// The recorder with pretend work.
+	rec := newRecorder()
+	// Two running pieces of work.
+	rec.work = []string{"speed test of model-a", "load of model-b"}
+	// A buffered channel.
+	sigs := make(chan os.Signal, 2)
+	// Run the watcher.
+	done := make(chan struct{})
+	// The goroutine.
+	go func() { watchStopSignals(sigs, rec.actions()); close(done) }()
+	// The signal.
+	sigs <- os.Interrupt
+	// Wait for the shutdown.
+	waitFor(t, rec.shutdownDone, "the clean shutdown")
+	// End the watcher.
+	close(sigs)
+	// Wait for it.
+	waitFor(t, done, "the watcher to end")
+	// One lock to read the results.
+	rec.mu.Lock()
+	// Release at the end.
+	defer rec.mu.Unlock()
+	// Both works are named in one line.
+	joined := strings.Join(rec.lines, "\n")
+	// Check both names.
+	if !strings.Contains(joined, "speed test of model-a; load of model-b") {
+		// Report it.
+		t.Fatalf("running work not named in %q", joined)
+	} // end of the name check
+} // end of TestRunningWorkIsNamed
+
+// TestWatcherEndsWhenChannelCloses checks that closing the channel ends the watcher without any action.
+func TestWatcherEndsWhenChannelCloses(t *testing.T) {
+	// The recorder and the channel.
+	rec := newRecorder()
+	// A channel nobody sends on.
+	sigs := make(chan os.Signal, 2)
+	// Run the watcher.
+	done := make(chan struct{})
+	// The goroutine.
+	go func() { watchStopSignals(sigs, rec.actions()); close(done) }()
+	// Close it at once.
+	close(sigs)
+	// The watcher must end.
+	waitFor(t, done, "the watcher to end")
+	// One lock to read the results.
+	rec.mu.Lock()
+	// Release at the end.
+	defer rec.mu.Unlock()
+	// Nothing happened.
+	if rec.shutdowns != 0 || len(rec.forced) != 0 || len(rec.lines) != 0 {
+		// Report it.
+		t.Fatalf("unexpected actions: shutdowns=%d forced=%v lines=%q", rec.shutdowns, rec.forced, rec.lines)
+	} // end of the nothing check
+} // end of TestWatcherEndsWhenChannelCloses
+
+// TestStopNowRunsCleanupBeforeStop checks the order: the clean-up of running work first, the shutdown after it.
+func TestStopNowRunsCleanupBeforeStop(t *testing.T) {
+	// Remember the real stop function and put it back afterwards.
+	old := stopRequest
+	// Restore at the end.
+	t.Cleanup(func() { stopRequest = old })
+	// The order in which things happen.
+	var order []string
+	// A mutex, because the clean-up runs in this goroutine but be safe.
+	var mu sync.Mutex
+	// A stop that only records itself.
+	stopRequest = func() { mu.Lock(); order = append(order, "stop"); mu.Unlock() }
+	// Register work whose clean-up records itself.
+	end := activeWork.begin("pretend work", func(ctx context.Context) { mu.Lock(); order = append(order, "cleanup"); mu.Unlock() })
+	// Forget the work at the end of the test.
+	t.Cleanup(end)
+	// Do the clean stop.
+	stopNow()
+	// Read the order.
+	mu.Lock()
+	// Release at the end.
+	defer mu.Unlock()
+	// Clean-up first, then stop.
+	if len(order) != 2 || order[0] != "cleanup" || order[1] != "stop" {
+		// Report it.
+		t.Fatalf("order = %v, want [cleanup stop]", order)
+	} // end of the order check
+} // end of TestStopNowRunsCleanupBeforeStop
+
+// TestOnceStopRunsOnce checks that asking for the stop twice (Ctrl+C and the Stop button) runs it only once.
+func TestOnceStopRunsOnce(t *testing.T) {
+	// A counter.
+	n := 0
+	// The wrapped function.
+	f := onceStop(func() { n++ })
+	// Ask three times.
+	f()
+	// Second ask.
+	f()
+	// Third ask.
+	f()
+	// Only the first one counted.
+	if n != 1 {
+		// Report it.
+		t.Fatalf("stop ran %d times, want 1", n)
+	} // end of the count check
+} // end of TestOnceStopRunsOnce
+
+// TestDefaultStopReasonIsThePage checks that without a signal the reason is the Stop button on the page.
+func TestDefaultStopReasonIsThePage(t *testing.T) {
+	// Make sure nothing is stored.
+	stopReason.Store("")
+	// The default.
+	if got := currentStopReason(); got != reasonPage {
+		// Report it.
+		t.Fatalf("default reason = %q, want %q", got, reasonPage)
+	} // end of the default check
+} // end of TestDefaultStopReasonIsThePage
OCC_PATCH_74_END

# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
[ "$(sha256sum about.go | cut -d' ' -f1)" = "$EXPECT_ABOUT_AFTER" ] || fail "about.go has an unexpected sha256 after the change"
# main.go after the change.
[ "$(sha256sum main.go | cut -d' ' -f1)" = "$EXPECT_MAIN_AFTER" ] || fail "main.go has an unexpected sha256 after the change"
# signals.go after the change.
[ "$(sha256sum signals.go | cut -d' ' -f1)" = "$EXPECT_SIGNALS_AFTER" ] || fail "signals.go has an unexpected sha256 after the change"
# signals_test.go after the change.
[ "$(sha256sum signals_test.go | cut -d' ' -f1)" = "$EXPECT_SIGNALS_TEST_AFTER" ] || fail "signals_test.go has an unexpected sha256 after the change"
# Report it.
pass "the four changed files have the expected sha256"

# gofmt -l lists files that are not formatted; no output means all are formatted.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter . || fail "go build failed"
# Report it.
pass "build for this computer: bin/OllamaControlCenter"

# Compile (without keeping the result) for the other systems, to be sure there is no compile error anywhere; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start the monitor, press Ctrl+C in its terminal, and check the log says it stopped by Ctrl+C (instructions follow in the chat)."
# Show what changed in the project folder; only the four files below should appear (plus your own files that were already modified).
git status --short
