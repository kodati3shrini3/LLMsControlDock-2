// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the packages this file uses.
	// bytes builds the page in memory before it is sent.
	"bytes"
	// embed lets the page template travel inside the program.
	_ "embed"
	// fmt writes numbers into the texts.
	"fmt"
	// html/template builds the page and escapes every value.
	"html/template"
	// log reports a template error in the terminal.
	"log"
	// net/http provides requests and responses.
	"net/http"
	// path/filepath shows the folder of the files.
	"path/filepath"
	// strconv turns the typed text into whole numbers.
	"strconv"
	// strings trims the typed text.
	"strings"
) // end of imports

// settingsTemplateText is the page template, embedded from web/settings.html.
//
//go:embed web/settings.html
var settingsTemplateText string

// settingsRow is one line of the settings table.
type settingsRow struct {
	// Label is the name of the setting.
	Label string
	// Help is one short sentence that explains it, with an example.
	Help string
	// Name is the name of the form field.
	Name string
	// Kind is the control: text, number or yesno.
	Kind string
	// Now is the value in use now.
	Now string
	// From says which layer supplied it (default, saved setting, command-line option, environment variable).
	From string
	// Pending says that a saved value waits for a restart (empty when nothing waits).
	Pending string
	// Typed is what the control holds.
	Typed string
	// Default is the built-in value.
	Default string
	// Applies says when a change takes effect: at once or after a restart.
	Applies string
	// Min and Max are the limits of a number.
	Min, Max int
} // end of settingsRow

// settingsPage is everything the template shows.
type settingsPage struct {
	// Theme and Size are the saved look choices.
	Theme, Size string
	// Token proves the form comes from this page.
	Token string
	// Rows are the table lines.
	Rows []settingsRow
	// Problems are the things wrong with what was typed.
	Problems []string
	// Saved is "saved", "draft" (defaults filled in but not saved) or empty, for the note above the table.
	Saved string
	// RestartNeeded is true when a restart value differs from what runs now.
	RestartNeeded bool
	// Note is the plain note about the file.
	Note string
	// Folder is the configuration folder, where the settings are kept (empty when none was found).
	Folder string
	// DataFolder is the data folder, where the results, saved copies and deleted models are kept (empty when none was found).
	DataFolder string
	// StateFolder is the state folder, where the check history and the log are kept (empty when none was found).
	StateFolder string
	// IconAvailable is true when this system can have a desktop icon; the section is hidden otherwise.
	IconAvailable bool
	// IconExists is true when the launcher is on the desktop now.
	IconExists bool
	// IconPath is the launcher's full path.
	IconPath string
	// IconNote is the plain sentence about what just happened (empty when nothing did).
	IconNote string
} // end of settingsPage

// iconNotes are the sentences shown after a desktop icon button; the address carries only the key, so no free text is ever echoed.
var iconNotes = map[string]string{
	// Created.
	"created": "Desktop icon created. On Ubuntu you may have to right-click it once and choose Allow Launching.",
	// Removed.
	"removed": "Desktop icon removed.",
	// No desktop.
	"unsupported": "This system has no desktop folder the program can use, so no icon was made.",
	// A path with unusual characters.
	"unusualpath": "The path of the program holds characters that cannot be used in a launcher (use letters, digits and . _ + - / only), so no icon was made. Move the program to a plainer folder and try again.",
	// Anything else.
	"failed": "The desktop icon could not be created or removed. Check that the folders are writable.",
} // end of iconNotes

// yesNo writes a flag as the words used in the form.
func yesNo(on bool) string {
	// Yes.
	if on {
		// The word.
		return "yes"
	} // end of the yes case
	// No.
	return "no"
} // end of yesNo

// numberOrZero reads a typed whole number; empty text means 0 (not set), anything else that is not a whole number is reported.
func numberOrZero(text string) (int, bool) {
	// Empty means not set.
	text = strings.TrimSpace(text)
	// Nothing typed.
	if text == "" {
		// Not set.
		return 0, true
	} // end of the empty case
	// Read it.
	n, err := strconv.Atoi(text)
	// Not a whole number.
	if err != nil {
		// Report it.
		return 0, false
	} // end of the parse check
	// A number.
	return n, true
} // end of numberOrZero

