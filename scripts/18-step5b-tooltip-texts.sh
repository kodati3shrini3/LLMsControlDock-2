#!/usr/bin/env bash
# Script 18: Step 5b, adds the tooltip texts (tooltips.go) and their tests (tooltips_test.go), then tests and builds.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write tooltips.go; the quoted EOF_TIPS marker saves every character exactly as typed.
cat > tooltips.go << 'EOF_TIPS'
// Package main tells Go that this folder builds into a runnable program.
package main

// tooltip is the help text for one heading: three short parts, plus an optional "also known as" line.
type tooltip struct {
	// Plain says what the heading means, in plain words.
	Plain string
	// Example gives a real case, taken from the six models this project was built with.
	Example string
	// Decide says what the person can decide with it.
	Decide string
	// AlsoKnown lists the common machine-learning task names (empty when there are none).
	AlsoKnown string
} // end of tooltip

// installedColumns are the ten column titles of the Installed table, in order; a test checks they match render.go.
var installedColumns = []string{"Model", "Abilities", "Size on disk", "Family", "Parameters", "Quantization", "Last modified", "State", "Max context length", "Embedding length"}

// loadedColumns are the five column titles of the Loaded table, in order; a test checks they match render.go.
var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Loaded context length", "Time until unload"}

// helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
// The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
var helpTexts = map[string]tooltip{
	// The model name, shared by both tables.
	"Model": {
		// What it means.
		Plain: "The model's name. The part after the colon is a version or size tag.",
		// A real case.
		Example: "medgemma:latest and medgemma:27b are two versions of one model.",
		// What it helps with.
		Decide: "Which exact model you are looking at.",
	}, // end of Model
	// The abilities list.
	"Abilities": {
		// What it means.
		Plain: "The things this model says it can do, in Ollama's own words.",
		// A real case.
		Example: "gemma4:e4b lists completion, vision, audio, tools and thinking.",
		// What it helps with.
		Decide: "Whether the model fits the job: images, audio, tool use or plain chat.",
	}, // end of Abilities
	// The size on disk.
	"Size on disk": {
		// What it means.
		Plain: "How much storage the model files take.",
		// A real case.
		Example: "medgemma:latest takes 3.3 GB (gigabytes); medgemma:27b takes 17.4 GB (gigabytes).",
		// What it helps with.
		Decide: "Whether it fits your disk, and a hint of how much memory it needs.",
	}, // end of Size on disk
	// The model family.
	"Family": {
		// What it means.
		Plain: "The model's family: the design it was built from.",
		// A real case.
		Example: "Both medgemma models belong to the gemma3 family.",
		// What it helps with.
		Decide: "Spotting models that were built the same way.",
	}, // end of Family
	// The parameter count.
	"Parameters": {
		// What it means.
		Plain: "A rough count of the numbers the model learned; B means billions. More is usually smarter but slower.",
		// A real case.
		Example: "medgemma:27b has 27.4B (billions); medgemma:latest has 4.3B (billions).",
		// What it helps with.
		Decide: "Quality versus speed.",
	}, // end of Parameters
	// The quantization level.
	"Quantization": {
		// What it means.
		Plain: "How tightly the numbers are squeezed to save memory. Q4 squeezes more; F16 keeps full detail.",
		// A real case.
		Example: "Your chat models use Q4_K_M; your embedding models use F16.",
		// What it helps with.
		Decide: "Smaller and faster, or more precise.",
	}, // end of Quantization
	// The last-modified time.
	"Last modified": {
		// What it means.
		Plain: "When the model files last changed, shown in UTC (coordinated universal time).",
		// A real case.
		Example: "medgemma:27b changed on 2026-10-24 at 17:40 UTC (coordinated universal time).",
		// What it helps with.
		Decide: "Telling fresh models from old ones.",
	}, // end of Last modified
	// The loaded or not-loaded state.
	"State": {
		// What it means.
		Plain: "Whether the model is in memory now (● Loaded) or only stored on disk (○ Not loaded).",
		// A real case.
		Example: "A ○ Not loaded model needs a moment to load before it answers.",
		// What it helps with.
		Decide: "Whether the next question answers at once or after a load.",
	}, // end of State
	// The largest context the model supports.
	"Max context length": {
		// What it means.
		Plain: "The most text the model can keep in mind at once, counted in tokens (word pieces).",
		// A real case.
		Example: "The medgemma models: 131072. qwen3.6:27b: 262144.",
		// What it helps with.
		Decide: "Whether it can handle long documents.",
	}, // end of Max context length
	// The embedding length.
	"Embedding length": {
		// What it means.
		Plain: "How many numbers the model uses to describe one piece of text.",
		// A real case.
		Example: "rjmalagon/gte-qwen2-instruct:1.5b-f16 uses 1536 numbers.",
		// What it helps with.
		Decide: "Matching a model to the search index it feeds.",
	}, // end of Embedding length
	// The size of a loaded model.
	"Size (as reported)": {
		// What it means.
		Plain: "The size Ollama reports for the model while it is in memory.",
		// A real case.
		Example: "medgemma:latest: 3.8 GB (gigabytes) in memory, 3.3 GB (gigabytes) on disk.",
		// What it helps with.
		Decide: "How much room it takes while running.",
	}, // end of Size (as reported)
	// The graphics memory in use.
	"Memory on GPU": {
		// What it means.
		Plain: "How much memory on the GPU (graphics processing unit) the model is using.",
		// A real case.
		Example: "medgemma:latest: 3.8 GB (gigabytes).",
		// What it helps with.
		Decide: "Whether the GPU (graphics processing unit) has room for it.",
	}, // end of Memory on GPU
	// The context length of a loaded model.
	"Loaded context length": {
		// What it means.
		Plain: "The context size set for this loaded copy. A bigger one needs more memory.",
		// A real case.
		Example: "medgemma:latest: 131072.",
		// What it helps with.
		Decide: "Why memory use changes from one load to another.",
	}, // end of Loaded context length
	// The countdown to unloading.
	"Time until unload": {
		// What it means.
		Plain: "A countdown until Ollama frees the model from memory.",
		// A real case.
		Example: "5 min 0 s right after a load with the default keep time.",
		// What it helps with.
		Decide: "When memory will free up by itself.",
	}, // end of Time until unload
	// The embedding category.
	"Search and similarity (embedding)": {
		// What it means.
		Plain: "These models don't chat. They turn text into numbers so a computer can find texts with similar meaning.",
		// A real case.
		Example: "rjmalagon/gte-qwen2-instruct:1.5b-f16",
		// What it helps with.
		Decide: "Use for search or retrieval, not for answers.",
		// The common task names.
		AlsoKnown: "Feature Extraction, Sentence Similarity",
	}, // end of the embedding category
	// The multimodal category.
	"Chat with images or audio (multimodal)": {
		// What it means.
		Plain: "Chat models that can also look at pictures or listen to audio.",
		// A real case.
		Example: "medgemma:27b (images), gemma4:e4b (images and audio)",
		// What it helps with.
		Decide: "Use when your input is not only text.",
		// The common task names.
		AlsoKnown: "Image-Text-to-Text, Audio-Text-to-Text",
	}, // end of the multimodal category
	// The text-only category.
	"Chat and writing (text only)": {
		// What it means.
		Plain: "Chat models that read and write text only.",
		// A real case: honest about having none.
		Example: "None of your six models are in this group right now.",
		// What it helps with.
		Decide: "A lighter choice when no images are needed.",
		// The common task names.
		AlsoKnown: "Text Generation",
	}, // end of the text-only category
	// The catch-all category.
	"Not yet classified": {
		// What it means.
		Plain: "The abilities list did not tell us what this is, so it is shown here instead of being hidden.",
		// A real case: honest about when it appears.
		Example: "Appears only if a model reports no known abilities.",
		// What it helps with.
		Decide: "Check the model's own page to see what it does.",
	}, // end of the catch-all category
} // end of helpTexts

