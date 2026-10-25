#!/usr/bin/env bash
# Script 19: Step 5c, shows the Installed models table on the page (web/index.html, web/app.css, web.go, tableview.go and three test files), tests, builds and checks the page against the real Ollama.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with script 05 on 18765.
TEST_PORT="${TEST_PORT:-18766}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write index.html page template; the quoted EOF_HTML marker saves every character exactly as typed.
cat > web/index.html << 'EOF_HTML'
{{/* Page template: the comments in this file are template comments, so they never reach the browser. */}}
<!DOCTYPE html>
{{/* lang tells screen readers which language the page is written in. */}}
<html lang="en">
<head>{{/* start of the head. */}}
{{/* Use UTF-8 so the symbols in the status line display correctly. */}}
<meta charset="utf-8">
{{/* Make the page scale to the screen width on phones and small windows. */}}
<meta name="viewport" content="width=device-width, initial-scale=1">
{{/* Tell the browser the page supports both light and dark colours. */}}
<meta name="color-scheme" content="light dark">
{{/* The product name is the page title. */}}
<title>OllamaControlCenter</title>
{{/* Load our own stylesheet; the safety policy allows only styles from this same address. */}}
<link rel="stylesheet" href="/app.css">
</head>{{/* end of the head. */}}
<body>{{/* start of the visible page. */}}
{{/* The page header. */}}
<header>
{{/* The main heading. */}}
<h1>OllamaControlCenter</h1>
{{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}
<p class="muted">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>
</header>{{/* end of the header. */}}
{{/* The main content area. */}}
<main>
{{/* The status panel; aria-live asks screen readers to announce changes. */}}
<section class="panel" aria-labelledby="status-title" aria-live="polite">
{{/* The panel heading. */}}
<h2 id="status-title">Ollama status</h2>
{{/* Online: a tick, the word Online, the version and the reply time. */}}
{{if .Online}}
{{/* The class ok colours the line, but the tick and the word carry the meaning. */}}
<p class="status ok"><span class="symbol" aria-hidden="true">✔</span> <strong>Online</strong> <span class="muted">version {{.Version}}, answered in {{.ElapsedMs}} ms</span></p>
{{/* Offline: a cross, the word Offline and the plain reason. */}}
{{else}}
{{/* The class bad colours the line, but the cross and the word carry the meaning. */}}
<p class="status bad"><span class="symbol" aria-hidden="true">✖</span> <strong>Offline</strong> <span class="muted">{{.Reason}} ({{.ElapsedMs}} ms)</span></p>
{{/* End of the online check. */}}
{{end}}
{{/* End of the status panel. */}}
</section>
{{/* The Installed models panel. */}}
<section class="panel" aria-labelledby="installed-title">
{{/* The panel heading, with the number of models when known. */}}
<h2 id="installed-title">Installed models{{if .HasTable}} ({{.Table.Total}}){{end}}</h2>
{{/* Case 1: Ollama answered but the lists could not be read; say why in plain words. */}}
{{if .TableError}}
{{/* The cross and the word carry the meaning, the colour only supports it. */}}
<p class="status bad"><span class="symbol" aria-hidden="true">✖</span> <strong>Could not read the model lists</strong> <span class="muted">{{.TableError}}</span></p>
{{/* Case 2: no table because Ollama did not answer; the status panel above has the reason. */}}
{{else if not .HasTable}}
{{/* A plain note. */}}
<p class="muted">The model tables appear when Ollama answers.</p>
{{/* Case 3: Ollama answered and has no models. */}}
{{else if not .Table.Groups}}
{{/* A plain note. */}}
<p class="muted">No models are installed.</p>
{{/* Case 4: the table itself. */}}
{{else}}
{{/* A hint above the table so people know the dotted headings have help. */}}
<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The table scrolls sideways.</p>
{{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
<div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
{{/* The table. */}}
<table class="models">
{{/* The header row. */}}
<thead>
<tr>{{/* start of a table row. */}}
{{/* One heading cell per column; $i is the column number. */}}
{{range $i, $c := .Table.Columns}}
{{/* The first column stays visible while the table scrolls sideways. */}}
<th scope="col"{{if eq $i 0}} class="stickycol"{{end}}>
{{/* The area that opens the bubble when the pointer is over it or the focus is inside it. */}}
<div class="tipbox">
{{/* The heading text; tabindex 0 lets the keyboard reach it, aria-describedby ties it to its bubble. */}}
<span class="help" tabindex="0" aria-describedby="{{$c.Tip.ID}}">{{$c.Title}}</span>
{{/* The bubble; it is fixed to the window, so the scroll box never cuts it off. */}}
<span class="tip" role="tooltip" id="{{$c.Tip.ID}}">{{template "tip" $c.Tip}}</span>
{{/* End of the bubble area. */}}
</div>
{{/* End of the heading cell. */}}
</th>
{{/* End of the column loop. */}}
{{end}}
{{/* End of the header row. */}}
</tr>
{{/* End of the table head. */}}
</thead>
{{/* The table body. */}}
<tbody>
{{/* One section per category. */}}
{{range $gi, $g := .Table.Groups}}
{{/* The category heading row: one cell across all columns. */}}
<tr class="grouprow">
{{/* The cell spans every column. */}}
<th scope="colgroup" colspan="10">
{{/* The bubble area stays at the left edge while the table scrolls. */}}
<div class="tipbox catbox">
{{/* The category name, reachable by keyboard. */}}
<span class="help" tabindex="0" aria-describedby="{{$g.Tip.ID}}"><strong>{{$g.Heading}}</strong></span>
{{/* The number of models in this category. */}}
<span class="muted">({{$g.CountText}})</span>
{{/* The category's bubble. */}}
<span class="tip" role="tooltip" id="{{$g.Tip.ID}}">{{template "tip" $g.Tip}}</span>
{{/* End of the bubble area. */}}
</div>
{{/* End of the heading cell. */}}
</th>
{{/* End of the category heading row. */}}
</tr>
{{/* One row per model in this category. */}}
{{range $g.Rows}}
{{/* A model row. */}}
<tr>{{/* start of a table row. */}}
{{/* The model name is the row heading and stays visible while scrolling. */}}
<th scope="row" class="stickycol">{{.Name}}</th>
{{/* The other nine cells. */}}
{{range .Cells}}
{{/* One cell. */}}
<td>{{.}}</td>
{{/* End of the cells. */}}
{{end}}
{{/* End of the model row. */}}
</tr>
{{/* End of the model loop. */}}
{{end}}
{{/* End of the category loop. */}}
{{end}}
{{/* End of the table body. */}}
</tbody>
{{/* End of the table. */}}
</table>
{{/* End of the scroll box. */}}
</div>
{{/* End of the four cases. */}}
{{end}}
{{/* End of the Installed models panel. */}}
</section>
{{/* End of the main content. */}}
</main>
</body>{{/* end of the visible page. */}}
</html>{{/* end of the page. */}}
{{/* The help bubble content: three labelled parts, and the task names when there are any. */}}
{{define "tip"}}
{{/* What the heading means. */}}
<span class="tip-part"><strong>In plain words:</strong> {{.Plain}}</span>
{{/* A real example. */}}
<span class="tip-part"><strong>Example:</strong> {{.Example}}</span>
{{/* What it helps you decide. */}}
<span class="tip-part"><strong>Helps you decide:</strong> {{.Decide}}</span>
{{/* Task names, only for categories. */}}
{{if .AlsoKnown}}
{{/* The common names. */}}
<span class="tip-part"><strong>Also known as:</strong> {{.AlsoKnown}}</span>
{{/* End of the task-name check. */}}
{{end}}
{{/* End of the bubble content. */}}
{{end}}
EOF_HTML

# Write app.css stylesheet; the quoted EOF_CSS marker saves every character exactly as typed.
cat > web/app.css << 'EOF_CSS'
/* Colours are defined once as variables; the light set is the default. */
:root {
  /* Page background. */
  --bg: #ffffff;
  /* Panel background, slightly different from the page. */
  --panel: #f4f6f8;
  /* Main text colour (contrast 17:1 on the page background). */
  --text: #1a1a1a;
  /* Secondary text colour (contrast 8:1). */
  --muted: #4a4f57;
  /* Colour for the online line (contrast 6.6:1). */
  --ok: #0b6b2f;
  /* Colour for the offline line (contrast 7.7:1). */
  --bad: #a4161a;
  /* Border colour (contrast 3.2:1 against the page, enough for outlines). */
  --border: #8a9099;
  /* Tell the browser to draw its own controls in light colours. */
  color-scheme: light;
} /* end of rule */

/* When the computer is set to a dark theme, replace the colours; the layout stays the same. */
@media (prefers-color-scheme: dark) {
  /* The dark set of colours. */
  :root {
    /* Page background. */
    --bg: #121417;
    /* Panel background. */
    --panel: #1b1f24;
    /* Main text colour (contrast 15.6:1). */
    --text: #ececec;
    /* Secondary text colour (contrast 9.8:1). */
    --muted: #b8bdc5;
    /* Colour for the online line (contrast 10.9:1). */
    --ok: #6fdc97;
    /* Colour for the offline line (contrast 9.1:1). */
    --bad: #ff9a9a;
    /* Border colour (contrast 3.8:1). */
    --border: #6b727c;
    /* Tell the browser to draw its own controls in dark colours. */
    color-scheme: dark;
  } /* end of rule */
} /* end of rule */

/* Page-wide basics: the system font, our colours, and comfortable line spacing. */
body {
  /* Use the font the operating system already has, so nothing is downloaded. */
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  /* Page background from the variables. */
  background: var(--bg);
  /* Text colour from the variables. */
  color: var(--text);
  /* Space lines out for readability. */
  line-height: 1.5;
  /* Keep the content away from the window edges. */
  margin: 0 auto;
  /* Limit the line length on very wide screens. */
  max-width: 80rem;
  /* Padding that also gives a 16px side gutter on phones. */
  padding: 1rem;
} /* end of rule */

/* The main heading. */
h1 {
  /* A little smaller than the browser default. */
  font-size: 1.6rem;
  /* Tighten the space below. */
  margin: 0 0 0.25rem;
} /* end of rule */

/* Section headings. */
h2 {
  /* Smaller than the page heading. */
  font-size: 1.15rem;
  /* Tighten the space above and below. */
  margin: 0 0 0.5rem;
} /* end of rule */

/* Secondary text such as the address line. */
.muted {
  /* Use the secondary colour. */
  color: var(--muted);
} /* end of rule */

/* A boxed area with a visible outline, so it is clear without colour. */
.panel {
  /* Panel background from the variables. */
  background: var(--panel);
  /* A solid outline, which keeps the box visible for people who cannot tell colours apart. */
  border: 2px solid var(--border);
  /* Slightly rounded corners. */
  border-radius: 0.5rem;
  /* Space inside the box. */
  padding: 0.75rem 1rem;
  /* Space between boxes. */
  margin: 1rem 0;
} /* end of rule */

/* The status line. */
.status {
  /* Larger than normal text so it is the first thing seen. */
  font-size: 1.2rem;
  /* No extra space around the paragraph. */
  margin: 0;
} /* end of rule */

/* The online line colour; the tick and the word say it too. */
.status.ok {
  /* Colour from the variables. */
  color: var(--ok);
} /* end of rule */

/* The offline line colour; the cross and the word say it too. */
.status.bad {
  /* Colour from the variables. */
  color: var(--bad);
} /* end of rule */

/* The status symbol. */
.symbol {
  /* Make the symbol bold so it stands out. */
  font-weight: 700;
} /* end of rule */

/* The explanation text next to the status keeps the secondary colour and normal size. */
.status .muted {
  /* Back to normal size. */
  font-size: 1rem;
} /* end of rule */

/* Show a clear outline on anything reached with the keyboard. */
:focus-visible {
  /* A thick outline in the text colour. */
  outline: 3px solid var(--text);
  /* Space between the element and its outline. */
  outline-offset: 2px;
} /* end of rule */

/* The scroll box around the table: it scrolls sideways when the table is wider than the window. */
.scrollbox {
  /* Scroll sideways when needed. */
  overflow-x: auto;
  /* The same solid outline as the other boxes. */
  border: 2px solid var(--border);
  /* Slightly rounded corners. */
  border-radius: 0.5rem;
  /* Page colour behind the table, so rows stand out from the panel. */
  background: var(--bg);
  /* No extra room is needed: bubbles are fixed to the window and are never cut off by the box. */
  padding-bottom: 0;
} /* end of rule */

/* The table itself. */
.models {
  /* Cells share borders instead of doubling them. */
  border-collapse: collapse;
  /* Keep each row on one line, so the table scrolls sideways instead of squeezing. */
  white-space: nowrap;
  /* At least as wide as the box. */
  min-width: 100%;
} /* end of rule */

/* Every cell and heading. */
.models th,
.models td { /* ...and every data cell. */
  /* Space inside the cell. */
  padding: 0.4rem 0.75rem;
  /* A thin line under every row so rows are easy to follow without colour. */
  border-bottom: 1px solid var(--border);
  /* Text starts at the left edge of the cell. */
  text-align: left;
  /* Align to the top when a cell is taller than its neighbours. */
  vertical-align: top;
} /* end of rule */

/* The column headings. */
.models thead th {
  /* Panel colour so the heading row differs from the rows. */
  background: var(--panel);
  /* A heavier line under the heading row. */
  border-bottom: 2px solid var(--border);
} /* end of rule */

/* The first column stays visible while the table scrolls sideways. */
.stickycol {
  /* Stick to the left edge of the scroll box. */
  position: sticky;
  /* Zero distance from the left edge. */
  left: 0;
  /* Solid colour so scrolled cells do not show through. */
  background: var(--bg);
  /* A line on the right so the edge is visible without colour. */
  border-right: 2px solid var(--border);
  /* Above the cells that scroll underneath. */
  z-index: 2;
} /* end of rule */

/* The corner cell (first heading) gets the heading colour and sits above everything else. */
.models thead .stickycol {
  /* Heading colour. */
  background: var(--panel);
  /* Above the sticky cells below it. */
  z-index: 4;
} /* end of rule */

/* The category heading rows. */
.grouprow th {
  /* A slightly different background so sections are clear. */
  background: var(--panel);
  /* Normal weight; the name inside is bold. */
  font-weight: 400;
  /* A heavier line above each section. */
  border-top: 2px solid var(--border);
} /* end of rule */

/* The area around a heading that opens its bubble. */
.tipbox {
  /* The bubble is placed relative to this box. */
  position: relative;
  /* Only as wide as its content, so the pointer must be on the heading. */
  display: inline-block;
} /* end of rule */

/* The category heading box stays at the left edge while the table scrolls sideways. */
.catbox {
  /* Stick to the left edge of the scroll box. */
  position: sticky;
  /* Zero distance from the left edge. */
  left: 0.75rem;
  /* Above scrolling cells. */
  z-index: 3;
} /* end of rule */

/* A heading that has help: a dotted underline is the cue. */
.help {
  /* A dotted line under the text. */
  text-decoration: underline dotted;
  /* Keep the line a little away from the letters. */
  text-underline-offset: 0.25em;
  /* A help cursor when the pointer is over it. */
  cursor: help;
} /* end of rule */

/* The bubble: hidden until the heading is pointed at or focused. */
.tip {
  /* Not shown by default; a screen reader can still read it through aria-describedby. */
  display: none;
  /* Fixed to the window, so the scroll box can never cut the bubble off; with no top value it stays right under its heading. */
  position: fixed;
  /* Centre the bubble across the window: start at the middle... */
  left: 50%;
  /* ...and move back by half of its own width. */
  transform: translateX(-50%);
  /* A comfortable reading width that still fits small windows. */
  width: min(26rem, 92vw);
  /* Wrap long text, even though the table does not wrap. */
  white-space: normal;
  /* Same colours as panels, so both themes work. */
  background: var(--panel);
  /* Text colour from the variables. */
  color: var(--text);
  /* A solid outline, visible without colour. */
  border: 2px solid var(--border);
  /* Slightly rounded corners. */
  border-radius: 0.5rem;
  /* Space inside the bubble. */
  padding: 0.6rem 0.8rem;
  /* Normal weight, even inside a heading. */
  font-weight: 400;
  /* A little smaller than body text. */
  font-size: 0.9rem;
  /* Text starts at the left, even inside a centred cell. */
  text-align: left;
  /* Above every cell, including the sticky ones. */
  z-index: 10;
} /* end of rule */

/* Show the bubble when the pointer is over the area or when the keyboard focus is inside it. */
.tipbox:hover > .tip,
.tipbox:focus-within > .tip { /* ...or when the focus is inside it. */
  /* Show it as a block. */
  display: block;
} /* end of rule */

/* Each part of the bubble on its own line. */
.tip-part {
  /* One part per line. */
  display: block;
  /* A little room between parts. */
  margin: 0.15rem 0;
} /* end of rule */
EOF_CSS

# Write web.go; the quoted EOF_WEB marker saves every character exactly as typed.
cat > web.go << 'EOF_WEB'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes provides a buffer so the page is built completely before anything is sent.
	"bytes"
	// embed lets files be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// html/template builds HTML and escapes every inserted value, so untrusted text cannot become markup.
	"html/template"
	// log prints messages to the terminal.
	"log"
	// net/http is Go's built-in web server.
	"net/http"
	// time provides durations.
	"time"
) // end of imports

// indexTemplateText is the page template, stored inside the executable at build time (requirements T3 and T4).
//
//go:embed web/index.html
var indexTemplateText string

// appCSS is the stylesheet, stored inside the executable at build time.
//
//go:embed web/app.css
var appCSS []byte

// contentSecurityPolicy tells the browser what the page may load: only our own stylesheet, no scripts, no frames, no forms.
const contentSecurityPolicy = "default-src 'none'; style-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

// pageData is everything the page template can show.
type pageData struct {
	// Address is the Ollama address with any password hidden.
	Address string
	// AddressSource names the layer that supplied the address.
	AddressSource string
	// Online is true when Ollama answered with a valid version.
	Online bool
	// Version is the Ollama version text.
	Version string
	// ElapsedMs is how long the check took, in milliseconds.
	ElapsedMs int64
	// Reason explains why Ollama is offline.
	Reason string
	// HasTable is true when the model lists were read and the table can be drawn.
	HasTable bool
	// Table is the Installed table, filled only when HasTable is true.
	Table tableView
	// TableError explains why the lists could not be read, when Ollama answered the version check but not the lists.
	TableError string
} // end of pageData

// secureHeaders wraps a handler so every reply, including errors, carries the same safety headers.
func secureHeaders(next http.Handler) http.Handler {
	// Return a handler that sets the headers and then calls the wrapped one.
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Limit what the page may load.
		w.Header().Set("Content-Security-Policy", contentSecurityPolicy)
		// Stop the browser from guessing a different content type.
		w.Header().Set("X-Content-Type-Options", "nosniff")
		// Forbid showing the page inside a frame (older browsers read this header).
		w.Header().Set("X-Frame-Options", "DENY")
		// Never send the page address to other sites.
		w.Header().Set("Referrer-Policy", "no-referrer")
		// A status page must never come from a cache.
		w.Header().Set("Cache-Control", "no-store")
		// Hand the request on.
		next.ServeHTTP(w, r)
	}) // end of the wrapper
} // end of secureHeaders

