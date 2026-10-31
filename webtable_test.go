// Package main tells Go that this test file belongs to the same program as web.go and tableview.go.
package main

import ( // import lists the packages this test file uses.
	// html turns plain text into the escaped form the page contains.
	"html"
	// net/http provides status codes.
	"net/http"
	// net/http/httptest provides the fake Ollama server type.
	"net/http/httptest"
	// regexp finds the element names in the page.
	"regexp"
	// strings searches and counts text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// fullOllama starts a fake Ollama that answers the version check, the installed list and the loaded list.
func fullOllama(t *testing.T, rows []realRow, psBody string) *httptest.Server {
	// Mark this as a helper.
	t.Helper()
	// Build the handler for the installed list once.
	tags := tagsHandler(t, rows)
	// Build the handler for the loaded list once.
	ps := psHandler(psBody)
	// Start the server with a small router.
	return fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
		// Pick the reply by path.
		switch r.URL.Path {
		// The version check.
		case "/api/version":
			// Send a valid version.
			w.Write([]byte(`{"version":"0.34.4"}`))
		// The installed list.
		case "/api/tags":
			// Let the tags handler answer.
			tags(w, r)
		// The loaded list.
		case "/api/ps":
			// Let the ps handler answer.
			ps(w, r)
		// Anything else.
		default:
			// A real Ollama would not know the path either.
			http.NotFound(w, r)
		} // end of the switch
	}) // end of the server
} // end of fullOllama

// pageFor fetches the page from a handler that watches the given fake Ollama.
func pageFor(t *testing.T, srv *httptest.Server) string {
	// Mark this as a helper.
	t.Helper()
	// Ask the page.
	status, _, body := get(t, handlerFor(t, srv.URL), http.MethodGet, "/")
	// The page must always load.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status = %d, want 200", status)
	} // end of the status check
	// Hand back the page text.
	return body
} // end of pageFor

// TestTablePageRealModels checks the table with the six real models.
func TestTablePageRealModels(t *testing.T) {
	// Fake Ollama with the six real models and medgemma:latest loaded.
	body := pageFor(t, fullOllama(t, realModels, realPsBody))
	// Pieces that must appear.
	for _, want := range []string{
		// The panel heading with the count.
		"Installed models (6)",
		// The two non-empty categories with their counts.
		"Search and similarity (embedding)", "(2 models)", "Chat with images or audio (multimodal)", "(4 models)",
		// Formatted cells from the real data.
		"17.4 GB", "2026-10-24 17:40 UTC", "262144", "27.4B", "Q4_K_M",
	} { // end of the list
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// Every model name must appear.
	for _, r := range realModels {
		// Look for the name (html.EscapeString matches how the template writes it).
		if !strings.Contains(body, html.EscapeString(r.name)) {
			// Report the gap.
			t.Errorf("page does not contain model %q", r.name)
		} // end of the name check
	} // end of the model loop
	// The empty categories must be hidden.
	for _, hidden := range []string{"Chat and writing (text only)", "Not yet classified"} {
		// They must not appear anywhere, bubbles included.
		if strings.Contains(body, hidden) {
			// Report the problem.
			t.Errorf("empty category %q is shown", hidden)
		} // end of the hidden check
	} // end of the hidden loop
	// Exactly one model is loaded and five are not; only the state labels in the table are counted, because the help bubbles mention the same words.
	if n := strings.Count(body, `<span class="statelabel"><span class="dot dot-on" aria-hidden="true"></span> Loaded</span>
`); n != 1 {
		// Report the difference.
		t.Errorf("loaded cells = %d, want 1", n)
	} // end of the loaded count
	// Five models are not loaded.
	if n := strings.Count(body, `<span class="statelabel"><span class="dot dot-off" aria-hidden="true"></span> Not loaded</span>
`); n != 5 {
		// Report the difference.
		t.Errorf("not-loaded cells = %d, want 5", n)
	} // end of the not-loaded count
	// Order: the embedding group comes first, and inside it hf.co comes before rjmalagon.
	i1 := strings.Index(body, "<strong>Search and similarity (embedding)</strong>")
	// The multimodal heading position.
	i2 := strings.Index(body, "<strong>Chat with images or audio (multimodal)</strong>")
	// The first embedding model, found as a table row (the help bubbles also mention model names).
	i3 := strings.Index(body, `<tr data-model="hf.co/NeoRoth`)
	// The second embedding model, found the same way.
	i4 := strings.Index(body, `<tr data-model="rjmalagon/gte-qwen2`)
	// All four positions must be in this order.
	if !(i1 < i3 && i3 < i4 && i4 < i2) {
		// Report the order found.
		t.Errorf("unexpected order: %d %d %d %d", i1, i3, i4, i2)
	} // end of the order check
	// The unreliable parent_model values must never be shown.
	if strings.Contains(body, "/root/.ollama") || strings.Contains(body, "qwen3.6-source") {
		// Report the leak.
		t.Errorf("parent_model text reached the page")
	} // end of the parent check
} // end of TestTablePageRealModels

// TestTableHelpForEveryHeading checks every heading has its bubble, wired with aria-describedby.
func TestTableHelpForEveryHeading(t *testing.T) {
	// Fake Ollama with the six real models.
	body := pageFor(t, fullOllama(t, realModels, realPsBody))
	// Ten column bubbles, two category bubbles and the bubbles of the API health and Event log headings; the short tips of the row icons are counted apart.
	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 14 {
		// Report the difference.
		t.Errorf("%d bubbles, want 14", n)
	} // end of the bubble count
	// Every column title must be a focusable heading.
	for _, col := range installedColumns {
		// The heading element holds the title text.
		if !strings.Contains(body, ">"+drawnHeading(col)+"</span>") {
			// Report the gap.
			t.Errorf("no heading element for column %q", col)
		} // end of the heading check
		// Its help text must be in the page, written the way the template escapes it.
		if tip, ok := helpFor(col); !ok || !strings.Contains(body, html.EscapeString(tip.Plain)) {
			// Report the gap.
			t.Errorf("help text for %q is missing from the page", col)
		} // end of the text check
	} // end of the column loop
	// Find every aria-describedby value.
	refs := regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1)
	// There must be one per bubble (the row icons have their own, counted apart).
	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 14 {
		// Report the difference.
		t.Errorf("%d aria-describedby attributes, want 14", n)
	} // end of the reference count
	// Each one must point at an element that exists.
	for _, m := range refs {
		// Look for the target.
		if !strings.Contains(body, `id="`+m[1]+`"`) {
			// Report the dangling reference.
			t.Errorf("aria-describedby=%q points at nothing", m[1])
		} // end of the target check
	} // end of the reference loop
} // end of TestTableHelpForEveryHeading