// settingsFormValues are the typed texts, kept so a refused form shows again what the person typed.
type settingsFormValues struct {
	// Address, Interval, Timeout and History are the typed texts.
	Address, Interval, Timeout, History string
	// Others and SaveHistory are "yes" or "no".
	Others, SaveHistory string
} // end of settingsFormValues

// formFromSettings fills the typed values from saved settings (a default value shows as empty or as the default number).
func formFromSettings(cfg appSettings) settingsFormValues {
	// The numbers show the value in use, so the person sees what a change starts from.
	return settingsFormValues{
		// The address shows only when one was saved.
		Address: cfg.OllamaURL,
		// The interval in use.
		Interval: strconv.Itoa(int(cfg.interval(sampleEvery).Seconds())),
		// The timeout in use.
		Timeout: strconv.Itoa(int(cfg.timeout(defaultCheckTimeout).Seconds())),
		// The history in use.
		History: strconv.Itoa(int(cfg.window().Minutes())),
		// The two switches.
		Others: yesNo(cfg.AllowOthers), SaveHistory: yesNo(cfg.SaveHistory),
	} // end of the values
} // end of formFromSettings

// fromLayer names the layer of a numeric setting: the saved setting when one is saved, else the default.
func fromLayer(saved bool) string {
	// Saved.
	if saved {
		// The name.
		return sourceSaved
	} // end of the saved case
	// Default.
	return sourceDefault
} // end of fromLayer

// buildSettingsRows makes the table lines from the saved settings, how the program runs now and what the form holds.
func buildSettingsRows(cfg appSettings, addr ollamaAddress, run runInfo, typed settingsFormValues) ([]settingsRow, bool) {
	// Whether any restart value waits.
	restart := false
	// The address row: what runs now, and a note when the saved value differs.
	pendAddr := ""
	// A saved address that is not the one in use, and no stronger layer overrides it, waits for a restart.
	if cfg.OllamaURL != "" && addr.Source != sourceFlag && addr.Source != sourceEnv && (addr.Source != sourceSaved || cfg.OllamaURL != addr.URL.String()) {
		// Say so.
		pendAddr = "saved: " + cfg.OllamaURL + " (used after a restart)"
		// A restart is needed.
		restart = true
	} // end of the pending address
	// A saved address that a stronger layer overrides is not used at all.
	if cfg.OllamaURL != "" && (addr.Source == sourceFlag || addr.Source == sourceEnv) {
		// Say so.
		pendAddr = "the " + addr.Source + " overrides the saved address"
	} // end of the overridden address
	// An address cleared on the page while a saved one runs also needs a restart.
	if cfg.OllamaURL == "" && addr.Source == sourceSaved {
		// Say so.
		pendAddr = "saved: (default) (used after a restart)"
		// A restart is needed.
		restart = true
	} // end of the cleared address
	// Whether the page is open to the network now.
	openNow := lanListen(run.Listen)
	// The network row's pending note.
	pendNet := ""
	// The saved choice differs from what runs, and the -listen option does not decide.
	if run.ListenSource != sourceFlag && cfg.AllowOthers != openNow {
		// Say so.
		pendNet = "saved: " + map[bool]string{true: "Yes", false: "No"}[cfg.AllowOthers] + " (used after a restart)"
		// A restart is needed.
		restart = true
	} // end of the pending network
	// The -listen option overrides the saved choice.
	if run.ListenSource == sourceFlag && cfg.AllowOthers {
		// Say so.
		pendNet = "the command-line option -listen overrides this"
	} // end of the overridden network
	// The words for the network row.
	netNow := "No (this computer only)"
	// Open now.
	if openNow {
		// The words.
		netNow = "Yes (" + run.Listen + ")"
	} // end of the network words
	// The history file row's words.
	histNow := "No"
	// On.
	if cfg.SaveHistory {
		// The words.
		histNow = "Yes"
	} // end of the history words
	// The seven lines.
	rows := []settingsRow{
		{Label: "Ollama address", Help: "Where Ollama listens, for example http://192.168.1.20:11434.", Name: "ollama_url", Kind: "text", Now: addr.URL.Redacted(), From: addr.Source, Pending: pendAddr, Typed: typed.Address, Default: defaultOllamaURL, Applies: "restart"},
		{Label: "Check interval (seconds)", Help: "How often the monitor asks Ollama in the background, for example 10.", Name: "interval", Kind: "number", Now: strconv.Itoa(int(cfg.interval(sampleEvery).Seconds())), From: fromLayer(cfg.IntervalSeconds > 0), Typed: typed.Interval, Default: strconv.Itoa(int(sampleEvery.Seconds())), Applies: "at once", Min: minIntervalSeconds, Max: maxIntervalSeconds},
		{Label: "Check timeout (seconds)", Help: "How long one status check waits for Ollama before it counts as failed, for example 5.", Name: "timeout", Kind: "number", Now: strconv.Itoa(int(cfg.timeout(defaultCheckTimeout).Seconds())), From: fromLayer(cfg.TimeoutSeconds > 0), Typed: typed.Timeout, Default: strconv.Itoa(int(defaultCheckTimeout.Seconds())), Applies: "at once", Min: minTimeoutSeconds, Max: maxTimeoutSeconds},
		{Label: "Chart history (minutes)", Help: "How far back the charts look, for example 30.", Name: "history", Kind: "number", Now: strconv.Itoa(int(cfg.window().Minutes())), From: fromLayer(cfg.HistoryMinutes > 0), Typed: typed.History, Default: strconv.Itoa(int(chartWindow.Minutes())), Applies: "at once", Min: minHistoryMinutes, Max: maxHistoryMinutes},
		{Label: "Let other machines open this page", Help: "Yes lets a browser on another computer open it; No keeps it on this computer.", Name: "others", Kind: "yesno", Now: netNow, From: run.ListenSource, Pending: pendNet, Typed: typed.Others, Default: "No", Applies: "restart"},
		{Label: "Save check history to a file", Help: "Yes keeps the charts after a restart; No keeps them in memory only.", Name: "savehistory", Kind: "yesno", Now: histNow, From: fromLayer(cfg.SaveHistory), Typed: typed.SaveHistory, Default: "No", Applies: "at once"},
	} // end of the rows
	// Hand back the lines and whether a restart is waiting.
	return rows, restart
} // end of buildSettingsRows

