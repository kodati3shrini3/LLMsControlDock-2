// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// strconv reads the coordinates back.
	"strconv"
	// strings searches the text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time builds the moments.
	"time"
) // end of imports

// chartNow is the moment the chart tests treat as now: 31 October 2026, 17:45:00 CET.
func chartNow() time.Time {
	// The moment.
	return at(17, 45, 0)
} // end of chartNow

// every builds n answered checks, one every 10 seconds, the last one at now, each taking ms milliseconds.
func every(n int, ms int64) []sample {
	// The list.
	var out []sample
	// Oldest first.
	for i := n - 1; i >= 0; i-- {
		// One check.
		out = append(out, sample{At: chartNow().Add(-time.Duration(i) * 10 * time.Second), Online: true, Ms: ms})
	} // end of the loop
	// Hand it back.
	return out
} // end of every

// TestChartsEmpty checks the box before any check was made.
func TestChartsEmpty(t *testing.T) {
	// Build with nothing.
	v := buildCharts(nil, chartNow(), true, false)
	// No data, a plain sentence, and a full bar of empty blocks.
	if v.HasData || v.Summary != "No checks yet in the last 30 minutes." || len(v.Cells) != stateCells || len(v.Dots) != 0 || len(v.Segments) != 0 {
		// Report it.
		t.Errorf("empty view wrong: %+v", v.Summary)
	} // end of the check
	// Every block is empty.
	for _, c := range v.Cells {
		// Empty.
		if c.Class != "none" {
			// Report it.
			t.Fatalf("a block of an empty chart is %q", c.Class)
		} // end of the check
	} // end of the loop
} // end of TestChartsEmpty

// TestChartsAllAnswered checks the summary when nothing failed: 100 without a decimal, no failure, no warning.
func TestChartsAllAnswered(t *testing.T) {
	// 180 checks fill the window.
	v := buildCharts(every(180, 20), chartNow(), true, false)
	// The sentence.
	if v.Summary != "Ollama answered 100 % of 180 checks in the last 30 minutes; 0 failed." || v.HasFailure {
		// Report it.
		t.Errorf("summary wrong: %q", v.Summary)
	} // end of the check
	// One unbroken line and a dot for every check.
	if len(v.Segments) != 1 || len(v.Dots) != 180 {
		// Report it.
		t.Errorf("%d lines, %d dots", len(v.Segments), len(v.Dots))
	} // end of the check
	// The text alternative says what the chart shows.
	if !strings.Contains(v.AnswerAlt, "scale 0 to 50 ms: lowest 20 ms, highest 20 ms, latest 20 ms") {
		// Report it.
		t.Errorf("alt wrong: %q", v.AnswerAlt)
	} // end of the check
} // end of TestChartsAllAnswered

// TestChartsFailureBreaksTheLine checks a failed check: the percentage, the moment, the hatched block and the broken line.
func TestChartsFailureBreaksTheLine(t *testing.T) {
	// 20 checks, the 10th failed.
	s := every(20, 30)
	// The failure.
	s[9].Online, s[9].Ms = false, 5
	// Build.
	v := buildCharts(s, chartNow(), false, false)
	// The summary names the failure and its moment, with the zone.
	for _, w := range []string{"Ollama answered 95.0 % of 20 checks", "1 failed.", "Last failure at 17:43:20 CET."} {
		// Look for it.
		if !strings.Contains(v.Summary, w) {
			// Report it.
			t.Errorf("summary lacks %q: %q", w, v.Summary)
		} // end of the check
	} // end of the loop
	// The warning sign shows, and the line is in two parts.
	if !v.HasFailure || len(v.Segments) != 2 || len(v.Dots) != 19 {
		// Report it.
		t.Errorf("failure %v, %d lines, %d dots", v.HasFailure, len(v.Segments), len(v.Dots))
	} // end of the check
	// One block is hatched.
	bad := 0
	// Count them.
	for _, c := range v.Cells {
		// A failed block.
		if c.Class == "bad" {
			// Count.
			bad++
		} // end of the check
	} // end of the loop
	// Exactly one.
	if bad != 1 {
		// Report it.
		t.Errorf("%d hatched blocks, want 1", bad)
	} // end of the check
	// The text alternative of the bar counts it.
	if !strings.Contains(v.StateAlt, "1 blocks had a failed check") {
		// Report it.
		t.Errorf("state alt wrong: %q", v.StateAlt)
	} // end of the check
	// A young monitor says how long it has watched: 190 seconds.
	if !strings.Contains(v.Summary, "Watching for 3 min 10 s so far.") {
		// Report it.
		t.Errorf("no young-monitor note: %q", v.Summary)
	} // end of the check
} // end of TestChartsFailureBreaksTheLine

