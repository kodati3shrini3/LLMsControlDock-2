// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages the tests use.
	// html unescapes the page text before it is compared.
	"html"
	// net/http gives the method names and status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestWrapText checks the line breaking: words stay whole and lines stay within the width.
func TestWrapText(t *testing.T) {
	// A sentence that needs three lines.
	got := wrapText("1. Shows the choices, with free disk and memory filled in.", 23)
	// Every line fits.
	for _, l := range got {
		// Too long.
		if len(l) > 23 {
			// Report.
			t.Errorf("line %q is longer than 23", l)
		} // end of the check
	} // end of the loop
	// Nothing is lost.
	if strings.Join(got, " ") != "1. Shows the choices, with free disk and memory filled in." {
		// Report.
		t.Errorf("the words changed: %q", got)
	} // end of the words check
	// A single long word stays whole.
	if w := wrapText("extraordinarily-long-word", 10); len(w) != 1 || w[0] != "extraordinarily-long-word" {
		// Report.
		t.Errorf("long word: %q", w)
	} // end of the long-word check
} // end of TestWrapText

// TestHelpTopicsFitTheirBoxes checks the data of every topic: lanes in range, and every step's words fit in a box of three lines.
func TestHelpTopicsFitTheirBoxes(t *testing.T) {
	// Each topic.
	for _, tp := range helpTopics {
		// There must be an introduction, and either steps (a diagram) or a guide, never both.
		if (len(tp.Steps) < 2) == (len(tp.Guide) == 0) || tp.Intro == "" || tp.ID == "" || tp.Title == "" {
			// Report.
			t.Errorf("topic %q is incomplete", tp.ID)
		} // end of the completeness check
		// Each step.
		for i, s := range tp.Steps {
			// The lane must exist.
			if s.Lane < 0 || s.Lane >= len(helpLanes) {
				// Report.
				t.Errorf("%s step %d: lane %d does not exist", tp.ID, i+1, s.Lane)
			} // end of the lane check
			// The words must fit.
			if n := len(wrapText("00. "+s.Text, helpWrap)); n > helpMaxLines {
				// Report.
				t.Errorf("%s step %d needs %d lines, the box holds %d: %q", tp.ID, i+1, n, helpMaxLines, s.Text)
			} // end of the fit check
		} // end of the step loop
	} // end of the topic loop
} // end of TestHelpTopicsFitTheirBoxes