// helpFor returns the tooltip for a heading, and false when there is none.
func helpFor(heading string) (tooltip, bool) {
	// Look the heading up in the table.
	t, ok := helpTexts[heading]
	// Hand back both answers.
	return t, ok
} // end of helpFor
EOF_TIPS

# Write tooltips_test.go; the quoted EOF_TT marker saves every character exactly as typed.
cat > tooltips_test.go << 'EOF_TT'
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
	}{
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
		}{
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
EOF_TT

# Fail if any Go file is not formatted the standard way (gofmt -l lists offenders).
unformatted="$(gofmt -l .)"
# An empty list means everything is formatted.
if [ -n "$unformatted" ]; then
  # Show the offenders and stop.
  echo "NOT FORMATTED: $unformatted"; exit 1
fi # end of the format check
# Ask Go to look for suspicious constructs in the program and the tests.
go vet ./...
# Run the new tooltip tests with their names shown (-count=1 forces a fresh run, never a cached one).
go test -count=1 -v -run 'Tooltip' ./... | grep -E '^(--- |ok|FAIL)'
# Run every test quietly; a failure stops the script and shows Go's own message.
go test -count=1 ./...
# Make sure the output folder exists.
mkdir -p bin
# Build the native executable (CGO_ENABLED=0 = no C libraries; -trimpath removes local paths).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build and tests worked.
echo "PASS  tests and build"
# Count the tooltip entries in the texts file (each heading key is a line that starts with a tab and a quote and ends with an opening brace).
echo "Tooltip entries: $(grep -cP '^\t"[^"]+": \{$' tooltips.go)"
