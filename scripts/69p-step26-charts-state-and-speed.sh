#!/usr/bin/env bash
# Script 69p: F8 part 1, the Charts box inside Monitoring details. It shows a summary (share of checks answered, failures), a state bar (one block per half minute, hatched when a check failed) and an answer-time line chart for the last 30 minutes, each with a text alternative, plus a link-driven table of the newest checks. The monitor now asks Ollama by itself every 10 seconds in the background, so the charts and the failed-check counters have no gaps while the page is closed. History lives in memory (at most 400 checks). Version 0.19.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/charts-state" ] || { echo "FAIL  not on feature/charts-state"; exit 1; }
# Script 69o (monitoring details twistie) must be applied already (merged into main).
[ -e details.go ] || { echo "FAIL  script 69o was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e monitor.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index f40bccc..b74b13f 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.18.0"
+const appVersion = "0.19.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/charts.go b/charts.go
new file mode 100644
index 0000000..cb9fd6d
--- /dev/null
+++ b/charts.go
@@ -0,0 +1,360 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds the texts.
+	"fmt"
+	// strconv writes the percentage without locale surprises.
+	"strconv"
+	// strings joins the points of a line.
+	"strings"
+	// time gives the moments and lengths.
+	"time"
+) // end of imports
+
+// chartTimeLayout writes a moment on an axis; it always carries the time zone name, as every time on every page does.
+const chartTimeLayout = "15:04 MST"
+
+// chartRowLayout writes a moment in the table of numbers, with the zone name.
+const chartRowLayout = "15:04:05 MST"
+
+// chartLastFailureLayout writes the moment of the last failure, with the zone name.
+const chartLastFailureLayout = "15:04:05 MST"
+
+// stateCells is how many blocks the state bar has: 60 blocks of 30 seconds make 30 minutes.
+const stateCells = 60
+
+// chartWidth is the drawing width, in drawing units; the picture scales to the box.
+const chartWidth = 600
+
+// chartHeight is the height of the answer-time drawing.
+const chartHeight = 120
+
+// cellHeight is the height of the state bar.
+const cellHeight = 24
+
+// chartPad keeps lines and dots off the edge of the drawing.
+const chartPad = 6
+
+// numbersRows is how many checks the table of numbers lists.
+const numbersRows = 20
+
+// chartGap is the longest pause between two checks that still joins them into one line; a longer pause breaks the line.
+const chartGap = 3 * sampleEvery
+
+// chartCell is one block of the state bar.
+type chartCell struct {
+	// X is the left edge in drawing units.
+	X int
+	// Class is ok (all checks answered), bad (a check failed) or none (no check in this block).
+	Class string
+} // end of chartCell
+
+// chartDot is one answered check on the answer-time chart.
+type chartDot struct {
+	// X and Y are drawing units.
+	X, Y string
+} // end of chartDot
+
+// chartRow is one line of the table of numbers.
+type chartRow struct {
+	// Time is the moment of the check, with its zone name.
+	Time string
+	// Online is true when Ollama answered.
+	Online bool
+	// Answer is the time the answer took, or a dash.
+	Answer string
+} // end of chartRow
+
+// chartsView is what the Charts box shows.
+type chartsView struct {
+	// WindowText is the length of history shown, in words.
+	WindowText string
+	// EverySeconds is the interval of the checks.
+	EverySeconds int
+	// Background is true when the checks run by themselves.
+	Background bool
+	// Summary is the one-sentence summary of the window.
+	Summary string
+	// HasFailure is true when the window holds a failed check, so the summary gets a warning sign.
+	HasFailure bool
+	// Cells are the blocks of the state bar.
+	Cells []chartCell
+	// CellWidth is the width of one block, in drawing units.
+	CellWidth int
+	// CellHeight is the height of the state bar.
+	CellHeight int
+	// StateAlt is the text alternative of the state bar.
+	StateAlt string
+	// Width and Height are the size of the answer-time drawing.
+	Width, Height int
+	// Segments are the lines of the answer-time chart, each a list of points.
+	Segments []string
+	// Dots are the answered checks.
+	Dots []chartDot
+	// BaseY is the vertical position of the zero line.
+	BaseY int
+	// AnswerAlt is the text alternative of the answer-time chart.
+	AnswerAlt string
+	// StartLabel, MidLabel and EndLabel are the times under the chart.
+	StartLabel, MidLabel, EndLabel string
+	// Rows are the newest checks for the table of numbers, newest first; empty unless the table is open.
+	Rows []chartRow
+	// NumbersOpen is true when the table of numbers is open.
+	NumbersOpen bool
+	// HasData is true when the window holds at least one check.
+	HasData bool
+} // end of chartsView
+
+// niceMax returns the first round number that is at least v, so the scale has tidy ends.
+func niceMax(v int64) int64 {
+	// The scale of round numbers.
+	for _, step := range []int64{10, 20, 50} {
+		// Big enough.
+		if v <= step {
+			// This one.
+			return step
+		} // end of the check
+	} // end of the loop
+	// Above 50: 100, 200, 500, 1000, and so on.
+	for base := int64(100); ; base *= 10 {
+		// The three round numbers of this size.
+		for _, m := range []int64{1, 2, 5} {
+			// Big enough.
+			if v <= base*m {
+				// This one.
+				return base * m
+			} // end of the check
+		} // end of the loop
+	} // end of the loop
+} // end of niceMax
+
+// windowWords writes a duration of whole minutes in words.
+func windowWords(d time.Duration) string {
+	// Whole minutes.
+	m := int(d / time.Minute)
+	// One minute is singular.
+	if m == 1 {
+		// Singular.
+		return "1 minute"
+	} // end of the singular case
+	// Plural.
+	return fmt.Sprintf("%d minutes", m)
+} // end of windowWords
+
+// watchedFor writes how long the monitor has been watching, in minutes and seconds.
+func watchedFor(d time.Duration) string {
+	// Whole seconds.
+	sec := int(d / time.Second)
+	// Under a minute.
+	if sec < 60 {
+		// Seconds only.
+		return fmt.Sprintf("%d s", sec)
+	} // end of the short case
+	// Minutes and seconds.
+	return fmt.Sprintf("%d min %d s", sec/60, sec%60)
+} // end of watchedFor
+
+// buildCharts turns the checks of the last window into what the page draws.
+func buildCharts(samples []sample, now time.Time, background, numbersOpen bool) chartsView {
+	// The start of the window.
+	start := now.Add(-chartWindow)
+	// The basic fields.
+	v := chartsView{WindowText: windowWords(chartWindow), EverySeconds: int(sampleEvery / time.Second), Background: background, NumbersOpen: numbersOpen,
+		CellHeight: cellHeight, Width: chartWidth, Height: chartHeight, BaseY: chartHeight - chartPad,
+		StartLabel: start.Format(chartTimeLayout), MidLabel: start.Add(chartWindow / 2).Format(chartTimeLayout), EndLabel: now.Format(chartTimeLayout)}
+	// The width of one block, leaving a one-unit gap.
+	v.CellWidth = chartWidth/stateCells - 1
+	// Only the checks inside the window count.
+	var in []sample
+	// Pick them.
+	for _, s := range samples {
+		// Inside the window.
+		if !s.At.Before(start) && !s.At.After(now) {
+			// Keep it.
+			in = append(in, s)
+		} // end of the window check
+	} // end of the loop
+	// The blocks start as empty.
+	classes := make([]string, stateCells)
+	// Every block is "none" until a check lands in it.
+	for i := range classes {
+		// No data.
+		classes[i] = "none"
+	} // end of the loop
+	// Counts for the summary.
+	failed, answered := 0, 0
+	// The last failure.
+	var lastFail time.Time
+	// The answer times of answered checks.
+	var lo, hi, last int64
+	// Walk the checks.
+	for _, s := range in {
+		// The block of this check.
+		i := int(s.At.Sub(start) * stateCells / chartWindow)
+		// The very end belongs to the last block.
+		if i >= stateCells {
+			// Clamp.
+			i = stateCells - 1
+		} // end of the clamp
+		// A failure marks the block bad; an answer marks it ok only when it is still empty.
+		if !s.Online {
+			// Bad.
+			classes[i] = "bad"
+			// Count it.
+			failed++
+			// Remember when.
+			lastFail = s.At
+		} else {
+			// Answered; a block that already failed stays bad.
+			if classes[i] == "none" {
+				// Ok.
+				classes[i] = "ok"
+			} // end of the empty check
+			// The lowest, highest and latest answer times.
+			if answered == 0 || s.Ms < lo {
+				// A new lowest.
+				lo = s.Ms
+			} // end of the lowest check
+			// The highest.
+			if s.Ms > hi {
+				// A new highest.
+				hi = s.Ms
+			} // end of the highest check
+			// The latest.
+			last = s.Ms
+			// One more answer.
+			answered++
+		} // end of the online check
+	} // end of the loop
+	// Draw the blocks.
+	okN, badN, noneN := 0, 0, 0
+	// One block at a time.
+	for i, c := range classes {
+		// Its place.
+		v.Cells = append(v.Cells, chartCell{X: i * (chartWidth / stateCells), Class: c})
+		// Count it for the text alternative.
+		switch c {
+		// Answered.
+		case "ok":
+			// Count.
+			okN++
+		// Failed.
+		case "bad":
+			// Count.
+			badN++
+		// Empty.
+		default:
+			// Count.
+			noneN++
+		} // end of the switch
+	} // end of the loop
+	// The text alternative of the state bar.
+	v.StateAlt = fmt.Sprintf("State of Ollama in the last %s, in %d blocks of 30 seconds: %d blocks answered, %d blocks had a failed check, %d blocks have no check yet.", v.WindowText, stateCells, okN, badN, noneN)
+	// Nothing measured yet.
+	if len(in) == 0 {
+		// Say so; the charts stay empty.
+		v.Summary = "No checks yet in the last " + v.WindowText + "."
+		// Hand it back.
+		v.AnswerAlt = "No answer times yet."
+		// Done.
+		return v
+	} // end of the empty case
+	// There is data.
+	v.HasData = true
+	// The percentage of checks that answered.
+	pct := float64(len(in)-failed) * 100 / float64(len(in))
+	// One decimal, or none at exactly 100.
+	pctText := strconv.FormatFloat(pct, 'f', 1, 64)
+	// All answered.
+	if failed == 0 {
+		// No decimal.
+		pctText = "100"
+	} // end of the full-score check
+	// The summary sentence.
+	v.Summary = fmt.Sprintf("Ollama answered %s %% of %d checks in the last %s; %d failed.", pctText, len(in), v.WindowText, failed)
+	// A failure adds its moment and the warning sign.
+	if failed > 0 {
+		// The warning.
+		v.HasFailure = true
+		// The moment.
+		v.Summary += " Last failure at " + lastFail.Format(chartLastFailureLayout) + "."
+	} // end of the failure check
+	// A young monitor says how long it has been watching.
+	if watched := now.Sub(in[0].At); watched < chartWindow-time.Minute {
+		// The note.
+		v.Summary += " Watching for " + watchedFor(watched) + " so far."
+	} // end of the young check
+	// The scale of the answer-time chart.
+	top := niceMax(hi)
+	// The drawing height inside the padding.
+	usable := float64(chartHeight - 2*chartPad)
+	// The lines are broken at failures and long pauses.
+	var cur []string
+	// The time of the previous answered check.
+	var prev time.Time
+	// Close the current line.
+	flush := func() {
+		// A line needs two points.
+		if len(cur) >= 2 {
+			// Keep it.
+			v.Segments = append(v.Segments, strings.Join(cur, " "))
+		} // end of the length check
+		// Start a new one.
+		cur = nil
+	} // end of flush
+	// Walk the checks again.
+	for _, s := range in {
+		// A failure breaks the line.
+		if !s.Online {
+			// End the line.
+			flush()
+			// Next check.
+			continue
+		} // end of the failure check
+		// A long pause breaks the line too.
+		if !prev.IsZero() && s.At.Sub(prev) > chartGap {
+			// End the line.
+			flush()
+		} // end of the pause check
+		// The position.
+		x := float64(s.At.Sub(start)) / float64(chartWindow) * chartWidth
+		// Zero at the bottom, the top of the scale at the top.
+		y := float64(chartHeight-chartPad) - float64(s.Ms)/float64(top)*usable
+		// The text of the point.
+		px, py := strconv.FormatFloat(x, 'f', 1, 64), strconv.FormatFloat(y, 'f', 1, 64)
+		// Add the point to the line and the dot to the dots.
+		cur = append(cur, px+","+py)
+		// The dot.
+		v.Dots = append(v.Dots, chartDot{X: px, Y: py})
+		// Remember the time.
+		prev = s.At
+	} // end of the loop
+	// Close the last line.
+	flush()
+	// The text alternative of the answer-time chart.
+	if answered == 0 {
+		// No answers.
+		v.AnswerAlt = "No answer times: Ollama did not answer in the last " + v.WindowText + "."
+	} else {
+		// The numbers.
+		v.AnswerAlt = fmt.Sprintf("Answer time of Ollama's status check in the last %s, scale 0 to %d ms: lowest %d ms, highest %d ms, latest %d ms.", v.WindowText, top, lo, hi, last)
+	} // end of the answers check
+	// The table of numbers is built only when it is open.
+	if numbersOpen {
+		// The newest first.
+		for i := len(in) - 1; i >= 0 && len(v.Rows) < numbersRows; i-- {
+			// The answer text.
+			ans := "-"
+			// Only an answer has a time.
+			if in[i].Online {
+				// Write it.
+				ans = fmt.Sprintf("%d ms", in[i].Ms)
+			} // end of the answer check
+			// Add the row.
+			v.Rows = append(v.Rows, chartRow{Time: in[i].At.Format(chartRowLayout), Online: in[i].Online, Answer: ans})
+		} // end of the loop
+	} // end of the table
+	// Hand it back.
+	return v
+} // end of buildCharts
diff --git a/charts_test.go b/charts_test.go
new file mode 100644
index 0000000..bda5f43
--- /dev/null
+++ b/charts_test.go
@@ -0,0 +1,233 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// strconv reads the coordinates back.
+	"strconv"
+	// strings searches the text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time builds the moments.
+	"time"
+) // end of imports
+
+// chartNow is the moment the chart tests treat as now: 31 October 2026, 17:45:00 CET.
+func chartNow() time.Time {
+	// The moment.
+	return at(17, 45, 0)
+} // end of chartNow
+
+// every builds n answered checks, one every 10 seconds, the last one at now, each taking ms milliseconds.
+func every(n int, ms int64) []sample {
+	// The list.
+	var out []sample
+	// Oldest first.
+	for i := n - 1; i >= 0; i-- {
+		// One check.
+		out = append(out, sample{At: chartNow().Add(-time.Duration(i) * 10 * time.Second), Online: true, Ms: ms})
+	} // end of the loop
+	// Hand it back.
+	return out
+} // end of every
+
+// TestChartsEmpty checks the box before any check was made.
+func TestChartsEmpty(t *testing.T) {
+	// Build with nothing.
+	v := buildCharts(nil, chartNow(), true, false)
+	// No data, a plain sentence, and a full bar of empty blocks.
+	if v.HasData || v.Summary != "No checks yet in the last 30 minutes." || len(v.Cells) != stateCells || len(v.Dots) != 0 || len(v.Segments) != 0 {
+		// Report it.
+		t.Errorf("empty view wrong: %+v", v.Summary)
+	} // end of the check
+	// Every block is empty.
+	for _, c := range v.Cells {
+		// Empty.
+		if c.Class != "none" {
+			// Report it.
+			t.Fatalf("a block of an empty chart is %q", c.Class)
+		} // end of the check
+	} // end of the loop
+} // end of TestChartsEmpty
+
+// TestChartsAllAnswered checks the summary when nothing failed: 100 without a decimal, no failure, no warning.
+func TestChartsAllAnswered(t *testing.T) {
+	// 180 checks fill the window.
+	v := buildCharts(every(180, 20), chartNow(), true, false)
+	// The sentence.
+	if v.Summary != "Ollama answered 100 % of 180 checks in the last 30 minutes; 0 failed." || v.HasFailure {
+		// Report it.
+		t.Errorf("summary wrong: %q", v.Summary)
+	} // end of the check
+	// One unbroken line and a dot for every check.
+	if len(v.Segments) != 1 || len(v.Dots) != 180 {
+		// Report it.
+		t.Errorf("%d lines, %d dots", len(v.Segments), len(v.Dots))
+	} // end of the check
+	// The text alternative says what the chart shows.
+	if !strings.Contains(v.AnswerAlt, "scale 0 to 20 ms: lowest 20 ms, highest 20 ms, latest 20 ms") {
+		// Report it.
+		t.Errorf("alt wrong: %q", v.AnswerAlt)
+	} // end of the check
+} // end of TestChartsAllAnswered
+
+// TestChartsFailureBreaksTheLine checks a failed check: the percentage, the moment, the hatched block and the broken line.
+func TestChartsFailureBreaksTheLine(t *testing.T) {
+	// 20 checks, the 10th failed.
+	s := every(20, 30)
+	// The failure.
+	s[9].Online, s[9].Ms = false, 5
+	// Build.
+	v := buildCharts(s, chartNow(), false, false)
+	// The summary names the failure and its moment, with the zone.
+	for _, w := range []string{"Ollama answered 95.0 % of 20 checks", "1 failed.", "Last failure at 17:43:20 CET."} {
+		// Look for it.
+		if !strings.Contains(v.Summary, w) {
+			// Report it.
+			t.Errorf("summary lacks %q: %q", w, v.Summary)
+		} // end of the check
+	} // end of the loop
+	// The warning sign shows, and the line is in two parts.
+	if !v.HasFailure || len(v.Segments) != 2 || len(v.Dots) != 19 {
+		// Report it.
+		t.Errorf("failure %v, %d lines, %d dots", v.HasFailure, len(v.Segments), len(v.Dots))
+	} // end of the check
+	// One block is hatched.
+	bad := 0
+	// Count them.
+	for _, c := range v.Cells {
+		// A failed block.
+		if c.Class == "bad" {
+			// Count.
+			bad++
+		} // end of the check
+	} // end of the loop
+	// Exactly one.
+	if bad != 1 {
+		// Report it.
+		t.Errorf("%d hatched blocks, want 1", bad)
+	} // end of the check
+	// The text alternative of the bar counts it.
+	if !strings.Contains(v.StateAlt, "1 blocks had a failed check") {
+		// Report it.
+		t.Errorf("state alt wrong: %q", v.StateAlt)
+	} // end of the check
+	// A young monitor says how long it has watched: 190 seconds.
+	if !strings.Contains(v.Summary, "Watching for 3 min 10 s so far.") {
+		// Report it.
+		t.Errorf("no young-monitor note: %q", v.Summary)
+	} // end of the check
+} // end of TestChartsFailureBreaksTheLine
+
+// TestChartsWindowEdges checks that checks outside the window are ignored.
+func TestChartsWindowEdges(t *testing.T) {
+	// One too old, one inside, one in the future.
+	s := []sample{
+		{At: chartNow().Add(-31 * time.Minute), Online: true, Ms: 99},
+		{At: chartNow().Add(-1 * time.Minute), Online: true, Ms: 10},
+		{At: chartNow().Add(time.Minute), Online: false, Ms: 1},
+	}
+	// Build.
+	v := buildCharts(s, chartNow(), true, false)
+	// Only the middle one counts.
+	if !strings.Contains(v.Summary, "100 % of 1 checks") || len(v.Dots) != 1 {
+		// Report it.
+		t.Errorf("edges wrong: %q, %d dots", v.Summary, len(v.Dots))
+	} // end of the check
+} // end of TestChartsWindowEdges
+
+// TestChartsLongPauseBreaksTheLine checks that two answers far apart are not joined by a line.
+func TestChartsLongPauseBreaksTheLine(t *testing.T) {
+	// Two answers a minute apart.
+	s := []sample{{At: chartNow().Add(-60 * time.Second), Online: true, Ms: 10}, {At: chartNow(), Online: true, Ms: 12}}
+	// Build.
+	v := buildCharts(s, chartNow(), false, false)
+	// Two dots and no line.
+	if len(v.Dots) != 2 || len(v.Segments) != 0 {
+		// Report it.
+		t.Errorf("%d dots, %d lines", len(v.Dots), len(v.Segments))
+	} // end of the check
+} // end of TestChartsLongPauseBreaksTheLine
+
+// TestChartsDotsStayInsideTheDrawing checks every coordinate lies inside the drawing, even for a huge answer time.
+func TestChartsDotsStayInsideTheDrawing(t *testing.T) {
+	// A normal one, a zero, and a huge one.
+	s := every(3, 10)
+	// The values.
+	s[0].Ms, s[1].Ms, s[2].Ms = 0, 7, 123456
+	// Build.
+	v := buildCharts(s, chartNow(), true, false)
+	// Check every dot.
+	for _, d := range v.Dots {
+		// The numbers.
+		x, errX := strconv.ParseFloat(d.X, 64)
+		// The other number.
+		y, errY := strconv.ParseFloat(d.Y, 64)
+		// They must read as numbers and lie inside.
+		if errX != nil || errY != nil || x < 0 || x > chartWidth || y < chartPad || y > chartHeight-chartPad {
+			// Report it.
+			t.Errorf("dot %s,%s is outside the drawing", d.X, d.Y)
+		} // end of the check
+	} // end of the loop
+	// The scale rounds up to a tidy number.
+	if !strings.Contains(v.AnswerAlt, "scale 0 to 200000 ms") {
+		// Report it.
+		t.Errorf("scale wrong: %q", v.AnswerAlt)
+	} // end of the check
+} // end of TestChartsDotsStayInsideTheDrawing
+
+// TestNiceMax checks the round numbers of the scale.
+func TestNiceMax(t *testing.T) {
+	// Input and expected.
+	for in, want := range map[int64]int64{0: 10, 10: 10, 11: 20, 20: 20, 21: 50, 50: 50, 51: 100, 101: 200, 201: 500, 501: 1000, 1001: 2000, 5001: 10000} {
+		// Compare.
+		if got := niceMax(in); got != want {
+			// Report it.
+			t.Errorf("niceMax(%d) = %d, want %d", in, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestNiceMax
+
+// TestChartsRowsOnlyWhenOpen checks the table of numbers: absent when closed; newest first, limited and with dashes when open.
+func TestChartsRowsOnlyWhenOpen(t *testing.T) {
+	// 30 checks, the newest failed.
+	s := every(30, 15)
+	// The newest failed.
+	s[29].Online = false
+	// Closed: no rows.
+	if v := buildCharts(s, chartNow(), true, false); len(v.Rows) != 0 {
+		// Report it.
+		t.Errorf("%d rows while closed", len(v.Rows))
+	} // end of the closed check
+	// Open.
+	v := buildCharts(s, chartNow(), true, true)
+	// Limited to the newest rows.
+	if len(v.Rows) != numbersRows {
+		// Report it.
+		t.Fatalf("%d rows, want %d", len(v.Rows), numbersRows)
+	} // end of the limit check
+	// The newest first: the failed check, with a dash and the zone name.
+	if v.Rows[0].Online || v.Rows[0].Answer != "-" || v.Rows[0].Time != "17:45:00 CET" || v.Rows[1].Answer != "15 ms" {
+		// Report it.
+		t.Errorf("rows wrong: %+v %+v", v.Rows[0], v.Rows[1])
+	} // end of the order check
+} // end of TestChartsRowsOnlyWhenOpen
+
+// TestChartsTimesCarryTheZone checks every time on the chart names its zone.
+func TestChartsTimesCarryTheZone(t *testing.T) {
+	// Build.
+	v := buildCharts(every(5, 10), chartNow(), true, false)
+	// Every label.
+	for _, l := range []string{v.StartLabel, v.MidLabel, v.EndLabel} {
+		// It must end with the zone name.
+		if !strings.HasSuffix(l, " CET") {
+			// Report it.
+			t.Errorf("label %q has no zone name", l)
+		} // end of the check
+	} // end of the loop
+	// The labels themselves.
+	if v.StartLabel != "17:15 CET" || v.MidLabel != "17:30 CET" || v.EndLabel != "17:45 CET" {
+		// Report it.
+		t.Errorf("labels %q %q %q", v.StartLabel, v.MidLabel, v.EndLabel)
+	} // end of the label check
+} // end of TestChartsTimesCarryTheZone
diff --git a/health.go b/health.go
index 813e0d1..0b3a39c 100644
--- a/health.go
+++ b/health.go
@@ -54,6 +54,22 @@ func (h *apiHealth) record(online bool, now time.Time) healthView {
 		// One more in total.
 		h.failedTotal++
 	} // end of the online check
+	// What the page shows.
+	return h.viewLocked()
+} // end of record
+
+// view returns what the page shows now, without counting a check.
+func (h *apiHealth) view() healthView {
+	// One request at a time.
+	h.mu.Lock()
+	// Release at the end.
+	defer h.mu.Unlock()
+	// What the page shows.
+	return h.viewLocked()
+} // end of view
+
+// viewLocked builds the view; the caller holds the lock.
+func (h *apiHealth) viewLocked() healthView {
 	// The text for the last good check.
 	last := healthNever
 	// There was one.
@@ -63,4 +79,4 @@ func (h *apiHealth) record(online bool, now time.Time) healthView {
 	} // end of the last-check text
 	// What the page shows.
 	return healthView{FailedRow: h.failedRow, FailedTotal: h.failedTotal, LastOK: last}
-} // end of record
+} // end of viewLocked
diff --git a/main.go b/main.go
index 140e849..2266789 100644
--- a/main.go
+++ b/main.go
@@ -132,7 +132,12 @@ func main() {
 
 	// Describe the web server: Addr is where to listen (the star reads the flag's value), Handler is the web interface from web.go wrapped in the Host-name check from guard.go,
 	// and ReadHeaderTimeout drops clients that take more than 5 seconds to send their request headers.
-	server := &http.Server{Addr: *listen, Handler: hostGuard(newWebHandler(addr, defaultCheckTimeout), *listen), ReadHeaderTimeout: 5 * time.Second}
+	// The monitor holds the counters and the history of checks; it asks Ollama in the background every sampleEvery, so the charts have no gaps while the page is closed.
+	mon := newMonitor()
+	// Start the background checks; they end with the program.
+	mon.start(context.Background(), addr.URL, defaultCheckTimeout, sampleEvery)
+	// The server, with the monitor built into the web interface.
+	server := &http.Server{Addr: *listen, Handler: hostGuard(newWebHandlerWith(addr, defaultCheckTimeout, mon), *listen), ReadHeaderTimeout: 5 * time.Second}
 
 	// Tell the person which address we are about to serve on.
 	log.Printf("OllamaControlCenter listening on http://%s (press Ctrl+C to stop)", *listen)
diff --git a/monitor.go b/monitor.go
new file mode 100644
index 0000000..598b088
--- /dev/null
+++ b/monitor.go
@@ -0,0 +1,157 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context stops the background checks when the program ends.
+	"context"
+	// net/url holds the Ollama address.
+	"net/url"
+	// sync protects the history from two writers at once.
+	"sync"
+	// sync/atomic holds the flag that says a background check is running.
+	"sync/atomic"
+	// time gives the moments and the interval.
+	"time"
+) // end of imports
+
+// sampleEvery is how often the background check asks Ollama whether it answers.
+const sampleEvery = 10 * time.Second
+
+// chartWindow is how much history the charts show and keep.
+const chartWindow = 30 * time.Minute
+
+// maxSamples is the most checks kept in memory, whatever the interval, so memory use has a ceiling.
+const maxSamples = 400
+
+// sample is one check of Ollama: when it was made, whether Ollama answered, and how long the answer took.
+type sample struct {
+	// At is the moment of the check.
+	At time.Time
+	// Online is true when Ollama answered correctly.
+	Online bool
+	// Ms is the time the check took, in milliseconds.
+	Ms int64
+} // end of sample
+
+// sampleHistory keeps the newest checks in memory only; it holds no text of prompts or answers.
+type sampleHistory struct {
+	// mu protects the list below.
+	mu sync.Mutex
+	// items are the checks, oldest first.
+	items []sample
+} // end of sampleHistory
+
+// add keeps one more check and forgets the ones that are too old or beyond the ceiling.
+func (h *sampleHistory) add(s sample) {
+	// One writer at a time.
+	h.mu.Lock()
+	// Release at the end.
+	defer h.mu.Unlock()
+	// Add the new check at the end.
+	h.items = append(h.items, s)
+	// Anything older than the window plus a minute of slack is no longer shown, so it goes.
+	cut := s.At.Add(-(chartWindow + time.Minute))
+	// Count the old ones at the front.
+	drop := 0
+	// The list is oldest first, so stop at the first one that is recent enough.
+	for drop < len(h.items) && h.items[drop].At.Before(cut) {
+		// One more to drop.
+		drop++
+	} // end of the loop
+	// The ceiling: drop the oldest when there are too many.
+	if over := len(h.items) - drop - maxSamples; over > 0 {
+		// Drop those too.
+		drop += over
+	} // end of the ceiling check
+	// Forget them, copying so the old memory can be released.
+	if drop > 0 {
+		// The kept part.
+		h.items = append([]sample(nil), h.items[drop:]...)
+	} // end of the drop
+} // end of add
+
+// since returns a copy of the checks made at or after the given moment, oldest first.
+func (h *sampleHistory) since(from time.Time) []sample {
+	// One reader at a time.
+	h.mu.Lock()
+	// Release at the end.
+	defer h.mu.Unlock()
+	// The copy.
+	var out []sample
+	// Pick the recent ones.
+	for _, s := range h.items {
+		// Recent enough.
+		if !s.At.Before(from) {
+			// Keep it.
+			out = append(out, s)
+		} // end of the age check
+	} // end of the loop
+	// Hand them back.
+	return out
+} // end of since
+
+// monitor holds what the page shows about Ollama's health: the counters and the history of checks.
+type monitor struct {
+	// health counts the failed checks (the API health box).
+	health *apiHealth
+	// hist keeps the checks for the charts.
+	hist *sampleHistory
+	// background is true while a background check runs; the page then does not count its own checks.
+	background atomic.Bool
+} // end of monitor
+
+// newMonitor builds an empty monitor.
+func newMonitor() *monitor {
+	// Empty counters and an empty history.
+	return &monitor{health: &apiHealth{}, hist: &sampleHistory{}}
+} // end of newMonitor
+
+// record counts one check in the counters and in the history.
+func (m *monitor) record(res checkResult, now time.Time) {
+	// The counters of the API health box.
+	m.health.record(res.Online, now)
+	// The history for the charts.
+	m.hist.add(sample{At: now, Online: res.Online, Ms: res.Elapsed.Milliseconds()})
+} // end of record
+
+// pageCheck is called by the page for its own check: it counts the check only when no background check runs, and returns the counters.
+func (m *monitor) pageCheck(res checkResult, now time.Time) healthView {
+	// With a background check the page only reads.
+	if m.background.Load() {
+		// Read the counters.
+		return m.health.view()
+	} // end of the background check
+	// Without one the page's own check is the only measurement.
+	m.record(res, now)
+	// Read the counters.
+	return m.health.view()
+} // end of pageCheck
+
+// start switches the background check on: one check now, then one every interval, until the context ends.
+func (m *monitor) start(ctx context.Context, base *url.URL, timeout, every time.Duration) {
+	// From now on the page does not count its own checks.
+	m.background.Store(true)
+	// The loop runs on its own.
+	go func() {
+		// One check straight away, so the charts start at once.
+		m.record(checkOllama(ctx, base, timeout), time.Now())
+		// The clock for the next ones.
+		tick := time.NewTicker(every)
+		// Stop the clock at the end.
+		defer tick.Stop()
+		// Wait for each tick or the end.
+		for {
+			// Which came first.
+			select {
+			// The program is ending.
+			case <-ctx.Done():
+				// Leave the loop.
+				return
+			// Time for the next check.
+			case <-tick.C:
+				// Check and remember.
+				m.record(checkOllama(ctx, base, timeout), time.Now())
+			} // end of the select
+		} // end of the loop
+	}() // end of the goroutine
+} // end of start
diff --git a/monitor_test.go b/monitor_test.go
new file mode 100644
index 0000000..b6815ab
--- /dev/null
+++ b/monitor_test.go
@@ -0,0 +1,170 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context stops the background check.
+	"context"
+	// net/http provides the method name and the cookie type.
+	"net/http"
+	// net/http/httptest builds a request with a query.
+	"net/http/httptest"
+	// net/url parses the fake address.
+	"net/url"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time builds the moments and the waits.
+	"time"
+) // end of imports
+
+// TestHistoryForgetsOldChecks checks that checks older than the window plus a minute are dropped.
+func TestHistoryForgetsOldChecks(t *testing.T) {
+	// An empty history.
+	h := &sampleHistory{}
+	// An old check and a new one.
+	h.add(sample{At: chartNow().Add(-40 * time.Minute), Online: true})
+	// The new one pushes the old one out.
+	h.add(sample{At: chartNow(), Online: true})
+	// Only one is left.
+	if got := h.since(chartNow().Add(-time.Hour)); len(got) != 1 || !got[0].At.Equal(chartNow()) {
+		// Report it.
+		t.Errorf("history holds %d checks", len(got))
+	} // end of the check
+} // end of TestHistoryForgetsOldChecks
+
+// TestHistoryHasACeiling checks that memory use is bounded even when checks arrive faster than expected.
+func TestHistoryHasACeiling(t *testing.T) {
+	// An empty history.
+	h := &sampleHistory{}
+	// Many checks within one second.
+	for i := 0; i < maxSamples*3; i++ {
+		// One check.
+		h.add(sample{At: chartNow().Add(time.Duration(i) * time.Millisecond), Online: true, Ms: int64(i)})
+	} // end of the loop
+	// The ceiling holds, and the newest are the ones kept.
+	got := h.since(chartNow().Add(-time.Hour))
+	// Check the count and the newest.
+	if len(got) != maxSamples || got[len(got)-1].Ms != int64(maxSamples*3-1) {
+		// Report it.
+		t.Errorf("%d checks kept", len(got))
+	} // end of the check
+} // end of TestHistoryHasACeiling
+
+// TestPageCheckCountsOnlyWithoutBackground checks who counts: the page when no background check runs, nobody else when one does.
+func TestPageCheckCountsOnlyWithoutBackground(t *testing.T) {
+	// A monitor without a background check.
+	m := newMonitor()
+	// A failed check.
+	bad := checkResult{Online: false, Reason: "x"}
+	// The page counts its own check.
+	if v := m.pageCheck(bad, chartNow()); v.FailedTotal != 1 || len(m.hist.since(chartNow().Add(-time.Hour))) != 1 {
+		// Report it.
+		t.Errorf("page check was not counted: %+v", v)
+	} // end of the check
+	// A background check is switched on.
+	m.background.Store(true)
+	// The page no longer counts.
+	if v := m.pageCheck(bad, chartNow()); v.FailedTotal != 1 || len(m.hist.since(chartNow().Add(-time.Hour))) != 1 {
+		// Report it.
+		t.Errorf("page check was counted during a background check: %+v", v)
+	} // end of the check
+} // end of TestPageCheckCountsOnlyWithoutBackground
+
+// TestBackgroundChecksRun checks that the background loop measures by itself and the page then only reads.
+func TestBackgroundChecksRun(t *testing.T) {
+	// A fake Ollama that answers.
+	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
+	// Its address.
+	base, err := url.Parse(srv.URL)
+	// It must parse.
+	if err != nil {
+		// Stop.
+		t.Fatalf("bad address: %v", err)
+	} // end of the check
+	// A monitor.
+	m := newMonitor()
+	// Stop the loop at the end of the test.
+	ctx, cancel := context.WithCancel(context.Background())
+	// Cancel at the end.
+	defer cancel()
+	// Check every 5 milliseconds.
+	m.start(ctx, base, time.Second, 5*time.Millisecond)
+	// The page now only reads.
+	if !m.background.Load() {
+		// Report it.
+		t.Fatalf("the background flag is not set")
+	} // end of the check
+	// Wait until a few checks arrived, at most 3 seconds.
+	deadline := time.Now().Add(3 * time.Second)
+	// Poll.
+	for time.Now().Before(deadline) && len(m.hist.since(time.Now().Add(-time.Hour))) < 3 {
+		// A short wait.
+		time.Sleep(5 * time.Millisecond)
+	} // end of the loop
+	// At least three answered checks.
+	got := m.hist.since(time.Now().Add(-time.Hour))
+	// Check them.
+	if len(got) < 3 || !got[0].Online {
+		// Report it.
+		t.Fatalf("%d background checks", len(got))
+	} // end of the check
+	// Stop the loop and wait for it to settle.
+	cancel()
+	// A moment for a check in flight to end.
+	time.Sleep(50 * time.Millisecond)
+	// The count must stop growing.
+	n := len(m.hist.since(time.Now().Add(-time.Hour)))
+	// Wait again.
+	time.Sleep(50 * time.Millisecond)
+	// Still the same.
+	if n2 := len(m.hist.since(time.Now().Add(-time.Hour))); n2 != n {
+		// Report it.
+		t.Errorf("checks kept running after the stop: %d then %d", n, n2)
+	} // end of the check
+} // end of TestBackgroundChecksRun
+
+// TestMainPageShowsTheCharts checks the Charts box on the page: shown by default, folded with the other two, and the table of numbers behind its own link.
+func TestMainPageShowsTheCharts(t *testing.T) {
+	// A fake and a rig; the rig already asked once, so one check is in the history.
+	rig, _ := perfRig(t, newPerfFake())
+	// The default page.
+	page := pageWithCookie(t, rig, nil)
+	// The parts.
+	for _, w := range []string{`aria-labelledby="charts-title"`, ">Charts</span>", "Ollama&#39;s answers over the last 30 minutes", "State of Ollama", "Answer time", "Ollama answered 100 % of", `<svg class="chartsvg"`, `id="hatch"`, `class="cell cell-ok"`, "each time this page loads", `href="/?numbers=open#numbers"`, `<meta http-equiv="refresh"`} {
+		// Look for it.
+		if !strings.Contains(page, w) {
+			// Report the gap.
+			t.Errorf("the page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// The table is closed by default.
+	if strings.Contains(page, "The newest checks, scrolls sideways") {
+		// Report it.
+		t.Errorf("the table of numbers is open by default")
+	} // end of the check
+	// Folded with the other two boxes.
+	if folded := pageWithCookie(t, rig, &http.Cookie{Name: detailsCookieName, Value: "closed"}); strings.Contains(folded, "charts-title") {
+		// Report it.
+		t.Errorf("the charts stay when the details are folded")
+	} // end of the check
+	// The open table pauses the refresh and lists the checks.
+	req, rec := httptest.NewRequest(http.MethodGet, "/?numbers=open", nil), httptest.NewRecorder()
+	// Serve it.
+	rig.h.ServeHTTP(rec, req)
+	// The page.
+	open := rec.Body.String()
+	// The parts.
+	for _, w := range []string{"The newest checks, scrolls sideways", "<th scope=\"col\">Answer time</th>", "Answered", "Paused while the numbers of the charts are open", `href="/#numbers"`} {
+		// Look for it.
+		if !strings.Contains(open, w) {
+			// Report the gap.
+			t.Errorf("the page with the numbers lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// No refresh while the numbers are open.
+	if strings.Contains(open, `http-equiv="refresh"`) {
+		// Report it.
+		t.Errorf("the page refreshes while the numbers are open")
+	} // end of the check
+} // end of TestMainPageShowsTheCharts
diff --git a/tooltips.go b/tooltips.go
index 20a4d1a..9cffbc0 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -23,7 +23,7 @@ var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Lo
 var gearHeadings = []string{"Set in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}
 
 // healthHeadings are the headings of the Ollama status panel on the main page that have a help bubble; a test checks each has a text.
-var healthHeadings = []string{"Monitoring details", "API health", "Event log"}
+var healthHeadings = []string{"Monitoring details", "API health", "Event log", "Charts"}
 
 // perfHeadings are the indicator names on the performance page that have a help bubble; a test checks each has a text.
 var perfHeadings = []string{"Answer speed", "Prompt reading speed", "Load time", "Total time", "Time to first word", "Tokens counted", "Embedding time", "Vector length", "Processor split", "Memory used", "Change since the previous run", "CPU cores", "CPU load", "Memory free", "Swap in use", "Other models loaded", "GPU"}
@@ -40,6 +40,15 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Whether you want the status in view or more room for the models.",
 	}, // end of Monitoring details
+	// The charts under the event log.
+	"Charts": {
+		// What it means.
+		Plain: "Ollama's answers over the last 30 minutes: how often it answered and how fast.",
+		// A real case.
+		Example: "A hatched block in the state bar means a check failed in that half minute.",
+		// What it helps with.
+		Decide: "Whether Ollama is slowing down or dropping out before you start a long test.",
+	}, // end of Charts
 	// The Ollama status panel on the main page.
 	"API health": {
 		// What it means.
diff --git a/web.go b/web.go
index 5e022af..7ba3f17 100644
--- a/web.go
+++ b/web.go
@@ -77,6 +77,12 @@ type pageData struct {
 	CompareCount int
 	// Paused is true when the person paused the automatic updates (a cookie remembers it).
 	Paused bool
+	// Charts is what the Charts box draws, and ChartsTip is the help bubble of its heading.
+	Charts chartsView
+	// ChartsTip is the help bubble of the heading "Charts".
+	ChartsTip tipView
+	// NumbersOpen is true when the person opened the table of numbers under the charts (the address then ends in ?numbers=open); the page does not update by itself meanwhile.
+	NumbersOpen bool
 	// DetailsClosed is true when the person folded the monitoring details (API health and Event log) away; a cookie remembers it.
 	DetailsClosed bool
 	// DetailsTip is the help bubble of the twistie "Monitoring details".
@@ -110,17 +116,23 @@ func secureHeaders(next http.Handler) http.Handler {
 
 // newWebHandler builds the whole web interface: the page at "/" and the stylesheet at "/app.css".
 func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
+	// Without a background check: each page load is one check (the tests and the plain handler use this).
+	return newWebHandlerWith(addr, timeout, newMonitor())
+} // end of newWebHandler
+
+// newWebHandlerWith builds the web interface around a monitor that main may have started in the background.
+func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor) http.Handler {
 	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
 	page := template.Must(template.New("index").Parse(indexTemplateText))
-	// The counters of failed checks live as long as the monitor runs.
-	health := &apiHealth{}
 	// The help bubble of the panel heading never changes, so build it once.
 	healthTip := makeTip("tip-health", "API health")
 	// The event log of changes also lives as long as the monitor runs.
 	events := &eventLog{}
 	// The help bubble of its heading never changes either.
 	eventsTip := makeTip("tip-events", "Event log")
-	// The help bubble of the twistie that folds both away.
+	// The help bubble of the Charts heading.
+	chartsTip := makeTip("tip-charts", "Charts")
+	// The help bubble of the twistie that folds the boxes away.
 	detailsTip := makeTip("tip-details", "Monitoring details")
 	// Create the page token: an unguessable value that every form on the page carries, so only this page can send a form (requirement S2).
 	token := mustToken()
@@ -254,7 +266,7 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			// The time taken.
 			ElapsedMs: res.Elapsed.Milliseconds(),
 			// The counters after this check, and the bubble of the heading.
-			Health: health.record(res.Online, time.Now()), HealthTip: healthTip,
+			Health: mon.pageCheck(res, time.Now()), HealthTip: healthTip,
 			// The reason, if offline.
 			Reason: res.Reason,
 			// The saved theme choice, from the cookie; empty means follow the system.
@@ -274,6 +286,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			// Whether the monitoring details are folded away, and their help bubble.
 			DetailsClosed: detailsClosed(r),
 			DetailsTip:    detailsTip,
+			// Whether the table of numbers under the charts is open.
+			NumbersOpen: r.URL.Query().Get("numbers") == "open",
 			// Whether the key to the symbols is open.
 			KeyOpen: r.URL.Query().Get("key") == "open",
 			// The update interval.
@@ -317,6 +331,12 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 		events.observe(time.Now(), res.Online, res.Version, res.Reason, listsOK, evInstalled, evLoaded)
 		// The lines and the bubble of the heading.
 		data.Events, data.EventsTip = events.view(time.Now()), eventsTip
+		// The charts of the last 30 minutes, and the bubble of their heading.
+		now := time.Now()
+		// Build them from the history of checks.
+		data.Charts = buildCharts(mon.hist.since(now.Add(-chartWindow)), now, mon.background.Load(), data.NumbersOpen)
+		// The bubble.
+		data.ChartsTip = chartsTip
 		// Build the whole page in memory first, so a template error produces a clean 500 and not a half page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/web/app.css b/web/app.css
index 1e3a03b..f495899 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2059,3 +2059,101 @@ html[data-size="medium"] svg[width="22"] {
   /* Bold, like the key twistie. */
   font-weight: 600;
 } /* end of rule */
+
+/* The charts: the drawings fill the box and scale with it. */
+.chartsvg {
+  /* Full width of the box. */
+  width: 100%;
+  /* The height follows the shape of the drawing. */
+  height: auto;
+  /* No gap under it from the line box. */
+  display: block;
+} /* end of rule */
+
+/* One block of the state bar: an outline keeps every block visible without colour. */
+.cell {
+  /* The outline colour. */
+  stroke: var(--border);
+  /* A thin outline. */
+  stroke-width: 1;
+} /* end of rule */
+
+/* Ollama answered in this half minute: filled. */
+.cell-ok {
+  /* The green of the page. */
+  fill: var(--ok);
+} /* end of rule */
+
+/* A check failed in this half minute: hatched, so it differs by pattern and not only by colour. */
+.cell-bad {
+  /* The diagonal pattern. */
+  fill: url(#hatch);
+} /* end of rule */
+
+/* No check in this half minute: empty. */
+.cell-none {
+  /* Nothing inside. */
+  fill: transparent;
+} /* end of rule */
+
+/* The background of the hatch pattern. */
+.hatchbg {
+  /* The panel colour. */
+  fill: var(--panel);
+} /* end of rule */
+
+/* The stripes of the hatch pattern. */
+.hatchline {
+  /* The red of the page. */
+  stroke: var(--bad);
+  /* Thick enough to see. */
+  stroke-width: 2;
+} /* end of rule */
+
+/* The zero line of the answer-time chart. */
+.chartbase {
+  /* The border colour. */
+  stroke: var(--border);
+  /* A thin line. */
+  stroke-width: 1;
+} /* end of rule */
+
+/* The answer-time line. */
+.chartline {
+  /* The accent colour. */
+  stroke: var(--cat-accent);
+  /* A clear line. */
+  stroke-width: 2;
+  /* No filling. */
+  fill: none;
+} /* end of rule */
+
+/* One answered check as a dot on the line. */
+.chartdot {
+  /* The accent colour. */
+  fill: var(--cat-accent);
+} /* end of rule */
+
+/* The times under the chart: start, middle and end. */
+.chartaxis {
+  /* Three labels in one row. */
+  display: flex;
+  /* First at the left, last at the right. */
+  justify-content: space-between;
+  /* Small gap above. */
+  margin: 0.25rem 0;
+} /* end of rule */
+
+/* The small titles above each drawing. */
+.chartlabel {
+  /* Bold. */
+  font-weight: 600;
+  /* Space above, little below. */
+  margin: 0.75rem 0 0.25rem;
+} /* end of rule */
+
+/* The line that explains the blocks. */
+.chartlegend {
+  /* Small gap above. */
+  margin: 0.25rem 0;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 4246a5d..6aecc4e 100644
--- a/web/index.html
+++ b/web/index.html
@@ -15,7 +15,7 @@
 <link rel="stylesheet" href="/app.css">
 {{/* While the page is being watched it reloads itself; Pause removes this line. It needs no script. */}}
 {{/* No automatic update while the key is open, so it does not vanish while it is being read. */}}
-{{if and (not .Paused) (not .KeyOpen)}}<meta http-equiv="refresh" content="{{.RefreshSeconds}}">{{end}}
+{{if and (not .Paused) (not .KeyOpen) (not .NumbersOpen)}}<meta http-equiv="refresh" content="{{.RefreshSeconds}}">{{end}}
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
 {{/* The page header. */}}
@@ -29,7 +29,7 @@
 {{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}
 <p class="muted">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>
 {{/* Says whether the page updates by itself, and how fresh it is; the symbol and the words carry the meaning. */}}
-<p class="muted" id="watchline">{{if and .KeyOpen (not .Paused)}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Paused while the key to the symbols is open. Page made at {{.UpdatedAt}}. Close the key to carry on watching.{{else if .Paused}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Paused: the page does not update by itself. Page made at {{.UpdatedAt}}.{{else}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><path d="M4 2.5v11l9-5.5z"/></svg> Watching: the page updates itself every {{.RefreshSeconds}} seconds. Page made at {{.UpdatedAt}}.{{end}}</p>
+<p class="muted" id="watchline">{{if and (or .KeyOpen .NumbersOpen) (not .Paused)}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Paused while the {{if .NumbersOpen}}numbers of the charts are{{else}}key to the symbols is{{end}} open. Page made at {{.UpdatedAt}}. Close {{if .NumbersOpen}}the numbers{{else}}the key{{end}} to carry on watching.{{else if .Paused}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Paused: the page does not update by itself. Page made at {{.UpdatedAt}}.{{else}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><path d="M4 2.5v11l9-5.5z"/></svg> Watching: the page updates itself every {{.RefreshSeconds}} seconds. Page made at {{.UpdatedAt}}.{{end}}</p>
 {{/* End of the title block. */}}
 </div>
 {{/* The right side of the header: the monitor controls, then the theme switch. */}}
@@ -190,6 +190,51 @@
 <p>Nothing seen yet.</p>
 {{end}}
 </section>
+{{/* The charts: the state of Ollama and its answer time over the last 30 minutes, drawn as pictures with a text alternative. */}}
+<section class="panel" aria-labelledby="charts-title">
+{{/* The heading with its help bubble. */}}
+<h2 id="charts-title"><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.ChartsTip.ID}}">{{.ChartsTip.Title}}</span><span class="tip" role="tooltip" id="{{.ChartsTip.ID}}">{{template "tip" .ChartsTip}}</span></span></h2>
+{{/* How the numbers are made. */}}
+<p class="muted">The last {{.Charts.WindowText}}, checked every {{.Charts.EverySeconds}} seconds {{if .Charts.Background}}in the background, also while this page is closed{{else}}each time this page loads{{end}}. Kept in memory until the monitor stops. Times are in the zone shown.</p>
+{{/* The summary; the warning sign and the words both show a failure. */}}
+<p class="chartsummary">{{if .Charts.HasFailure}}<span class="symbol" aria-hidden="true">⚠</span> {{end}}<strong>{{.Charts.Summary}}</strong></p>
+{{/* The state bar: one block per half minute. */}}
+<p class="chartlabel">State of Ollama</p>
+<svg class="chartsvg" viewBox="0 0 {{.Charts.Width}} {{.Charts.CellHeight}}" role="img" aria-label="{{.Charts.StateAlt}}">
+<defs><pattern id="hatch" width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="4" height="4" class="hatchbg"/><line x1="0" y1="0" x2="0" y2="4" class="hatchline"/></pattern></defs>
+{{range .Charts.Cells}}<rect class="cell cell-{{.Class}}" x="{{.X}}" y="0" width="{{$.Charts.CellWidth}}" height="{{$.Charts.CellHeight}}"/>{{end}}
+</svg>
+<p class="muted chartlegend">Filled: Ollama answered. Hatched: a check failed. Empty: no check in that half minute.</p>
+{{/* The answer-time chart. */}}
+<p class="chartlabel">Answer time</p>
+<svg class="chartsvg" viewBox="0 0 {{.Charts.Width}} {{.Charts.Height}}" aria-hidden="true">
+<line class="chartbase" x1="0" y1="{{.Charts.BaseY}}" x2="{{.Charts.Width}}" y2="{{.Charts.BaseY}}"/>
+{{range .Charts.Segments}}<polyline class="chartline" points="{{.}}"/>{{end}}
+{{range .Charts.Dots}}<circle class="chartdot" cx="{{.X}}" cy="{{.Y}}" r="2.5"/>{{end}}
+</svg>
+<p class="chartaxis muted"><span>{{.Charts.StartLabel}}</span><span>{{.Charts.MidLabel}}</span><span>{{.Charts.EndLabel}}</span></p>
+<p class="muted">{{.Charts.AnswerAlt}}</p>
+{{/* The twistie for the numbers: a link, so the choice needs no script; the page pauses while it is open. */}}
+{{if .Charts.NumbersOpen}}
+<p class="keytoggle" id="numbers"><a href="/#numbers"><span aria-hidden="true">&#9662;</span> The numbers <span class="keyhint">(click to hide)</span></a></p>
+{{if .Charts.Rows}}
+<div class="scrollbox" tabindex="0" role="region" aria-label="The newest checks, scrolls sideways">
+<table class="models comparetable">
+<thead><tr><th scope="col">Time</th><th scope="col">State</th><th scope="col">Answer time</th></tr></thead>
+<tbody>
+{{range .Charts.Rows}}
+<tr><td>{{.Time}}</td><td>{{if .Online}}<span class="symbol" aria-hidden="true">✔</span> Answered{{else}}<span class="symbol" aria-hidden="true">✖</span> Failed{{end}}</td><td>{{.Answer}}</td></tr>
+{{end}}
+</tbody>
+</table>
+</div>
+{{else}}
+<p>No checks yet.</p>
+{{end}}
+{{else}}
+<p class="keytoggle" id="numbers"><a href="/?numbers=open#numbers"><span aria-hidden="true">&#9656;</span> The numbers <span class="keyhint">(click to show the newest checks)</span></a></p>
+{{end}}
+</section>
 {{/* End of the folded part. */}}
 {{end}}
 {{/* The Installed models panel. */}}
diff --git a/webtable_test.go b/webtable_test.go
index bf17963..efd8a99 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -135,9 +135,9 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	// Fake Ollama with the six real models.
 	body := pageFor(t, fullOllama(t, realModels, realPsBody))
 	// Ten column bubbles, two category bubbles and the bubbles of the API health and Event log headings; the short tips of the row icons are counted apart.
-	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 15 {
+	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 16 {
 		// Report the difference.
-		t.Errorf("%d bubbles, want 15", n)
+		t.Errorf("%d bubbles, want 16", n)
 	} // end of the bubble count
 	// Every column title must be a focusable heading.
 	for _, col := range installedColumns {
@@ -155,9 +155,9 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	// Find every aria-describedby value.
 	refs := regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1)
 	// There must be one per bubble (the row icons have their own, counted apart).
-	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 15 {
+	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 16 {
 		// Report the difference.
-		t.Errorf("%d aria-describedby attributes, want 15", n)
+		t.Errorf("%d aria-describedby attributes, want 16", n)
 	} // end of the reference count
 	// Each one must point at an element that exists.
 	for _, m := range refs {
@@ -189,7 +189,7 @@ func TestTableAccessibility(t *testing.T) {
 		// The scroll box is a labelled region that the keyboard can reach.
 		{`role="region"`, 2},
 		// Fourteen headings (ten columns, two categories, API health and Event log) plus the two scroll boxes (models and event log) can take the focus.
-		{`tabindex="0"`, 17},
+		{`tabindex="0"`, 18},
 	} { // end of the list
 		// Count it.
 		if n := strings.Count(body, c.text); n != c.want {
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
2edb9ffc13a873ab1e52d7ea96502968551b8d4cdb88dfc8c285627c04b5217d  about.go
309fd1ca96176d0d9e47cbd4f26ae7dd015df7f09cdde9596c0e71dca1e7a30a  tooltips.go
97b05e85b6454db25bf3e52657e8170e099ea86d90ab386fece06784234e750c  web.go
9004ac60d53f0e6273608b3f1e56d08fecedbcb2b660ae2ebc1524ce62932efb  main.go
0f0051d9412abe712c3458d2a4e727b5b46de2809db5fd28c58c444fce63f176  health.go
3397beac2343f345df2ccc04cd611723ebff2dc67287ce86163607146d8be026  web/index.html
db2819274afd5639e1db1acae22115a559eeec85d7152a2ec3341e1b568226c5  web/app.css
36fe6d4330e6ad2e7c54ffffef4aaa46fe14c92b299829aade0e06cf7fafd622  webtable_test.go
7b0b9ba901427f665224a5a2b9dbdb2e9c28629f6bb78d0e908d48015ccdbaf2  monitor.go
1e917bf4f745fd15e432b45f1a4ff7f8ebf0b38bfe462f4f3bbe10ebd6a3de80  monitor_test.go
4e06d17ba1a03190d25ebaf54a1ef8ac806a343e697854507e2679e6ab323a37  charts.go
1e8d6ed1c7833878a0d59b88782d1222d29568aec9b92c5bd214a7040857f387  charts_test.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# Tell the person how to use the new command.
echo "NEXT  start ./bin/OllamaControlCenter and look for the Charts box under Event log (inside Monitoring details)"
# List the changed files; nothing is committed yet.
git status --short