// newWebHandler builds the whole web interface: the page at "/" and the stylesheet at "/app.css".
func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
	page := template.Must(template.New("index").Parse(indexTemplateText))
	// Create a router for the two routes.
	mux := http.NewServeMux()
	// Route: a GET request for exactly "/" shows the page; other paths get 404 and other methods get 405 from the router.
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		// Ask Ollama once; the request's own context cancels the check if the browser goes away.
		res := checkOllama(r.Context(), addr.URL, timeout)
		// Fill in what the template shows.
		data := pageData{
			// The address with any password replaced by xxxxx.
			Address: addr.URL.Redacted(),
			// Which layer supplied it.
			AddressSource: addr.Source,
			// Online or offline.
			Online: res.Online,
			// The version, if online.
			Version: res.Version,
			// The time taken.
			ElapsedMs: res.Elapsed.Milliseconds(),
			// The reason, if offline.
			Reason: res.Reason,
		} // end of the data
		// Only an online Ollama can be asked for its model lists.
		if res.Online {
			// Read the installed models; the request's context cancels the call if the browser goes away.
			installed, err := fetchInstalled(r.Context(), addr.URL, timeout)
			// Read the loaded models only if the first call worked.
			var loaded []loadedModel
			// Skip the second call after a failure.
			if err == nil {
				// Read the loaded models.
				loaded, err = fetchLoaded(r.Context(), addr.URL, timeout)
			} // end of the second call
			// A failure is shown in the page, using the same safe wording as the terminal.
			if err != nil {
				// Keep the plain reason.
				data.TableError = err.Error()
			} else { // the other case
				// Build the table and switch it on.
				data.Table = buildTableView(installed, loaded)
				// The table can be drawn now.
				data.HasTable = true
			} // end of the error check
		} // end of the online check
		// Build the whole page in memory first, so a template error produces a clean 500 and not a half page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the finished page.
		w.Write(buf.Bytes())
	}) // end of the page route
	// Route: a GET request for "/app.css" sends the embedded stylesheet.
	mux.HandleFunc("GET /app.css", func(w http.ResponseWriter, r *http.Request) {
		// Tell the browser this is a stylesheet.
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		// Send it.
		w.Write(appCSS)
	}) // end of the stylesheet route
	// Wrap the router so every reply carries the safety headers.
	return secureHeaders(mux)
} // end of newWebHandler
EOF_WEB