// TestTableAccessibility checks the structure that keyboard and screen-reader users rely on.
func TestTableAccessibility(t *testing.T) {
	// Fake Ollama with the six real models.
	body := pageFor(t, fullOllama(t, realModels, realPsBody))
	// What to count: the text and the number expected.
	for _, c := range []struct {
		// text is what to count.
		text string
		// want is the expected number.
		want int
	}{ // the cases follow
		// Ten column headings of the models table and two of the event log.
		{`scope="col"`, 12},
		// One row heading per model.
		{`scope="row"`, 6},
		// One group heading per non-empty category.
		{`scope="colgroup"`, 2},
		// The scroll box is a labelled region that the keyboard can reach.
		{`role="region"`, 2},
		// Fourteen headings (ten columns, two categories, API health and Event log) plus the two scroll boxes (models and event log) can take the focus.
		{`tabindex="0"`, 16},
	} { // end of the list
		// Count it.
		if n := strings.Count(body, c.text); n != c.want {
			// Report the difference.
			t.Errorf("%s appears %d times, want %d", c.text, n, c.want)
		} // end of the count check
	} // end of the loop
	// The hover-only title attribute must not be used for help.
	if strings.Contains(body, " title=") {
		// Report the problem.
		t.Errorf("a title attribute is used; help must work from the keyboard")
	} // end of the title check
} // end of TestTableAccessibility

// TestTableEscapesHostileModelNames checks that markup in a model name or ability is shown as text.
func TestTableEscapesHostileModelNames(t *testing.T) {
	// One hostile model: a name and an ability that look like markup.
	rows := []realRow{{"<img src=x onerror=alert(1)>", 1000, "2026-01-02T03:04:05Z", []string{"completion", "<b>x</b>"}, "<i>f</i>", "1B", "Q4", 10, 10, ""}}
	// Ask the page.
	body := pageFor(t, fullOllama(t, rows, `{"models":[]}`))
	// No raw markup may appear.
	for _, bad := range []string{"<img src=x", "<b>x</b>", "<i>f</i>"} {
		// Look for it.
		if strings.Contains(body, bad) {
			// Report the problem.
			t.Errorf("raw markup %q reached the page", bad)
		} // end of the check
	} // end of the loop
	// The escaped text must appear instead.
	if !strings.Contains(body, "&lt;img src=x onerror=alert(1)&gt;") {
		// Report the problem.
		t.Errorf("the hostile name was not shown as text")
	} // end of the escaped check
} // end of TestTableEscapesHostileModelNames

// TestTableNoModels checks the note for an Ollama with nothing installed.
func TestTableNoModels(t *testing.T) {
	// Fake Ollama with an empty list.
	body := pageFor(t, fullOllama(t, nil, `{"models":[]}`))
	// The note must appear and no table may be drawn.
	if !strings.Contains(body, "No models are installed.") || strings.Contains(body, `<table class="models"`) {
		// Report the problem.
		t.Errorf("unexpected page for an empty list")
	} // end of the check
} // end of TestTableNoModels

