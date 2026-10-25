// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes provides a text buffer the table is written into.
	"bytes"
	// fmt builds formatted text.
	"fmt"
	// strconv turns whole numbers into text.
	"strconv"
	// strings joins, repeats and trims text.
	"strings"
	// text/tabwriter lines up columns for us (standard library only, requirement T1).
	"text/tabwriter"
	// time provides the timestamp type.
	"time"
) // end of imports

// The size units Ollama's own "ollama list" uses: decimal, so 1 GB is 1,000,000,000 bytes.
const (
	// bytesPerMB is one megabyte in bytes.
	bytesPerMB = 1000 * 1000
	// bytesPerGB is one gigabyte in bytes.
	bytesPerGB = 1000 * bytesPerMB
) // end of the size units

// formatSize turns a number of bytes into text such as 17.4 GB, 500 MB or 12 B.
func formatSize(b int64) string {
	// Pick the unit by size.
	switch {
	// One gigabyte or more: one decimal.
	case b >= bytesPerGB:
		// Divide as a decimal number so the fraction is kept.
		return fmt.Sprintf("%.1f GB", float64(b)/bytesPerGB)
	// One megabyte or more: no decimal.
	case b >= bytesPerMB:
		// Divide as a decimal number and round to a whole megabyte.
		return fmt.Sprintf("%.0f MB", float64(b)/bytesPerMB)
	} // end of the switch
	// Anything smaller is shown in bytes.
	return fmt.Sprintf("%d B", b)
} // end of formatSize

// formatTime shows a moment in UTC with a label, such as 2026-10-24 17:40 UTC; a zero time becomes "unknown".
func formatTime(t time.Time) string {
	// A zero time means Ollama did not report one.
	if t.IsZero() {
		// Say so plainly.
		return "unknown"
	} // end of the zero check
	// Convert to UTC and format with the label; Go's layout uses the fixed example date 2006-01-02 15:04.
	return t.UTC().Format("2006-01-02 15:04") + " UTC"
} // end of formatTime

// formatCount shows a whole number exactly, or a dash when it is zero (not reported).
func formatCount(n int64) string {
	// Zero means the field was missing or empty.
	if n == 0 {
		// Show a dash.
		return "-"
	} // end of the zero check
	// Show the exact number.
	return strconv.FormatInt(n, 10)
} // end of formatCount

// orDash returns the text, or a dash when it is empty.
func orDash(s string) string {
	// An empty text becomes a dash.
	if s == "" {
		// Show a dash.
		return "-"
	} // end of the empty check
	// Otherwise keep the text.
	return s
} // end of orDash

// trimLines removes the spaces the column aligner leaves at the end of each line.
func trimLines(s string) string {
	// Split into lines.
	lines := strings.Split(s, "\n")
	// Go through every line.
	for i, l := range lines {
		// Remove trailing spaces.
		lines[i] = strings.TrimRight(l, " ")
	} // end of the line loop
	// Join the lines again.
	return strings.Join(lines, "\n")
} // end of trimLines

// renderInstalled draws the Installed table: one column header row, then a heading row and the models for each non-empty category.
func renderInstalled(groups []categoryGroup) string {
	// The buffer the table is written into.
	var buf bytes.Buffer
	// Create the column aligner: no minimum width, 2 spaces between columns, spaces as padding.
	w := tabwriter.NewWriter(&buf, 0, 0, 2, ' ', 0)
	// The ten column titles; tabs separate the columns.
	fmt.Fprintln(w, "Model\tAbilities\tSize on disk\tFamily\tParameters\tQuantization\tLast modified\tState\tMax context length\tEmbedding length")
	// Go through every non-empty category.
	for _, g := range groups {
		// A heading row: the title, then empty cells so the columns stay in one block and keep their alignment.
		fmt.Fprintf(w, "== %s ==%s\n", g.Category, strings.Repeat("\t", 9))
		// Go through the models of this category.
		for _, row := range g.Rows {
			// A short name for the model's data.
			m := row.Model
			// One row: ten cells separated by tabs.
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
				// The model name, never shortened.
				m.Name,
				// Ollama's own words for the abilities.
				orDash(strings.Join(m.Capabilities, ", ")),
				// Size on disk.
				formatSize(m.Size),
				// Family as reported.
				orDash(m.Details.Family),
				// Parameter size as reported.
				orDash(m.Details.ParameterSize),
				// Quantization level as reported.
				orDash(m.Details.QuantizationLevel),
				// Last modified, in UTC.
				formatTime(m.ModifiedAt),
				// Loaded or not, symbol plus words.
				stateText(row.Loaded),
				// Largest context the model supports.
				formatCount(m.Details.ContextLength),
				// Width of the model's vectors.
				formatCount(m.Details.EmbeddingLength)) // end of the row
		} // end of the model loop
	} // end of the group loop
	// Write everything out; Flush runs the alignment.
	w.Flush()
	// Return the table without trailing spaces.
	return trimLines(buf.String())
} // end of renderInstalled

// renderLoaded draws the Loaded table, or a plain note when nothing is loaded.
func renderLoaded(loaded []loadedModel, now time.Time) string {
	// Nothing loaded: say so.
	if len(loaded) == 0 {
		// Return the note.
		return "(none loaded)"
	} // end of the empty check
	// The buffer the table is written into.
	var buf bytes.Buffer
	// Create the column aligner.
	w := tabwriter.NewWriter(&buf, 0, 0, 2, ' ', 0)
	// The five column titles.
	fmt.Fprintln(w, "Model\tSize (as reported)\tMemory on GPU\tLoaded context length\tTime until unload")
	// Go through every loaded model.
	for _, l := range loaded {
		// Read the unload time; ok is false when it is missing or unreadable.
		expires, ok := l.expiresTime()
		// One row: five cells separated by tabs.
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n",
			// The model name.
			l.Name,
			// Size as Ollama reports it.
			formatSize(l.Size),
			// How much of it sits in GPU memory.
			formatSize(l.SizeVRAM),
			// The context window of the running model.
			formatCount(l.ContextLength),
			// Time left, as text.
			formatRemaining(now, expires, ok)) // end of the row
	} // end of the loaded loop
	// Write everything out.
	w.Flush()
	// Return the table without trailing spaces.
	return trimLines(buf.String())
} // end of renderLoaded

// renderReport builds the whole -models output: the Installed table grouped by category, then the Loaded table.
func renderReport(installed []installedModel, loaded []loadedModel, now time.Time) string {
	// Mark each installed model as loaded or not.
	rows := combine(installed, loaded)
	// Sort the rows into categories.
	groups := groupRows(rows)
	// The installed section: a title with the count, then the table or a note.
	installedPart := fmt.Sprintf("INSTALLED MODELS (%d)\n", len(installed))
	// With no models installed, say so.
	if len(installed) == 0 {
		// Add the note.
		installedPart += "(none installed)"
	} else {
		// Add the table.
		installedPart += renderInstalled(groups)
	} // end of the installed table
	// The loaded section: a title with the count, then the table or a note.
	loadedPart := fmt.Sprintf("LOADED MODELS (%d)\n%s", len(loaded), renderLoaded(loaded, now))
	// Put the two sections together with a blank line between them.
	return installedPart + "\n\n" + loadedPart
} // end of renderReport