# Write tableview.go; the quoted EOF_TV marker saves every character exactly as typed.
cat > tableview.go << 'EOF_TV'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the element names (ids) that tie a heading to its help bubble.
	"fmt"
	// strings joins the abilities into one cell.
	"strings"
) // end of imports

// tipView is one help bubble as the page template needs it.
type tipView struct {
	// ID is the element name that the heading points at with aria-describedby (so screen readers read the bubble too).
	ID string
	// Plain, Example, Decide and AlsoKnown are the four parts from tooltips.go.
	Plain, Example, Decide, AlsoKnown string
} // end of tipView

// columnView is one column heading.
type columnView struct {
	// Title is the heading text.
	Title string
	// Tip is the help bubble.
	Tip tipView
} // end of columnView

// rowView is one model row: its name (the sticky first column) and the nine other cells.
type rowView struct {
	// Name is the model name, never shortened.
	Name string
	// Cells are the other nine columns, in order.
	Cells []string
} // end of rowView

// groupView is one category section.
type groupView struct {
	// Heading is the category's display name.
	Heading string
	// CountText says how many models are in it, such as "2 models".
	CountText string
	// Tip is the category's help bubble.
	Tip tipView
	// Rows are the models in this section.
	Rows []rowView
} // end of groupView

// tableView is everything the page needs to draw the Installed table.
type tableView struct {
	// Total is the number of installed models.
	Total int
	// Columns are the ten column headings.
	Columns []columnView
	// Groups are the non-empty category sections, in the fixed order.
	Groups []groupView
} // end of tableView

