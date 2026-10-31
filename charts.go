// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the texts.
	"fmt"
	// strconv writes the percentage without locale surprises.
	"strconv"
	// strings joins the points of a line.
	"strings"
	// time gives the moments and lengths.
	"time"
) // end of imports

// chartTimeLayout writes a moment on an axis; it always carries the time zone name, as every time on every page does.
const chartTimeLayout = "15:04 MST"

// chartRowLayout writes a moment in the table of numbers, with the zone name.
const chartRowLayout = "15:04:05 MST"

// chartLastFailureLayout writes the moment of the last failure, with the zone name.
const chartLastFailureLayout = "15:04:05 MST"

// stateCells is how many blocks the state bar has: 60 blocks of 30 seconds make 30 minutes.
const stateCells = 60

// chartWidth is the drawing width, in drawing units; the picture scales to the box.
const chartWidth = 600

// chartHeight is the height of the answer-time drawing; the picture keeps its proportions, so a low drawing stays compact on a wide screen.
const chartHeight = 80

// minScale is the smallest top of the answer-time scale, in milliseconds, so that small differences of a few milliseconds look flat.
const minScale int64 = 50

// cellHeight is the height of the state bar.
const cellHeight = 24

// chartPad keeps lines and dots off the edge of the drawing.
const chartPad = 6

// numbersRows is how many checks the table of numbers lists.
const numbersRows = 20

// chartGap is the longest pause between two checks that still joins them into one line; a longer pause breaks the line.
const chartGap = 3 * sampleEvery

// chartCell is one block of the state bar.
type chartCell struct {
	// X is the left edge in drawing units.
	X int
	// Class is ok (all checks answered), bad (a check failed) or none (no check in this block).
	Class string
} // end of chartCell

// chartDot is one answered check on the answer-time chart.
type chartDot struct {
	// X and Y are drawing units.
	X, Y string
} // end of chartDot

// chartRow is one line of the table of numbers.
type chartRow struct {
	// Time is the moment of the check, with its zone name.
	Time string
	// Online is true when Ollama answered.
	Online bool
	// Answer is the time the answer took, or a dash.
	Answer string
} // end of chartRow

// chartsView is what the Charts box shows.
type chartsView struct {
	// WindowText is the length of history shown, in words.
	WindowText string
	// EverySeconds is the interval of the checks.
	EverySeconds int
	// Background is true when the checks run by themselves.
	Background bool
	// Summary is the one-sentence summary of the window.
	Summary string
	// HasFailure is true when the window holds a failed check, so the summary gets a warning sign.
	HasFailure bool
	// Cells are the blocks of the state bar.
	Cells []chartCell
	// CellWidth is the width of one block, in drawing units.
	CellWidth int
	// CellHeight is the height of the state bar.
	CellHeight int
	// StateAlt is the text alternative of the state bar.
	StateAlt string
	// Width and Height are the size of the answer-time drawing.
	Width, Height int
	// Segments are the lines of the answer-time chart, each a list of points.
	Segments []string
	// Dots are the answered checks.
	Dots []chartDot
	// BaseY is the vertical position of the zero line.
	BaseY int
	// AnswerAlt is the text alternative of the answer-time chart.
	AnswerAlt string
	// StartLabel, MidLabel and EndLabel are the times under the chart.
	StartLabel, MidLabel, EndLabel string
	// Rows are the newest checks for the table of numbers, newest first; empty unless the table is open.
	Rows []chartRow
	// NumbersOpen is true when the table of numbers is open.
	NumbersOpen bool
	// HasData is true when the window holds at least one check.
	HasData bool
} // end of chartsView

// niceMax returns the first round number that is at least v, and never less than minScale, so the scale has tidy ends.
func niceMax(v int64) int64 {
	// Small answer times all fit on the smallest scale.
	if v <= minScale {
		// The smallest scale.
		return minScale
	} // end of the small case
	// Above the smallest: 100, 200, 500, 1000, and so on.
	for base := int64(100); ; base *= 10 {
		// The three round numbers of this size.
		for _, m := range []int64{1, 2, 5} {
			// Big enough.
			if v <= base*m {
				// This one.
				return base * m
			} // end of the check
		} // end of the loop
	} // end of the loop
} // end of niceMax

// windowWords writes a duration of whole minutes in words.
func windowWords(d time.Duration) string {
	// Whole minutes.
	m := int(d / time.Minute)
	// One minute is singular.
	if m == 1 {
		// Singular.
		return "1 minute"
	} // end of the singular case
	// Plural.
	return fmt.Sprintf("%d minutes", m)
} // end of windowWords

