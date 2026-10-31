// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http serves the route and sets the cookie.
	"net/http"
) // end of imports

// detailsCookieName is the cookie that remembers that the person folded the monitoring details away.
const detailsCookieName = "occ_details"

// detailsClosed says whether the request carries the cookie of a folded "Monitoring details" twistie.
func detailsClosed(r *http.Request) bool {
	// Look for the cookie.
	c, err := r.Cookie(detailsCookieName)
	// No cookie means the twistie is open, which is the default.
	if err != nil {
		// Open.
		return false
	} // end of the cookie check
	// Only the exact word counts.
	return c.Value == "closed"
} // end of detailsClosed

// detailsHandler folds or unfolds the monitoring details; it only sets a cookie and goes back to the page.
func detailsHandler(token string) http.HandlerFunc {
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
		// Close: remember it in the browser for a year.
		case "close":
			// Set the cookie.
			http.SetCookie(w, &http.Cookie{Name: detailsCookieName, Value: "closed", Path: "/", MaxAge: themeCookieMaxAge, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Open: delete the cookie, because open is the default.
		case "open":
			// Delete it.
			http.SetCookie(w, &http.Cookie{Name: detailsCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
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
} // end of detailsHandler