// makeTip looks up the help text for a heading and attaches the element name.
func makeTip(id, heading string) tipView {
	// A heading without a text gives empty parts; a test makes sure that never happens.
	t, _ := helpFor(heading)
	// Build the view.
	return tipView{ID: id, Plain: t.Plain, Example: t.Example, Decide: t.Decide, AlsoKnown: t.AlsoKnown}
} // end of makeTip

// countText says "1 model" or "N models".
func countText(n int) string {
	// One model is singular.
	if n == 1 {
		// Return the singular form.
		return "1 model"
	} // end of the singular case
	// Everything else is plural.
	return fmt.Sprintf("%d models", n)
} // end of countText

// buildTableView turns the installed and loaded lists into the data the page template draws.
func buildTableView(installed []installedModel, loaded []loadedModel) tableView {
	// Mark each model as loaded or not, then sort into category sections (both from the terminal version).
	groups := groupRows(combine(installed, loaded))
	// Start the view with the total.
	view := tableView{Total: len(installed)}
	// One heading per column, in the fixed order.
	for i, title := range installedColumns {
		// Add the heading with its bubble.
		view.Columns = append(view.Columns, columnView{Title: title, Tip: makeTip(fmt.Sprintf("tip-col-%d", i), title)})
	} // end of the column loop
	// One section per non-empty category.
	for gi, g := range groups {
		// Start the section with its heading, count and bubble.
		gv := groupView{Heading: g.Category.String(), CountText: countText(len(g.Rows)), Tip: makeTip(fmt.Sprintf("tip-cat-%d", gi), g.Category.String())}
		// One row per model.
		for _, r := range g.Rows {
			// A short name for the model's data.
			m := r.Model
			// Add the row: the name first, then the nine cells in the same order and formats as the terminal table.
			gv.Rows = append(gv.Rows, rowView{Name: m.Name, Cells: []string{
				// Ollama's own words for the abilities.
				orDash(strings.Join(m.Capabilities, ", ")),
				// Size on disk.
				formatSize(m.Size),
				// Family as reported.
				orDash(m.Details.Family),
				// Parameter size as reported.
				orDash(m.Details.ParameterSize),
				// Quantization level as reported.
				orDash(m.Details.QuantizationLevel),
				// Last modified, in UTC.
				formatTime(m.ModifiedAt),
				// Loaded or not, symbol plus words.
				stateText(r.Loaded),
				// Largest context the model supports.
				formatCount(m.Details.ContextLength),
				// Width of the model's vectors.
				formatCount(m.Details.EmbeddingLength),
			}}) // end of the row
		} // end of the model loop
		// Add the finished section.
		view.Groups = append(view.Groups, gv)
	} // end of the group loop
	// Return the view.
	return view
} // end of buildTableView
EOF_TV

