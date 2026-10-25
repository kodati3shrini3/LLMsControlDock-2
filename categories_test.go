// Package main tells Go that this test file belongs to the same program as categories.go.
package main

import ( // import lists the packages this test file uses.
	// strings joins names so a whole group can be compared at once.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestCategorize checks every rule, including the edge cases.
func TestCategorize(t *testing.T) {
	// A table of cases: capabilities and the expected category.
	cases := []struct {
		// name labels the case.
		name string
		// caps is the capabilities list.
		caps []string
		// want is the expected category.
		want category
	}{
		// Rule 1: a plain embedding model.
		{"embedding", []string{"embedding"}, categoryEmbedding},
		// Rule 1 wins even when completion is also reported.
		{"embedding and completion", []string{"completion", "embedding"}, categoryEmbedding},
		// Rule 2: completion with vision.
		{"completion and vision", []string{"completion", "vision"}, categoryMultimodal},
		// Rule 2: completion with audio only.
		{"completion and audio", []string{"completion", "audio"}, categoryMultimodal},
		// Rule 2: extra words such as tools and thinking do not change the result.
		{"all abilities", []string{"completion", "vision", "audio", "tools", "thinking"}, categoryMultimodal},
		// Rule 3: completion alone.
		{"completion only", []string{"completion"}, categoryText},
		// Rule 3: completion with tools.
		{"completion and tools", []string{"completion", "tools"}, categoryText},
		// Rule 3: an unknown extra word is ignored.
		{"completion and an unknown word", []string{"completion", "somethingnew"}, categoryText},
		// Rule 4: vision alone is not enough.
		{"vision only", []string{"vision"}, categoryUnclassified},
		// Rule 4: tools alone is not enough.
		{"tools only", []string{"tools"}, categoryUnclassified},
		// Rule 4: an empty list.
		{"empty list", []string{}, categoryUnclassified},
		// Rule 4: a missing list (older Ollama versions).
		{"missing list", nil, categoryUnclassified},
		// Exact spelling matters: a capital letter is a different word.
		{"wrong case", []string{"Completion"}, categoryUnclassified},
	} // end of the case table
	// Go through every case.
	for _, tc := range cases {
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Call the function under test.
			if got := categorize(tc.caps); got != tc.want {
				// Report the difference.
				t.Errorf("categorize(%v) = %v, want %v", tc.caps, got, tc.want)
			} // end of the check
		}) // end of the subtest
	} // end of the case loop
} // end of TestCategorize

// TestCategoryNames checks the display names the user confirmed.
func TestCategoryNames(t *testing.T) {
	// A table of categories and their names.
	cases := map[category]string{
		// Embedding.
		categoryEmbedding: "Search and similarity (embedding)",
		// Multimodal.
		categoryMultimodal: "Chat with images or audio (multimodal)",
		// Text only.
		categoryText: "Chat and writing (text only)",
		// Everything else.
		categoryUnclassified: "Not yet classified",
	} // end of the table
	// Go through every entry.
	for c, want := range cases {
		// Compare the name.
		if got := c.String(); got != want {
			// Report the difference.
			t.Errorf("category %d is named %q, want %q", int(c), got, want)
		} // end of the check
	} // end of the loop
} // end of TestCategoryNames

// namesOf joins the model names of one group, so a test can compare the whole group in one line.
func namesOf(g categoryGroup) string {
	// Collect the names.
	var names []string
	// Go through every row.
	for _, r := range g.Rows {
		// Add the name.
		names = append(names, r.Model.Name)
	} // end of the row loop
	// Join them with commas.
	return strings.Join(names, ", ")
} // end of namesOf

