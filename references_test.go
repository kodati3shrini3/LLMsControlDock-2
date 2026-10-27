// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/url checks the form of every address.
	"net/url"
	// regexp finds the reference markers in the text.
	"regexp"
	// strconv turns the marker numbers into integers.
	"strconv"
	// strings joins and searches text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// verifiedAddresses are the exact addresses that were opened and read in the session that wrote the list; a source may only be added here after its page was read.
var verifiedAddresses = map[int]string{
	// NVIDIA blog article.
	1: "https://developer.nvidia.com/blog/llm-benchmarking-fundamental-concepts",
	// NVIDIA NIM metrics page.
	2: "https://docs.nvidia.com/nim/benchmarking/llm/latest/metrics.html",
	// Artificial Analysis methodology.
	3: "https://artificialanalysis.ai/methodology/performance-benchmarking",
	// MLPerf Inference paper.
	4: "https://arxiv.org/abs/1911.02549",
	// Ollama API usage page.
	5: "https://docs.ollama.com/api/usage",
	// MTEB paper.
	6: "https://arxiv.org/abs/2210.07316v3",
} // end of verifiedAddresses

// referenceMarker finds a number in brackets, such as [3].
var referenceMarker = regexp.MustCompile(`\[(\d+)\]`)

// citingTexts gathers every piece of text on the comparison page that may carry a reference marker.
func citingTexts() []string {
	// The method answers.
	var out []string
	// Each row.
	for _, h := range howRows() {
		// The answer.
		out = append(out, h.Answer)
	} // end of the loop
	// The reasons of every kind of group.
	for _, k := range []int{0, 1, 2, 3, 4, classUnknown, -2} {
		// The reason.
		out = append(out, groupWhy(k))
	} // end of the group loop
	// The first sentence of the findings.
	p := buildCompare([]perfRun{okRun("a:4b", 100)}, 0, nil, false)
	// All findings.
	out = append(out, p.Findings...)
	// The cautions.
	out = append(out, p.Notes...)
	// The notice.
	out = append(out, noticeShort)
	// And the full notice.
	out = append(out, noticeFull...)
	// The texts.
	return out
} // end of citingTexts

// TestReferenceListIsWellFormedAndVerified checks the list entry by entry: numbering, content and the exact verified addresses.
func TestReferenceListIsWellFormedAndVerified(t *testing.T) {
	// The list must not be empty and must match the verified set in size.
	if len(compareReferences) == 0 || len(compareReferences) != len(verifiedAddresses) {
		// Stop the test.
		t.Fatalf("%d references, %d verified", len(compareReferences), len(verifiedAddresses))
	} // end of the size check
	// Addresses seen so far.
	seen := map[string]bool{}
	// Check each entry.
	for i, r := range compareReferences {
		// Numbers run from 1 without gaps.
		if r.N != i+1 {
			// Report it.
			t.Errorf("entry %d has number %d", i, r.N)
		} // end of the number check
		// No field may be empty.
		for name, v := range map[string]string{"authors": r.Authors, "title": r.Title, "where": r.Where, "url": r.URL, "used": r.Used} {
			// An empty field.
			if strings.TrimSpace(v) == "" {
				// Report it.
				t.Errorf("reference %d has an empty %s", r.N, name)
			} // end of the check
		} // end of the field loop
		// The address must be exactly the one that was opened.
		if r.URL != verifiedAddresses[r.N] {
			// Report it.
			t.Errorf("reference %d address %q is not the verified %q", r.N, r.URL, verifiedAddresses[r.N])
		} // end of the address check
		// The address must be a plain https address with a host, and no password, query tricks or fragment.
		u, err := url.Parse(r.URL)
		// A parse failure.
		if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
			// Report it.
			t.Errorf("reference %d address is not a plain https address: %q", r.N, r.URL)
		} // end of the form check
		// No address twice.
		if seen[r.URL] {
			// Report it.
			t.Errorf("address %q appears twice", r.URL)
		} // end of the repeat check
		// Remember it.
		seen[r.URL] = true
	} // end of the loop
	// The date of the reading is written the way the page shows it.
	if !regexp.MustCompile(`^\d{1,2} [A-Z][a-z]+ 20\d\d$`).MatchString(referencesChecked) {
		// Report it.
		t.Errorf("referencesChecked = %q", referencesChecked)
	} // end of the date check
} // end of TestReferenceListIsWellFormedAndVerified

// TestEveryMarkerPointsAtAReferenceAndEveryReferenceIsCited checks the text and the list agree in both directions.
func TestEveryMarkerPointsAtAReferenceAndEveryReferenceIsCited(t *testing.T) {
	// Which numbers are cited anywhere.
	cited := map[int]bool{}
	// Every text.
	for _, text := range citingTexts() {
		// Every marker in it.
		for _, m := range referenceMarker.FindAllStringSubmatch(text, -1) {
			// The number.
			n, _ := strconv.Atoi(m[1])
			// It must exist.
			if n < 1 || n > len(compareReferences) {
				// Report it.
				t.Errorf("marker [%d] points at no reference in: %.60s", n, text)
			} // end of the existence check
			// Remember it.
			cited[n] = true
		} // end of the marker loop
	} // end of the text loop
	// Every reference must be cited at least once, so the list holds nothing that the text does not use.
	for _, r := range compareReferences {
		// Not cited.
		if !cited[r.N] {
			// Report it.
			t.Errorf("reference %d is never cited", r.N)
		} // end of the check
	} // end of the loop
	// The claims that must carry a source: the method rows about test design, token counting, groups and embedding models.
	need := map[string][]string{
		// How a test is run.
		"How is a test run?": {"[1]", "[3]"},
		// Why characters.
		"Why characters per second?": {"[3]"},
		// What is measured.
		"What is measured?": {"[4]"},
		// The figures come from Ollama.
		"How are the figures worked out?": {"[5]"},
		// Nothing across groups.
		"Why is nothing ranked across groups?": {"[2]", "[4]"},
		// Embedding models.
		"How are the groups chosen?": {"[6]"},
	} // end of the needs
	// Check each.
	for _, h := range howRows() {
		// The markers needed here.
		for _, m := range need[h.Question] {
			// Missing.
			if !strings.Contains(h.Answer, m) {
				// Report it.
				t.Errorf("%q lacks marker %s", h.Question, m)
			} // end of the check
		} // end of the marker loop
	} // end of the row loop
	// The statements that are the program's own choice say so in plain words.
	own := strings.Join(citingTexts(), "\n")
	// The words.
	for _, w := range []string{"this program's own choice, not an industry standard", "this program's own rule", "these two formulas are this program's own calculations"} {
		// Missing, ignoring case.
		if !strings.Contains(strings.ToLower(own), w) {
			// Report it.
			t.Errorf("the page does not say %q", w)
		} // end of the check
	} // end of the loop
} // end of TestEveryMarkerPointsAtAReferenceAndEveryReferenceIsCited