# Write tableview_test.go; the quoted EOF_TVT marker saves every character exactly as typed.
cat > tableview_test.go << 'EOF_TVT'
// Package main tells Go that this test file belongs to the same program as tableview.go.
package main

import ( // import lists the packages this test file uses.
	// reflect compares whole lists of text.
	"reflect"
	// strings searches the terminal table's lines.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides the clock the terminal table needs.
	"time"
) // end of imports

// TestBuildTableViewShape checks the sections, counts and order built from the six real models.
func TestBuildTableViewShape(t *testing.T) {
	// Build the view with nothing loaded.
	v := buildTableView(realInstalled(t), nil)
	// The total.
	if v.Total != 6 {
		// Report the difference.
		t.Errorf("Total = %d, want 6", v.Total)
	} // end of the total check
	// The ten column titles, in the fixed order.
	var titles []string
	// Collect them.
	for _, c := range v.Columns {
		// Add the title.
		titles = append(titles, c.Title)
	} // end of the column loop
	// Compare.
	if !reflect.DeepEqual(titles, installedColumns) {
		// Report the difference.
		t.Errorf("columns = %v", titles)
	} // end of the title check
	// Two sections: embedding first, then multimodal.
	if len(v.Groups) != 2 || v.Groups[0].Heading != categoryEmbedding.String() || v.Groups[1].Heading != categoryMultimodal.String() {
		// Report the difference.
		t.Fatalf("groups = %+v", v.Groups)
	} // end of the group check
	// The counts.
	if v.Groups[0].CountText != "2 models" || v.Groups[1].CountText != "4 models" {
		// Report the difference.
		t.Errorf("counts = %q, %q", v.Groups[0].CountText, v.Groups[1].CountText)
	} // end of the count check
	// Every row has a name and nine other cells.
	for _, g := range v.Groups {
		// Go through the rows.
		for _, r := range g.Rows {
			// Check the cell count.
			if r.Name == "" || len(r.Cells) != 9 {
				// Report the problem.
				t.Errorf("row %q has %d cells", r.Name, len(r.Cells))
			} // end of the row check
		} // end of the row loop
	} // end of the group loop
} // end of TestBuildTableViewShape

