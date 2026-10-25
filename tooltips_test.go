// Package main tells Go that this test file belongs to the same program as tooltips.go.
package main

import ( // import lists the packages this test file uses.
	// strings searches and counts text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides a fixed clock for rendering the tables.
	"time"
	// unicode/utf8 counts characters, not bytes, so symbols like ● count once.
	"unicode/utf8"
) // end of imports

// allHeadings lists every heading that must have a tooltip: both tables' columns plus the four categories, without repeats.
func allHeadings() []string {
	// Remember which headings were added already.
	seen := map[string]bool{}
	// The list to return.
	var out []string
	// The two column lists first.
	for _, h := range append(append([]string{}, installedColumns...), loadedColumns...) {
		// Skip a heading that is already in (Model is in both tables).
		if !seen[h] {
			// Remember it.
			seen[h] = true
			// Add it.
			out = append(out, h)
		} // end of the repeat check
	} // end of the column loop
	// Then the four categories, by their display names.
	for c := categoryEmbedding; c <= categoryUnclassified; c++ {
		// Add the category's heading text.
		out = append(out, c.String())
	} // end of the category loop
	// Hand back the list.
	return out
} // end of allHeadings

// TestTooltipsCoverEveryHeading checks that every column and category has a tooltip, and that the table holds nothing extra.
func TestTooltipsCoverEveryHeading(t *testing.T) {
	// Go through every heading that needs help text.
	for _, h := range allHeadings() {
		// Look it up.
		if _, ok := helpFor(h); !ok {
			// Report the gap.
			t.Errorf("no tooltip for heading %q", h)
		} // end of the lookup check
	} // end of the heading loop
	// The number of tooltips must equal the number of headings, so no stray entry hides a typo in a key.
	if len(helpTexts) != len(allHeadings()) {
		// Report the difference.
		t.Errorf("%d tooltips for %d headings", len(helpTexts), len(allHeadings()))
	} // end of the count check
	// A heading that does not exist must give no tooltip.
	if _, ok := helpFor("No such heading"); ok {
		// Report the problem.
		t.Errorf("helpFor invented a tooltip")
	} // end of the unknown check
} // end of TestTooltipsCoverEveryHeading

// TestTooltipHeadingsMatchTheTables checks the heading lists in tooltips.go are the ones the tables really print.
func TestTooltipHeadingsMatchTheTables(t *testing.T) {
	// Draw both tables with one loaded model, so both have header rows.
	report := renderReport(realInstalled(t), []loadedModel{{Name: "medgemma:latest"}}, time.Unix(0, 0))
	// Take the first line of the Installed table: the line after "INSTALLED MODELS".
	installedHeader := lineAfter(report, "INSTALLED MODELS")
	// Take the header line of the Loaded table.
	loadedHeader := lineAfter(report, "LOADED MODELS")
	// Each list must appear in its header line, in order.
	for name, pair := range map[string]struct {
		// cols are the titles to look for.
		cols []string
		// line is the printed header line.
		line string
	}{ // the cases follow
		// The Installed table.
		"installed": {installedColumns, installedHeader},
		// The Loaded table.
		"loaded": {loadedColumns, loadedHeader},
	} { // end of the table map
		// Look from the start of the line forward, so the order is checked too.
		rest := pair.line
		// Go through every title.
		for _, col := range pair.cols {
			// Find it in what is left of the line.
			i := strings.Index(rest, col)
			// A missing title means the lists no longer match the table.
			if i < 0 {
				// Report the problem.
				t.Errorf("%s table header %q does not contain %q in order", name, pair.line, col)
				// Stop checking this table.
				break
			} // end of the find check
			// Continue after the title.
			rest = rest[i+len(col):]
		} // end of the title loop
	} // end of the table loop
} // end of TestTooltipHeadingsMatchTheTables

// lineAfter returns the first line after the line that starts with the given text.
func lineAfter(text, start string) string {
	// Split the report into lines.
	lines := strings.Split(text, "\n")
	// Look for the starting line.
	for i, l := range lines {
		// Found it, and there is a line after it.
		if strings.HasPrefix(l, start) && i+1 < len(lines) {
			// Return the next line.
			return lines[i+1]
		} // end of the match check
	} // end of the line loop
	// Not found.
	return ""
} // end of lineAfter

