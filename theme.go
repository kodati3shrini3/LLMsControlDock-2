// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides cookies, redirects and status codes.
	"net/http"
) // end of imports

// themeCookieName is the name of the cookie that remembers the chosen theme in this browser (it holds only the word light or dark).
const themeCookieName = "occ_theme"

// themeCookieMaxAge keeps the choice for one year, in seconds.
const themeCookieMaxAge = 365 * 24 * 60 * 60

// themeFromRequest reads the saved theme from the cookie: "light", "dark", or "" for follow the system (also used for a missing or unknown value).
func themeFromRequest(r *http.Request) string {
	// Read the cookie; an error means it is not there.
	c, err := r.Cookie(themeCookieName)
	// No cookie: follow the system.
	if err != nil {
		// The empty text means follow the system.
		return ""
	} // end of the cookie check
	// Only the two known words are accepted, so a changed cookie can never put other text into the page.
	if c.Value == "light" || c.Value == "dark" {
		// A valid choice.
		return c.Value
	} // end of the value check
	// Anything else is ignored.
	return ""
} // end of themeFromRequest

// themeHandler handles the POST that the theme switch sends: it checks where the request came from, checks the page token, saves the choice in a cookie and goes back to the page.
func themeHandler(token string) http.HandlerFunc {
	// Return the handler function.
	return func(w http.ResponseWriter, r *http.Request) {
		// Never read more than 1 KB of form data; the real form is tiny.
		r.Body = http.MaxBytesReader(w, r.Body, 1024)
		// Only a form on this very page may send this request.
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return
		} // end of the origin check
		// Read the form fields.
		if err := r.ParseForm(); err != nil {
			// A broken or too large form.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the form check
		// The token proves the form came from a page this monitor made.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return
		} // end of the token check
		// Act on the chosen theme.
		switch choice := r.PostFormValue("theme"); choice {
		// A fixed theme: remember it in the cookie.
		case "light", "dark":
			// Save it for one year; HttpOnly keeps it from page scripts, SameSite=Strict keeps it from other sites.
			http.SetCookie(w, &http.Cookie{Name: themeCookieName, Value: choice, Path: "/", MaxAge: themeCookieMaxAge, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Follow the system: delete the cookie (a negative MaxAge means delete).
		case "system":
			// Send an empty cookie that expires at once.
			http.SetCookie(w, &http.Cookie{Name: themeCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Anything else is a mistake.
		default:
			// Refuse.
			http.Error(w, "unknown theme", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the theme choice
		// Go back to the page, which now uses the new theme (303 makes the browser ask with GET).
		http.Redirect(w, r, "/", http.StatusSeeOther)
	} // end of the handler
} // end of themeHandler
