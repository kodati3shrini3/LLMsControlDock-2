// Package main tells Go that this file belongs to the program itself.
package main

import ( // import lists the packages this file uses.
	// bytes builds the page in memory before it is sent.
	"bytes"
	// html/template builds the page and escapes every inserted text, so a Modelfile can never inject markup.
	"html/template"
	// embed stores the page template inside the executable.
	_ "embed"
	// log writes the real reason for an error for the person running the program.
	"log"
	// net/http provides the request and response types.
	"net/http"
	// unicode/utf8 finds a safe place to cut a long text.
	"unicode/utf8"
	// fmt builds the text of a refusal from Ollama.
	"fmt"
) // end of imports

// modelfileTemplateText holds the Modelfile page, stored inside the executable at build time.
//
//go:embed web/modelfile.html
var modelfileTemplateText string

// maxModelfileShown is the most Modelfile text the page shows (512 KiB; a real Modelfile with its licence is far smaller).
const maxModelfileShown = 512 * 1024

// modelfilePage is everything the Modelfile page needs.
type modelfilePage struct {
	// Theme is the chosen colour theme, or empty to follow the system.
	Theme string
	// Size is the saved text size, medium, or empty for the browser's own size.
	Size string
	// Kind is modelfile, notinstalled or error.
	Kind string
	// Model is the model name.
	Model string
	// Text is the Modelfile text.
	Text string
	// Truncated is true when the text was cut because it was very long.
	Truncated bool
	// Detail is the plain reason shown on the error page.
	Detail string
} // end of modelfilePage

// cutText shortens a text to at most max bytes without splitting a character; the flag says whether anything was cut.
func cutText(text string, max int) (string, bool) {
	// A short text stays as it is.
	if len(text) <= max {
		// Nothing was cut.
		return text, false
	} // end of the length check
	// Step back to the start of a character, so no character is split.
	for max > 0 && !utf8.RuneStart(text[max]) {
		// One byte back.
		max--
	} // end of the loop
	// Hand back the shortened text.
	return text[:max], true
} // end of cutText

// modelfileHandler builds the handler of the read-only Modelfile page: it only reads from Ollama and changes nothing.
func modelfileHandler(addr ollamaAddress, token string) http.HandlerFunc {
	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
	page := template.Must(template.New("modelfile").Parse(modelfileTemplateText))
	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, status int, data modelfilePage) {
		// Add the theme.
		data.Theme = themeFromRequest(r)
		// The saved text size, from the cookie; empty means the browser's own size.
		data.Size = sizeFromRequest(r)
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason.
			log.Printf("modelfile page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the status line.
		w.WriteHeader(status)
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of show
	// The handler itself.
	return func(w http.ResponseWriter, r *http.Request) {
		// The same checks as every other form: same page, valid token, sensible model name.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Read the installed models now, not what the page showed earlier.
		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, modelfilePage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the installed read check
		// The model must exist.
		if _, found := findInstalled(installed, name); !found {
			// Say so.
			show(w, r, http.StatusOK, modelfilePage{Kind: "notinstalled", Model: name})
			// Stop here.
			return
		} // end of the installed check
		// Read the model's details, which include its Modelfile.
		info, status, err := fetchShow(r.Context(), addr.URL, name, gearTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, modelfilePage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the show read check
		// Ollama does not know the model.
		if status == http.StatusNotFound {
			// Say so.
			show(w, r, http.StatusOK, modelfilePage{Kind: "notinstalled", Model: name})
			// Stop here.
			return
		} // end of the unknown check
		// Any other refusal.
		if status != http.StatusOK {
			// Say so.
			show(w, r, http.StatusBadGateway, modelfilePage{Kind: "error", Model: name, Detail: fmt.Sprintf("Ollama answered the details request with status %d", status)})
			// Stop here.
			return
		} // end of the status check
		// Shorten an extremely long text.
		text, cut := cutText(info.Modelfile, maxModelfileShown)
		// Show the Modelfile.
		show(w, r, http.StatusOK, modelfilePage{Kind: "modelfile", Model: name, Text: text, Truncated: cut})
	} // end of the handler
} // end of modelfileHandler
