// Package main tells Go that this test file belongs to the same program as tableview.go.
package main

import ( // import lists the packages this test file uses.
	// reflect compares whole lists of text.
	"reflect"
	// strings searches the terminal table's lines.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides the clock the terminal table needs.
	"time"
) // end of imports

// TestBuildTableViewShape checks the sections, counts and order built from the six real models.
func TestBuildTableViewShape(t *testing.T) {
	// Build the view with nothing loaded.
	v := buildTableView(realInstalled(t), nil)
	// The total.
	if v.Total != 6 {
		// Report the difference.
		t.Errorf("Total = %d, want 6", v.Total)
	} // end of the total check
	// The ten column titles, in the fixed order.
	var titles []string
	// Collect them.
	for _, c := range v.Columns {
		// Add the title.
		titles = append(titles, c.Title)
	} // end of the column loop
	// Compare.
	if !reflect.DeepEqual(titles, installedColumns) {
		// Report the difference.
		t.Errorf("columns = %v", titles)
	} // end of the title check
	// Two sections: embedding first, then multimodal.
	if len(v.Groups) != 2 || v.Groups[0].Heading != categoryEmbedding.String() || v.Groups[1].Heading != categoryMultimodal.String() {
		// Report the difference.
		t.Fatalf("groups = %+v", v.Groups)
	} // end of the group check
	// The counts.
	if v.Groups[0].CountText != "2 models" || v.Groups[1].CountText != "4 models" {
		// Report the difference.
		t.Errorf("counts = %q, %q", v.Groups[0].CountText, v.Groups[1].CountText)
	} // end of the count check
	// Every row has a name and nine other cells.
	for _, g := range v.Groups {
		// Go through the rows.
		for _, r := range g.Rows {
			// Check the cell count.
			if r.Name == "" || len(r.Cells) != 9 {
				// Report the problem.
				t.Errorf("row %q has %d cells", r.Name, len(r.Cells))
			} // end of the row check
		} // end of the row loop
	} // end of the group loop
} // end of TestBuildTableViewShape

// TestBuildTableViewCells checks the exact text of one real row, with the model loaded.
func TestBuildTableViewCells(t *testing.T) {
	// Build the view with medgemma:latest loaded.
	v := buildTableView(realInstalled(t), []loadedModel{{Name: "medgemma:latest"}})
	// Find the row.
	for _, g := range v.Groups {
		// Go through the rows.
		for _, r := range g.Rows {
			// Only the row we want.
			if r.Name != "medgemma:latest" {
				// Skip the others.
				continue
			} // end of the name check
			// The nine cells exactly as the terminal table shows them.
			want := []string{"● Loaded", "3.3 GB", "gemma3", "4.3B", "Q4_K_M", "131072", "2560", "2026-10-21 15:48 UTC", "completion, vision"}
			// Compare.
			if !reflect.DeepEqual(r.Cells, want) {
				// Report the difference.
				t.Errorf("cells = %q, want %q", r.Cells, want)
			} // end of the compare
			// Done.
			return
		} // end of the row loop
	} // end of the group loop
	// The row was never found.
	t.Errorf("medgemma:latest is missing from the view")
} // end of TestBuildTableViewCells

// TestTableViewMatchesTerminalTable checks that every cell on the page also appears in the terminal table's line for that model.
func TestTableViewMatchesTerminalTable(t *testing.T) {
	// The installed list and the loaded list.
	installed := realInstalled(t)
	// One loaded model.
	loaded := []loadedModel{{Name: "medgemma:latest"}}
	// The terminal table.
	terminal := renderInstalled(groupRows(combine(installed, loaded)))
	// The page view.
	v := buildTableView(installed, loaded)
	// Go through every row of the view.
	for _, g := range v.Groups {
		// Go through the rows.
		for _, r := range g.Rows {
			// Find the terminal line that starts with the model name.
			var line string
			// Look at every terminal line.
			for _, l := range strings.Split(terminal, "\n") {
				// A match starts with the name followed by a space.
				if strings.HasPrefix(l, r.Name+" ") {
					// Remember it.
					line = l
				} // end of the match check
			} // end of the line loop
			// A missing line is a failure.
			if line == "" {
				// Report the problem.
				t.Errorf("no terminal line for %q", r.Name)
				// Go to the next row.
				continue
			} // end of the missing check
			// Every cell must appear in that line.
			for _, c := range r.Cells {
				// Look for it.
				if !strings.Contains(line, c) {
					// Report the difference.
					t.Errorf("%q: cell %q is not in the terminal line %q", r.Name, c, line)
				} // end of the cell check
			} // end of the cell loop
		} // end of the row loop
	} // end of the group loop
	// Keep the clock import used by the terminal helper in one place.
	_ = time.Now
} // end of TestTableViewMatchesTerminalTable

// TestBuildTableViewEmpty checks the view for an Ollama with no models.
func TestBuildTableViewEmpty(t *testing.T) {
	// Build the view from nothing.
	v := buildTableView(nil, nil)
	// No total and no sections.
	if v.Total != 0 || len(v.Groups) != 0 {
		// Report the difference.
		t.Errorf("view = %+v", v)
	} // end of the check
} // end of TestBuildTableViewEmpty

// TestCountText checks the singular and plural forms.
func TestCountText(t *testing.T) {
	// A table of numbers and wanted text.
	for n, want := range map[int]string{0: "0 models", 1: "1 model", 2: "2 models", 4: "4 models"} {
		// Compare.
		if got := countText(n); got != want {
			// Report the difference.
			t.Errorf("countText(%d) = %q, want %q", n, got, want)
		} // end of the compare
	} // end of the loop
} // end of TestCountText

// TestTipIDsAreUnique checks that no two bubbles share an element name, which would break aria-describedby.
func TestTipIDsAreUnique(t *testing.T) {
	// Build the view.
	v := buildTableView(realInstalled(t), nil)
	// Remember the names seen.
	seen := map[string]bool{}
	// Collect every bubble name.
	var ids []string
	// The columns first.
	for _, c := range v.Columns {
		// Add the name.
		ids = append(ids, c.Tip.ID)
	} // end of the column loop
	// Then the sections.
	for _, g := range v.Groups {
		// Add the name.
		ids = append(ids, g.Tip.ID)
	} // end of the group loop
	// Check each one.
	for _, id := range ids {
		// An empty or repeated name is a mistake.
		if id == "" || seen[id] {
			// Report the problem.
			t.Errorf("bad or repeated bubble name %q", id)
		} // end of the check
		// Remember it.
		seen[id] = true
	} // end of the loop
} // end of TestTipIDsAreUnique