// TestBuildTableViewCells checks the exact text of one real row, with the model loaded.
func TestBuildTableViewCells(t *testing.T) {
	// Build the view with medgemma:latest loaded.
	v := buildTableView(realInstalled(t), []loadedModel{{Name: "medgemma:latest"}})
	// Find the row.
	for _, g := range v.Groups {
		// Go through the rows.
		for _, r := range g.Rows {
			// Only the row we want.
			if r.Name != "medgemma:latest" {
				// Skip the others.
				continue
			} // end of the name check
			// The nine cells exactly as the terminal table shows them.
			want := []string{"completion, vision", "3.3 GB", "gemma3", "4.3B", "Q4_K_M", "2026-10-21 15:48 UTC", "● Loaded", "131072", "2560"}
			// Compare.
			if !reflect.DeepEqual(r.Cells, want) {
				// Report the difference.
				t.Errorf("cells = %q, want %q", r.Cells, want)
			} // end of the compare
			// Done.
			return
		} // end of the row loop
	} // end of the group loop
	// The row was never found.
	t.Errorf("medgemma:latest is missing from the view")
} // end of TestBuildTableViewCells

// TestTableViewMatchesTerminalTable checks that every cell on the page also appears in the terminal table's line for that model.
func TestTableViewMatchesTerminalTable(t *testing.T) {
	// The installed list and the loaded list.
	installed := realInstalled(t)
	// One loaded model.
	loaded := []loadedModel{{Name: "medgemma:latest"}}
	// The terminal table.
	terminal := renderInstalled(groupRows(combine(installed, loaded)))
	// The page view.
	v := buildTableView(installed, loaded)
	// Go through every row of the view.
	for _, g := range v.Groups {
		// Go through the rows.
		for _, r := range g.Rows {
			// Find the terminal line that starts with the model name.
			var line string
			// Look at every terminal line.
			for _, l := range strings.Split(terminal, "\n") {
				// A match starts with the name followed by a space.
				if strings.HasPrefix(l, r.Name+" ") {
					// Remember it.
					line = l
				} // end of the match check
			} // end of the line loop
			// A missing line is a failure.
			if line == "" {
				// Report the problem.
				t.Errorf("no terminal line for %q", r.Name)
				// Go to the next row.
				continue
			} // end of the missing check
			// Every cell must appear in that line.
			for _, c := range r.Cells {
				// Look for it.
				if !strings.Contains(line, c) {
					// Report the difference.
					t.Errorf("%q: cell %q is not in the terminal line %q", r.Name, c, line)
				} // end of the cell check
			} // end of the cell loop
		} // end of the row loop
	} // end of the group loop
	// Keep the clock import used by the terminal helper in one place.
	_ = time.Now
} // end of TestTableViewMatchesTerminalTable

// TestBuildTableViewEmpty checks the view for an Ollama with no models.
func TestBuildTableViewEmpty(t *testing.T) {
	// Build the view from nothing.
	v := buildTableView(nil, nil)
	// No total and no sections.
	if v.Total != 0 || len(v.Groups) != 0 {
		// Report the difference.
		t.Errorf("view = %+v", v)
	} // end of the check
} // end of TestBuildTableViewEmpty

