// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides cookies, redirects and status codes.
	"net/http"
) // end of imports

// sizeCookieName is the name of the cookie that remembers the chosen text size in this browser (it holds only the word medium).
const sizeCookieName = "occ_size"

// sizeCookieMaxAge keeps the choice for one year, in seconds.
const sizeCookieMaxAge = 365 * 24 * 60 * 60

// sizeFromRequest reads the saved text size from the cookie: "medium", or "" for large, which is the browser's own text size (also used for a missing or unknown value).
func sizeFromRequest(r *http.Request) string {
	// Look for the cookie.
	c, err := r.Cookie(sizeCookieName)
	// No cookie: follow the browser.
	if err != nil {
		// Large is the default.
		return ""
	} // end of the cookie check
	// Only one saved value is known.
	if c.Value == "medium" {
		// Medium: 81 percent of the browser's text size.
		return "medium"
	} // end of the value check
	// Anything else is ignored, so a damaged cookie can never break the page.
	return ""
} // end of sizeFromRequest

// sizeHandler handles the POST that the text-size switch sends: it checks where the request came from, checks the page token, saves or clears the choice in a cookie and goes back to the page.
func sizeHandler(token string) http.HandlerFunc {
	// The handler itself.
	return func(w http.ResponseWriter, r *http.Request) {
		// A size form is tiny; refuse anything larger than 1 KB.
		r.Body = http.MaxBytesReader(w, r.Body, 1024)
		// The request must come from this monitor's own page.
		if !sameOrigin(r) {
			// Refuse without saying more.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return
		} // end of the origin check
		// Read the form.
		if err := r.ParseForm(); err != nil {
			// A broken or too large form.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the form check
		// The page token proves the form came from a page this monitor made.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return
		} // end of the token check
		// Act on the choice.
		switch choice := r.PostFormValue("size"); choice {
		// Medium is remembered.
		case "medium":
			// Save the word medium; the cookie is not readable by scripts and is never sent to other sites.
			http.SetCookie(w, &http.Cookie{Name: sizeCookieName, Value: "medium", Path: "/", MaxAge: sizeCookieMaxAge, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Large and Auto both mean: follow the browser's own text size, so the saved choice is removed.
		case "large", "auto":
			// An empty value with a negative age deletes the cookie.
			http.SetCookie(w, &http.Cookie{Name: sizeCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Anything else is a mistake.
		default:
			// Refuse.
			http.Error(w, "unknown text size", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the size choice
		// Go back to the main page; 303 makes the browser use GET, so a reload does not send the form again.
		http.Redirect(w, r, "/", http.StatusSeeOther)
	} // end of the handler
} // end of sizeHandler
