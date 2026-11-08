// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// context gives the clean-up of running work a time limit.
	"context"
	// log prints timestamped messages to the terminal.
	"log"
	// os supplies the Interrupt signal and the immediate exit.
	"os"
	// os/signal delivers Ctrl+C and the termination request to a channel (the official Go package for this).
	"os/signal"
	// strings joins the descriptions of running work into one line.
	"strings"
	// sync makes sure the shutdown runs only once, however many things ask for it.
	"sync"
	// sync/atomic holds the reason for stopping so main can read it safely from another goroutine.
	"sync/atomic"
	// syscall names SIGTERM; Go defines that name on Windows too.
	"syscall"
) // end of imports

// reasonPage is the stop reason when the person pressed Stop on the page (the default).
const reasonPage = "from its page"

// reasonSignal is the stop reason when Ctrl+C or a termination request arrived.
const reasonSignal = "by Ctrl+C or a termination request"

// stopReason holds the reason for stopping as text, so the last log line can say why the program ended.
var stopReason atomic.Value

// currentStopReason returns the reason for stopping; the page is the default when nothing else was stored.
func currentStopReason() string {
	// Read the stored value; it is empty (nil) until a signal arrives.
	if s, ok := stopReason.Load().(string); ok && s != "" {
		// A stored reason wins.
		return s
	} // end of the stored check
	// Nothing stored: the Stop button on the page.
	return reasonPage
} // end of currentStopReason

// onceStop wraps a stop function so that it runs only the first time it is called (a second Ctrl+C or the Stop button after it must not shut down twice).
func onceStop(f func()) func() {
	// The guard that lets the first call through and turns the others away.
	var once sync.Once
	// The wrapped function.
	return func() {
		// Run f one time only.
		once.Do(f)
	} // end of the wrapper
} // end of onceStop

// stopNow is the clean stop for a signal: it undoes what running work changed (within the time limit), then shuts the program down the same way the Stop button does.
func stopNow() {
	// The same time limit the Stop button uses for the clean-up.
	ctx, cancel := context.WithTimeout(context.Background(), stopCleanupLimit)
	// Undo what running work changed, for example unload a model a test loaded.
	activeWork.runCleanups(ctx)
	// Release the timer.
	cancel()
	// Save the history if the person turned that on, close the web server, and let main leave.
	stopRequest()
} // end of stopNow

// signalActions are the things the signal watcher does; tests replace them with recorders.
type signalActions struct {
	// shutdown stops the program cleanly; it runs in its own goroutine so a second signal can still be read.
	shutdown func()
	// force ends the program at once with the given exit code.
	force func(code int)
	// logf writes one line to the log.
	logf func(format string, args ...any)
	// running returns the descriptions of the work that is running right now.
	running func() []string
} // end of signalActions

// realSignalActions wires the watcher to the real program.
func realSignalActions() signalActions {
	// The real parts.
	return signalActions{shutdown: stopNow, force: os.Exit, logf: log.Printf, running: activeWork.texts}
} // end of realSignalActions

// watchStopSignals reads signals until the channel closes: the first one starts the clean stop, the second one quits at once.
func watchStopSignals(sigs <-chan os.Signal, act signalActions) {
	// True until the first signal has been handled.
	first := true
	// Wait for each signal in turn; the loop ends when the channel is closed.
	for sig := range sigs {
		// The first signal asks for a clean stop.
		if first {
			// From now on a signal means "quit at once".
			first = false
			// Remember why we stop, so the last log line can say it.
			stopReason.Store(reasonSignal)
			// Tell the person what is happening and how to hurry it up.
			act.logf("LLMsControlDock received %v: stopping cleanly (press Ctrl+C again to quit at once)", sig)
			// Work that is still running is cut short; say which.
			if work := act.running(); len(work) > 0 {
				// One line naming the work.
				act.logf("work still running will be stopped: %s", strings.Join(work, "; "))
			} // end of the running-work check
			// Run the clean stop in the background, so this loop keeps listening.
			go act.shutdown()
			// Wait for the next signal.
			continue
		} // end of the first-signal case
		// A second signal: the person does not want to wait.
		act.logf("LLMsControlDock received %v again: quitting at once; nothing more is saved", sig)
		// Leave with a failure code, because the clean stop did not finish.
		act.force(1)
		// Stop reading signals.
		return
	} // end of the signal loop
} // end of watchStopSignals

// startStopSignals asks the operating system to deliver Ctrl+C (os.Interrupt) and the termination request (SIGTERM) to the watcher.
func startStopSignals() {
	// A buffer of 2, because the signal package never waits for a slow reader and would drop a signal otherwise.
	sigs := make(chan os.Signal, 2)
	// os.Interrupt is Ctrl+C on every system; SIGTERM is what "kill", "docker stop" and a service manager send (on Windows it also stands for the console closing).
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	// Watch in the background for as long as the program runs.
	go watchStopSignals(sigs, realSignalActions())
} // end of startStopSignals
