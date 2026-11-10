#!/usr/bin/env bash
# Script 113 (Help page, guide to reading performance results): a new Help topic, right after Performance test, explains every figure of the Performance page in plain words (what it tells you, which way is better, a real example), in three steps: check the test was fair, read the main figures, compare fairly. It gives no invented limits; explanations and examples come from the Performance page's own help bubbles. The Performance results and the Compare page get a 'How to read these results' link that opens this topic. The smoke test now expects 12 topics. Tests follow.
# Run it from a new branch made from main: cd ~/LLMsControlDock && bash scripts/113-step76-help-performance-guide.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as on main after pull request #51), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["help.go"]="36d8c2b6bd2d37f7efdd921a31e84f60ec7492832fd9150f03331b9a5e2d7d1f"
BEFORE["help_test.go"]="4df71b19a0841d4aaac1e94a3134d67ee36a3cdb4205891799cd8c2a3ba3125b"
BEFORE["web/help.html"]="ccade38e803d313f074b2e1b8a261e0841885231dfe757c6965435527837da1a"
BEFORE["web/performance.html"]="637f89913eca7ab516f115880d86d8506c9ee791c9be373380f667be071ce841"
BEFORE["web/compare.html"]="22a96b32b257ebae722d071e2d3caa2fba3561b050fd2fbf9772e25137c05aa8"
BEFORE["web/app.css"]="8a87e5ddb121243b5925627b430fdeb7d86f5aec62fd8be93ef0891e14f42bb8"
BEFORE["scripts/test-smoke-load.sh"]="c8729094e8247bedfd2a0a567d0b14c12ce922b2eb515932f92cea6fd4d329ee"
AFTER["help.go"]="b02424699b4f914a33de672140bb2f33a9ec4cea27cd93eda815a13f34ad2978"
AFTER["help_test.go"]="478fbfb1add08db6fb89caa9e1c017522ec6269394d0425a260bd6a7df896daf"
AFTER["web/help.html"]="47bde9010484fb8860bd2842ef397e1ad8664652c6951f40a9b675464d7af4eb"
AFTER["web/performance.html"]="2664bb07f9c33d2a969003d2716d5a39f65c928c5bdeb40293aaec2a61d14058"
AFTER["web/compare.html"]="78b8271d4508668d329ce13c4ca46dd43b384e1ac32d4e4d0de4942a0517b08b"
AFTER["web/app.css"]="2327c582e39b759f149859f230f00ae980911acdbc9dfa2ffd35023d42e159d9"
AFTER["scripts/test-smoke-load.sh"]="445169a646a56be501255f054eeb5f5fed90c5566a86f5af249c2b9663db714c"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/help-performance-guide"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 112 and the smoke test must be in place: the band rule is in the style sheet and the smoke test script exists.
grep -q 'details.helptopic:nth-of-type(even)' web/app.css && [ -f scripts/test-smoke-load.sh ] || fail "script 112 and scripts/test-smoke-load.sh must be in place first (pull main)"
# Report it.
pass "script 112 and the smoke test are in place"

# Refuse to run twice: the guide's name is already in help.go when this change was applied before.
if grep -q 'helpPerfGuideID' help.go; then fail "the guide is already in help.go: this script was already applied"; fi
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
index 50db500..c6b6217 100644
--- a/help.go
+++ b/help.go
@@ -42,10 +42,71 @@ type helpTopic struct {
 	Title string
 	// Intro is one or two plain sentences before the diagram.
 	Intro string
-	// Steps are the steps, in order.
+	// Steps are the steps, in order; a guide topic has none.
 	Steps []helpStep
+	// Guide holds the parts of a reading guide; a topic has either steps (a diagram) or a guide (tables of figures).
+	Guide []helpGuidePart
 } // end of helpTopic
 
