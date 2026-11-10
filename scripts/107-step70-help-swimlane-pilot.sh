#!/usr/bin/env bash
# Script 107 (Help page, pilot): a new Help page, opened from a Help button in the monitor's footer bar, shows the help topics as swimlane diagrams (lanes: You, LLMsControlDock, Ollama, ollama.com). This pilot has one topic, Find LLM, drawn as a fixed picture inside the page (no script, nothing loaded from the internet) with the same steps listed in words under it. Tests follow.
# Run it from a new branch made from main (after script 106 is merged): cd ~/LLMsControlDock && git switch -c feature/help-swimlane-pilot && bash scripts/107-step70-help-swimlane-pilot.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 106), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["web.go"]="c4a35c301cb27b92cf82303f4534b064436859cc53211cf86d4da8954d319b20"
BEFORE["web/index.html"]="7d728a5b7903e355b38c763c9d53688d5bfc3590ddf0e880956ee448d9904ba5"
BEFORE["web/app.css"]="9e23db3c0823a8c04bfca47a95bc626f9f957e9d4cb470cb14e6591730a026c6"
AFTER["web.go"]="a5018cdb39d400f97d6effb701de70eb0edf52f794f3fc10ec7be68f2ccec05d"
AFTER["web/index.html"]="5a68852630bd637f60acd78be864393e734295bb0c45bc1e50bbe2fa42ef7ccf"
AFTER["web/app.css"]="a0aad37afed17c08c185f2d331621caa63078380e3ed76c7249a31898d73ff1d"
AFTER["help.go"]="2d3041719ee1df54aae085e8a8ecf4781153336667071583323480df68dab175"
AFTER["help_test.go"]="8204ec551ff624d93216fc3a0e40345b7802e9797bdb5e66734585f28892684f"
AFTER["web/help.html"]="d8ec2a70356d1a06d044bdda5974b2fb1cbc865489c667368fb93f45ccaa4de9"

# Count of passed checks.
PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/help-swimlane-pilot"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 106 must have been applied: its new file exists.
[ -f selfusage.go ] || fail "script 106 must be applied first"
# Report it.
pass "script 106 is applied"

