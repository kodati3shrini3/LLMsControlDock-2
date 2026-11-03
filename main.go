// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// context supplies the (empty) context the fetch functions need.
	"context"
	// errors tells a normal shutdown from a real failure.
	"errors"
	// flag reads command-line options such as -listen.
	"flag"
	// fmt writes formatted text to the terminal.
	"fmt"
	// log prints timestamped messages to the terminal.
	"log"
	// net/http is Go's built-in web server (standard library only, requirement T1).
	"net/http"
	// os reads environment variables and ends the program with an exit code.
	"os"
	// strings cuts the port out of the listen address.
	"strings"
	// time provides durations such as the request-header timeout.
	"time"
) // end of imports

// defaultListen is where the page is served unless the user chooses otherwise: this machine only (requirement S1).
const defaultListen = "127.0.0.1:8765"

// openListen is the address used when the person allowed other machines: every network address of this computer, same port as the default.
const openListen = "0.0.0.0:8765"

// listenGiven says whether -listen was written on the command line (flag.Visit only walks the options that were set).
func listenGiven() bool {
	// Not given until seen.
	given := false
	// Walk the options that were set.
	flag.Visit(func(f *flag.Flag) {
		// The one we look for.
		if f.Name == "listen" {
			// Seen.
			given = true
		} // end of the name check
	}) // end of the walk
	// The answer.
	return given
} // end of listenGiven

// chooseListen picks the listen address by precedence: the -listen option (when given), then "other machines allowed" from the settings, then this computer only; the second value names the layer.
func chooseListen(flagValue string, flagGiven, allowOthers bool) (string, string) {
	// The command line wins.
	if flagGiven {
		// Use it.
		return flagValue, sourceFlag
	} // end of the option case
	// The saved setting opens the page to the network.
	if allowOthers {
		// Use the open address.
		return openListen, sourceSaved
	} // end of the saved case
	// Otherwise this computer only.
	return defaultListen, sourceDefault
} // end of chooseListen

// launchURL turns a listen address (host:port) into the address a browser on this computer opens.
func launchURL(listen string) string {
	// The port is the part after the last colon.
	port := listen[strings.LastIndex(listen, ":")+1:]
	// Always this computer.
	return "http://127.0.0.1:" + port + "/"
} // end of launchURL

// formatCheck turns one check result into the single status line the -check option prints.
func formatCheck(res checkResult) string {
	// A successful check says ONLINE, the version and the time taken.
	if res.Online {
		// Build the online line; %s is text and %d is a whole number.
		return fmt.Sprintf("ONLINE  version %s  %d ms", res.Version, res.Elapsed.Milliseconds())
	} // end of the online case
	// A failed check says OFFLINE, the reason and the time taken.
	return fmt.Sprintf("OFFLINE  %s  %d ms", res.Reason, res.Elapsed.Milliseconds())
} // end of formatCheck

// runModels fetches both lists, prints the report, and returns the exit code (0 = printed, 1 = Ollama could not be read).
func runModels(addr ollamaAddress) int {
	// An empty context with no deadline; each request has its own timeout.
	ctx := context.Background()
	// Fetch the installed models.
	installed, err := fetchInstalled(ctx, addr.URL, defaultCheckTimeout)
	// A failure here means Ollama could not be read.
	if err != nil {
		// Print one OFFLINE line with the plain reason, like -check does.
		fmt.Println("OFFLINE  " + err.Error())
		// Exit code 1 means failure.
		return 1
	} // end of the installed check
	// Fetch the loaded models.
	loaded, err := fetchLoaded(ctx, addr.URL, defaultCheckTimeout)
	// A failure here also means Ollama could not be read.
	if err != nil {
		// Print one OFFLINE line with the plain reason.
		fmt.Println("OFFLINE  " + err.Error())
		// Exit code 1 means failure.
		return 1
	} // end of the loaded check
	// Print the whole report; time.Now() is the clock used for the "time until unload" column.
	fmt.Println(renderReport(installed, loaded, time.Now()))
	// Exit code 0 means success.
	return 0
} // end of runModels