// TestGroupRowsReal checks that the user's six real models land exactly where the rules say, sorted by name.
func TestGroupRowsReal(t *testing.T) {
	// Build the rows from the six real models (realModels comes from models_test.go).
	var rows []installedRow
	// Go through the real data.
	for _, r := range realModels {
		// Add a row with the name and the capabilities; none is loaded.
		rows = append(rows, installedRow{Model: installedModel{Name: r.name, Capabilities: r.caps}})
	} // end of the loop
	// Call the function under test.
	groups := groupRows(rows)
	// Exactly two groups: the text-only and unclassified sections are empty and therefore hidden.
	if len(groups) != 2 {
		// Stop the test.
		t.Fatalf("got %d groups, want 2", len(groups))
	} // end of the count check
	// The first group is Search and similarity.
	if groups[0].Category != categoryEmbedding {
		// Report the difference.
		t.Errorf("group 0 is %v, want %v", groups[0].Category, categoryEmbedding)
	} // end of the first-group check
	// Its models, sorted by name.
	if got, want := namesOf(groups[0]), "hf.co/NeoRoth/nemotron-3-embed-1b-gguf:F16, rjmalagon/gte-qwen2-instruct:1.5b-f16"; got != want {
		// Report the difference.
		t.Errorf("group 0 models = %q, want %q", got, want)
	} // end of the first-names check
	// The second group is the multimodal chat models.
	if groups[1].Category != categoryMultimodal {
		// Report the difference.
		t.Errorf("group 1 is %v, want %v", groups[1].Category, categoryMultimodal)
	} // end of the second-group check
	// Its models, sorted by name.
	if got, want := namesOf(groups[1]), "gemma4:e4b, medgemma:27b, medgemma:latest, qwen3.6:27b"; got != want {
		// Report the difference.
		t.Errorf("group 1 models = %q, want %q", got, want)
	} // end of the second-names check
} // end of TestGroupRowsReal

// TestGroupRowsOrderAndSorting checks the fixed group order, hiding, and case-insensitive stable sorting.
func TestGroupRowsOrderAndSorting(t *testing.T) {
	// Rows given in the opposite order to the display order, with names that test the sorting.
	rows := []installedRow{
		// Unclassified first in the input.
		{Model: installedModel{Name: "odd:1", Capabilities: []string{"tools"}}},
		// Text-only, with a capital letter that must not change the sort.
		{Model: installedModel{Name: "Zeta:1", Capabilities: []string{"completion"}}},
		// Text-only, which must sort before Zeta even though it is lowercase.
		{Model: installedModel{Name: "alpha:1", Capabilities: []string{"completion"}}},
		// Multimodal.
		{Model: installedModel{Name: "vis:1", Capabilities: []string{"completion", "vision"}}},
		// Embedding.
		{Model: installedModel{Name: "emb:1", Capabilities: []string{"embedding"}}},
	} // end of the rows
	// Call the function under test.
	groups := groupRows(rows)
	// All four categories are present.
	if len(groups) != 4 {
		// Stop the test.
		t.Fatalf("got %d groups, want 4", len(groups))
	} // end of the count check
	// The groups must come in the fixed order.
	wantOrder := []category{categoryEmbedding, categoryMultimodal, categoryText, categoryUnclassified}
	// Compare each position.
	for i, want := range wantOrder {
		// Compare the category.
		if groups[i].Category != want {
			// Report the difference.
			t.Errorf("group %d is %v, want %v", i, groups[i].Category, want)
		} // end of the category check
	} // end of the order loop
	// The text-only group must be sorted ignoring capital letters.
	if got, want := namesOf(groups[2]), "alpha:1, Zeta:1"; got != want {
		// Report the difference.
		t.Errorf("text-only group = %q, want %q", got, want)
	} // end of the sort check
} // end of TestGroupRowsOrderAndSorting

// TestGroupRowsEmpty checks that no rows give no groups.
func TestGroupRowsEmpty(t *testing.T) {
	// Call the function under test with nothing.
	if got := groupRows(nil); len(got) != 0 {
		// Report the difference.
		t.Errorf("got %d groups, want 0", len(got))
	} // end of the check
} // end of TestGroupRowsEmpty