# Refuse to run twice: the new file exists when this change was applied before.
if [ -e help.go ]; then fail "help.go already exists: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files to change are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/help.go b/help.go
new file mode 100644
index 0000000..a5682de
--- /dev/null
+++ b/help.go
@@ -0,0 +1,268 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds the page in memory.
+	"bytes"
+	// embed lets the page template be stored inside the executable (the blank name means we only need its side effect).
+	_ "embed"
+	// fmt builds the path texts of the arrows.
+	"fmt"
+	// html/template fills the page and escapes every value.
+	"html/template"
+	// log writes the reason when the page cannot be built.
+	"log"
+	// net/http provides requests and status codes.
+	"net/http"
+	// strings splits text into lines.
+	"strings"
+) // end of imports
+
+// helpTemplateText holds the Help page, stored inside the executable at build time.
+//
+//go:embed web/help.html
+var helpTemplateText string
+
+// helpLanes are the lanes (rows of who does what) every diagram uses, in this order.
+var helpLanes = []string{"You", "LLMsControlDock", "Ollama", "ollama.com"}
+
+// helpStep is one step of a topic: the lane that does it (an index into helpLanes) and what is done, in one short sentence.
+type helpStep struct {
+	// Lane is the index of the lane in helpLanes.
+	Lane int
+	// Text is what happens in this step.
+	Text string
+} // end of helpStep
+
+// helpTopic is one help topic: a title, a plain introduction and the steps of its swimlane diagram.
+type helpTopic struct {
+	// ID is the name used for the link to this topic on the page.
+	ID string
+	// Title is the heading of the topic.
+	Title string
+	// Intro is one or two plain sentences before the diagram.
+	Intro string
+	// Steps are the steps, in order.
+	Steps []helpStep
+} // end of helpTopic
+
+// helpTopics are the topics of the Help page; each one is checked against what the program really does.
+var helpTopics = []helpTopic{
+	{
+		ID:    "find-llm",
+		Title: "Find LLM: from your needs to a model you can install",
+		Intro: "Find LLM lists the models of the official Ollama library that fit what you tick and what this computer has. It never installs anything: you copy a command and run it yourself. If ollama.com cannot be reached, a saved copy of the list is shown with its date and without versions.",
+		Steps: []helpStep{
+			{0, "Open Find LLM from the monitor."},
+			{1, "Shows the choices, with free disk and memory filled in."},
+			{0, "Tick what you need and press Find LLM."},
+			{1, "Asks ollama.com for the library list."},
+			{3, "Sends the public list. Your choices are not sent."},
+			{1, "Keeps matching models, asks for each one's versions."},
+			{3, "Sends sizes, context lengths and update ages."},
+			{1, "Asks Ollama which models are installed."},
+			{2, "Lists the installed models."},
+			{1, "Checks every version against your limits and lists them."},
+			{0, "Copy the command of a version that fits."},
+			{2, "Downloads the model when you run the command."},
+		},
+	},
+} // end of helpTopics
+
+// The measures of a diagram, in the units of its drawing area.
+const (
+	// helpLaneW is the width of one lane.
+	helpLaneW = 190
+	// helpHeaderH is the height of the lane names at the top.
+	helpHeaderH = 36
+	// helpBoxW is the width of a step box.
+	helpBoxW = 170
+	// helpBoxH is the height of a step box (three lines of text).
+	helpBoxH = 64
+	// helpGap is the space between two boxes, where the arrow runs.
+	helpGap = 30
+	// helpWrap is the longest line of text inside a box, in characters.
+	helpWrap = 23
+	// helpMaxLines is the most lines a box can hold.
+	helpMaxLines = 3
+) // end of the measures
+
+// helpLine is one line of text inside a box.
+type helpLine struct {
+	// X and Y are the place of the line.
+	X, Y int
+	// Text is the words.
+	Text string
+} // end of helpLine
+
+// helpBox is one step as drawn.
+type helpBox struct {
+	// X, Y, W and H are the place and size of the box.
+	X, Y, W, H int
+	// Lines are the lines of text.
+	Lines []helpLine
+	// Arrow is the path of the arrow that leaves this box towards the next one; empty for the last.
+	Arrow string
+} // end of helpBox
+
+// helpLaneView is one lane as drawn.
+type helpLaneView struct {
+	// Name is the lane's name.
+	Name string
+	// X is the left edge and W the width.
+	X, W int
+	// NameX and NameY are where the name is written.
+	NameX, NameY int
+	// Odd is true for every second lane, which gets a tinted background.
+	Odd bool
+} // end of helpLaneView
+
+// helpListItem is one step as the numbered list under the diagram shows it.
+type helpListItem struct {
+	// Lane is the lane's name.
+	Lane string
+	// Text is the step's sentence.
+	Text string
+} // end of helpListItem
+
+// helpTopicView is one topic ready for the page.
+type helpTopicView struct {
+	// ID, Title and Intro come from the topic.
+	ID, Title, Intro string
+	// Width and Height are the size of the drawing area.
+	Width, Height int
+	// Lanes are the lanes.
+	Lanes []helpLaneView
+	// Boxes are the steps.
+	Boxes []helpBox
+	// List is the same steps as text, for people who cannot see the picture.
+	List []helpListItem
+	// Description is a sentence for screen readers that says what the picture is.
+	Description string
+} // end of helpTopicView
+
+// wrapText cuts a sentence into lines of at most width characters, breaking only between words; a word longer than the width stays whole.
+func wrapText(s string, width int) []string {
+	// The lines.
+	var lines []string
+	// The line being built.
+	cur := ""
+	// Each word.
+	for _, w := range strings.Fields(s) {
+		// The first word of a line.
+		if cur == "" {
+			// Start it.
+			cur = w
+			// Next word.
+			continue
+		} // end of the start check
+		// It still fits on the line.
+		if len(cur)+1+len(w) <= width {
+			// Add it.
+			cur += " " + w
+		} else {
+			// Close the line and start the next.
+			lines = append(lines, cur)
+			// The word starts the next line.
+			cur = w
+		} // end of the fit check
+	} // end of the word loop
+	// The last line.
+	if cur != "" {
+		// Keep it.
+		lines = append(lines, cur)
+	} // end of the last-line check
+	// The lines.
+	return lines
+} // end of wrapText
+
+// buildHelpTopic works out where every lane, box, line of text and arrow goes.
+func buildHelpTopic(t helpTopic) helpTopicView {
+	// The basic facts.
+	v := helpTopicView{ID: t.ID, Title: t.Title, Intro: t.Intro, Width: helpLaneW * len(helpLanes)}
+	// The height: the header, a margin, and every step with its gap.
+	top := helpHeaderH + 14
+	// The total height.
+	v.Height = top + len(t.Steps)*(helpBoxH+helpGap)
+	// The lanes.
+	for i, name := range helpLanes {
+		// One lane.
+		v.Lanes = append(v.Lanes, helpLaneView{Name: name, X: i * helpLaneW, W: helpLaneW, NameX: i*helpLaneW + helpLaneW/2, NameY: 23, Odd: i%2 == 1})
+	} // end of the lane loop
+	// The steps.
+	for i, s := range t.Steps {
+		// The box: centred in its lane.
+		b := helpBox{X: s.Lane*helpLaneW + (helpLaneW-helpBoxW)/2, Y: top + i*(helpBoxH+helpGap), W: helpBoxW, H: helpBoxH}
+		// The words, with the step number in front.
+		for j, line := range wrapText(fmt.Sprintf("%d. %s", i+1, s.Text), helpWrap) {
+			// One line, centred in the box.
+			b.Lines = append(b.Lines, helpLine{X: b.X + b.W/2, Y: b.Y + 21 + j*16, Text: line})
+		} // end of the line loop
+		// The arrow to the next step.
+		if i+1 < len(t.Steps) {
+			// Where it starts: the middle of the bottom edge.
+			x1, y1 := b.X+b.W/2, b.Y+b.H
+			// Where it ends: the middle of the next box's top edge.
+			x2, y2 := t.Steps[i+1].Lane*helpLaneW+helpLaneW/2, top+(i+1)*(helpBoxH+helpGap)
+			// The same lane: straight down.
+			if x1 == x2 {
+				// A vertical line.
+				b.Arrow = fmt.Sprintf("M%d %d V%d", x1, y1, y2)
+			} else {
+				// Down, across, down.
+				b.Arrow = fmt.Sprintf("M%d %d V%d H%d V%d", x1, y1, y1+helpGap/2, x2, y2)
+			} // end of the lane check
+		} // end of the arrow check
+		// Keep the box.
+		v.Boxes = append(v.Boxes, b)
+		// And the list item.
+		v.List = append(v.List, helpListItem{Lane: helpLanes[s.Lane], Text: s.Text})
+	} // end of the step loop
+	// The sentence for screen readers.
+	v.Description = fmt.Sprintf("Swimlane diagram with %d lanes (%s) and %d numbered steps from top to bottom; the same steps are listed below it.", len(helpLanes), strings.Join(helpLanes, ", "), len(t.Steps))
+	// The finished view.
+	return v
+} // end of buildHelpTopic
+
+// helpPage is what the Help template needs.
+type helpPage struct {
+	// Theme is the saved colour theme, or empty to follow the system.
+	Theme string
+	// Size is the saved text size, or empty for the browser's own size.
+	Size string
+	// Topics are the topics to show.
+	Topics []helpTopicView
+} // end of helpPage
+
+// helpHandler builds the handler of the read-only Help page; it changes nothing and needs no token.
+func helpHandler() http.HandlerFunc {
+	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
+	page := template.Must(template.New("help").Parse(helpTemplateText))
+	// The topics are fixed, so their drawings are worked out once.
+	var topics []helpTopicView
+	// Each topic.
+	for _, t := range helpTopics {
+		// Its drawing.
+		topics = append(topics, buildHelpTopic(t))
+	} // end of the topic loop
+	// The handler itself.
+	return func(w http.ResponseWriter, r *http.Request) {
+		// What the template shows.
+		data := helpPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Topics: topics}
+		// Build the page in memory first, so a template error produces a clean 500 and not a half page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason.
+			log.Printf("help page error: %v", err)
+			// Send a plain 500 without details.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the finished page.
+		w.Write(buf.Bytes())
+	} // end of the handler
+} // end of helpHandler
diff --git a/help_test.go b/help_test.go
new file mode 100644
index 0000000..c2de9b4
--- /dev/null
+++ b/help_test.go
@@ -0,0 +1,159 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages the tests use.
+	// html unescapes the page text before it is compared.
+	"html"
+	// net/http gives the method names and status codes.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestWrapText checks the line breaking: words stay whole and lines stay within the width.
+func TestWrapText(t *testing.T) {
+	// A sentence that needs three lines.
+	got := wrapText("1. Shows the choices, with free disk and memory filled in.", 23)
+	// Every line fits.
+	for _, l := range got {
+		// Too long.
+		if len(l) > 23 {
+			// Report.
+			t.Errorf("line %q is longer than 23", l)
+		} // end of the check
+	} // end of the loop
+	// Nothing is lost.
+	if strings.Join(got, " ") != "1. Shows the choices, with free disk and memory filled in." {
+		// Report.
+		t.Errorf("the words changed: %q", got)
+	} // end of the words check
+	// A single long word stays whole.
+	if w := wrapText("extraordinarily-long-word", 10); len(w) != 1 || w[0] != "extraordinarily-long-word" {
+		// Report.
+		t.Errorf("long word: %q", w)
+	} // end of the long-word check
+} // end of TestWrapText
+
+// TestHelpTopicsFitTheirBoxes checks the data of every topic: lanes in range, and every step's words fit in a box of three lines.
+func TestHelpTopicsFitTheirBoxes(t *testing.T) {
+	// Each topic.
+	for _, tp := range helpTopics {
+		// There must be steps and an introduction.
+		if len(tp.Steps) < 2 || tp.Intro == "" || tp.ID == "" || tp.Title == "" {
+			// Report.
+			t.Errorf("topic %q is incomplete", tp.ID)
+		} // end of the completeness check
+		// Each step.
+		for i, s := range tp.Steps {
+			// The lane must exist.
+			if s.Lane < 0 || s.Lane >= len(helpLanes) {
+				// Report.
+				t.Errorf("%s step %d: lane %d does not exist", tp.ID, i+1, s.Lane)
+			} // end of the lane check
+			// The words must fit.
+			if n := len(wrapText("00. "+s.Text, helpWrap)); n > helpMaxLines {
+				// Report.
+				t.Errorf("%s step %d needs %d lines, the box holds %d: %q", tp.ID, i+1, n, helpMaxLines, s.Text)
+			} // end of the fit check
+		} // end of the step loop
+	} // end of the topic loop
+} // end of TestHelpTopicsFitTheirBoxes
+
+// TestHelpPage checks the Help page: it is a plain read-only page with no script, each step is in the picture and in the list, the arrows join the steps, and the monitor links to it.
+func TestHelpPage(t *testing.T) {
+	// A rig.
+	rig := newThemeRig(t)
+	// Fetch the page.
+	status, header, body := get(t, rig.h, http.MethodGet, "/help")
+	// Found, as HTML, under the strict policy.
+	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/html") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
+		// Stop.
+		t.Fatalf("status %d, type %q, policy %q", status, header.Get("Content-Type"), header.Get("Content-Security-Policy"))
+	} // end of the check
+	// No script, and only reading.
+	if strings.Contains(body, "<script") {
+		// Report.
+		t.Error("the Help page carries a script")
+	} // end of the script check
+	// Only GET is allowed.
+	if res := post(t, rig.h, "/help", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
+		// Report.
+		t.Errorf("POST /help = %d, want 405", res.StatusCode)
+	} // end of the method check
+	// The back arrow and the picture's accessible name.
+	for _, want := range []string{backArrowMarkup, `role="img"`, `<title id="find-llm-svgtitle">`, "The steps in words", `<h1>Help</h1>`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the Help page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// The page as plain text for the comparison of the words.
+	plain := html.UnescapeString(body)
+	// Each step appears twice: in the picture (possibly split over lines) and in the list.
+	for _, tp := range helpTopics {
+		// Each step.
+		for i, s := range tp.Steps {
+			// In the list, whole.
+			if !strings.Contains(plain, "</strong> "+s.Text+"</li>") {
+				// Report.
+				t.Errorf("%s step %d is not in the list", tp.ID, i+1)
+			} // end of the list check
+			// In the picture, line by line.
+			for _, l := range wrapText(strings.Join([]string{itoa(i + 1), ". ", s.Text}, ""), helpWrap) {
+				// Look for the line.
+				if !strings.Contains(plain, ">"+l+"</text>") {
+					// Report.
+					t.Errorf("%s step %d: line %q is not in the picture", tp.ID, i+1, l)
+				} // end of the line check
+			} // end of the line loop
+		} // end of the step loop
+		// One box per step and one arrow between each pair.
+		if n := strings.Count(body, `class="lanebox"`); n != len(tp.Steps) {
+			// Report.
+			t.Errorf("%d boxes, want %d", n, len(tp.Steps))
+		} // end of the box check
+		// The arrows.
+		if n := strings.Count(body, `class="lanearrow"`); n != len(tp.Steps)-1 {
+			// Report.
+			t.Errorf("%d arrows, want %d", n, len(tp.Steps)-1)
+		} // end of the arrow check
+	} // end of the topic loop
+	// Every lane has its name.
+	for _, l := range helpLanes {
+		// Look for it.
+		if !strings.Contains(body, `>`+l+`</text>`) {
+			// Report.
+			t.Errorf("lane %q has no name in the picture", l)
+		} // end of the look
+	} // end of the lane loop
+	// The monitor links to the Help page.
+	if _, _, main := get(t, rig.h, http.MethodGet, "/"); !strings.Contains(main, `<a class="brandbtn" href="/help">Help</a>`) {
+		// Report.
+		t.Error("the monitor has no Help button")
+	} // end of the link check
+} // end of TestHelpPage
+
+// itoa writes a small number as text.
+func itoa(n int) string {
+	// Digits.
+	s := ""
+	// A zero.
+	if n == 0 {
+		// Zero.
+		return "0"
+	} // end of the zero check
+	// Build from the right.
+	for n > 0 {
+		// The last digit in front.
+		s = string(rune('0'+n%10)) + s
+		// The rest.
+		n /= 10
+	} // end of the loop
+	// The text.
+	return s
+} // end of itoa
diff --git a/web/app.css b/web/app.css
index dc88a49..29b576b 100644
--- a/web/app.css
+++ b/web/app.css
@@ -3038,3 +3038,93 @@ html[data-size="medium"] svg[width="22"] {
   /* A little larger than body text. */
   font-size: 1.1rem;
 } /* end of rule */
