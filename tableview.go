// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the element names (ids) that tie a heading to its help bubble.
	"fmt"
	// strings joins the abilities into one cell.
	"strings"
	// time provides the clock reading the unload timer is worked out from.
	"time"
) // end of imports

// tipView is one help bubble as the page template needs it.
type tipView struct {
	// Title is the heading text the bubble belongs to (used where the heading is drawn from the bubble data).
	Title string
	// ID is the element name that the heading points at with aria-describedby (so screen readers read the bubble too).
	ID string
	// Plain, Example, Decide and AlsoKnown are the four parts from tooltips.go.
	Plain, Example, Decide, AlsoKnown string
} // end of tipView

// columnView is one column heading.
type columnView struct {
	// Title is the heading text.
	Title string
	// Lines is the heading split into the lines it is drawn on (one line for most headings).
	Lines []string
	// Tip is the help bubble.
	Tip tipView
} // end of columnView

// headingLines splits the three long column headings into two lines, to save width; every other heading stays on one line. The full title is still used for the help text and for the terminal view.
func headingLines(title string) []string {
	// The three headings and where they break.
	switch title {
	// Size on disk.
	case "Size on disk":
		// Two lines.
		return []string{"Size", "on disk"}
	// Max context length.
	case "Max context length":
		// Two lines.
		return []string{"Max context", "length"}
	// Embedding length.
	case "Embedding length":
		// Two lines.
		return []string{"Embedding", "length"}
	} // end of the switch
	// Everything else is one line.
	return []string{title}
} // end of headingLines

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
	// Timer is the text of the unload timer for a loaded model (empty for a model that is not loaded).
	Timer string
	// TimerSeconds is the whole seconds left when the timer should tick (0 means a fixed text such as "stays loaded").
	TimerSeconds int
	// TimerExpired is true when the unload time has arrived but Ollama still lists the model; the page asks again soon.
	TimerExpired bool
	// Tags are the plain-word tags under the name: size class, memory of a conversation and abilities.
	Tags []string
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

// deletedRow is one greyed-out row for a model that was deleted.
type deletedRow struct {
	// Name is the model name.
	Name string
	// SizeText is the size it had, in words.
	SizeText string
	// WhenText is the deletion time in words, with the year and the computer's own time zone.
	WhenText string
	// Tags are the plain-word tags of the model, from what was saved at deletion or, failing that, from its saved tests; empty when nothing is known.
	Tags []string
} // end of deletedRow

