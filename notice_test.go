// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// strings searches the notice text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestNoticeSaysWhatItMustSay checks the notice for the points that protect the reader and the developer, so an edit cannot quietly remove one.
func TestNoticeSaysWhatItMustSay(t *testing.T) {
	// The short notice.
	for _, w := range []string{"Informational only", "not a clinical validation", "patient care"} {
		// Missing.
		if !strings.Contains(noticeShort, w) {
			// Report it.
			t.Errorf("the short notice lacks %q", w)
		} // end of the check
	} // end of the short loop
	// The full notice, as one text.
	full := strings.Join(noticeFull, "\n")
	// The points.
	for _, w := range []string{
		// It is about speed and memory only.
		"speed and memory use", "quality, accuracy or safety",
		// It is not for clinical use.
		"not a clinical validation", "medical-device assessment", "regulatory submission", "certification", "patient care", "clinical, diagnostic or treatment decision",
		// The reader is responsible.
		"You are responsible for validating any model for your intended use",
		// No warranty and no liability, naming the company, its site and the developer.
		"\"as is\"", "without warranty of any kind", "To the fullest extent permitted by applicable law", companyName, "termgate.com", appDeveloper, "no liability", "misinterpretation", "contributors",
		// The limit of the clause.
		"Nothing here limits any liability that cannot be limited by law",
		// Third parties.
		"belong to their owners", "do not mean that their owners endorse",
	} {
		// Missing.
		if !strings.Contains(full, w) {
			// Report it.
			t.Errorf("the full notice lacks %q", w)
		} // end of the check
	} // end of the loop
	// Five paragraphs, each starting with its label.
	if len(noticeFull) != 5 {
		// Report it.
		t.Errorf("%d notice paragraphs, want 5", len(noticeFull))
	} // end of the count check
	// The labels.
	for i, label := range []string{"Purpose.", "Not for clinical use.", "Your responsibility.", "No warranty and no liability.", "Third parties."} {
		// The start.
		if !strings.HasPrefix(noticeFull[i], label) {
			// Report it.
			t.Errorf("paragraph %d does not start with %q", i, label)
		} // end of the check
	} // end of the loop
	// The notice makes no claim to be a legal guarantee.
	for _, bad := range []string{"guarantee", "legally binding", "fully protected"} {
		// Present.
		if strings.Contains(strings.ToLower(full), bad) {
			// Report it.
			t.Errorf("the notice must not say %q", bad)
		} // end of the check
	} // end of the loop
} // end of TestNoticeSaysWhatItMustSay