+
+/* The Help page: the card and its topics. */
+.helpcard {
+  /* Space between the topics is made by the topic's own margin. */
+  position: relative;
+} /* end of rule */
+
+/* One topic on the Help page. */
+.helptopic {
+  /* Space above the topic. */
+  margin: 1.5rem 0;
+} /* end of rule */
+
+/* The swimlane picture: as wide as the card, never wider, so the page does not scroll sideways. */
+.swimlane {
+  /* Full width of the card. */
+  width: 100%;
+  /* The height follows the drawing's proportions. */
+  height: auto;
+  /* Never wider than the card. */
+  max-width: 100%;
+  /* A thin outline. */
+  border: 1px solid var(--border);
+  /* Rounded corners. */
+  border-radius: 0.5rem;
+  /* The page colour behind the lanes. */
+  background: var(--bg);
+} /* end of rule */
+
+/* Every second lane is tinted so the lanes can be told apart without colour names. */
+.swimlane .laneband {
+  /* The page colour. */
+  fill: var(--bg);
+} /* end of rule */
+
+/* The tinted lanes. */
+.swimlane .laneodd {
+  /* The panel colour. */
+  fill: var(--panel);
+} /* end of rule */
+
+/* The lane names. */
+.swimlane .lanename {
+  /* The text colour. */
+  fill: var(--text);
+  /* Bold, so they read as headings. */
+  font-weight: 700;
+  /* Size in drawing units. */
+  font-size: 14px;
+} /* end of rule */
+
+/* A step box. */
+.swimlane .lanebox {
+  /* The page colour inside. */
+  fill: var(--bg);
+  /* An outline that is visible in both themes. */
+  stroke: var(--text);
+  /* Outline thickness. */
+  stroke-width: 1.5;
+} /* end of rule */
+
+/* The words in a step box. */
+.swimlane .lanetext {
+  /* The text colour. */
+  fill: var(--text);
+  /* Size in drawing units. */
+  font-size: 13px;
+} /* end of rule */
+
+/* An arrow between two steps. */
+.swimlane .lanearrow {
+  /* No fill, only a line. */
+  fill: none;
+  /* The secondary text colour. */
+  stroke: var(--muted);
+  /* Line thickness. */
+  stroke-width: 2;
+} /* end of rule */
+
+/* The arrow head. */
+.swimlane .lanehead {
+  /* Same colour as the line. */
+  fill: var(--muted);
+} /* end of rule */
+
+/* The numbered steps in words. */
+.helpsteps {
+  /* Room for the numbers. */
+  padding-left: 1.5rem;
+} /* end of rule */
diff --git a/web/help.html b/web/help.html
new file mode 100644
index 0000000..da7c7b0
--- /dev/null
+++ b/web/help.html
@@ -0,0 +1,69 @@
+{{/* Help page template: swimlane diagrams that show who does what in each task. The pictures are drawn as inline SVG from fixed data, so no script and nothing from the internet is needed. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in; the theme and the text size come from the saved choices. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Help - LLMsControlDock</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* One card holds everything. */}}
+<section class="panel helpcard">
+{{/* The back arrow in the top right corner of this box. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
+{{/* The name of the page. */}}
+<h1>Help</h1>
+{{/* What the page is. */}}
+<p class="muted">Each topic shows who does what, in lanes, from the top down. This is the first topic; more follow.</p>
+{{/* The topics. */}}
+{{range $t := .Topics}}
+{{/* One topic. */}}
+<section class="helptopic" id="{{.ID}}" aria-labelledby="{{.ID}}-title">
+{{/* Its heading. */}}
+<h2 id="{{.ID}}-title">{{.Title}}</h2>
+{{/* The plain introduction. */}}
+<p>{{.Intro}}</p>
+{{/* The picture; its name and description are read by screen readers, and the numbered list below says the same in words. */}}
+<svg class="swimlane" viewBox="0 0 {{.Width}} {{.Height}}" role="img" aria-labelledby="{{.ID}}-svgtitle {{.ID}}-svgdesc" focusable="false">
+<title id="{{.ID}}-svgtitle">{{.Title}}</title>
+<desc id="{{.ID}}-svgdesc">{{.Description}}</desc>
+{{/* The arrow head used by every arrow. */}}
+<defs><marker id="{{.ID}}-head" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path class="lanehead" d="M0 0 L10 5 L0 10 z"/></marker></defs>
+{{/* The lanes: a tinted band and a name each. */}}
+{{range .Lanes}}<rect class="laneband{{if .Odd}} laneodd{{end}}" x="{{.X}}" y="0" width="{{.W}}" height="{{$t.Height}}"/>
+{{end}}
+{{range .Lanes}}<text class="lanename" x="{{.NameX}}" y="{{.NameY}}" text-anchor="middle">{{.Name}}</text>
+{{end}}
+{{/* The arrows go under the boxes. */}}
+{{range .Boxes}}{{if .Arrow}}<path class="lanearrow" d="{{.Arrow}}" marker-end="url(#{{$t.ID}}-head)"/>
+{{end}}{{end}}
+{{/* The step boxes with their words. */}}
+{{range .Boxes}}<rect class="lanebox" x="{{.X}}" y="{{.Y}}" width="{{.W}}" height="{{.H}}" rx="8"/>
+{{range .Lines}}<text class="lanetext" x="{{.X}}" y="{{.Y}}" text-anchor="middle">{{.Text}}</text>
+{{end}}{{end}}
+{{/* End of the picture. */}}
+</svg>
+{{/* The same steps in words. */}}
+<h3>The steps in words</h3>
+<ol class="helpsteps">
+{{range .List}}<li><strong>{{.Lane}}:</strong> {{.Text}}</li>
+{{end}}</ol>
+{{/* End of the topic. */}}
+</section>
+{{end}}
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* End of the card. */}}
+</section>
+{{/* End of the main content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/web/index.html b/web/index.html
index 785d34a..e25c6eb 100644
--- a/web/index.html
+++ b/web/index.html
@@ -621,6 +621,8 @@
 <div class="brandbtns">
 {{/* The System check page: what this computer offers for Ollama. */}}
 <a class="brandbtn" href="/systemcheck">System check</a>
+{{/* The Help page: swimlane diagrams of the tasks. */}}
+<a class="brandbtn" href="/help">Help</a>
 {{/* The About page of this program. */}}
 <a class="brandbtn" href="/about">About this program</a>
 {{/* End of the buttons. */}}
diff --git a/web.go b/web.go
index a2fac1d..8a2c9dd 100644
--- a/web.go
+++ b/web.go
@@ -180,6 +180,8 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	}) // end of the icon route
 	// Route: a GET request for "/about" shows the read-only About page (see about.go).
 	mux.HandleFunc("GET /about", aboutHandler(token))
+	// Route: a GET request for "/help" shows the Help page with the swimlane diagrams (read-only).
+	mux.HandleFunc("GET /help", helpHandler())
 	// Route: a POST request for "/about/estimate" runs the System check, measures this program and saves the estimate.
 	mux.HandleFunc("POST /about/estimate", selfEstimateHandler(token))
 	// Make the two Settings handlers: the first shows the page, the second saves the form (see settingspage.go).
OCC_PATCH_94_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched and new files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done


# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and open the new Help page from the monitor (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