// settingsHandlers returns the page (GET) and the save (POST) handlers.
func settingsHandlers(addr ollamaAddress, mon *monitor, token string) (http.HandlerFunc, http.HandlerFunc) {
	// Parse the template once.
	page := template.Must(template.New("settings").Parse(settingsTemplateText))
	// The folder shown to the person.
	folder := ""
	// Only when a folder is in use.
	if mon.store.dir != "" {
		// Show it as a clean path.
		folder = filepath.Clean(mon.store.dir)
	} // end of the folder check
	// The data and state folders shown to the person, as clean paths.
	dataFolder, stateFolder := "", ""
	// The data folder.
	if d := dataRoot(); d != "" {
		// Show it as a clean path.
		dataFolder = filepath.Clean(d)
	} // end of the data check
	// The state folder.
	if st := mon.store.stateFolder(); st != "" {
		// Show it as a clean path.
		stateFolder = filepath.Clean(st)
	} // end of the state check
	// render draws the page for the given typed values and problems.
	render := func(w http.ResponseWriter, r *http.Request, typed settingsFormValues, problems []string, saved string, status int) {
		// The saved settings.
		cfg := mon.store.get()
		// The lines and the restart flag.
		rows, restart := buildSettingsRows(cfg, addr, mon.run, typed)
		// Everything the template needs.
		desk := desktopIcon{env: mon.denv, dir: mon.store.dir, dataDir: dataRoot()}
		// The icon section's facts.
		iconAvail, iconExists, iconPath := desk.available(), desk.exists(), desk.desktopPath()
		// The note after a button; unknown keys show nothing.
		iconNote := iconNotes[r.URL.Query().Get("icon")]
		// Everything the template needs.
		data := settingsPage{IconAvailable: iconAvail, IconExists: iconExists, IconPath: iconPath, IconNote: iconNote, Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder, DataFolder: dataFolder, StateFolder: stateFolder}
		// Build the page in memory first, so a template error gives a clean 500.
		var buf bytes.Buffer
		// Fill the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the cause in the terminal.
			log.Printf("settings page: %v", err)
			// Tell the browser plainly.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the error check
		// The page is HTML in UTF-8.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// The page shows live values, so it is never cached.
		w.Header().Set("Cache-Control", "no-store")
		// The status (200, or 422 when a form was refused).
		w.WriteHeader(status)
		// Send it.
		w.Write(buf.Bytes())
	} // end of render
	// show answers a plain visit.
	show := func(w http.ResponseWriter, r *http.Request) {
		// The note after a save comes in the address.
		saved := r.URL.Query().Get("saved")
		// Only the two known words are shown.
		if saved != "saved" && saved != "reset" {
			// Nothing.
			saved = ""
		} // end of the word check
		// Draw it with the saved values.
		render(w, r, formFromSettings(mon.store.get()), nil, saved, http.StatusOK)
	} // end of show
	// save answers the form.
	save := func(w http.ResponseWriter, r *http.Request) {
		// A form is small.
		r.Body = http.MaxBytesReader(w, r.Body, 4096)
		// It must come from this page.
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return
		} // end of the origin check
		// Read the form.
		if err := r.ParseForm(); err != nil {
			// Refuse.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the form check
		// The token must match.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return
		} // end of the token check
		// Back to the defaults: nothing is saved here. The form is filled with the default values, and the person decides: Save settings keeps them, Cancel leaves everything as it was.
		if r.PostFormValue("action") == "defaults" {
			// The default values as the form shows them.
			render(w, r, formFromSettings(appSettings{}), nil, "draft", http.StatusOK)
			// Stop here.
			return
		} // end of the defaults case
		// What the person typed.
		typed := settingsFormValues{
			// The address.
			Address: strings.TrimSpace(r.PostFormValue("ollama_url")),
			// The numbers.
			Interval: strings.TrimSpace(r.PostFormValue("interval")), Timeout: strings.TrimSpace(r.PostFormValue("timeout")), History: strings.TrimSpace(r.PostFormValue("history")),
			// The switches; anything but yes is no.
			Others: yesNo(r.PostFormValue("others") == "yes"), SaveHistory: yesNo(r.PostFormValue("savehistory") == "yes"),
		} // end of the typed values
		// The new settings; a value equal to the default is stored as "not set".
		var next appSettings
		// The problems of the typed texts.
		var problems []string
		// The address; the default address means not set.
		if typed.Address != defaultOllamaURL {
			// Keep it.
			next.OllamaURL = typed.Address
		} // end of the address
		// The three numbers, each with its own name for the message.
		for _, f := range []struct {
			// The text, the destination, the default and the name.
			text string
			dst  *int
			def  int
			name string
		}{
			{typed.Interval, &next.IntervalSeconds, int(sampleEvery.Seconds()), "Check interval"},
			{typed.Timeout, &next.TimeoutSeconds, int(defaultCheckTimeout.Seconds()), "Check timeout"},
			{typed.History, &next.HistoryMinutes, int(chartWindow.Minutes()), "Chart history"},
		} {
			// Read the number.
			n, ok := numberOrZero(f.text)
			// Not a whole number.
			if !ok {
				// Say so.
				problems = append(problems, fmt.Sprintf("%s: use a whole number.", f.name))
				// Next one.
				continue
			} // end of the number check
			// A value equal to the default is stored as not set; the limits are checked below.
			if n != f.def {
				// Keep it.
				*f.dst = n
			} // end of the default check
		} // end of the loop
		// The two switches.
		next.AllowOthers = typed.Others == "yes"
		// The history file.
		next.SaveHistory = typed.SaveHistory == "yes"
		// Add the limit problems.
		problems = append(problems, next.problems()...)
		// Something is wrong: save nothing and show the form again as typed.
		if len(problems) > 0 {
			// Refused.
			render(w, r, typed, problems, "", http.StatusUnprocessableEntity)
			// Stop here.
			return
		} // end of the problem check
		// The timeout against the interval must be checked with the values in use, because one of them may be at its default.
		if next.timeout(defaultCheckTimeout) >= next.interval(sampleEvery) {
			// Refused.
			render(w, r, typed, []string{"Check timeout: it must be shorter than the check interval."}, "", http.StatusUnprocessableEntity)
			// Stop here.
			return
		} // end of the overlap check
		// Save.
		if err := mon.store.put(next); err != nil {
			// The file could not be written; nothing changed.
			render(w, r, typed, []string{"The settings could not be saved: " + err.Error()}, "", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the save check
		// Turning the history file on writes it soon; write what is in memory now so it is not empty.
		if next.SaveHistory {
			// A failed write is not fatal.
			_ = mon.store.saveSamples(mon.hist.all())
		} // end of the history write
		// Show the page again with the note.
		http.Redirect(w, r, "/settings?saved=saved", http.StatusSeeOther)
	} // end of save
	// Hand back both.
	return show, save
} // end of settingsHandlers