// watchedFor writes how long the monitor has been watching, in minutes and seconds.
func watchedFor(d time.Duration) string {
	// Whole seconds.
	sec := int(d / time.Second)
	// Under a minute.
	if sec < 60 {
		// Seconds only.
		return fmt.Sprintf("%d s", sec)
	} // end of the short case
	// Minutes and seconds.
	return fmt.Sprintf("%d min %d s", sec/60, sec%60)
} // end of watchedFor

// buildCharts builds the charts with the built-in window and check interval (the page uses buildChartsFor with the saved settings).
func buildCharts(samples []sample, now time.Time, background, numbersOpen bool) chartsView {
	// The defaults.
	return buildChartsFor(samples, now, background, numbersOpen, chartWindow, sampleEvery)
} // end of buildCharts

// spanWords writes a short duration in words: seconds under a minute, whole minutes when it divides evenly, otherwise seconds.
func spanWords(d time.Duration) string {
	// Whole seconds.
	sec := int(d / time.Second)
	// A whole number of minutes of one minute or more.
	if sec >= 60 && sec%60 == 0 {
		// Reuse the minutes wording.
		return windowWords(d)
	} // end of the minutes case
	// One second is singular.
	if sec == 1 {
		// Singular.
		return "1 second"
	} // end of the singular case
	// Plural seconds.
	return fmt.Sprintf("%d seconds", sec)
} // end of spanWords

