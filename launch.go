// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the packages this file uses.
	// fmt builds the plain error messages.
	"fmt"
	// net/http asks the monitor whether it already answers.
	"net/http"
	// os reads the program's own arguments and opens the log file.
	"os"
	// os/exec starts the monitor and the browser.
	"os/exec"
	// path/filepath joins the log file's path.
	"path/filepath"
	// runtime tells which operating system the program runs on.
	"runtime"
	// time provides the waiting times.
	"time"
) // end of imports

// maxLogFile is the size at which the monitor's log file is started again (1 MiB).
const maxLogFile = 1 << 20

// launcher holds the three actions of "-launch"; a test replaces them.
type launcher struct {
	// probe says whether the monitor already answers at the address.
	probe func(url string) bool
	// start starts the monitor in the background.
	start func() error
	// open opens the page in the browser.
	open func(url string) error
	// wait is how long to wait for a freshly started monitor.
	wait time.Duration
	// poll is the time between two looks.
	poll time.Duration
} // end of launcher

// run does what a double-click on the desktop icon does: open the page, starting the monitor first when it is not running.
func (l launcher) run(url string) error {
	// Already running: only open the page.
	if l.probe(url) {
		// Open it.
		return l.open(url)
	} // end of the running case
	// Start the monitor.
	if err := l.start(); err != nil {
		// Report it.
		return fmt.Errorf("the monitor could not be started: %w", err)
	} // end of the start check
	// The moment to give up.
	deadline := time.Now().Add(l.wait)
	// Look until it answers or the time is over.
	for time.Now().Before(deadline) {
		// It answers.
		if l.probe(url) {
			// Open the page.
			return l.open(url)
		} // end of the answer check
		// Wait a little.
		time.Sleep(l.poll)
	} // end of the waiting loop
	// It did not answer in time.
	return fmt.Errorf("the monitor did not answer within %v; see the log file", l.wait)
} // end of run

// httpProbe asks the page once; any answer with status 200 means the monitor runs.
func httpProbe(url string) bool {
	// A short time limit.
	c := &http.Client{Timeout: 2 * time.Second}
	// Ask.
	res, err := c.Get(url)
	// No answer.
	if err != nil {
		// Not running.
		return false
	} // end of the error check
	// Close the body at the end.
	defer res.Body.Close()
	// Running when the page answers.
	return res.StatusCode == http.StatusOK
} // end of httpProbe

// openBrowser opens the address in the person's default browser, with the command each system provides.
func openBrowser(url string) error {
	// The command for this system.
	switch runtime.GOOS {
	// Windows.
	case "windows":
		// The documented way to open an address.
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	// macOS.
	case "darwin":
		// The "open" command.
		return exec.Command("open", url).Start()
	// Linux and the others.
	default:
		// The freedesktop command.
		return exec.Command("xdg-open", url).Start()
	} // end of the system switch
} // end of openBrowser

// childArgs are this program's own arguments without -launch, so the background copy runs as a normal monitor with the same options.
func childArgs(args []string) []string {
	// The result.
	var out []string
	// Walk the arguments.
	for _, a := range args {
		// Drop the launch switch in its two spellings.
		if a == "-launch" || a == "--launch" {
			// Skip it.
			continue
		} // end of the switch check
		// Keep the rest.
		out = append(out, a)
	} // end of the loop
	// Hand them back.
	return out
} // end of childArgs

// startMonitor starts a copy of this program in the background, without a window, with its messages written to a log file in the settings folder.
func startMonitor(logDir string) error {
	// The program's own file.
	exe, err := os.Executable()
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the program check
	// The log file; without a folder the messages are dropped.
	sink := os.DevNull
	// With a folder, a real file.
	if logDir != "" {
		// Make the folder, private to the owner.
		if err := os.MkdirAll(logDir, 0o700); err != nil {
			// Report it.
			return err
		} // end of the folder check
		// The file.
		sink = filepath.Join(logDir, "OllamaControlCenter.log")
		// A file that grew too big is started again.
		if info, err := os.Stat(sink); err == nil && info.Size() > maxLogFile {
			// Remove it.
			_ = os.Remove(sink)
		} // end of the size check
	} // end of the log case
	// Open it for appending, private to the owner.
	f, err := os.OpenFile(sink, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	// Report a failure.
	if err != nil {
		// Report it.
		return err
	} // end of the open check
	// The log file belongs to the child now; this copy lets go of it at the end.
	defer f.Close()
	// The command: this program again, without -launch.
	cmd := exec.Command(exe, childArgs(os.Args[1:])...)
	// Its messages go to the log.
	cmd.Stdout, cmd.Stderr = f, f
	// Detach it from this process, so closing the launcher does not stop the monitor (the way depends on the system).
	detach(cmd)
	// Start it, without waiting.
	if err := cmd.Start(); err != nil {
		// Report it.
		return err
	} // end of the start check
	// Let go of it.
	return cmd.Process.Release()
} // end of startMonitor

// runLaunch is the -launch option: returns the exit code (0 = the page was opened).
func runLaunch(url, logDir string) int {
	// The real actions.
	l := launcher{probe: httpProbe, start: func() error { return startMonitor(logDir) }, open: openBrowser, wait: 15 * time.Second, poll: 300 * time.Millisecond}
	// Do it.
	if err := l.run(url); err != nil {
		// Tell the terminal (a double-click has none, but a person who ran it by hand sees it).
		fmt.Fprintln(os.Stderr, "launch:", err)
		// Failure.
		return 1
	} // end of the error check
	// Success.
	return 0
} // end of runLaunch
