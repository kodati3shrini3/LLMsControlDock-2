// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes holds the finished page.
	"bytes"
	// context lets a request be cancelled or given a deadline.
	"context"
	// embed lets the delete page template be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// fmt builds formatted text.
	"fmt"
	// html/template builds HTML and escapes every inserted value.
	"html/template"
	// log prints messages to the terminal.
	"log"
	// net/http provides requests and status codes.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// time provides durations and the deletion stamp.
	"time"
) // end of imports

// deleteTemplateText is the delete page template, stored inside the executable at build time.
//
//go:embed web/delete.html
var deleteTemplateText string

// deleteTimeout is how long the delete request may take; removing a big model's files can take a moment.
const deleteTimeout = 30 * time.Second

// deleteModel asks Ollama to remove one model from the disk (the documented DELETE /api/delete request).
func deleteModel(ctx context.Context, base *url.URL, name string, timeout time.Duration) error {
	// Send the request with the DELETE method.
	status, err := sendJSON(ctx, http.MethodDelete, base, "api/delete", timeout, map[string]any{"model": name})
	// No answer at all.
	if err != nil {
		// Pass the safe error on.
		return err
	} // end of the send check
	// Status 200 means Ollama removed it.
	if status == http.StatusOK {
		// Done.
		return nil
	} // end of the success case
	// Status 404 means Ollama does not know the name (it may have been removed by someone else a moment ago).
	if status == http.StatusNotFound {
		// Say so in words.
		return fmt.Errorf("Ollama does not have a model with this name (status 404)")
	} // end of the 404 case
	// Any other status.
	return fmt.Errorf("Ollama answered the delete request with status %d", status)
} // end of deleteModel

// deletePage is everything the delete page template can show.
type deletePage struct {
	// Kind says which version of the page to draw: confirm, busy, done, gone, restore, forgotten, error.
	Kind string
	// Model is the model name.
	Model string
	// SizeText is the size on disk in words, for example "4.7 GB".
	SizeText string
	// When is the deletion time in words (restore page).
	When string
	// Digest is the model's fingerprint as remembered (restore page).
	Digest string
	// Remaining is the time left before Ollama unloads the model by itself (busy page).
	Remaining string
	// Seconds is the same time in seconds, for the ticking timer; 0 means no ticking timer.
	Seconds int
	// Mismatch is true when the typed name did not match (busy page after a failed force delete).
	Mismatch bool
	// Detail is the plain reason shown on the error page.
	Detail string
	// Note carries a warning that does not stop the work (for example, the list could not be saved).
	Note string
	// LibText is what the check of the Ollama library found, in words (empty when no check was made).
	LibText string
	// LibClass is "ok" for good news and "warn" for a caution; it decides how the note is drawn.
	LibClass string
	// ShowPull is false when the library has no such model, so the page does not offer a command that must fail.
	ShowPull bool
	// Theme is the saved theme choice, as on the main page.
	Theme string
	// Token is the page token for the forms on this page.
	Token string
} // end of deletePage

