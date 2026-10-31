// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides the method names and the cookie type.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestDetailsTwistieDefaultsOpen checks that a person with no cookie sees both boxes and the hide button.
func TestDetailsTwistieDefaultsOpen(t *testing.T) {
	// A fake and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// The page with no cookie.
	page := pageWithCookie(t, rig, nil)
	// The open state: the twistie, both boxes, the bubble and the hide button.
	for _, w := range []string{`action="/details"`, `name="action" value="close"`, `aria-expanded="true"`, "Monitoring details", "click to hide", `aria-label="API health"`, `aria-labelledby="events-title"`, `id="tip-details"`, "Folds the API health and Event log boxes away"} {
		// Look for it.
		if !strings.Contains(page, w) {
			// Report the gap.
			t.Errorf("the open page lacks %q", w)
		} // end of the check
	} // end of the loop
} // end of TestDetailsTwistieDefaultsOpen

// TestDetailsTwistieFolded checks that the cookie hides both boxes but keeps the twistie, the models and the log running.
func TestDetailsTwistieFolded(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, _ := perfRig(t, f)
	// The folded page.
	folded := &http.Cookie{Name: detailsCookieName, Value: "closed"}
	// Ask for it.
	page := pageWithCookie(t, rig, folded)
	// Both boxes are gone.
	for _, w := range []string{`aria-label="API health"`, `aria-labelledby="events-title"`, "Failed checks:", "Changes seen between two checks"} {
		// It must be absent.
		if strings.Contains(page, w) {
			// Report it.
			t.Errorf("the folded page still shows %q", w)
		} // end of the check
	} // end of the loop
	// The twistie stays, offers to show, and the models box is still there.
	for _, w := range []string{`name="action" value="open"`, `aria-expanded="false"`, "click to show", `aria-labelledby="installed-title"`} {
		// Look for it.
		if !strings.Contains(page, w) {
			// Report the gap.
			t.Errorf("the folded page lacks %q", w)
		} // end of the check
	} // end of the loop
	// A model is loaded while the boxes are folded.
	f.mu.Lock()
	// In memory.
	f.loaded["seen-while-folded:1b"] = true
	// Release the fake.
	f.mu.Unlock()
	// The folded page is asked again, so the log sees the change.
	pageWithCookie(t, rig, folded)
	// Unfolded, the line is there: folding hides the log, it does not stop it.
	if open := pageWithCookie(t, rig, nil); !strings.Contains(open, "Model loaded: seen-while-folded:1b") {
		// Report the problem.
		t.Errorf("the event log missed a change while it was folded")
	} // end of the log check
	// A cookie with another value does not fold.
	if strings.Contains(pageWithCookie(t, rig, &http.Cookie{Name: detailsCookieName, Value: "yes"}), `value="open"`) {
		// Report it.
		t.Errorf("a wrong cookie value folded the details")
	} // end of the value check
} // end of TestDetailsTwistieFolded

// TestDetailsHandler checks the cookie set by closing and opening, and the form rules.
func TestDetailsHandler(t *testing.T) {
	// A fake and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// Closing sets the cookie and goes back to the page.
	res := post(t, rig.h, "/details", url.Values{"token": {rig.token}, "action": {"close"}}, fromThisPage)
	// A redirect to the page.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
		// Report it.
		t.Errorf("close: %d to %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the redirect check
	// The cookie.
	var closed *http.Cookie
	// Find it.
	for _, c := range res.Cookies() {
		// The right one.
		if c.Name == detailsCookieName {
			// Keep it.
			closed = c
		} // end of the name check
	} // end of the loop
	// It says closed, lasts a year, is not readable by scripts and is not sent from other sites.
	if closed == nil || closed.Value != "closed" || !closed.HttpOnly || closed.MaxAge != themeCookieMaxAge || closed.SameSite != http.SameSiteStrictMode {
		// Report it.
		t.Fatalf("close cookie wrong: %+v", closed)
	} // end of the cookie check
	// Opening deletes the cookie.
	res = post(t, rig.h, "/details", url.Values{"token": {rig.token}, "action": {"open"}}, fromThisPage)
	// A deleting cookie has a negative age.
	gone := false
	// Look at the cookies.
	for _, c := range res.Cookies() {
		// The right one, deleted.
		if c.Name == detailsCookieName && c.MaxAge < 0 {
			// Found.
			gone = true
		} // end of the check
	} // end of the loop
	// It must be deleted.
	if res.StatusCode != http.StatusSeeOther || !gone {
		// Report it.
		t.Errorf("open: %d, deleted=%v", res.StatusCode, gone)
	} // end of the open check
	// The rules: a wrong token, another site and a bad action are refused without a cookie.
	for name, tc := range map[string]struct {
		// form is what is sent.
		form url.Values
		// headers are the request headers.
		headers map[string]string
		// want is the expected status.
		want int
	}{
		"wrong token": {url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "action": {"close"}}, fromThisPage, http.StatusForbidden},
		"other site":  {url.Values{"token": {rig.token}, "action": {"close"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		"bad action":  {url.Values{"token": {rig.token}, "action": {"explode"}}, fromThisPage, http.StatusBadRequest},
	} { // end of the cases
		// Send it.
		if res := post(t, rig.h, "/details", tc.form, tc.headers); res.StatusCode != tc.want || len(res.Cookies()) != 0 {
			// Report it.
			t.Errorf("%s: %d (cookies %d), want %d without cookies", name, res.StatusCode, len(res.Cookies()), tc.want)
		} // end of the check
	} // end of the loop
	// A GET is not a route.
	if status, _, _ := get(t, rig.h, http.MethodGet, "/details"); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
		// Report it.
		t.Errorf("GET /details = %d", status)
	} // end of the GET check
} // end of TestDetailsHandler
