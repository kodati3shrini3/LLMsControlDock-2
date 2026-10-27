// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds a page in memory before it is sent.
	"bytes"
	// context carries the time limit of the clean-up before stopping.
	"context"
	// embed lets the page template be stored inside the executable.
	_ "embed"
	// html/template builds the page and escapes every value.
	"html/template"
	// log records a real failure for the person running the program.
	"log"
	// net/http serves the pages and sets the cookie.
	"net/http"
	// sort keeps the list of running work in the order it started.
	"sort"
	// sync protects the list of running work and makes the stop happen once.
	"sync"
	// time gives the time limit of the clean-up.
	"time"
) // end of imports

// controlTemplateText is the template of the Stop pages, stored inside the executable at build time.
//
//go:embed web/control.html
var controlTemplateText string

// watchCookieName is the cookie that remembers that the person paused the page.
const watchCookieName = "occ_watch"

// watchRefreshSeconds is how often the page updates itself while it is being watched.
const watchRefreshSeconds = 10

// stopCleanupLimit is how long the clean-up of running work may take before the monitor stops anyway.
const stopCleanupLimit = 20 * time.Second

// workItem is one piece of work that is running right now.
type workItem struct {
	// id orders the items by start time.
	id int
	// text says in plain words what is running and what Stop would do to it.
	text string
	// cleanup undoes what the work changed (for example unloads the model a test loaded); it may be nil.
	cleanup func(ctx context.Context)
} // end of workItem

// workTracker remembers the work that is running right now, so the Stop page can warn about it.
type workTracker struct {
	// mu protects the fields below.
	mu sync.Mutex
	// next is the id of the next item.
	next int
	// items are the running pieces of work.
	items map[int]workItem
} // end of workTracker

// activeWork is the one tracker of this program.
var activeWork = &workTracker{items: map[int]workItem{}}

// stopRequest shuts the program down; main replaces it, and the tests replace it with a recorder.
var stopRequest = func() {}

// begin records the start of some work and returns the function that records its end.
func (t *workTracker) begin(text string, cleanup func(ctx context.Context)) func() {
	// One writer at a time.
	t.mu.Lock()
	// Release at the end.
	defer t.mu.Unlock()
	// The id of this item.
	id := t.next
	// The next one gets a higher id.
	t.next++
	// Remember it.
	t.items[id] = workItem{id: id, text: text, cleanup: cleanup}
	// The function that ends it.
	return func() {
		// One writer at a time.
		t.mu.Lock()
		// Release at the end.
		defer t.mu.Unlock()
		// Forget it.
		delete(t.items, id)
	} // end of the end function
} // end of begin

// list returns the running items, oldest first.
func (t *workTracker) list() []workItem {
	// One reader at a time.
	t.mu.Lock()
	// Release at the end.
	defer t.mu.Unlock()
	// The copy.
	out := make([]workItem, 0, len(t.items))
	// Fill it.
	for _, it := range t.items {
		// One item.
		out = append(out, it)
	} // end of the loop
	// Oldest first.
	sort.Slice(out, func(i, j int) bool { return out[i].id < out[j].id })
	// Hand it back.
	return out
} // end of list

// texts returns the plain descriptions of the running work.
func (t *workTracker) texts() []string {
	// The descriptions.
	var out []string
	// Fill them.
	for _, it := range t.list() {
		// One description.
		out = append(out, it.text)
	} // end of the loop
	// Hand them back.
	return out
} // end of texts

// runCleanups undoes what the running work changed, one after the other, within the time limit.
func (t *workTracker) runCleanups(ctx context.Context) {
	// Each item with a clean-up.
	for _, it := range t.list() {
		// Nothing to undo.
		if it.cleanup == nil {
			// Next item.
			continue
		} // end of the nil check
		// Undo it.
		it.cleanup(ctx)
	} // end of the loop
} // end of runCleanups

// watchPaused says whether the request carries the cookie of a paused page.
func watchPaused(r *http.Request) bool {
	// Look for the cookie.
	c, err := r.Cookie(watchCookieName)
	// No cookie means the page is being watched.
	if err != nil {
		// Watching.
		return false
	} // end of the cookie check
	// Only the exact word counts.
	return c.Value == "paused"
} // end of watchPaused