// TestCountText checks the singular and plural forms.
func TestCountText(t *testing.T) {
	// A table of numbers and wanted text.
	for n, want := range map[int]string{0: "0 models", 1: "1 model", 2: "2 models", 4: "4 models"} {
		// Compare.
		if got := countText(n); got != want {
			// Report the difference.
			t.Errorf("countText(%d) = %q, want %q", n, got, want)
		} // end of the compare
	} // end of the loop
} // end of TestCountText

// TestTipIDsAreUnique checks that no two bubbles share an element name, which would break aria-describedby.
func TestTipIDsAreUnique(t *testing.T) {
	// Build the view.
	v := buildTableView(realInstalled(t), nil)
	// Remember the names seen.
	seen := map[string]bool{}
	// Collect every bubble name.
	var ids []string
	// The columns first.
	for _, c := range v.Columns {
		// Add the name.
		ids = append(ids, c.Tip.ID)
	} // end of the column loop
	// Then the sections.
	for _, g := range v.Groups {
		// Add the name.
		ids = append(ids, g.Tip.ID)
	} // end of the group loop
	// Check each one.
	for _, id := range ids {
		// An empty or repeated name is a mistake.
		if id == "" || seen[id] {
			// Report the problem.
			t.Errorf("bad or repeated bubble name %q", id)
		} // end of the check
		// Remember it.
		seen[id] = true
	} // end of the loop
} // end of TestTipIDsAreUnique
EOF_TVT