// TestTooltipPartsAreFilledAndShort checks that no part is empty and that every bubble stays short enough to read.
func TestTooltipPartsAreFilledAndShort(t *testing.T) {
	// The longest allowed length of each part, in characters.
	const maxPlain, maxExample, maxDecide = 130, 120, 100
	// Go through every heading.
	for _, h := range allHeadings() {
		// Look up its tooltip.
		tip, _ := helpFor(h)
		// Each part must be filled and within its limit.
		for _, p := range []struct {
			// part names the part for the message.
			part string
			// text is its content.
			text string
			// limit is the longest allowed length.
			limit int
		}{ // the cases follow
			// The plain-words part.
			{"Plain", tip.Plain, maxPlain},
			// The example part.
			{"Example", tip.Example, maxExample},
			// The decision part.
			{"Decide", tip.Decide, maxDecide},
		} { // end of the part table
			// An empty part is a mistake.
			if strings.TrimSpace(p.text) == "" {
				// Report the problem.
				t.Errorf("%q: %s is empty", h, p.part)
			} // end of the empty check
			// A part that is too long would not fit a bubble.
			if n := utf8.RuneCountInString(p.text); n > p.limit {
				// Report the problem.
				t.Errorf("%q: %s is %d characters, the limit is %d", h, p.part, n, p.limit)
			} // end of the length check
			// Markup characters must not appear: the page escapes them anyway, but plain text keeps the texts portable.
			if strings.ContainsAny(p.text, "<>{}") {
				// Report the problem.
				t.Errorf("%q: %s contains markup characters", h, p.part)
			} // end of the markup check
		} // end of the part loop
	} // end of the heading loop
} // end of TestTooltipPartsAreFilledAndShort

// TestTooltipAbbreviationsAreExplained checks the house rule: every abbreviation is followed by its full form in brackets, every time.
func TestTooltipAbbreviationsAreExplained(t *testing.T) {
	// The abbreviations used in the texts and their full forms.
	rules := map[string]string{
		// Gigabytes.
		"GB": "gigabytes",
		// Graphics processing unit.
		"GPU": "graphics processing unit",
		// Coordinated universal time.
		"UTC": "coordinated universal time",
	} // end of the rules
	// Go through every heading.
	for _, h := range allHeadings() {
		// Look up its tooltip.
		tip, _ := helpFor(h)
		// Join its parts into one text.
		all := tip.Plain + " | " + tip.Example + " | " + tip.Decide + " | " + tip.AlsoKnown
		// Check every abbreviation.
		for abbr, full := range rules {
			// How many times it appears, and how many times it appears with its full form.
			total := strings.Count(all, abbr)
			// The explained form.
			explained := strings.Count(all, abbr+" ("+full+")")
			// Every appearance must be an explained one.
			if total != explained {
				// Report the problem.
				t.Errorf("%q: %q appears %d times but is explained %d times", h, abbr, total, explained)
			} // end of the count check
		} // end of the abbreviation loop
	} // end of the heading loop
} // end of TestTooltipAbbreviationsAreExplained

// TestTooltipCategoryNames checks the "also known as" line: present for the three real categories, absent for the catch-all.
func TestTooltipCategoryNames(t *testing.T) {
	// Go through the four categories.
	for c := categoryEmbedding; c <= categoryUnclassified; c++ {
		// Look up the tooltip by the category's display name.
		tip, ok := helpFor(c.String())
		// It must exist.
		if !ok {
			// Report the problem.
			t.Errorf("no tooltip for category %q", c)
			// Go to the next category.
			continue
		} // end of the lookup check
		// The catch-all has no task names; the others must have them.
		if (c == categoryUnclassified) != (tip.AlsoKnown == "") {
			// Report the problem.
			t.Errorf("%q: unexpected 'also known as' value %q", c, tip.AlsoKnown)
		} // end of the task-name check
	} // end of the category loop
} // end of TestTooltipCategoryNames