// TestTableListError checks the message when Ollama answers the version check but not the lists.
func TestTableListError(t *testing.T) {
	// Fake Ollama whose lists fail with status 500.
	srv := fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
		// The version check works.
		if r.URL.Path == "/api/version" {
			// Send a valid version.
			w.Write([]byte(`{"version":"0.34.4"}`))
			// Stop here.
			return
		} // end of the version case
		// Everything else fails.
		w.WriteHeader(http.StatusInternalServerError)
	}) // end of the server
	// Ask the page.
	body := pageFor(t, srv)
	// The message, the symbol and the status number must appear, and no table.
	for _, want := range []string{"Could not read the model lists", "✖", "status 500"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// No table may be drawn.
	if strings.Contains(body, `<table class="models"`) {
		// Report the problem.
		t.Errorf("a table was drawn although the lists failed")
	} // end of the table check
} // end of TestTableListError

// TestTableWhenOffline checks that an offline Ollama gives a note and no table.
func TestTableWhenOffline(t *testing.T) {
	// Ask the page with nothing listening.
	_, _, body := get(t, handlerFor(t, "http://"+closedAddress(t)), http.MethodGet, "/")
	// The note must appear and no table may be drawn.
	if !strings.Contains(body, "The model tables appear when Ollama answers.") || strings.Contains(body, `<table class="models"`) {
		// Report the problem.
		t.Errorf("unexpected page while offline")
	} // end of the check
} // end of TestTableWhenOffline

// TestStylesheetHasTableAndBubbleRules checks the rules the table and the bubbles depend on.
func TestStylesheetHasTableAndBubbleRules(t *testing.T) {
	// The stylesheet text is embedded in the program.
	css := string(appCSS)
	// Each of these rules protects one behaviour.
	for name, want := range map[string]string{
		// The table scrolls sideways inside its own box.
		"sideways scrolling": "overflow-x: auto",
		// The first column stays visible.
		"sticky name column": "position: sticky",
		// The bubble opens on pointer hover.
		"bubble on hover": ".tipbox:hover > .tip",
		// The bubble opens on keyboard focus.
		"bubble on focus": ".tipbox:focus-within > .tip",
		// The bubble cannot be cut off by the scroll box.
		"bubble fixed to the window": "position: fixed",
		// Headings with help carry a dotted underline.
		"dotted cue": "underline dotted",
		// Category rows are drawn as a coloured band.
		"category band colour": "background: var(--cat-bg)",
		// The band has an accent bar, so it does not rely on colour alone.
		"category accent bar": "border-left: 6px solid var(--cat-accent)",
		// The dark theme redefines the band colours.
		"dark band colour": "--cat-bg: #1f3550",
		// The loaded dot is green.
		"loaded dot colour": "background: var(--dot-on)",
		// The dot is round.
		"round dot": "border-radius: 50%",
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestStylesheetHasTableAndBubbleRules

// drawnHeading is a column title the way the page draws it: the lines joined by a line break, each escaped.
func drawnHeading(col string) string {
	// Escape each line, then join them with a break.
	var parts []string
	// Go through the lines.
	for _, l := range headingLines(col) {
		// Escape it.
		parts = append(parts, html.EscapeString(l))
	} // end of the loop
	// Join.
	return strings.Join(parts, "<br>")
} // end of drawnHeading

// TestLongHeadingsUseTwoLines checks the three long headings are drawn on two lines, the others on one, and that the help text of the page no longer carries the label "In plain words".
func TestLongHeadingsUseTwoLines(t *testing.T) {
	// Fake Ollama with the six real models.
	body := pageFor(t, fullOllama(t, realModels, realPsBody))
	// The three two-line headings.
	for _, want := range []string{">Size<br>on disk</span>", ">Max context<br>length</span>", ">Embedding<br>length</span>"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The short headings stay on one line.
	for _, want := range []string{">Model</span>", ">Family</span>", ">Parameters</span>", ">Quantization</span>", ">Last modified</span>", ">Abilities</span>"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The label is gone from every bubble, and the other two labels stay.
	if strings.Contains(body, "In plain words") || !strings.Contains(body, "<strong>Example:</strong>") || !strings.Contains(body, "<strong>Helps you decide:</strong>") {
		// Report the problem.
		t.Errorf("the bubble labels are wrong")
	} // end of the label check
} // end of TestLongHeadingsUseTwoLines

// TestTableColumnOrder checks the headings appear on the page in the order the person asked for.
func TestTableColumnOrder(t *testing.T) {
	// Fake Ollama with the six real models.
	body := pageFor(t, fullOllama(t, realModels, realPsBody))
	// The wanted order.
	want := []string{"Model", "State", "Size on disk", "Family", "Parameters", "Quantization", "Max context length", "Embedding length", "Last modified", "Abilities"}
	// Start looking from the table head.
	pos := strings.Index(body, "<thead>")
	// Go through the titles in order.
	for _, col := range want {
		// Find the heading element after the previous one.
		i := strings.Index(body[pos:], ">"+drawnHeading(col)+"</span>")
		// A missing or early heading means the order is wrong.
		if i < 0 {
			// Report the problem.
			t.Fatalf("heading %q is missing or out of order", col)
		} // end of the find check
		// Continue after this heading.
		pos += i + len(col)
	} // end of the title loop
} // end of TestTableColumnOrder
