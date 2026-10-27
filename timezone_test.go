// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// os reads the source files.
	"os"
	// path/filepath finds the source files.
	"path/filepath"
	// regexp finds the time layouts.
	"regexp"
	// strings searches the source lines.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time builds a moment in a chosen zone.
	"time"
) // end of imports

// TestEveryShownTimeNamesItsZone is a standing rule of the project: wherever a time or date is shown or stored, its time zone is mentioned. It reads the program's own source and fails when a time layout with hours or minutes has no zone.
func TestEveryShownTimeNamesItsZone(t *testing.T) {
	// The program's source files.
	files, err := filepath.Glob("*.go")
	// A failure here is a broken test setup.
	if err != nil || len(files) == 0 {
		// Stop the test.
		t.Fatalf("no source files found: %v", err)
	} // end of the glob check
	// A Format call with a text layout.
	layout := regexp.MustCompile(`\.Format\("([^"]*)"\)`)
	// What counts as naming the zone inside the layout.
	zones := []string{"MST", "UTC", "Z0700", "-0700", "Z07:00", "-07:00"}
	// How many layouts were checked, so the test cannot pass by finding nothing.
	checked := 0
	// Go through the files.
	for _, f := range files {
		// Tests may use any layout.
		if strings.HasSuffix(f, "_test.go") {
			// Skip it.
			continue
		} // end of the test-file check
		// Read the file.
		data, err := os.ReadFile(f)
		// A failure here is a broken test setup.
		if err != nil {
			// Stop the test.
			t.Fatalf("cannot read %s: %v", f, err)
		} // end of the read check
		// Go through the lines.
		for i, line := range strings.Split(string(data), "\n") {
			// Comments may talk about layouts freely.
			if strings.HasPrefix(strings.TrimSpace(line), "//") {
				// Skip it.
				continue
			} // end of the comment check
			// Every layout on the line.
			for _, m := range layout.FindAllStringSubmatch(line, -1) {
				// Only layouts that show a time of day need a zone.
				if !strings.Contains(m[1], "15") && !strings.Contains(m[1], "04") {
					// A date alone is not checked here.
					continue
				} // end of the time-of-day check
				// One more layout checked.
				checked++
				// The zone may be in the layout itself.
				ok := false
				// Look for each zone marker.
				for _, z := range zones {
					// Found one.
					if strings.Contains(m[1], z) {
						// Fine.
						ok = true
					} // end of the marker check
				} // end of the zone loop
				// Or the same line adds the word UTC after the time.
				if strings.Contains(line, `" UTC"`) {
					// Fine.
					ok = true
				} // end of the added-word check
				// Report a layout without a zone.
				if !ok {
					// Name the place.
					t.Errorf("%s:%d shows a time without its time zone: %q", f, i+1, m[1])
				} // end of the zone check
			} // end of the layout loop
		} // end of the line loop
	} // end of the file loop
	// The test must have looked at something.
	if checked < 5 {
		// Report it.
		t.Errorf("only %d time layouts were found; the scan is not working", checked)
	} // end of the count check
} // end of TestEveryShownTimeNamesItsZone

// TestSnapshotFileNameHasZone checks the snapshot file name carries the time zone offset.
func TestSnapshotFileNameHasZone(t *testing.T) {
	// A store in a private folder.
	h := &historyStore{dir: filepath.Join(t.TempDir(), "history")}
	// A moment in a zone one hour ahead of UTC.
	at := time.Date(2026, 10, 27, 17, 30, 0, 0, time.FixedZone("CET", 3600))
	// Save.
	name, err := h.save(paramSnapshot{Model: "a:1", DeletedAt: at})
	// It must work and carry the offset.
	if err != nil || !strings.HasPrefix(name, "2026-10-27_17-30-00+0100_a-1_") {
		// Report it.
		t.Errorf("name %q (err %v) lacks the zone offset", name, err)
	} // end of the CET check
	// The same moment in UTC is marked with Z.
	name, err = h.save(paramSnapshot{Model: "a:1", DeletedAt: at.UTC()})
	// Check.
	if err != nil || !strings.HasPrefix(name, "2026-10-27_16-30-00Z_a-1_") {
		// Report it.
		t.Errorf("name %q (err %v) lacks the UTC mark", name, err)
	} // end of the UTC check
	// The time stored inside the file keeps its offset too.
	data, _ := os.ReadFile(filepath.Join(h.dir, h.list("a:1")[1].File))
	// The text.
	if !strings.Contains(string(data), "2026-10-27T17:30:00+01:00") {
		// Report it.
		t.Errorf("the stored time lacks its offset: %s", data)
	} // end of the stored check
} // end of TestSnapshotFileNameHasZone

// TestGreyedRowTimeHasYearAndZone checks the deleted-at text in the table carries the year and the zone.
func TestGreyedRowTimeHasYearAndZone(t *testing.T) {
	// A moment in a known zone; Local() would convert it, so the check is on the layout's parts.
	rows := deletedRows([]deletedModel{{Name: "m:1", Size: 1, DeletedAt: time.Date(2026, 10, 27, 17, 30, 0, 0, time.UTC)}}, nil)
	// One row.
	if len(rows) != 1 {
		// Stop the test.
		t.Fatalf("rows: %v", rows)
	} // end of the count check
	// Year, hour and minute, and a zone name or offset at the end.
	if ok, _ := regexp.MatchString(`^\d{1,2} [A-Z][a-z]{2} 2026 \d{2}:\d{2} \S+$`, rows[0].WhenText); !ok {
		// Report it.
		t.Errorf("greyed row time %q lacks the year or the zone", rows[0].WhenText)
	} // end of the pattern check
} // end of TestGreyedRowTimeHasYearAndZone
