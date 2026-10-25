// Package main tells Go that this test file belongs to the same program as the stylesheet.
package main

import ( // import lists the packages this test file uses.
	// regexp finds the rule in the stylesheet.
	"regexp"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestCodeFontMatchesText checks the stylesheet gives code (model names) the same size as the text around it and a font list that avoids the browser's shrinking of plain "monospace".
func TestCodeFontMatchesText(t *testing.T) {
	// Find the rule for code (the first line of the rule starts at the beginning of a line).
	m := regexp.MustCompile(`(?s)\ncode \{(.*?)\}`).FindStringSubmatch(string(appCSS))
	// The rule must exist.
	if m == nil {
		// Stop the test.
		t.Fatalf("the stylesheet has no rule for code")
	} // end of the existence check
	// The size must follow the surrounding text exactly.
	if !regexp.MustCompile(`font-size:\s*1em;`).MatchString(m[1]) {
		// Report the problem.
		t.Errorf("code does not take the size of its surroundings: %s", m[1])
	} // end of the size check
	// The font list must name a real monospace font first; a list of only "monospace" makes browsers shrink the text.
	if !regexp.MustCompile(`font-family:\s*ui-monospace,`).MatchString(m[1]) {
		// Report the problem.
		t.Errorf("code font list does not start with a named monospace font: %s", m[1])
	} // end of the family check
} // end of TestCodeFontMatchesText
