#!/usr/bin/env bash
# Script 15: Step 4d, adds the category rules and grouping (categories.go), tested with the user's six real models.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write categories.go; the quoted EOF_CAT marker saves every character exactly as typed.
cat > categories.go << 'EOF_CAT'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// sort orders the models inside each group.
	"sort"
	// strings lowercases names so sorting ignores capital letters.
	"strings"
) // end of imports

// category says which section of the Installed table a model belongs to.
type category int

// The four categories; iota counts up from 0, and that number is also the order the groups are shown in.
const (
	// categoryEmbedding is for models that turn text into numbers for search and similarity.
	categoryEmbedding category = iota
	// categoryMultimodal is for chat models that can also take images or audio.
	categoryMultimodal
	// categoryText is for chat models that work with text only.
	categoryText
	// categoryUnclassified is for everything the rules do not cover.
	categoryUnclassified
) // end of the category constants

// String gives the category its display name.
func (c category) String() string {
	// Pick the name that goes with the value.
	switch c {
	// Embedding models.
	case categoryEmbedding:
		// Return the display name.
		return "Search and similarity (embedding)"
	// Multimodal chat models.
	case categoryMultimodal:
		// Return the display name.
		return "Chat with images or audio (multimodal)"
	// Text-only chat models.
	case categoryText:
		// Return the display name.
		return "Chat and writing (text only)"
	} // end of the switch
	// Anything else is not yet classified.
	return "Not yet classified"
} // end of String

// hasCapability reports whether the list contains the wanted word exactly as Ollama spells it.
func hasCapability(caps []string, want string) bool {
	// Look at every word in the list.
	for _, c := range caps {
		// An exact match is enough.
		if c == want {
			// Found it.
			return true
		} // end of the match check
	} // end of the word loop
	// Not found.
	return false
} // end of hasCapability

// categorize applies the rules in order: the first rule that fits wins; words the rules do not mention are ignored.
func categorize(caps []string) category {
	// Rule 1: an embedding model, even if it also reports completion.
	if hasCapability(caps, "embedding") {
		// Return the category.
		return categoryEmbedding
	} // end of rule 1
	// Rules 2 and 3 need completion, which means the model can generate text.
	if hasCapability(caps, "completion") {
		// Rule 2: completion plus vision or audio.
		if hasCapability(caps, "vision") || hasCapability(caps, "audio") {
			// Return the category.
			return categoryMultimodal
		} // end of rule 2
		// Rule 3: completion without vision or audio.
		return categoryText
	} // end of the completion check
	// Rule 4: nothing above fits, including a missing or empty list.
	return categoryUnclassified
} // end of categorize

// categoryGroup is one section of the Installed table.
type categoryGroup struct {
	// Category says which section this is.
	Category category
	// Rows are the models in this section, sorted by name.
	Rows []installedRow
} // end of categoryGroup

// groupRows sorts the rows into sections in the fixed order, hides empty sections, and sorts each section by name.
func groupRows(rows []installedRow) []categoryGroup {
	// One bucket per category, indexed by the category's number.
	buckets := make([][]installedRow, categoryUnclassified+1)
	// Put every row into the bucket its capabilities select.
	for _, row := range rows {
		// Find the category.
		c := categorize(row.Model.Capabilities)
		// Add the row to that bucket.
		buckets[c] = append(buckets[c], row)
	} // end of the row loop
	// Prepare the result.
	var groups []categoryGroup
	// Go through the buckets in category order.
	for c, bucket := range buckets {
		// Skip empty sections.
		if len(bucket) == 0 {
			// Move on to the next bucket.
			continue
		} // end of the empty check
		// Sort by lowercase name; the sort is stable, so equal names keep their original order.
		sort.SliceStable(bucket, func(i, j int) bool {
			// Compare two names ignoring capital letters.
			return strings.ToLower(bucket[i].Model.Name) < strings.ToLower(bucket[j].Model.Name)
		}) // end of the sort
		// Add the section to the result.
		groups = append(groups, categoryGroup{Category: category(c), Rows: bucket})
	} // end of the bucket loop
	// Return the sections.
	return groups
} // end of groupRows
EOF_CAT

# Write categories_test.go; the quoted EOF_CATT marker saves every character exactly as typed.
cat > categories_test.go << 'EOF_CATT'
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
EOF_CATT

# Fail if any Go file is not formatted the standard way (gofmt -l lists offenders).
unformatted="$(gofmt -l .)"
# An empty list means everything is formatted.
if [ -n "$unformatted" ]; then
  # Show the offenders and stop.
  echo "NOT FORMATTED: $unformatted"; exit 1
fi # end of the format check
# Ask Go to look for suspicious constructs in the program and the tests.
go vet ./...
# Run every test; -v lists each one, -count=1 forbids cached results so the tests really run.
go test -v -count=1 ./...
# Build the native executable to prove the whole program still compiles.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build worked.
echo "PASS  build"