// deletedRows turns the remembered deleted models into rows; a name that is installed again is left out (it was restored, or pulled by hand).
func deletedRows(items []deletedModel, installed []installedModel, facts func(string) (string, int64, bool)) []deletedRow {
	// The rows to show.
	var rows []deletedRow
	// Go through the remembered models, newest first.
	for _, d := range items {
		// Installed again: no ghost.
		if _, back := findInstalled(installed, d.Name); back {
			// Skip it.
			continue
		} // end of the installed check
		// Add the row.
		rows = append(rows, deletedRow{Name: d.Name, SizeText: formatSize(d.Size), WhenText: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST"), Tags: deletedTags(d, facts)})
	} // end of the loop
	// Hand back.
	return rows
} // end of deletedRows

// tableView is everything the page needs to draw the Installed table.
type tableView struct {
	// Total is the number of installed models.
	Total int
	// Columns are the ten column headings.
	Columns []columnView
	// Groups are the non-empty category sections, in the fixed order.
	Groups []groupView
	// Deleted are the models this monitor deleted and that are not installed now; they are drawn greyed out at the end of the table.
	Deleted []deletedRow
	// GroupedTip is the help bubble "How models are grouped", shown above the table.
	GroupedTip tipView
} // end of tableView

// makeTip looks up the help text for a heading and attaches the element name.
func makeTip(id, heading string) tipView {
	// A heading without a text gives empty parts; a test makes sure that never happens.
	t, _ := helpFor(heading)
	// Build the view.
	return tipView{Title: heading, ID: id, Plain: t.Plain, Example: t.Example, Decide: t.Decide, AlsoKnown: t.AlsoKnown}
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

// longKeepText is shown for a model that Ollama keeps loaded indefinitely (its keep-alive is set to never unload).
const longKeepText = "stays loaded"

// timerFor works out the text, the ticking seconds and the "time has arrived" flag of the unload timer for one loaded model.
func timerFor(l loadedModel, now time.Time) (string, int, bool) {
	// Read the unload time; ok is false when it is missing or unreadable.
	expires, ok := l.expiresTime()
	// No usable time: say so, and do not tick.
	if !ok {
		// The same wording as the terminal table.
		return formatRemaining(now, expires, ok), 0, false
	} // end of the no-time case
	// How long is left.
	left := expires.Sub(now)
	// So far away that the model is set to stay loaded: a fixed text, no ticking.
	if left > 30*24*time.Hour {
		// Say it stays loaded.
		return longKeepText, 0, false
	} // end of the far-away case
	// The ticking seconds; 0 here means the time has arrived or passed.
	secs := remainingSeconds(now, expires, ok)
	// Time has arrived: the text says so, and the page asks Ollama again soon.
	if secs == 0 {
		// The same wording as the terminal table, flagged as arrived.
		return formatRemaining(now, expires, ok), 0, true
	} // end of the arrived case
	// A normal countdown: the text and the seconds the script ticks from.
	return formatRemaining(now, expires, ok), secs, false
} // end of timerFor

// buildTableView builds the page data using the current clock.
func buildTableView(installed []installedModel, loaded []loadedModel) tableView {
	// Delegate with the real time; tests call buildTableViewAt with a fixed time.
	return buildTableViewAt(installed, loaded, time.Now())
} // end of buildTableView

// buildTableViewAt turns the installed and loaded lists into the data the page template draws, using the given moment for the unload timers.
func buildTableViewAt(installed []installedModel, loaded []loadedModel, now time.Time) tableView {
	// Remember each loaded model by name, so a row can find its unload time.
	byName := make(map[string]loadedModel, len(loaded))
	// Go through the loaded models.
	for _, l := range loaded {
		// Store it.
		byName[l.Name] = l
	} // end of the loaded loop
	// Mark each model as loaded or not, then sort into category sections (both from the terminal version).
	groups := groupRows(combine(installed, loaded))
	// Start the view with the total.
	view := tableView{Total: len(installed), GroupedTip: makeFindTip("tip-grouped", "How models are grouped")}
	// One heading per column, in the fixed order.
	for i, title := range installedColumns {
		// Add the heading with its bubble.
		view.Columns = append(view.Columns, columnView{Title: title, Lines: headingLines(title), Tip: makeTip(fmt.Sprintf("tip-col-%d", i), title)})
	} // end of the column loop
	// One section per non-empty category.
	for gi, g := range groups {
		// Start the section with its heading, count and bubble.
		gv := groupView{Heading: g.Category.String(), CountText: countText(len(g.Rows)), Tip: makeTip(fmt.Sprintf("tip-cat-%d", gi), g.Category.String())}
		// One row per model.
		for _, r := range g.Rows {
			// A short name for the model's data.
			m := r.Model
			// The unload timer exists only for a loaded model.
			var timer string
			// The seconds the timer ticks from.
			var timerSecs int
			// True when the unload time has arrived.
			var timerExpired bool
			// Look the model up in the loaded list.
			if r.Loaded {
				// Work out the timer text and seconds.
				timer, timerSecs, timerExpired = timerFor(byName[m.Name], now)
			} // end of the timer
			// Add the row: the name first, then the nine cells in the same order and formats as the terminal table.
			gv.Rows = append(gv.Rows, rowView{Name: m.Name, Tags: installedTags(m), Loaded: r.Loaded, StateWord: stateWord(r.Loaded), Timer: timer, TimerSeconds: timerSecs, TimerExpired: timerExpired, Cells: []string{
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
} // end of buildTableViewAt
