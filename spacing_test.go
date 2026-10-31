// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides the method name.
	"net/http"
	// regexp reads the margin value out of a rule.
	"regexp"
	// strings splits the value.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// marginTop returns the top margin of a rule: the first of the values of its margin line.
func marginTop(t *testing.T, css, selector string) string {
	// Mark this as a helper.
	t.Helper()
	// The rule.
	rule := ruleOf(css, selector)
	// The margin line.
	m := regexp.MustCompile(`margin:\s*([^;]+);`).FindStringSubmatch(rule)
	// It must have one.
	if m == nil {
		// Stop the test.
		t.Fatalf("%s has no margin line: %q", selector, rule)
	} // end of the presence check
	// The first value is the top margin.
	return strings.Fields(m[1])[0]
} // end of marginTop

// TestBoxesHaveEvenGaps checks the gap above the footer bar equals the gap between the boxes, so the spaces on the main page are all the same.
func TestBoxesHaveEvenGaps(t *testing.T) {
	// A fake and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// The stylesheet the monitor serves.
	_, _, css := get(t, rig.h, http.MethodGet, "/app.css")
	// The gap that boxes leave above and below themselves.
	box := marginTop(t, css, ".panel")
	// The gap above the footer bar.
	bar := marginTop(t, css, ".brandbar")
	// They must be the same.
	if box != bar {
		// Report the problem.
		t.Errorf("gap above the footer bar is %s, between the boxes %s", bar, box)
	} // end of the equality check
} // end of TestBoxesHaveEvenGaps
