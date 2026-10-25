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