// buildChartsFor turns the checks of the last window into what the page draws; window is the history length and every is the time between two checks (both come from the settings).
func buildChartsFor(samples []sample, now time.Time, background, numbersOpen bool, window, every time.Duration) chartsView {
	// The start of the window.
	start := now.Add(-window)
	// The basic fields.
	v := chartsView{WindowText: windowWords(window), EverySeconds: int(every / time.Second), Background: background, NumbersOpen: numbersOpen,
		CellHeight: cellHeight, Width: chartWidth, Height: chartHeight, BaseY: chartHeight - chartPad,
		StartLabel: start.Format(chartTimeLayout), MidLabel: start.Add(window / 2).Format(chartTimeLayout), EndLabel: now.Format(chartTimeLayout)}
	// The width of one block, leaving a one-unit gap.
	v.CellWidth = chartWidth/stateCells - 1
	// Only the checks inside the window count.
	var in []sample
	// Pick them.
	for _, s := range samples {
		// Inside the window.
		if !s.At.Before(start) && !s.At.After(now) {
			// Keep it.
			in = append(in, s)
		} // end of the window check
	} // end of the loop
	// The blocks start as empty.
	classes := make([]string, stateCells)
	// Every block is "none" until a check lands in it.
	for i := range classes {
		// No data.
		classes[i] = "none"
	} // end of the loop
	// Counts for the summary.
	failed, answered := 0, 0
	// The last failure.
	var lastFail time.Time
	// The answer times of answered checks.
	var lo, hi, last int64
	// Walk the checks.
	for _, s := range in {
		// The block of this check.
		i := int(s.At.Sub(start) * stateCells / window)
		// The very end belongs to the last block.
		if i >= stateCells {
			// Clamp.
			i = stateCells - 1
		} // end of the clamp
		// A failure marks the block bad; an answer marks it ok only when it is still empty.
		if !s.Online {
			// Bad.
			classes[i] = "bad"
			// Count it.
			failed++
			// Remember when.
			lastFail = s.At
		} else {
			// Answered; a block that already failed stays bad.
			if classes[i] == "none" {
				// Ok.
				classes[i] = "ok"
			} // end of the empty check
			// The lowest, highest and latest answer times.
			if answered == 0 || s.Ms < lo {
				// A new lowest.
				lo = s.Ms
			} // end of the lowest check
			// The highest.
			if s.Ms > hi {
				// A new highest.
				hi = s.Ms
			} // end of the highest check
			// The latest.
			last = s.Ms
			// One more answer.
			answered++
		} // end of the online check
	} // end of the loop
	// Draw the blocks.
	okN, badN, noneN := 0, 0, 0
	// One block at a time.
	for i, c := range classes {
		// Its place.
		v.Cells = append(v.Cells, chartCell{X: i * (chartWidth / stateCells), Class: c})
		// Count it for the text alternative.
		switch c {
		// Answered.
		case "ok":
			// Count.
			okN++
		// Failed.
		case "bad":
			// Count.
			badN++
		// Empty.
		default:
			// Count.
			noneN++
		} // end of the switch
	} // end of the loop
	// The text alternative of the state bar.
	v.StateAlt = fmt.Sprintf("State of Ollama in the last %s, in %d blocks of %s: %d blocks answered, %d blocks had a failed check, %d blocks have no check yet.", v.WindowText, stateCells, spanWords(window/stateCells), okN, badN, noneN)
	// Nothing measured yet.
	if len(in) == 0 {
		// Say so; the charts stay empty.
		v.Summary = "No checks yet in the last " + v.WindowText + "."
		// Hand it back.
		v.AnswerAlt = "No answer times yet."
		// Done.
		return v
	} // end of the empty case
	// There is data.
	v.HasData = true
	// The percentage of checks that answered.
	pct := float64(len(in)-failed) * 100 / float64(len(in))
	// One decimal, or none at exactly 100.
	pctText := strconv.FormatFloat(pct, 'f', 1, 64)
	// All answered.
	if failed == 0 {
		// No decimal.
		pctText = "100"
	} // end of the full-score check
	// The summary sentence.
	v.Summary = fmt.Sprintf("Ollama answered %s %% of %d checks in the last %s; %d failed.", pctText, len(in), v.WindowText, failed)
	// A failure adds its moment and the warning sign.
	if failed > 0 {
		// The warning.
		v.HasFailure = true
		// The moment.
		v.Summary += " Last failure at " + lastFail.Format(chartLastFailureLayout) + "."
	} // end of the failure check
	// A young monitor says how long it has been watching.
	if watched := now.Sub(in[0].At); watched < window-time.Minute {
		// The note.
		v.Summary += " Watching for " + watchedFor(watched) + " so far."
	} // end of the young check
	// The scale of the answer-time chart.
	top := niceMax(hi)
	// The drawing height inside the padding.
	usable := float64(chartHeight - 2*chartPad)
	// The lines are broken at failures and long pauses.
	var cur []string
	// The time of the previous answered check.
	var prev time.Time
	// Close the current line.
	flush := func() {
		// A line needs two points.
		if len(cur) >= 2 {
			// Keep it.
			v.Segments = append(v.Segments, strings.Join(cur, " "))
		} // end of the length check
		// Start a new one.
		cur = nil
	} // end of flush
	// Walk the checks again.
	for _, s := range in {
		// A failure breaks the line.
		if !s.Online {
			// End the line.
			flush()
			// Next check.
			continue
		} // end of the failure check
		// A long pause breaks the line too.
		if !prev.IsZero() && s.At.Sub(prev) > 3*every {
			// End the line.
			flush()
		} // end of the pause check
		// The position.
		x := float64(s.At.Sub(start)) / float64(window) * chartWidth
		// Zero at the bottom, the top of the scale at the top.
		y := float64(chartHeight-chartPad) - float64(s.Ms)/float64(top)*usable
		// The text of the point.
		px, py := strconv.FormatFloat(x, 'f', 1, 64), strconv.FormatFloat(y, 'f', 1, 64)
		// Add the point to the line and the dot to the dots.
		cur = append(cur, px+","+py)
		// The dot.
		v.Dots = append(v.Dots, chartDot{X: px, Y: py})
		// Remember the time.
		prev = s.At
	} // end of the loop
	// Close the last line.
	flush()
	// The text alternative of the answer-time chart.
	if answered == 0 {
		// No answers.
		v.AnswerAlt = "No answer times: Ollama did not answer in the last " + v.WindowText + "."
	} else {
		// The numbers.
		v.AnswerAlt = fmt.Sprintf("Answer time of Ollama's status check in the last %s, scale 0 to %d ms: lowest %d ms, highest %d ms, latest %d ms.", v.WindowText, top, lo, hi, last)
	} // end of the answers check
	// The table of numbers is built only when it is open.
	if numbersOpen {
		// The newest first.
		for i := len(in) - 1; i >= 0 && len(v.Rows) < numbersRows; i-- {
			// The answer text.
			ans := "-"
			// Only an answer has a time.
			if in[i].Online {
				// Write it.
				ans = fmt.Sprintf("%d ms", in[i].Ms)
			} // end of the answer check
			// Add the row.
			v.Rows = append(v.Rows, chartRow{Time: in[i].At.Format(chartRowLayout), Online: in[i].Online, Answer: ans})
		} // end of the loop
	} // end of the table
	// Hand it back.
	return v
} // end of buildChartsFor