// TestHelpPage checks the Help page: it is a plain read-only page with no script, each step is in the picture and in the list, the arrows join the steps, and the monitor links to it.
func TestHelpPage(t *testing.T) {
	// A rig.
	rig := newThemeRig(t)
	// Fetch the page.
	status, header, body := get(t, rig.h, http.MethodGet, "/help")
	// Found, as HTML, under the policy that allows this program's own script file and nothing inline.
	if csp := header.Get("Content-Security-Policy"); status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/html") || !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") || strings.Contains(csp, "unsafe-eval") {
		// Stop.
		t.Fatalf("status %d, type %q, policy %q", status, header.Get("Content-Type"), header.Get("Content-Security-Policy"))
	} // end of the check
	// Exactly one script: the monitor's own small file for the collapse buttons.
	if strings.Count(body, "<script") != 1 || strings.Count(body, `<script src="/helpclose.js" defer></script>`) != 1 {
		// Report.
		t.Error("the Help page must carry only the helpclose.js script")
	} // end of the script check
	// Only GET is allowed.
	if res := post(t, rig.h, "/help", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
		// Report.
		t.Errorf("POST /help = %d, want 405", res.StatusCode)
	} // end of the method check
	// The back arrow and the picture's accessible name.
	for _, want := range []string{backArrowMarkup, `role="img"`, `<title id="find-llm-svgtitle">`, "The steps in words", `<h1>Help</h1>`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the Help page lacks %q", want)
		} // end of the look
	} // end of the loop
	// The page as plain text for the comparison of the words.
	plain := html.UnescapeString(body)
	// Each step appears twice: in the picture (possibly split over lines) and in the list.
	for _, tp := range helpTopics {
		// Each step.
		for i, s := range tp.Steps {
			// In the list, whole.
			if !strings.Contains(plain, "</strong> "+s.Text+"</li>") {
				// Report.
				t.Errorf("%s step %d is not in the list", tp.ID, i+1)
			} // end of the list check
			// In the picture, line by line.
			for _, l := range wrapText(strings.Join([]string{itoa(i + 1), ". ", s.Text}, ""), helpWrap) {
				// Look for the line.
				if !strings.Contains(plain, ">"+l+"</text>") {
					// Report.
					t.Errorf("%s step %d: line %q is not in the picture", tp.ID, i+1, l)
				} // end of the line check
			} // end of the line loop
		} // end of the step loop
	} // end of the topic loop
	// One box per step and one arrow between each pair, over all topics.
	boxes, arrows := 0, 0
	// Add them up.
	for _, tp := range helpTopics {
		// A guide topic has no diagram.
		if len(tp.Steps) == 0 {
			// Nothing to add.
			continue
		} // end of the guide case
		// Steps and the arrows between them.
		boxes += len(tp.Steps)
		// One fewer arrow than steps.
		arrows += len(tp.Steps) - 1
	} // end of the sum loop
	// Compare with the page.
	if n := strings.Count(body, `class="lanebox"`); n != boxes {
		// Report.
		t.Errorf("%d boxes, want %d", n, boxes)
	} // end of the box check
	// The arrows.
	if n := strings.Count(body, `class="lanearrow"`); n != arrows {
		// Report.
		t.Errorf("%d arrows, want %d", n, arrows)
	} // end of the arrow check
	// Every lane has its name.
	for _, l := range helpLanes {
		// Look for it.
		if !strings.Contains(body, `>`+l+`</text>`) {
			// Report.
			t.Errorf("lane %q has no name in the picture", l)
		} // end of the look
	} // end of the lane loop
	// Each topic is a closed section that opens when its title is clicked, and the contents list links to it.
	for _, tp := range helpTopics {
		// The closed section (no "open" word).
		if !strings.Contains(body, `<details class="helptopic" id="`+tp.ID+`">`) || strings.Contains(body, `<details class="helptopic" id="`+tp.ID+`" open`) {
			// Report.
			t.Errorf("topic %s is not a closed section", tp.ID)
		} // end of the section check
		// The title is the clickable row.
		if !strings.Contains(body, `<summary class="helpsum"><h2 id="`+tp.ID+`-title">`) {
			// Report.
			t.Errorf("topic %s has no clickable title", tp.ID)
		} // end of the title check
		// A collapse button at the top of the open topic (before the picture) and one at the bottom (after the list).
		start := strings.Index(body, `<details class="helptopic" id="`+tp.ID+`">`)
		// The topic's own section.
		sec := body[start : start+strings.Index(body[start:], `</details>`)]
		// The arrows, the picture and the list inside it.
		top, bottom := strings.Index(sec, `id="tipclose-`+tp.ID+`-top"`), strings.Index(sec, `id="tipclose-`+tp.ID+`-bottom"`)
		// The picture and the list.
		svg, list := strings.Index(sec, `<svg class="swimlane"`), strings.Index(sec, `<ol class="helpsteps">`)
		// A guide topic has its guide in place of both.
		if len(tp.Guide) > 0 {
			// The guide stands for the picture and the list.
			svg = strings.Index(sec, `<div class="helpguide">`)
			// The same place.
			list = svg
		} // end of the guide case
		// Check the order.
		if top < 0 || bottom < 0 || !(top < svg && list < bottom) {
			// Report.
			t.Errorf("topic %s: arrows at %d and %d, picture at %d, list at %d", tp.ID, top, bottom, svg, list)
		} // end of the arrow check
	} // end of the topic loop
	// Only the page's own back arrow; the topics carry collapse buttons, which start hidden.
	if n := strings.Count(body, `aria-label="Back to the monitor"`); n != 1 {
		// Report.
		t.Errorf("%d back arrows, want 1", n)
	} // end of the arrow count
	// Two collapse buttons for every topic, each hidden until the script shows it.
	if n := strings.Count(body, `class="backcircle helpclose" hidden aria-label="Collapse this topic"`); n != 2*len(helpTopics) {
		// Report.
		t.Errorf("%d collapse buttons, want %d", n, 2*len(helpTopics))
	} // end of the collapse count
	// The old contents list is gone.
	if strings.Contains(body, `class="helptoc"`) || strings.Contains(body, "This is the first topic") {
		// Report.
		t.Error("the contents list or the old sentence is still on the page")
	} // end of the old-text check
	// The opening sentence is the short one, without the sentence about the lanes.
	if !strings.Contains(body, "Click a topic to open a diagram of what happens, step by step.</p>") || strings.Contains(body, "one lane for each") {
		// Report.
		t.Error("the opening sentence of the Help page is not the short one")
	} // end of the opening sentence check
	// The monitor links to the Help page.
	if _, _, main := get(t, rig.h, http.MethodGet, "/"); !strings.Contains(main, `<a class="brandbtn" href="/help">Help</a>`) {
		// Report.
		t.Error("the monitor has no Help button")
	} // end of the link check
} // end of TestHelpPage