// main is where every Go program starts running.
func main() {
	// Define a -listen option: its name, its default value, and the help text shown by -h.
	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
	// Define an -ollama-url option; empty means "not given", so the environment variable or the default is used.
	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the OCC_OLLAMA_URL environment variable (default http://127.0.0.1:11434)")
	// Define a -launch switch: what a double-click on the desktop icon runs; it opens the page and starts the monitor first when it is not running.
	launchFlag := flag.Bool("launch", false, "open the monitor page in the browser, starting the monitor in the background first when it is not running (this is what the desktop icon runs)")
	// Define a -check switch: false unless given on the command line.
	checkFlag := flag.Bool("check", false, "check Ollama once, print one status line, and exit (0 = online, 1 = offline)")
	// Define a -models switch: false unless given on the command line.
	modelsFlag := flag.Bool("models", false, "print the installed and loaded models as tables, and exit (0 = printed, 1 = Ollama not reachable)")
	// Define a -check-links switch: opens every reference address of the comparison page once, prints the result, and exits (the only time the program contacts the internet).
	linksFlag := flag.Bool("check-links", false, "open every reference address of the comparison page once, print which answer, and exit (0 = all answered, 1 = at least one did not)")
	// Read the command line now, so the variables above receive their values.
	flag.Parse()

	// The one-shot modes cannot be combined; ask the person to choose one.
	modes := 0
	// Count the modes that were given.
	for _, on := range []bool{*checkFlag, *modelsFlag, *linksFlag, *launchFlag} {
		// One more mode.
		if on {
			// Count it.
			modes++
		} // end of the mode check
	} // end of the loop
	// More than one is not allowed.
	if modes > 1 {
		// log.Fatal prints the message and exits with code 1.
		log.Fatal("use only one of -check, -models, -check-links and -launch")
	} // end of the combination check

	// In -check-links mode, no Ollama is needed: open the reference addresses, print the result and leave.
	if *linksFlag {
		// Run it and leave with its exit code.
		os.Exit(runCheckLinks(compareReferences, newLinkClient(), referencesChecked, os.Stdout))
	} // end of the links mode

	// Choose the Ollama address by precedence: option, then environment variable, then default.
	// The saved settings are read first (a damaged file is ignored with a note).
	dir, dirNote := settingsFolder()
	// Version 0.25.0 kept the check history and the icon picture in the configuration folder; copy them once to the state and data folders (the old files are left in place).
	for _, msg := range migrateOldFiles(dir, dataRoot(), stateRoot()) {
		// Say so in the log.
		log.Print(msg)
	} // end of the copy loop
	// Open the store.
	store := openSettingsStore(dir, dirNote)
	// The check history belongs in the state folder.
	store.stateDir = stateRoot()
	// Tell the person when the file was ignored.
	if n := store.noteText(); n != "" {
		// Print the note.
		log.Print(n)
	} // end of the note check
	// The address: option, then environment variable, then saved setting, then default.
	addr, err := resolveWithSaved(*ollamaFlag, os.Getenv(envOllamaURL), store.get().OllamaURL)
	// If the address is unusable, stop with a clear message and a failure exit code.
	if err != nil {
		// log.Fatalf prints the message and exits with code 1.
		log.Fatalf("%v", err)
	} // end of the address check
	// Print the address (any password shown as xxxxx) and which layer supplied it.
	log.Printf("Ollama address: %s (from %s)", addr.URL.Redacted(), addr.Source)

	// In -models mode, print both tables and leave without starting the web page.
	if *modelsFlag {
		// Run it and leave with its exit code.
		os.Exit(runModels(addr))
	} // end of the models mode

	// In -check mode, knock once, print the result, and leave without starting the web page.
	if *checkFlag {
		// Ask Ollama once, waiting at most the default timeout.
		res := checkOllama(context.Background(), addr.URL, defaultCheckTimeout)
		// Print the single status line.
		fmt.Println(formatCheck(res))
		// Exit with 0 when online, so scripts can tell it worked.
		if res.Online {
			// Leave with the success code.
			os.Exit(0)
		} // end of the online exit
		// Leave with the failure code.
		os.Exit(1)
	} // end of the check mode

	// Describe the web server: Addr is where to listen (the star reads the flag's value), Handler is the web interface from web.go wrapped in the Host-name check from guard.go,
	// and ReadHeaderTimeout drops clients that take more than 5 seconds to send their request headers.
	// The monitor holds the counters and the history of checks; it asks Ollama in the background every sampleEvery, so the charts have no gaps while the page is closed.
	// In -launch mode, open the page (starting the monitor first when needed) and leave.
	if *launchFlag {
		// The address the page is served on, by the same precedence as below.
		la, _ := chooseListen(*listen, listenGiven(), store.get().AllowOthers)
		// Run it and leave with its exit code.
		os.Exit(runLaunch(launchURL(la), store.stateFolder()))
	} // end of the launch mode
	mon := newMonitorWith(store)
	// The real desktop, so the first-run banner and the Settings buttons can place the icon.
	mon.denv = realDesktopEnv()
	// The first start shows the System check.
	mon.firstRunCheck = true
	// The listen address: the -listen option if it was given, else "other machines allowed" from the settings, else this computer only.
	listenAddr, listenSource := chooseListen(*listen, listenGiven(), store.get().AllowOthers)
	// Tell the Settings page how the program was started.
	mon.run = runInfo{Listen: listenAddr, ListenSource: listenSource}
	// Start the background checks; they end with the program.
	mon.start(context.Background(), addr.URL, defaultCheckTimeout, sampleEvery)
	// The server, with the monitor built into the web interface.
	server := &http.Server{Addr: listenAddr, Handler: hostGuard(newWebHandlerWith(addr, defaultCheckTimeout, mon), listenAddr), ReadHeaderTimeout: 5 * time.Second}

	// Tell the person which address we are about to serve on.
	log.Printf("OllamaControlCenter listening on http://%s (from %s; press Ctrl+C to stop)", listenAddr, listenSource)
	// Closed when the shutdown that the Stop button started has finished.
	stopped := make(chan struct{})
	// The Stop button's last step: shut the web server down, waiting at most 5 seconds for requests that are still running.
	stopRequest = func() {
		// In the background, so the request that asked for it can finish.
		go func() {
			// A time limit for the polite shutdown.
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			// Release the timer at the end.
			defer cancel()
			// With the history file switched on, write the checks one last time, so a stop loses nothing.
			if store.get().SaveHistory && !noSaveOnStop.Load() {
				// A failed write is not fatal.
				_ = store.saveSamples(mon.hist.all())
			} // end of the history write
			// Ask politely first.
			if err := server.Shutdown(ctx); err != nil {
				// Requests that would not finish are cut off.
				server.Close()
			} // end of the shutdown check
			// Tell main that it can leave.
			close(stopped)
		}() // end of the goroutine
	} // end of stopRequest
	// Start serving; this call blocks (waits) until the server stops or fails, for example if the port is taken.
	err = server.ListenAndServe()
	// A shutdown asked for by the Stop button is a normal end, not an error.
	if errors.Is(err, http.ErrServerClosed) {
		// Wait until the shutdown has finished.
		<-stopped
		// Say why the program ends.
		log.Printf("OllamaControlCenter stopped from its page")
		// Leave with the success code.
		return
	} // end of the normal stop
	// If we get here the server has stopped for another reason; log.Fatal prints it and exits with an error code.
	log.Fatal(err)
} // end of main
