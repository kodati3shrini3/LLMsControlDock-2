// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes provides a buffer so the page is built completely before anything is sent.
	"bytes"
	// embed lets files be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// html/template builds HTML and escapes every inserted value, so untrusted text cannot become markup.
	"html/template"
	// log prints messages to the terminal.
	"log"
	// net/http is Go's built-in web server.
	"net/http"
	// time provides durations.
	"time"
) // end of imports

// indexTemplateText is the page template, stored inside the executable at build time (requirements T3 and T4).
//
//go:embed web/index.html
var indexTemplateText string

// appCSS is the stylesheet, stored inside the executable at build time.
//
//go:embed web/app.css
var appCSS []byte

// contentSecurityPolicy tells the browser what the page may load: only our own stylesheet and our own images, no scripts, no frames, and forms that send only to this same page.
const contentSecurityPolicy = "default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"

// pageData is everything the page template can show.
type pageData struct {
	// Address is the Ollama address with any password hidden.
	Address string
	// AddressSource names the layer that supplied the address.
	AddressSource string
	// Online is true when Ollama answered with a valid version.
	Online bool
	// Version is the Ollama version text.
	Version string
	// ElapsedMs is how long the check took, in milliseconds.
	ElapsedMs int64
	// Reason explains why Ollama is offline.
	Reason string
	// HasTable is true when the model lists were read and the table can be drawn.
	HasTable bool
	// Table is the Installed table, filled only when HasTable is true.
	Table tableView
	// TableError explains why the lists could not be read, when Ollama answered the version check but not the lists.
	TableError string
	// Theme is the saved choice, light or dark; empty means follow the system.
	Theme string
	// Size is the saved text size, medium, or empty for the browser's own size.
	Size string
	// CompanyName is the developer's company, shown under the title and in the footer bar.
	CompanyName string
	// CompanyTagline is the company's tagline, shown in the footer bar.
	CompanyTagline string
	// CompanyAILine is the line that ties the program to the company's work.
	CompanyAILine string
	// HeaderURL is the company website address for the link under the title.
	HeaderURL string
	// FooterURL is the company website address for the footer bar.
	FooterURL string
	// Health holds the counters of failed checks and the last successful check.
	Health healthView
	// HealthTip is the help bubble of the panel heading "API health".
	HealthTip tipView
	// Token is the page token that every form on the page carries.
	Token string
	// CompareCount is how many models have a saved performance test that can be compared.
	CompareCount int
	// Paused is true when the person paused the automatic updates (a cookie remembers it).
	Paused bool
	// KeyOpen is true when the person opened the key to the symbols (the address then ends in ?key=open); the page does not update by itself meanwhile.
	KeyOpen bool
	// RefreshSeconds is how often the page updates itself while it is being watched.
	RefreshSeconds int
	// UpdatedAt is the time of day this page was made, so a person can see how fresh it is.
	UpdatedAt string
} // end of pageData

// secureHeaders wraps a handler so every reply, including errors, carries the same safety headers.
func secureHeaders(next http.Handler) http.Handler {
	// Return a handler that sets the headers and then calls the wrapped one.
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Limit what the page may load.
		w.Header().Set("Content-Security-Policy", contentSecurityPolicy)
		// Stop the browser from guessing a different content type.
		w.Header().Set("X-Content-Type-Options", "nosniff")
		// Forbid showing the page inside a frame (older browsers read this header).
		w.Header().Set("X-Frame-Options", "DENY")
		// Never send the page address to other sites.
		w.Header().Set("Referrer-Policy", "no-referrer")
		// A status page must never come from a cache.
		w.Header().Set("Cache-Control", "no-store")
		// Hand the request on.
		next.ServeHTTP(w, r)
	}) // end of the wrapper
} // end of secureHeaders