+// helpGuidePart is one part of a reading guide: a heading, a plain paragraph and, when there is one, a table of figures.
+type helpGuidePart struct {
+	// Heading is the part's heading.
+	Heading string
+	// Text is a plain paragraph under the heading.
+	Text string
+	// Rows are the figures of this part; empty for a part with text only.
+	Rows []helpGuideRow
+} // end of helpGuidePart
+
+// helpGuideRow is one figure of the Performance page, explained: its name as the page shows it, what it tells you, which way is better, and a real example.
+// Means and Example are left empty for every figure that has a help bubble on the Performance page: they are then taken from that bubble, so the guide and the page always say the same.
+type helpGuideRow struct {
+	// Figure is the name as the Performance page shows it.
+	Figure string
+	// Means is what the figure tells you, in plain words (empty: taken from the figure's help bubble).
+	Means string
+	// Better says which way is better.
+	Better string
+	// Example is a real figure measured on a DGX Spark (empty: taken from the figure's help bubble).
+	Example string
+} // end of helpGuideRow
+
+// fillGuide returns a copy of a guide in which every empty explanation and example is taken from the help bubble of the same figure.
+func fillGuide(parts []helpGuidePart) []helpGuidePart {
+	// The copy.
+	out := make([]helpGuidePart, len(parts))
+	// Each part.
+	for i, part := range parts {
+		// The part itself.
+		out[i] = part
+		// Its own copy of the rows, so the shared list is never changed.
+		out[i].Rows = make([]helpGuideRow, len(part.Rows))
+		// Each row.
+		for j, row := range part.Rows {
+			// The bubble of this figure, when it has one.
+			if tip, ok := helpFor(row.Figure); ok {
+				// The explanation, when none is written here.
+				if row.Means == "" {
+					// From the bubble.
+					row.Means = tip.Plain
+				} // end of the explanation check
+				// The example, when none is written here.
+				if row.Example == "" {
+					// From the bubble.
+					row.Example = tip.Example
+				} // end of the example check
+			} // end of the bubble check
+			// Keep the row.
+			out[i].Rows[j] = row
+		} // end of the row loop
+	} // end of the part loop
+	// The filled copy.
+	return out
+} // end of fillGuide
+
+// helpPerfGuideID is the name of the reading guide; the Performance and Compare pages link to it.
+const helpPerfGuideID = "read-performance"
+
 // helpTopics are the topics of the Help page, in the order a person typically meets them (first start, finding and loading a model, tuning, testing, comparing, tidying up, settings, stopping, uninstalling); each one is checked against what the program really does.
 var helpTopics = []helpTopic{
 	{
@@ -129,6 +190,57 @@ var helpTopics = []helpTopic{
 			{1, "Shows the speed and the tests saved for this model."},
 		},
 	},
+	{
+		ID:    helpPerfGuideID,
+		Title: "Read the results of a performance test",
+		Intro: "The Performance page shows figures measured on this machine. Read them in three steps: check that the test was fair, read the main figures, then compare. Ollama publishes no official limits for fast or slow, so this guide gives none: compare models with each other, on the same machine. The examples were measured on a DGX Spark.",
+		Guide: []helpGuidePart{
+			{
+				Heading: "1. Check that the test was fair",
+				Text:    "Look at the warnings at the top of the results and at the table Machine condition during the test. When the machine was busy, the figures come out too low: run the test again when it is quiet.",
+				Rows: []helpGuideRow{
+					{Figure: "The machine looked busy (warning)", Means: "Other work was running when the test started.", Better: "No warning", Example: "The page names the reason: the graphics card was more than 10% busy, or the processor load was above half of its cores."},
+					{Figure: "Other models loaded", Better: "None"},
+					{Figure: "CPU load", Better: "At most half the number of cores (above that, the page warns)"},
+					{Figure: "Swap in use", Better: "0"},
+					{Figure: "GPU", Better: "At most 10% busy (above that, the page warns)"},
+				},
+			},
+			{
+				Heading: "2. Read the main figures (models that write text)",
+				Text:    "Tokens are pieces of words; a short English word is often one token. Speeds are the middle value (median) of three timed runs.",
+				Rows: []helpGuideRow{
+					{Figure: "Answer speed", Better: "Higher"},
+					{Figure: "Prompt reading speed", Better: "Higher"},
+					{Figure: "Time to first word", Better: "Lower"},
+					{Figure: "Total time", Better: "Lower"},
+					{Figure: "Load time", Better: "Lower"},
+					{Figure: "Processor split", Better: "100% on the graphics card"},
+					{Figure: "Memory used", Better: "Lower leaves room for other models"},
+				},
+			},
+			{
+				Heading: "Embedding models (they turn text into numbers for search)",
+				Text:    "An embedding model writes no text, so the page shows two other figures.",
+				Rows: []helpGuideRow{
+					{Figure: "Embedding time", Better: "Lower"},
+					{Figure: "Vector length", Better: "Neither: it must fit your search system"},
+				},
+			},
+			{
+				Heading: "3. Compare fairly",
+				Text:    "Compare only results from this same machine. One run can differ a little from the next, so when two models are close, run the test again before you decide. The Compare page puts the tested models side by side.",
+				Rows: []helpGuideRow{
+					{Figure: "Tokens counted", Better: "The same prompt version on both sides"},
+					{Figure: "Change since the previous run", Better: "Up for speeds, down for times"},
+				},
+			},
+			{
+				Heading: "Which figure matters for your work",
+				Text:    "For a chat, look first at Answer speed and Time to first word. For long documents, look at Prompt reading speed. If you switch models often, look at Load time. When a model is slow and Processor split shows a share on the processor, a smaller model or a smaller version may fit on the graphics card.",
+			},
+		},
+	},
 	{
 		ID:    "compare-models",
 		Title: "Compare tested models, and re-test",
@@ -290,6 +402,10 @@ type helpTopicView struct {
 	List []helpListItem
 	// Description is a sentence for screen readers that says what the picture is.
 	Description string
+	// Guide holds the parts of a reading guide; empty for a diagram topic.
+	Guide []helpGuidePart
+	// Open is true when the page was asked to show this topic open (from a link on another page).
+	Open bool
 } // end of helpTopicView
 
 // wrapText cuts a sentence into lines of at most width characters, breaking only between words; a word longer than the width stays whole.
@@ -330,7 +446,12 @@ func wrapText(s string, width int) []string {
 // buildHelpTopic works out where every lane, box, line of text and arrow goes.
 func buildHelpTopic(t helpTopic) helpTopicView {
 	// The basic facts.
-	v := helpTopicView{ID: t.ID, Title: t.Title, Intro: t.Intro, Width: helpLaneW * len(helpLanes)}
+	v := helpTopicView{ID: t.ID, Title: t.Title, Intro: t.Intro, Width: helpLaneW * len(helpLanes), Guide: fillGuide(t.Guide)}
+	// A guide has no diagram, so nothing more is worked out.
+	if len(t.Guide) > 0 {
+		// The finished view.
+		return v
+	} // end of the guide check
 	// The height: the header, a margin, and every step with its gap.
 	top := helpHeaderH + 14
 	// The total height.
@@ -398,8 +519,19 @@ func helpHandler() http.HandlerFunc {
 	} // end of the topic loop
 	// The handler itself.
 	return func(w http.ResponseWriter, r *http.Request) {
+		// The topic asked to be shown open, for example by the link on the Performance page; only a known name is used, nothing is echoed.
+		want := r.URL.Query().Get("topic")
+		// A copy of the topics for this request, so the shared list is never changed.
+		shown := make([]helpTopicView, len(topics))
+		// Copy them.
+		copy(shown, topics)
+		// Mark the wanted one open.
+		for i := range shown {
+			// Only an exact match.
+			shown[i].Open = shown[i].ID == want
+		} // end of the open loop
 		// What the template shows.
-		data := helpPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Topics: topics}
+		data := helpPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Topics: shown}
 		// Build the page in memory first, so a template error produces a clean 500 and not a half page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/help_test.go b/help_test.go
index bb266e4..f0297c0 100644
--- a/help_test.go
+++ b/help_test.go
@@ -42,8 +42,8 @@ func TestWrapText(t *testing.T) {
 func TestHelpTopicsFitTheirBoxes(t *testing.T) {
 	// Each topic.
 	for _, tp := range helpTopics {
-		// There must be steps and an introduction.
-		if len(tp.Steps) < 2 || tp.Intro == "" || tp.ID == "" || tp.Title == "" {
+		// There must be an introduction, and either steps (a diagram) or a guide, never both.
+		if (len(tp.Steps) < 2) == (len(tp.Guide) == 0) || tp.Intro == "" || tp.ID == "" || tp.Title == "" {
 			// Report.
 			t.Errorf("topic %q is incomplete", tp.ID)
 		} // end of the completeness check
@@ -117,6 +117,11 @@ func TestHelpPage(t *testing.T) {
 	boxes, arrows := 0, 0
 	// Add them up.
 	for _, tp := range helpTopics {
+		// A guide topic has no diagram.
+		if len(tp.Steps) == 0 {
+			// Nothing to add.
+			continue
+		} // end of the guide case
 		// Steps and the arrows between them.
 		boxes += len(tp.Steps)
 		// One fewer arrow than steps.
@@ -160,6 +165,13 @@ func TestHelpPage(t *testing.T) {
 		top, bottom := strings.Index(sec, `id="tipclose-`+tp.ID+`-top"`), strings.Index(sec, `id="tipclose-`+tp.ID+`-bottom"`)
 		// The picture and the list.
 		svg, list := strings.Index(sec, `<svg class="swimlane"`), strings.Index(sec, `<ol class="helpsteps">`)
+		// A guide topic has its guide in place of both.
+		if len(tp.Guide) > 0 {
+			// The guide stands for the picture and the list.
+			svg = strings.Index(sec, `<div class="helpguide">`)
+			// The same place.
+			list = svg
+		} // end of the guide case
 		// Check the order.
 		if top < 0 || bottom < 0 || !(top < svg && list < bottom) {
 			// Report.
@@ -297,3 +309,103 @@ func TestHelpTopicsAreBanded(t *testing.T) {
 		} // end of the muted contrast
 	} // end of the loop
 } // end of TestHelpTopicsAreBanded
+
+// TestHelpPerformanceGuide checks the reading guide: it follows the Performance test topic, every figure is explained with an example taken from the Performance page's own help bubbles, the page opens it when a link asks for it, and the Performance and Compare pages link to it.
+func TestHelpPerformanceGuide(t *testing.T) {
+	// Find the guide and the topic before it.
+	idx := -1
+	// Look through the topics.
+	for i, tp := range helpTopics {
+		// The guide.
+		if tp.ID == helpPerfGuideID {
+			// Found.
+			idx = i
+		} // end of the match
+	} // end of the search
+	// It must exist and come right after the Performance test topic.
+	if idx < 1 || helpTopics[idx-1].ID != "performance-test" || len(helpTopics[idx].Steps) != 0 || len(helpTopics[idx].Guide) == 0 {
+		// Stop.
+		t.Fatalf("the guide is missing, misplaced or not a guide (index %d)", idx)
+	} // end of the place check
+	// The filled guide.
+	parts := fillGuide(helpTopics[idx].Guide)
+	// Count the figures.
+	rows := 0
+	// Each part and row.
+	for _, part := range parts {
+		// A heading and a paragraph.
+		if part.Heading == "" || part.Text == "" {
+			// Report.
+			t.Errorf("a part lacks its heading or text: %+v", part)
+		} // end of the part check
+		// Each row.
+		for _, r := range part.Rows {
+			// One more.
+			rows++
+			// Every column is filled.
+			if r.Figure == "" || r.Means == "" || r.Better == "" || r.Example == "" {
+				// Report.
+				t.Errorf("figure %q has an empty column", r.Figure)
+			} // end of the column check
+			// A figure with a help bubble says exactly what the bubble says.
+			if tip, ok := helpFor(r.Figure); ok && (r.Means != tip.Plain || r.Example != tip.Example) {
+				// Report.
+				t.Errorf("figure %q differs from its help bubble", r.Figure)
+			} // end of the bubble check
+		} // end of the row loop
+	} // end of the part loop
+	// Every main figure of the Performance page is in the guide.
+	for _, want := range []string{"Answer speed", "Prompt reading speed", "Time to first word", "Total time", "Load time", "Processor split", "Memory used", "Embedding time", "Vector length", "Tokens counted", "Change since the previous run", "Other models loaded", "CPU load", "Swap in use", "GPU"} {
+		// Look for it.
+		found := false
+		// Each part and row.
+		for _, part := range parts {
+			// Each row.
+			for _, r := range part.Rows {
+				// A match.
+				if r.Figure == want {
+					// Found.
+					found = true
+				} // end of the match
+			} // end of the row loop
+		} // end of the part loop
+		// It must be there.
+		if !found {
+			// Report.
+			t.Errorf("the guide does not explain %q", want)
+		} // end of the found check
+	} // end of the figure loop
+	// The page.
+	rig := newThemeRig(t)
+	// Without a request, every topic is closed and the guide is drawn as tables.
+	_, _, body := get(t, rig.h, http.MethodGet, "/help")
+	// No open topic, and one table row per figure.
+	if strings.Contains(body, `" open>`) || strings.Count(body, `<td data-label="What it tells you">`) != rows {
+		// Report.
+		t.Errorf("closed page: open topic found or %d figure rows, want %d", strings.Count(body, `<td data-label="What it tells you">`), rows)
+	} // end of the closed check
+	// Asked for the guide: only the guide is open.
+	_, _, body = get(t, rig.h, http.MethodGet, "/help?topic="+helpPerfGuideID)
+	// Exactly one open topic, and it is the guide.
+	if strings.Count(body, `" open>`) != 1 || !strings.Contains(body, `<details class="helptopic" id="`+helpPerfGuideID+`" open>`) {
+		// Report.
+		t.Error("the guide is not the one open topic when asked for")
+	} // end of the open check
+	// An unknown name opens nothing and is not written into the page.
+	_, _, body = get(t, rig.h, http.MethodGet, "/help?topic=%3Cb%3Enope")
+	// Nothing open, nothing echoed.
+	if strings.Contains(body, `" open>`) || strings.Contains(body, "nope") {
+		// Report.
+		t.Error("an unknown topic name opened a topic or was echoed")
+	} // end of the unknown check
+	// The link that the Performance and Compare pages carry.
+	link := `href="/help?topic=` + helpPerfGuideID + `#` + helpPerfGuideID + `">How to read these results</a>`
+	// Both templates carry it.
+	for name, text := range map[string]string{"performance": performanceTemplateText, "compare": compareTemplateText} {
+		// Look for it.
+		if !strings.Contains(text, link) {
+			// Report.
+			t.Errorf("the %s page has no link to the guide", name)
+		} // end of the link check
+	} // end of the template loop
+} // end of TestHelpPerformanceGuide
diff --git a/scripts/test-smoke-load.sh b/scripts/test-smoke-load.sh
index d580241..4f3f457 100644
--- a/scripts/test-smoke-load.sh
+++ b/scripts/test-smoke-load.sh
@@ -166,10 +166,10 @@ page_check "monitor (home) page" / 200 text/html "LLMsControlDock"
 page_check "About page" /about 200 text/html "About LLMsControlDock"
 # The Help page.
 page_check "Help page" /help 200 text/html "Help"
-# The Help page must carry all eleven topics.
+# The Help page must carry all twelve topics.
 TOPICS="$(grep -o '<details class="helptopic"' "$WORK/body" | wc -l)"
 # Count them.
-if [ "$TOPICS" = "11" ]; then ok "Help page has 11 topics"; else bad "Help page has 11 topics" "found $TOPICS"; fi
+if [ "$TOPICS" = "12" ]; then ok "Help page has 12 topics"; else bad "Help page has 12 topics" "found $TOPICS"; fi
 # The Settings page.
 page_check "Settings page" /settings 200 text/html "Settings"
 # The Find LLM page (only the choices; this does not search the internet).
diff --git a/web/app.css b/web/app.css
index 9f7693a..2103859 100644
--- a/web/app.css
+++ b/web/app.css
@@ -3069,6 +3069,14 @@ details.helptopic[open] {
   border-left-color: var(--cat-accent);
 } /* end of rule */
 
+/* The reading guide of the Help page: its tables fill the width, and a little space separates the parts. */
+.helpguide table {
+  /* As wide as the topic. */
+  width: 100%;
+  /* Space under each table. */
+  margin-bottom: 1rem;
+} /* end of rule */
+
 /* The swimlane picture: as wide as the card, never wider, so the page does not scroll sideways. */
 .swimlane {
   /* Full width of the card. */
diff --git a/web/compare.html b/web/compare.html
index 6411621..d73527c 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -33,6 +33,7 @@
 <form method="post" action="/compare/pdf"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Save this comparison as PDF</button></form>
 <form method="post" action="/compare/csv"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Save the data as CSV</button></form>
 <a class="btn-plain" href="#how">How and why this was done</a>
+<a class="btn-plain" href="/help?topic=read-performance#read-performance">How to read these results</a>
 </div>
 {{/* What the figures say, in plain words. */}}
 <h2>What the figures say</h2>
diff --git a/web/help.html b/web/help.html
index d7a0b45..23ef9d8 100644
--- a/web/help.html
+++ b/web/help.html
@@ -26,13 +26,29 @@
 {{/* The topics; each one starts closed and opens when its title is clicked (no script is needed). */}}
 {{range $t := .Topics}}
 {{/* One topic. */}}
-<details class="helptopic" id="{{.ID}}">
+<details class="helptopic" id="{{.ID}}"{{if .Open}} open{{end}}>
 {{/* Its heading, which is also the button that opens it. */}}
 <summary class="helpsum"><h2 id="{{.ID}}-title">{{.Title}}</h2></summary>
 {{/* A button that collapses the open topic again; it is hidden until the small script file shows it, because it does nothing without the script. */}}
 <p class="helpback"><span class="tipbox backhere"><button type="button" class="backcircle helpclose" hidden aria-label="Collapse this topic" aria-describedby="tipclose-{{$t.ID}}-top"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15l6-6 6 6"/></svg></button><span class="tip tip-icon" role="tooltip" id="tipclose-{{$t.ID}}-top">Collapse this topic</span></span></p>
 {{/* The plain introduction. */}}
 <p>{{.Intro}}</p>
+{{/* A reading guide: its parts, each with a paragraph and a table of figures (the table becomes small cards on a narrow screen). */}}
+{{if .Guide}}
+<div class="helpguide">
+{{range .Guide}}
+{{/* One part. */}}
+<h3>{{.Heading}}</h3>
+<p>{{.Text}}</p>
+{{if .Rows}}<table class="settingtable">
+<thead><tr><th scope="col">Figure</th><th scope="col">What it tells you</th><th scope="col">Better when</th><th scope="col">Example</th></tr></thead>
+<tbody>
+{{range .Rows}}<tr><th scope="row">{{.Figure}}</th><td data-label="What it tells you">{{.Means}}</td><td data-label="Better when">{{.Better}}</td><td data-label="Example">{{.Example}}</td></tr>
+{{end}}</tbody>
+</table>{{end}}
+{{end}}
+</div>
+{{else}}
 {{/* The picture; its name and description are read by screen readers, and the numbered list below says the same in words. */}}
 <svg class="swimlane" viewBox="0 0 {{.Width}} {{.Height}}" role="img" aria-labelledby="{{.ID}}-svgtitle {{.ID}}-svgdesc" focusable="false">
 <title id="{{.ID}}-svgtitle">{{.Title}}</title>
@@ -58,6 +74,8 @@
 <ol class="helpsteps">
 {{range .List}}<li><strong>{{.Lane}}:</strong> {{.Text}}</li>
 {{end}}</ol>
+{{/* End of the diagram or guide choice. */}}
+{{end}}
 {{/* The same button at the bottom of the open topic, because the pictures are long. */}}
 <p class="helpback"><span class="tipbox backhere"><button type="button" class="backcircle helpclose" hidden aria-label="Collapse this topic" aria-describedby="tipclose-{{$t.ID}}-bottom"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15l6-6 6 6"/></svg></button><span class="tip tip-icon" role="tooltip" id="tipclose-{{$t.ID}}-bottom">Collapse this topic</span></span></p>
 {{/* End of the topic. */}}
diff --git a/web/performance.html b/web/performance.html
index 61750e5..e954565 100644
--- a/web/performance.html
+++ b/web/performance.html
@@ -159,6 +159,8 @@
 {{if .LeftLoaded}}
 <p class="warn" role="alert"><strong>⚠ The model could not be unloaded again.</strong> It is still in memory; use the Unload button on the monitor page.</p>
 {{end}}
+{{/* The way to the reading guide on the Help page, opened at the right topic. */}}
+<p><a class="btn-plain" href="/help?topic=read-performance#read-performance">How to read these results</a></p>
 {{/* The four tables. */}}
 {{range .Groups}}{{template "perfgroup" .}}{{end}}
 {{/* The saved tests, with the clear button. */}}
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
echo "NEXT  start bin/LLMsControlDock and run a performance test and press How to read these results (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