// itoa writes a small number as text.
func itoa(n int) string {
	// Digits.
	s := ""
	// A zero.
	if n == 0 {
		// Zero.
		return "0"
	} // end of the zero check
	// Build from the right.
	for n > 0 {
		// The last digit in front.
		s = string(rune('0'+n%10)) + s
		// The rest.
		n /= 10
	} // end of the loop
	// The text.
	return s
} // end of itoa

// TestHelpCloseScriptIsServedAndHarmless checks the script is sent as JavaScript, only on GET, and only closes a topic: nothing is sent anywhere.
func TestHelpCloseScriptIsServedAndHarmless(t *testing.T) {
	// A rig.
	rig := newThemeRig(t)
	// Fetch the script.
	status, header, body := get(t, rig.h, http.MethodGet, "/helpclose.js")
	// Found and typed as JavaScript.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "helpclose") {
		// Report.
		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the check
	// Only GET is allowed.
	if res := post(t, rig.h, "/helpclose.js", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
		// Report.
		t.Errorf("POST /helpclose.js = %d, want 405", res.StatusCode)
	} // end of the method check
	// Nothing that sends data away, runs text as code, writes markup or opens an address.
	for _, bad := range []string{"fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "eval(", "new Function", "innerHTML", "outerHTML", "document.write", "http://", "https://", "location", "import("} {
		// Present.
		if strings.Contains(body, bad) {
			// Report.
			t.Errorf("the help script must not contain %q", bad)
		} // end of the check
	} // end of the loop
	// Every code line carries a comment on the line above it or ends a block.
	lines := strings.Split(body, "\n")
	// Check from the second line.
	for i := 1; i < len(lines); i++ {
		// The trimmed line.
		l := strings.TrimSpace(lines[i])
		// Blank lines, comments and lines that close a block need nothing.
		if l == "" || strings.HasPrefix(l, "//") || strings.HasPrefix(l, "}") {
			// Fine.
			continue
		} // end of the skip check
		// The line above must be a comment.
		if !strings.HasPrefix(strings.TrimSpace(lines[i-1]), "//") {
			// Report.
			t.Errorf("helpclose.js line %d has no comment above it: %q", i+1, l)
		} // end of the comment check
	} // end of the line loop
} // end of TestHelpCloseScriptIsServedAndHarmless

// TestHelpTopicsAreBanded checks the style sheet tints every second topic and marks the open one, with colours that exist in all three colour sets and stay readable.
func TestHelpTopicsAreBanded(t *testing.T) {
	// Get the style sheet the way a browser does.
	rig := newThemeRig(t)
	// Fetch it.
	_, _, css := get(t, rig.h, http.MethodGet, "/app.css")
	// The three rules must exist.
	for _, want := range []string{"details.helptopic:nth-of-type(even) {", "background: var(--cat-bg);", "details.helptopic[open] {", "border-left-color: var(--cat-accent);", "border-left: 6px solid transparent;"} {
		// Look for it.
		if !strings.Contains(css, want) {
			// Report.
			t.Errorf("the style sheet lacks %q", want)
		} // end of the look
	} // end of the loop
	// The band and bar colours must be set in the light set, the automatic dark set and the chosen dark set: each variable appears three times.
	for _, name := range []string{"--cat-bg:", "--cat-accent:"} {
		// Count the definitions.
		if n := strings.Count(css, name); n != 3 {
			// Report.
			t.Errorf("%s is defined %d times, want 3 (light, automatic dark, chosen dark)", name, n)
		} // end of the count
	} // end of the loop
	// The text must stay readable on the band: at least 7:1 (AAA) in both sets, using the colours the sheet defines.
	for _, th := range []struct{ name, band, text, muted string }{{"light", "#dbe7f5", "#1a1a1a", "#4a4f57"}, {"dark", "#1f3550", "#ececec", "#b8bdc5"}} {
		// The band colour must really be the one the sheet defines.
		if !strings.Contains(css, "--cat-bg: "+th.band+";") {
			// Report.
			t.Errorf("%s: the band colour %s is not defined", th.name, th.band)
		} // end of the colour check
		// The main text on the band.
		if r := contrastOf(th.text, th.band); r < 7 {
			// Report.
			t.Errorf("%s: text on the band has contrast %.1f, want at least 7", th.name, r)
		} // end of the text contrast
		// The secondary text on the band, at least 4.5:1.
		if r := contrastOf(th.muted, th.band); r < 4.5 {
			// Report.
			t.Errorf("%s: secondary text on the band has contrast %.1f, want at least 4.5", th.name, r)
		} // end of the muted contrast
	} // end of the loop
} // end of TestHelpTopicsAreBanded

// TestHelpPerformanceGuide checks the reading guide: it follows the Performance test topic, every figure is explained with an example taken from the Performance page's own help bubbles, the page opens it when a link asks for it, and the Performance and Compare pages link to it.
func TestHelpPerformanceGuide(t *testing.T) {
	// Find the guide and the topic before it.
	idx := -1
	// Look through the topics.
	for i, tp := range helpTopics {
		// The guide.
		if tp.ID == helpPerfGuideID {
			// Found.
			idx = i
		} // end of the match
	} // end of the search
	// It must exist and come right after the Performance test topic.
	if idx < 1 || helpTopics[idx-1].ID != "performance-test" || len(helpTopics[idx].Steps) != 0 || len(helpTopics[idx].Guide) == 0 {
		// Stop.
		t.Fatalf("the guide is missing, misplaced or not a guide (index %d)", idx)
	} // end of the place check
	// The filled guide.
	parts := fillGuide(helpTopics[idx].Guide)
	// Count the figures.
	rows := 0
	// Each part and row.
	for _, part := range parts {
		// A heading and a paragraph.
		if part.Heading == "" || part.Text == "" {
			// Report.
			t.Errorf("a part lacks its heading or text: %+v", part)
		} // end of the part check
		// Each row.
		for _, r := range part.Rows {
			// One more.
			rows++
			// Every column is filled.
			if r.Figure == "" || r.Means == "" || r.Better == "" || r.Example == "" {
				// Report.
				t.Errorf("figure %q has an empty column", r.Figure)
			} // end of the column check
			// A figure with a help bubble says exactly what the bubble says.
			if tip, ok := helpFor(r.Figure); ok && (r.Means != tip.Plain || r.Example != tip.Example) {
				// Report.
				t.Errorf("figure %q differs from its help bubble", r.Figure)
			} // end of the bubble check
		} // end of the row loop
	} // end of the part loop
	// Every main figure of the Performance page is in the guide.
	for _, want := range []string{"Answer speed", "Prompt reading speed", "Time to first word", "Total time", "Load time", "Processor split", "Memory used", "Embedding time", "Vector length", "Tokens counted", "Change since the previous run", "Other models loaded", "CPU load", "Swap in use", "GPU"} {
		// Look for it.
		found := false
		// Each part and row.
		for _, part := range parts {
			// Each row.
			for _, r := range part.Rows {
				// A match.
				if r.Figure == want {
					// Found.
					found = true
				} // end of the match
			} // end of the row loop
		} // end of the part loop
		// It must be there.
		if !found {
			// Report.
			t.Errorf("the guide does not explain %q", want)
		} // end of the found check
	} // end of the figure loop
	// The page.
	rig := newThemeRig(t)
	// Without a request, every topic is closed and the guide is drawn as tables.
	_, _, body := get(t, rig.h, http.MethodGet, "/help")
	// No open topic, and one table row per figure.
	if strings.Contains(body, `" open>`) || strings.Count(body, `<td data-label="What it tells you">`) != rows {
		// Report.
		t.Errorf("closed page: open topic found or %d figure rows, want %d", strings.Count(body, `<td data-label="What it tells you">`), rows)
	} // end of the closed check
	// Asked for the guide: only the guide is open.
	_, _, body = get(t, rig.h, http.MethodGet, "/help?topic="+helpPerfGuideID)
	// Exactly one open topic, and it is the guide.
	if strings.Count(body, `" open>`) != 1 || !strings.Contains(body, `<details class="helptopic" id="`+helpPerfGuideID+`" open>`) {
		// Report.
		t.Error("the guide is not the one open topic when asked for")
	} // end of the open check
	// An unknown name opens nothing and is not written into the page.
	_, _, body = get(t, rig.h, http.MethodGet, "/help?topic=%3Cb%3Enope")
	// Nothing open, nothing echoed.
	if strings.Contains(body, `" open>`) || strings.Contains(body, "nope") {
		// Report.
		t.Error("an unknown topic name opened a topic or was echoed")
	} // end of the unknown check
	// The link that the Performance and Compare pages carry.
	link := `href="/help?topic=` + helpPerfGuideID + `#` + helpPerfGuideID + `">How to read these results</a>`
	// Both templates carry it.
	for name, text := range map[string]string{"performance": performanceTemplateText, "compare": compareTemplateText} {
		// Look for it.
		if !strings.Contains(text, link) {
			// Report.
			t.Errorf("the %s page has no link to the guide", name)
		} // end of the link check
	} // end of the template loop
} // end of TestHelpPerformanceGuide