// TestChartsWindowEdges checks that checks outside the window are ignored.
func TestChartsWindowEdges(t *testing.T) {
	// One too old, one inside, one in the future.
	s := []sample{
		{At: chartNow().Add(-31 * time.Minute), Online: true, Ms: 99},
		{At: chartNow().Add(-1 * time.Minute), Online: true, Ms: 10},
		{At: chartNow().Add(time.Minute), Online: false, Ms: 1},
	}
	// Build.
	v := buildCharts(s, chartNow(), true, false)
	// Only the middle one counts.
	if !strings.Contains(v.Summary, "100 % of 1 checks") || len(v.Dots) != 1 {
		// Report it.
		t.Errorf("edges wrong: %q, %d dots", v.Summary, len(v.Dots))
	} // end of the check
} // end of TestChartsWindowEdges

// TestChartsLongPauseBreaksTheLine checks that two answers far apart are not joined by a line.
func TestChartsLongPauseBreaksTheLine(t *testing.T) {
	// Two answers a minute apart.
	s := []sample{{At: chartNow().Add(-60 * time.Second), Online: true, Ms: 10}, {At: chartNow(), Online: true, Ms: 12}}
	// Build.
	v := buildCharts(s, chartNow(), false, false)
	// Two dots and no line.
	if len(v.Dots) != 2 || len(v.Segments) != 0 {
		// Report it.
		t.Errorf("%d dots, %d lines", len(v.Dots), len(v.Segments))
	} // end of the check
} // end of TestChartsLongPauseBreaksTheLine

// TestChartsDotsStayInsideTheDrawing checks every coordinate lies inside the drawing, even for a huge answer time.
func TestChartsDotsStayInsideTheDrawing(t *testing.T) {
	// A normal one, a zero, and a huge one.
	s := every(3, 10)
	// The values.
	s[0].Ms, s[1].Ms, s[2].Ms = 0, 7, 123456
	// Build.
	v := buildCharts(s, chartNow(), true, false)
	// Check every dot.
	for _, d := range v.Dots {
		// The numbers.
		x, errX := strconv.ParseFloat(d.X, 64)
		// The other number.
		y, errY := strconv.ParseFloat(d.Y, 64)
		// They must read as numbers and lie inside.
		if errX != nil || errY != nil || x < 0 || x > chartWidth || y < chartPad || y > chartHeight-chartPad {
			// Report it.
			t.Errorf("dot %s,%s is outside the drawing", d.X, d.Y)
		} // end of the check
	} // end of the loop
	// The scale rounds up to a tidy number.
	if !strings.Contains(v.AnswerAlt, "scale 0 to 200000 ms") {
		// Report it.
		t.Errorf("scale wrong: %q", v.AnswerAlt)
	} // end of the check
} // end of TestChartsDotsStayInsideTheDrawing

// TestNiceMax checks the round numbers of the scale.
func TestNiceMax(t *testing.T) {
	// Input and expected.
	for in, want := range map[int64]int64{0: 50, 10: 50, 11: 50, 20: 50, 49: 50, 50: 50, 51: 100, 100: 100, 101: 200, 201: 500, 501: 1000, 1001: 2000, 5001: 10000} {
		// Compare.
		if got := niceMax(in); got != want {
			// Report it.
			t.Errorf("niceMax(%d) = %d, want %d", in, got, want)
		} // end of the check
	} // end of the loop
} // end of TestNiceMax

// TestChartsRowsOnlyWhenOpen checks the table of numbers: absent when closed; newest first, limited and with dashes when open.
func TestChartsRowsOnlyWhenOpen(t *testing.T) {
	// 30 checks, the newest failed.
	s := every(30, 15)
	// The newest failed.
	s[29].Online = false
	// Closed: no rows.
	if v := buildCharts(s, chartNow(), true, false); len(v.Rows) != 0 {
		// Report it.
		t.Errorf("%d rows while closed", len(v.Rows))
	} // end of the closed check
	// Open.
	v := buildCharts(s, chartNow(), true, true)
	// Limited to the newest rows.
	if len(v.Rows) != numbersRows {
		// Report it.
		t.Fatalf("%d rows, want %d", len(v.Rows), numbersRows)
	} // end of the limit check
	// The newest first: the failed check, with a dash and the zone name.
	if v.Rows[0].Online || v.Rows[0].Answer != "-" || v.Rows[0].Time != "17:45:00 CET" || v.Rows[1].Answer != "15 ms" {
		// Report it.
		t.Errorf("rows wrong: %+v %+v", v.Rows[0], v.Rows[1])
	} // end of the order check
} // end of TestChartsRowsOnlyWhenOpen

// TestChartsTimesCarryTheZone checks every time on the chart names its zone.
func TestChartsTimesCarryTheZone(t *testing.T) {
	// Build.
	v := buildCharts(every(5, 10), chartNow(), true, false)
	// Every label.
	for _, l := range []string{v.StartLabel, v.MidLabel, v.EndLabel} {
		// It must end with the zone name.
		if !strings.HasSuffix(l, " CET") {
			// Report it.
			t.Errorf("label %q has no zone name", l)
		} // end of the check
	} // end of the loop
	// The labels themselves.
	if v.StartLabel != "17:15 CET" || v.MidLabel != "17:30 CET" || v.EndLabel != "17:45 CET" {
		// Report it.
		t.Errorf("labels %q %q %q", v.StartLabel, v.MidLabel, v.EndLabel)
	} // end of the label check
} // end of TestChartsTimesCarryTheZone