// deleteHandlers builds the handlers: ask (changes nothing), confirm, force, restore (information only) and forget.
func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask, confirm, force, restore, forget http.HandlerFunc) {
	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
	page := template.Must(template.New("delete").Parse(deleteTemplateText))
	// readForm runs the checks that all handlers share and returns the model name; ok is false when a refusal was already sent.
	readForm := func(w http.ResponseWriter, r *http.Request) (string, bool) {
		// Never read more than 2 KB of form data; the real forms are tiny.
		r.Body = http.MaxBytesReader(w, r.Body, 2048)
		// Only a form on this very page may send this request (requirement S2).
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return "", false
		} // end of the origin check
		// Read the form fields.
		if err := r.ParseForm(); err != nil {
			// A broken or too large form.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return "", false
		} // end of the form check
		// The token proves the form came from a page this monitor made.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return "", false
		} // end of the token check
		// The model name must be present and not absurdly long.
		name := r.PostFormValue("model")
		// Check the name.
		if name == "" || len(name) > maxModelNameLen {
			// Refuse.
			http.Error(w, "bad model name", http.StatusBadRequest)
			// Stop here.
			return "", false
		} // end of the name check
		// All checks passed.
		return name, true
	} // end of readForm
	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, status int, data deletePage) {
		// Add what every version of the page needs.
		data.Theme, data.Token = themeFromRequest(r), token
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("delete page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// A page with a ticking timer may run the monitor's own script, and nothing else.
		if data.Seconds > 0 {
			// Replace the strict policy by the one that allows the script file.
			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
		} // end of the script policy
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the status line.
		w.WriteHeader(status)
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of show
	// busyPage fills the "model is loaded, it may be in use" version, with the time left before Ollama unloads it by itself.
	busyPage := func(name string, size int64, l loadedModel, mismatch bool) deletePage {
		// Work out the time left.
		exp, expOK := l.expiresTime()
		// Build the page data.
		return deletePage{Kind: "busy", Model: name, SizeText: formatSize(size), Remaining: remainingText(time.Now(), exp, expOK), Seconds: remainingSeconds(time.Now(), exp, expOK), Mismatch: mismatch}
	} // end of busyPage
	// withLib asks the Ollama library, read-only, about this model and adds the answer in words to the page; phase is "delete" or "restore". Only the model name leaves this computer.
	withLib := func(r *http.Request, p deletePage, name, digest, phase string) deletePage {
		// Ask the library.
		state := checkLibrary(r.Context(), name, digest)
		// Word the answer.
		p.LibText, p.LibClass = libraryNote(state, phase)
		// A command that is certain to fail is not offered.
		p.ShowPull = state != libMissing
		// Hand the page back.
		return p
	} // end of withLib
	// look asks Ollama, right now, what is installed and what is loaded; the loaded entry has an empty name when the model is not loaded. It shows the error or "gone" page itself when it cannot go on, and then returns false.
	look := func(w http.ResponseWriter, r *http.Request, name string) (installedModel, loadedModel, bool) {
		// What is installed.
		inst, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, deletePage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return installedModel{}, loadedModel{}, false
		} // end of the installed check
		// What is loaded.
		ld, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, deletePage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return installedModel{}, loadedModel{}, false
		} // end of the loaded check
		// The model, if it is installed.
		m, found := findInstalled(inst, name)
		// It is not installed (any more): say so, with no delete button.
		if !found {
			// Show that page.
			show(w, r, http.StatusOK, deletePage{Kind: "gone", Model: name})
			// Stop here.
			return installedModel{}, loadedModel{}, false
		} // end of the installed case
		// The loaded entry, if it is loaded (the zero value otherwise).
		l, _ := findLoaded(ld, name)
		// Hand back the facts and say no page has been sent yet.
		return m, l, true
	} // end of look
	// doDelete deletes, checks that the model is really gone, remembers it, and shows the result page.
	doDelete := func(w http.ResponseWriter, r *http.Request, m installedModel) {
		// Ask Ollama to delete it.
		if err := deleteModel(r.Context(), addr.URL, m.Name, deleteTimeout); err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, deletePage{Kind: "error", Model: m.Name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the delete check
		// Do not trust the 200 alone: ask Ollama whether the model is still installed.
		inst, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// The list could not be read afterwards.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, deletePage{Kind: "error", Model: m.Name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the verify check
		// Still listed: say so honestly.
		if _, still := findInstalled(inst, m.Name); still {
			// Show the plain reason.
			show(w, r, http.StatusOK, deletePage{Kind: "error", Model: m.Name, Detail: "Ollama accepted the request, but the model is still listed. Reload the monitor page in a moment to check."})
			// Stop here.
			return
		} // end of the still-listed case
		// Remember it, so the table can show it greyed out and Restore can offer it again.
		note := ""
		// Save; a failure does not undo the deletion, it only means the ghost row will be missing.
		if err := store.add(deletedModel{Name: m.Name, Digest: m.Digest, Size: m.Size, DeletedAt: time.Now()}); err != nil {
			// Say so in words.
			note = "The model is deleted, but this monitor could not remember it, so there will be no Restore row. " + err.Error()
		} // end of the save check
		// Done.
		show(w, r, http.StatusOK, deletePage{Kind: "done", Model: m.Name, SizeText: formatSize(m.Size), Note: note})
	} // end of doDelete
	// ask is the first step: it re-checks Ollama and shows the right warning; it never deletes anything.
	ask = func(w http.ResponseWriter, r *http.Request) {
		// Run the shared checks.
		name, ok := readForm(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Ask Ollama what is installed and loaded right now.
		m, l, ok := look(w, r, name)
		// A page was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the look check
		// Loaded means it may be in use: Hold or Force delete.
		if l.Name == name {
			// Show the busy version.
			show(w, r, http.StatusOK, withLib(r, busyPage(name, m.Size, l, false), name, m.Digest, "delete"))
			// Stop here.
			return
		} // end of the loaded case
		// Not loaded: the normal warning.
		show(w, r, http.StatusOK, withLib(r, deletePage{Kind: "confirm", Model: name, SizeText: formatSize(m.Size)}, name, m.Digest, "delete"))
	} // end of ask
	// confirm is the second step for a model that is not loaded; if it has been loaded meanwhile, it goes back to the busy version.
	confirm = func(w http.ResponseWriter, r *http.Request) {
		// Run the shared checks.
		name, ok := readForm(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Look again.
		m, l, ok := look(w, r, name)
		// A page was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the look check
		// Loaded in the meantime: this button must not delete it.
		if l.Name == name {
			// Show the busy version.
			show(w, r, http.StatusOK, withLib(r, busyPage(name, m.Size, l, false), name, m.Digest, "delete"))
			// Stop here.
			return
		} // end of the loaded case
		// Delete it.
		doDelete(w, r, m)
	} // end of confirm
	// force deletes a model that is loaded, but only when its exact name was typed.
	force = func(w http.ResponseWriter, r *http.Request) {
		// Run the shared checks.
		name, ok := readForm(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Look again.
		m, l, ok := look(w, r, name)
		// A page was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the look check
		// The typed name must match exactly.
		if r.PostFormValue("typed") != name {
			// Show the busy version again with a note; if it is no longer loaded, show the normal warning.
			if l.Name == name {
				// Busy again.
				show(w, r, http.StatusOK, withLib(r, busyPage(name, m.Size, l, true), name, m.Digest, "delete"))
			} else { // the other case
				// Normal warning.
				show(w, r, http.StatusOK, withLib(r, deletePage{Kind: "confirm", Model: name, SizeText: formatSize(m.Size)}, name, m.Digest, "delete"))
			} // end of the loaded check
			// Stop here.
			return
		} // end of the name check
		// Delete it.
		doDelete(w, r, m)
	} // end of force
	// restore (Phase 1) only explains how to bring a deleted model back; it changes nothing.
	restore = func(w http.ResponseWriter, r *http.Request) {
		// Run the shared checks.
		name, ok := readForm(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// The monitor must remember this name.
		d, found := store.find(name)
		// Unknown name.
		if !found {
			// Say so.
			show(w, r, http.StatusOK, deletePage{Kind: "forgotten", Model: name})
			// Stop here.
			return
		} // end of the unknown case
		// Show the information page.
		show(w, r, http.StatusOK, withLib(r, deletePage{Kind: "restore", Model: d.Name, SizeText: formatSize(d.Size), Digest: d.Digest, When: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST")}, d.Name, d.Digest, "restore"))
	} // end of restore
	// forget removes the greyed row, without touching Ollama.
	forget = func(w http.ResponseWriter, r *http.Request) {
		// Run the shared checks.
		name, ok := readForm(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Remove it from the list.
		if err := store.forget(name); err != nil {
			// Show the plain reason.
			show(w, r, http.StatusInternalServerError, deletePage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the save check
		// Done.
		show(w, r, http.StatusOK, deletePage{Kind: "forgotten", Model: name})
	} // end of forget
	// Hand all five back (they are the named results).
	return
} // end of deleteHandlers
