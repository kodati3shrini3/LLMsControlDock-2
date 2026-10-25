// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the element names (ids) that tie a heading to its help bubble.
	"fmt"
	// strings joins the abilities into one cell.
	"strings"
) // end of imports

// tipView is one help bubble as the page template needs it.
type tipView struct {
	// ID is the element name that the heading points at with aria-describedby (so screen readers read the bubble too).
	ID string
	// Plain, Example, Decide and AlsoKnown are the four parts from tooltips.go.
	Plain, Example, Decide, AlsoKnown string
} // end of tipView

// columnView is one column heading.
type columnView struct {
	// Title is the heading text.
	Title string
	// Tip is the help bubble.
	Tip tipView
} // end of columnView

// rowView is one model row: its name (the sticky first column) and the nine other cells.
type rowView struct {
	// Name is the model name, never shortened.
	Name string
	// Cells are the other nine columns, in order.
	Cells []string
	// Loaded is true when the model is in memory now; the page draws a green dot for it.
	Loaded bool
	// StateWord is "Loaded" or "Not loaded"; the page shows it next to the dot.
	StateWord string
} // end of rowView

// groupView is one category section.
type groupView struct {
	// Heading is the category's display name.
	Heading string
	// CountText says how many models are in it, such as "2 models".
	CountText string
	// Tip is the category's help bubble.
	Tip tipView
	// Rows are the models in this section.
	Rows []rowView
} // end of groupView

// tableView is everything the page needs to draw the Installed table.
type tableView struct {
	// Total is the number of installed models.
	Total int
	// Columns are the ten column headings.
	Columns []columnView
	// Groups are the non-empty category sections, in the fixed order.
	Groups []groupView
} // end of tableView

// makeTip looks up the help text for a heading and attaches the element name.
func makeTip(id, heading string) tipView {
	// A heading without a text gives empty parts; a test makes sure that never happens.
	t, _ := helpFor(heading)
	// Build the view.
	return tipView{ID: id, Plain: t.Plain, Example: t.Example, Decide: t.Decide, AlsoKnown: t.AlsoKnown}
} // end of makeTip

// countText says "1 model" or "N models".
func countText(n int) string {
	// One model is singular.
	if n == 1 {
		// Return the singular form.
		return "1 model"
	} // end of the singular case
	// Everything else is plural.
	return fmt.Sprintf("%d models", n)
} // end of countText

// stateWord is the state in words only; the page draws the dot itself.
func stateWord(loaded bool) string {
	// A loaded model.
	if loaded {
		// Say so.
		return "Loaded"
	} // end of the loaded case
	// Everything else.
	return "Not loaded"
} // end of stateWord

// buildTableView turns the installed and loaded lists into the data the page template draws.
func buildTableView(installed []installedModel, loaded []loadedModel) tableView {
	// Mark each model as loaded or not, then sort into category sections (both from the terminal version).
	groups := groupRows(combine(installed, loaded))
	// Start the view with the total.
	view := tableView{Total: len(installed)}
	// One heading per column, in the fixed order.
	for i, title := range installedColumns {
		// Add the heading with its bubble.
		view.Columns = append(view.Columns, columnView{Title: title, Tip: makeTip(fmt.Sprintf("tip-col-%d", i), title)})
	} // end of the column loop
	// One section per non-empty category.
	for gi, g := range groups {
		// Start the section with its heading, count and bubble.
		gv := groupView{Heading: g.Category.String(), CountText: countText(len(g.Rows)), Tip: makeTip(fmt.Sprintf("tip-cat-%d", gi), g.Category.String())}
		// One row per model.
		for _, r := range g.Rows {
			// A short name for the model's data.
			m := r.Model
			// Add the row: the name first, then the nine cells in the same order and formats as the terminal table.
			gv.Rows = append(gv.Rows, rowView{Name: m.Name, Loaded: r.Loaded, StateWord: stateWord(r.Loaded), Cells: []string{
				// Loaded or not, symbol plus words.
				stateText(r.Loaded),
				// Size on disk.
				formatSize(m.Size),
				// Family as reported.
				orDash(m.Details.Family),
				// Parameter size as reported.
				orDash(m.Details.ParameterSize),
				// Quantization level as reported.
				orDash(m.Details.QuantizationLevel),
				// Largest context the model supports.
				formatCount(m.Details.ContextLength),
				// Width of the model's vectors.
				formatCount(m.Details.EmbeddingLength),
				// Last modified, in UTC.
				formatTime(m.ModifiedAt),
				// Ollama's own words for the abilities.
				orDash(strings.Join(m.Capabilities, ", ")),
			}}) // end of the row
		} // end of the model loop
		// Add the finished section.
		view.Groups = append(view.Groups, gv)
	} // end of the group loop
	// Return the view.
	return view
} // end of buildTableView