# Write webtable_test.go; the quoted EOF_WTT marker saves every character exactly as typed.
cat > webtable_test.go << 'EOF_WTT'
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
	// Exactly one model is loaded and five are not; only table cells are counted, because the help bubbles mention the same words.
	if n := strings.Count(body, "<td>● Loaded</td>"); n != 1 {
		// Report the difference.
		t.Errorf("loaded cells = %d, want 1", n)
	} // end of the loaded count
	// Five models are not loaded.
	if n := strings.Count(body, "<td>○ Not loaded</td>"); n != 5 {
		// Report the difference.
		t.Errorf("not-loaded cells = %d, want 5", n)
	} // end of the not-loaded count
	// Order: the embedding group comes first, and inside it hf.co comes before rjmalagon.
	i1 := strings.Index(body, "<strong>Search and similarity (embedding)</strong>")
	// The multimodal heading position.
	i2 := strings.Index(body, "<strong>Chat with images or audio (multimodal)</strong>")
	// The first embedding model, found as a row heading (the help bubbles also mention model names).
	i3 := strings.Index(body, `class="stickycol">hf.co/NeoRoth`)
	// The second embedding model, found the same way.
	i4 := strings.Index(body, `class="stickycol">rjmalagon/gte-qwen2`)
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
	// Ten column bubbles plus two category bubbles.
	if n := strings.Count(body, `role="tooltip"`); n != 12 {
		// Report the difference.
		t.Errorf("%d bubbles, want 12", n)
	} // end of the bubble count
	// Every column title must be a focusable heading.
	for _, col := range installedColumns {
		// The heading element holds the title text.
		if !strings.Contains(body, ">"+html.EscapeString(col)+"</span>") {
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
	// There must be one per bubble.
	if len(refs) != 12 {
		// Report the difference.
		t.Errorf("%d aria-describedby attributes, want 12", len(refs))
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
		// Ten column headings.
		{`scope="col"`, 10},
		// One row heading per model.
		{`scope="row"`, 6},
		// One group heading per non-empty category.
		{`scope="colgroup"`, 2},
		// The scroll box is a labelled region that the keyboard can reach.
		{`role="region"`, 1},
		// Twelve headings plus the scroll box can take the focus.
		{`tabindex="0"`, 13},
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
	if !strings.Contains(body, "No models are installed.") || strings.Contains(body, "<table") {
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
	if strings.Contains(body, "<table") {
		// Report the problem.
		t.Errorf("a table was drawn although the lists failed")
	} // end of the table check
} // end of TestTableListError

// TestTableWhenOffline checks that an offline Ollama gives a note and no table.
func TestTableWhenOffline(t *testing.T) {
	// Ask the page with nothing listening.
	_, _, body := get(t, handlerFor(t, "http://"+closedAddress(t)), http.MethodGet, "/")
	// The note must appear and no table may be drawn.
	if !strings.Contains(body, "The model tables appear when Ollama answers.") || strings.Contains(body, "<table") {
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
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestStylesheetHasTableAndBubbleRules
EOF_WTT

# Two earlier test files had a few structural lines without a comment; this adds a trailing comment to them (safe to run twice).
python3 - << 'EOF_PY'
# Regular expressions find the lines to change; pathlib reads and writes the files.
import re, pathlib
# The two files that need the change.
for name in ["web_test.go", "tooltips_test.go"]:
    # Load the file.
    path = pathlib.Path(name)
    # Read its text.
    text = path.read_text()
    # A line that is only a tab-indented "}{" gets a trailing comment; lines that already have one do not match.
    text = re.sub(r'(?m)^(\t+)\}\{$', r'\1}{ // the cases follow', text)
    # Write the file back.
    path.write_text(text)
# Say what happened.
print("comment fix applied to web_test.go and tooltips_test.go")
EOF_PY

# Fail if any Go file is not formatted the standard way (gofmt -l lists offenders).
unformatted="$(gofmt -l .)"
# An empty list means everything is formatted.
if [ -n "$unformatted" ]; then
  # Show the offenders and stop.
  echo "NOT FORMATTED: $unformatted"; exit 1
fi # end of the format check
# Ask Go to look for suspicious constructs in the program and the tests.
go vet ./...
# Run every test quietly; a failure stops the script and shows Go's own message (-count=1 forces a fresh run).
go test -count=1 ./... 2>&1 | grep -v 'TLS handshake'
# Make sure the output folder exists.
mkdir -p bin
# Build the native executable (CGO_ENABLED=0 = no C libraries; -trimpath removes local paths).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build and tests worked.
echo "PASS  tests and build"

# Run the smoke test from script 05 again; it must still pass with the bigger page.
scripts/05-smoke-test.sh | tail -1

# ---------- Page check against the real Ollama ----------
# Refuse to run if something on this machine already listens on the page-check port (-H hides the header, so any output means in use).
if [ -n "$(ss -ltnH "sport = :$TEST_PORT")" ]; then
  # Explain the problem and stop.
  echo "IN USE: something is already listening on port $TEST_PORT; set TEST_PORT to another port" >&2; exit 1
fi # end of the host port check
# Read the ports published by Docker containers, running and stopped (|| true: carry on if Docker is not available to this user).
DOCKER_PORTS="$(docker ps -a --format '{{.Ports}}' 2> /dev/null || true)"
# Look for the test port in that list (a here-string, not a pipe, so there is no early-exit problem).
if grep -q ":$TEST_PORT->" <<< "$DOCKER_PORTS"; then
  # Explain the problem and stop.
  echo "IN USE: a Docker container publishes port $TEST_PORT; set TEST_PORT to another port" >&2; exit 1
fi # end of the Docker port check
# Start the monitor in the background on the spare port, watching the chosen Ollama; its messages are discarded.
OCC_OLLAMA_URL="" ./bin/OllamaControlCenter -listen "127.0.0.1:$TEST_PORT" -ollama-url "$OLLAMA_TEST_URL" > /dev/null 2>&1 &
# Remember the background process so it can be stopped.
PID=$!
# Stop the monitor when the script ends for any reason.
trap 'kill "$PID" 2> /dev/null || true' EXIT
# Wait up to 5 seconds for the page to answer.
for _ in $(seq 1 50); do
  # Any answer at all means it is up.
  if curl -s -o /dev/null "http://127.0.0.1:$TEST_PORT/"; then break; fi # end of the answer check
  # Wait a moment before asking again.
  sleep 0.1
done # end of the waiting loop

# Fetch the page once (-s hides the progress bar).
PAGE="$(curl -s "http://127.0.0.1:$TEST_PORT/")"
# Ask the terminal version for the number of installed models: the number inside the brackets of the INSTALLED MODELS line.
N="$(OCC_OLLAMA_URL="" ./bin/OllamaControlCenter -models -ollama-url "$OLLAMA_TEST_URL" | grep -m1 'INSTALLED MODELS' | sed 's/[^0-9]//g')"
# Count the category headings and the help bubbles on the page (grep -o prints each match on its own line, wc -l counts the lines).
GROUPS_ON_PAGE="$(grep -o 'scope="colgroup"' <<< "$PAGE" | wc -l)"
# Count the bubbles.
BUBBLES="$(grep -o 'role="tooltip"' <<< "$PAGE" | wc -l)"
# Count the model rows.
ROWS="$(grep -o 'scope="row"' <<< "$PAGE" | wc -l)"

# Counters for passed and failed checks.
pass=0; fail=0
# check LABEL RESULT: prints PASS when the result is "yes".
check() {
  # Print the result and count it.
  if [ "$2" = "yes" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi # end of the verdict
} # end of check

# Check 1: the panel heading shows the same number of models as the terminal version.
check "page says Installed models ($N), same as -models" "$(grep -qF "Installed models ($N)" <<< "$PAGE" && echo yes || echo no)"
# Check 2: one table row per installed model.
check "$ROWS model rows for $N models" "$([ "$ROWS" = "$N" ] && echo yes || echo no)"
# Check 3: ten column bubbles plus one per category heading.
check "$BUBBLES help bubbles = 10 columns + $GROUPS_ON_PAGE categories" "$([ "$BUBBLES" = "$((10 + GROUPS_ON_PAGE))" ] && echo yes || echo no)"
# Check 4: the page still has no script, no style tag and no inline style.
check "page has no script or inline style" "$(grep -qiE '<script|<style| style=' <<< "$PAGE" && echo no || echo yes)"
# Check 5: no title attribute is used for help (it would not work from the keyboard).
check "no title= attribute used for help" "$(grep -qi ' title=' <<< "$PAGE" && echo no || echo yes)"

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Show the category headings and model names exactly as the page has them (read-only).
echo "Categories and models in the page:"
# Print the category names and the model names in page order.
grep -oE '<strong>[^<]*</strong></span>|class="stickycol">[^<]*' <<< "$PAGE" | sed -E 's#<strong>(.*)</strong></span>#== \1 ==#; s#class="stickycol">#   #' | grep -v '^ *$'
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