// newWebHandler builds the whole web interface: the page at "/" and the stylesheet at "/app.css".
func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
	page := template.Must(template.New("index").Parse(indexTemplateText))
	// The counters of failed checks live as long as the monitor runs.
	health := &apiHealth{}
	// The help bubble of the panel heading never changes, so build it once.
	healthTip := makeTip("tip-health", "API health")
	// Create the page token: an unguessable value that every form on the page carries, so only this page can send a form (requirement S2).
	token := mustToken()
	// Create a router for the routes.
	mux := http.NewServeMux()
	// Route: a POST request for "/theme" saves the chosen theme in a cookie (the checks are in theme.go).
	mux.HandleFunc("POST /theme", themeHandler(token))
	// Route: a POST request for "/textsize" saves the chosen text size in a cookie (the checks are in size.go).
	mux.HandleFunc("POST /textsize", sizeHandler(token))
	// Route: a GET request for "/about" shows the read-only About page (see about.go).
	mux.HandleFunc("GET /about", aboutHandler())
	// Make the two unload handlers: the first asks "are you sure?", the second unloads (the checks are in unload.go).
	unloadAsk, unloadConfirm := unloadHandlers(addr, token)
	// Route: a POST request for "/unload" shows the warning page and changes nothing.
	mux.HandleFunc("POST /unload", unloadAsk)
	// Route: a POST request for "/unload/confirm" unloads the model.
	mux.HandleFunc("POST /unload/confirm", unloadConfirm)
	// Make the two load handlers: the first shows the memory warning, the second loads (the checks are in load.go).
	loadAsk, loadConfirm := loadHandlers(addr, token)
	// Route: a POST request for "/load" shows the memory warning and changes nothing.
	mux.HandleFunc("POST /load", loadAsk)
	// Route: a POST request for "/load/confirm" loads the model.
	mux.HandleFunc("POST /load/confirm", loadConfirm)
	// Make the three settings handlers: the settings page, the review step and the save (the checks are in gear.go).
	gearShow, gearReview, gearSave := gearHandlers(addr, token)
	// Route: a POST request for "/gear" shows a model's settings and changes nothing.
	mux.HandleFunc("POST /gear", gearShow)
	// Route: a POST request for "/gear/review" checks the typed size and asks for confirmation.
	mux.HandleFunc("POST /gear/review", gearReview)
	// Route: a POST request for "/gear/save" saves the size inside the model.
	mux.HandleFunc("POST /gear/save", gearSave)
	// Route: a POST request for "/modelfile" shows a model's Modelfile, read-only.
	mux.HandleFunc("POST /modelfile", modelfileHandler(addr, token))
	// Make the four performance handlers: the start page, the test run, and the two steps of clearing the saved results (the checks are in perfpage.go); the history lives in the person's configuration folder.
	histPath, histNote := defaultHistoryPath()
	// An earlier version named the results folder with a capital P; rename it before anything is opened, so the saved results are found.
	if msg := moveOldHistoryFolder(histPath); msg != "" {
		// Say so in the log.
		log.Print(msg)
	} // end of the rename check
	// Open the saved results.
	// One history store, shared by the performance pages and the comparison page.
	perfHistory := openPerfStore(histPath, histNote)
	// An older version kept the list of deleted models next to the results; bring it to the new folder first.
	if msg := moveOldDeletedFile(histPath); msg != "" {
		// Say so in the log; the list is then simply empty until the file can be moved.
		log.Print(msg)
	} // end of the move check
	// The deleted models are remembered in a small file in the deletedHistory folder (kept out of GitHub by .gitignore).
	deletedList := openDeletedStore(deletedPathFor(histPath))
	// The folder for the snapshots of deleted models' parameters ("history" next to the program, kept out of GitHub by .gitignore).
	histDir, histDirNote := defaultHistoryDir()
	// The snapshot store.
	historyDir := &historyStore{dir: histDir, note: histDirNote}
	// The six delete and restore handlers.
	delAsk, delConfirm, delForce, restoreInfo, restoreForget, restoreHistory := deleteHandlers(addr, token, deletedList, historyDir)
	// The first delete step: shows the warning, changes nothing.
	mux.HandleFunc("POST /delete", delAsk)
	// The second step for a model that is not loaded.
	mux.HandleFunc("POST /delete/confirm", delConfirm)
	// The force step for a loaded model; it needs the typed name.
	mux.HandleFunc("POST /delete/force", delForce)
	// The restore information page.
	mux.HandleFunc("POST /restore", restoreInfo)
	// Remove a greyed row.
	mux.HandleFunc("POST /restore/forget", restoreForget)
	// The read-only list of parameter snapshots of a deleted model.
	mux.HandleFunc("POST /restore/history", restoreHistory)
	// The four handlers of the performance pages.
	perfStart, perfRun, perfClearAsk, perfClearDo, perfClearOneAsk, perfClearOneDo := perfHandlers(addr, token, perfHistory, historyDir)
	// Route: a POST request for "/performance" shows the performance page and changes nothing.
	mux.HandleFunc("POST /performance", perfStart)
	// Route: a POST request for "/performance/run" runs the test.
	mux.HandleFunc("POST /performance/run", perfRun)
	// Route: a POST request for "/performance/clear" asks whether to remove the saved results.
	mux.HandleFunc("POST /performance/clear", perfClearAsk)
	// Route: a POST request for "/performance/clear/confirm" removes them.
	mux.HandleFunc("POST /performance/clear/confirm", perfClearDo)
	// Route: a POST request for "/performance/clear/model" shows what removing one model's saved results would lose, and changes nothing.
	mux.HandleFunc("POST /performance/clear/model", perfClearOneAsk)
	// Route: a POST request for "/performance/clear/model/confirm" removes one model's saved results (after keeping a copy).
	mux.HandleFunc("POST /performance/clear/model/confirm", perfClearOneDo)
	// Route: a POST request for "/compare" shows the comparison of the tested models and changes nothing.
	mux.HandleFunc("POST /compare", compareHandler(addr, token, perfHistory))
	// The two downloads of the comparison: a PDF report and the data as CSV (both carry the notice; the checks are in compreport.go).
	comparePDF, compareCSV := compareDownloadHandlers(addr, token, perfHistory)
	// Route: a POST request for "/compare/pdf" sends the comparison as a PDF file.
	mux.HandleFunc("POST /compare/pdf", comparePDF)
	// Route: a POST request for "/compare/csv" sends the data as a CSV file.
	mux.HandleFunc("POST /compare/csv", compareCSV)
	// Route: a POST request for "/watch" pauses or resumes the automatic updates of the page.
	mux.HandleFunc("POST /watch", watchHandler(token))
	// The two steps of stopping the monitor.
	stopAsk, stopConfirm := stopHandlers(token)
	// Route: a POST request for "/stop" asks whether to stop the monitor and changes nothing.
	mux.HandleFunc("POST /stop", stopAsk)
	// Route: a POST request for "/stop/confirm" sends the last page and stops the monitor.
	mux.HandleFunc("POST /stop/confirm", stopConfirm)
	// Route: a GET request for "/countdown.js" sends the small script that makes the timers tick (only the message pages use it).
	mux.HandleFunc("GET /countdown.js", countdownHandler)
	// Route: a GET request for "/copy.js" sends the small script behind the copy buttons next to commands (only the restore page uses it).
	mux.HandleFunc("GET /copy.js", copyHandler)
	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
	mux.HandleFunc("GET /loading.js", loadingHandler)
	// Route: a GET request for exactly "/" shows the page; other paths get 404 and other methods get 405 from the router.
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		// Ask Ollama once; the request's own context cancels the check if the browser goes away.
		res := checkOllama(r.Context(), addr.URL, timeout)
		// Fill in what the template shows.
		data := pageData{
			// The address with any password replaced by xxxxx.
			Address: addr.URL.Redacted(),
			// Which layer supplied it.
			AddressSource: addr.Source,
			// Online or offline.
			Online: res.Online,
			// The version, if online.
			Version: res.Version,
			// The time taken.
			ElapsedMs: res.Elapsed.Milliseconds(),
			// The counters after this check, and the bubble of the heading.
			Health: health.record(res.Online, time.Now()), HealthTip: healthTip,
			// The reason, if offline.
			Reason: res.Reason,
			// The saved theme choice, from the cookie; empty means follow the system.
			Theme: themeFromRequest(r),
			// The saved text size, from the cookie; empty means the browser's own size.
			Size: sizeFromRequest(r),
			// The company name, tagline and AI line.
			CompanyName: companyName, CompanyTagline: companyTagline, CompanyAILine: companyAILine,
			// The company website addresses, tagged for the two places.
			HeaderURL: companyLink("header"), FooterURL: companyLink("footer"),
			// The page token for the forms.
			Token: token,
			// How many models can be compared.
			CompareCount: perfHistory.testedModels(),
			// Whether the automatic updates are paused.
			Paused: watchPaused(r),
			// Whether the key to the symbols is open.
			KeyOpen: r.URL.Query().Get("key") == "open",
			// The update interval.
			RefreshSeconds: watchRefreshSeconds,
			// When this page was made.
			UpdatedAt: time.Now().Format("15:04:05 MST"),
		} // end of the data
		// Only an online Ollama can be asked for its model lists.
		if res.Online {
			// Read the installed models; the request's context cancels the call if the browser goes away.
			installed, err := fetchInstalled(r.Context(), addr.URL, timeout)
			// Read the loaded models only if the first call worked.
			var loaded []loadedModel
			// Skip the second call after a failure.
			if err == nil {
				// Read the loaded models.
				loaded, err = fetchLoaded(r.Context(), addr.URL, timeout)
			} // end of the second call
			// A failure is shown in the page, using the same safe wording as the terminal.
			if err != nil {
				// Keep the plain reason.
				data.TableError = err.Error()
			} else { // the other case
				// Build the table and switch it on.
				data.Table = buildTableView(installed, loaded)
				// Add the greyed rows of deleted models that are still gone.
				data.Table.Deleted = deletedRows(deletedList.list(), installed)
				// The table can be drawn now.
				data.HasTable = true
			} // end of the error check
		} // end of the online check
		// Build the whole page in memory first, so a template error produces a clean 500 and not a half page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// With a table the page runs the monitor's own script, so it gets the policy that also lets the script ask this same address for fresh figures.
		if data.HasTable {
			// Replace the strict policy.
			w.Header().Set("Content-Security-Policy", contentSecurityPolicyMainPage)
		} // end of the script policy
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the finished page.
		w.Write(buf.Bytes())
	}) // end of the page route
	// Route: a GET request for "/app.css" sends the embedded stylesheet.
	mux.HandleFunc("GET /app.css", func(w http.ResponseWriter, r *http.Request) {
		// Tell the browser this is a stylesheet.
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		// Send it.
		w.Write(appCSS)
	}) // end of the stylesheet route
	// Route: a GET request for "/termgate-logo.png" sends the embedded company logo.
	mux.HandleFunc("GET /termgate-logo.png", func(w http.ResponseWriter, r *http.Request) {
		// Tell the browser this is a PNG image.
		w.Header().Set("Content-Type", "image/png")
		// Send it.
		w.Write(companyLogo)
	}) // end of the logo route
	// Wrap the router so every reply carries the safety headers.
	return secureHeaders(mux)
} // end of newWebHandler