// watchHandler pauses or resumes the automatic updates; it only sets a cookie and goes back to the page.
func watchHandler(token string) http.HandlerFunc {
	// The handler.
	return func(w http.ResponseWriter, r *http.Request) {
		// Never read more than 1 KB of form data.
		r.Body = http.MaxBytesReader(w, r.Body, 1024)
		// Only a form on this very page may send this request.
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
		// The page token must match.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return
		} // end of the token check
		// Which action.
		switch r.PostFormValue("action") {
		// Pause: remember it in the browser for a year.
		case "pause":
			// Set the cookie.
			http.SetCookie(w, &http.Cookie{Name: watchCookieName, Value: "paused", Path: "/", MaxAge: themeCookieMaxAge, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Resume: delete the cookie.
		case "resume":
			// Delete it.
			http.SetCookie(w, &http.Cookie{Name: watchCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Anything else is refused.
		default:
			// Refuse.
			http.Error(w, "unknown action", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the action choice
		// Back to the page.
		http.Redirect(w, r, "/", http.StatusSeeOther)
	} // end of the handler
} // end of watchHandler

// controlPage is what the Stop template shows.
type controlPage struct {
	// Theme is the colour scheme asked for in the cookie, or empty.
	Theme string
	// Size is the saved text size, medium, or empty for the browser's own size.
	Size string
	// Token is the page token for the confirm form.
	Token string
	// Kind is stopask (the question) or stopped (the last page).
	Kind string
	// Work describes what is running right now.
	Work []string
} // end of controlPage

// stopHandlers returns the two steps of stopping: the question, and the real stop.
func stopHandlers(token string) (http.HandlerFunc, http.HandlerFunc) {
	// Read the template once.
	page := template.Must(template.New("control").Parse(controlTemplateText))
	// Stop only once, however many times the button is pressed.
	var once sync.Once
	// check runs the shared form checks; ok is false when a refusal was already sent.
	check := func(w http.ResponseWriter, r *http.Request) bool {
		// Never read more than 1 KB of form data.
		r.Body = http.MaxBytesReader(w, r.Body, 1024)
		// Only a form on this very page may send this request (requirement S2).
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return false
		} // end of the origin check
		// Read the form.
		if err := r.ParseForm(); err != nil {
			// Refuse.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return false
		} // end of the form check
		// The page token must match.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return false
		} // end of the token check
		// All good.
		return true
	} // end of check
	// show builds a page in memory first, so a template error gives a clean 500.
	show := func(w http.ResponseWriter, r *http.Request, data controlPage) {
		// What every version needs.
		data.Theme, data.Token = themeFromRequest(r), token
		// The saved text size, from the cookie; empty means the browser's own size.
		data.Size = sizeFromRequest(r)
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason.
			log.Printf("stop page error: %v", err)
			// Send a plain 500.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the page.
		w.Write(buf.Bytes())
	} // end of show
	// ask is the first step: the question, with a warning about running work; it changes nothing.
	ask := func(w http.ResponseWriter, r *http.Request) {
		// The checks.
		if !check(w, r) {
			// A refusal was already sent.
			return
		} // end of the checks
		// Show the question.
		show(w, r, controlPage{Kind: "stopask", Work: activeWork.texts()})
	} // end of ask
	// confirm is the second step: the last page is sent first, then the clean-up and the stop follow.
	confirm := func(w http.ResponseWriter, r *http.Request) {
		// The checks.
		if !check(w, r) {
			// A refusal was already sent.
			return
		} // end of the checks
		// The last page.
		show(w, r, controlPage{Kind: "stopped"})
		// Send it now, so it reaches the browser before the program ends.
		if f, ok := w.(http.Flusher); ok {
			// Flush.
			f.Flush()
		} // end of the flush check
		// Clean up and stop in the background, once.
		once.Do(func() {
			// A goroutine, so this handler can finish.
			go func() {
				// A short moment for the page to arrive.
				time.Sleep(200 * time.Millisecond)
				// Undo what running work changed, within a time limit.
				ctx, cancel := context.WithTimeout(context.Background(), stopCleanupLimit)
				// Run the clean-ups.
				activeWork.runCleanups(ctx)
				// Release the timer.
				cancel()
				// Shut the program down.
				stopRequest()
			}() // end of the goroutine
		}) // end of once
	} // end of confirm
	// Hand both back.
	return ask, confirm
} // end of stopHandlers
