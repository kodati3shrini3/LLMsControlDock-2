// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds names.
	"fmt"
	// net/http provides the method name.
	"net/http"
	// regexp checks that every time carries its zone name.
	"regexp"
	// strings searches the text.
	"strings"
	// sync runs the many-requests test.
	"sync"
	// testing is Go's test framework.
	"testing"
	// time builds the moments.
	"time"
) // end of imports

// cet is a fixed zone with the name CET, so the times in the tests do not depend on the machine.
var cet = time.FixedZone("CET", 3600)

// at builds a moment on 31 October 2026 in CET.
func at(h, m, s int) time.Time {
	// The moment.
	return time.Date(2026, 10, 31, h, m, s, 0, cet)
} // end of at

// inst builds an installed-models list from names.
func inst(n ...string) []installedModel {
	// The list.
	var out []installedModel
	// Fill it.
	for _, name := range n {
		// One model.
		out = append(out, installedModel{Name: name})
	} // end of the loop
	// Hand it back.
	return out
} // end of inst

// load builds a loaded-models list from names, each with a 9.6 GB size.
func load(n ...string) []loadedModel {
	// The list.
	var out []loadedModel
	// Fill it.
	for _, name := range n {
		// One model.
		out = append(out, loadedModel{Name: name, Size: 9600000000})
	} // end of the loop
	// Hand it back.
	return out
} // end of load

// texts returns the texts of all lines, oldest first.
func texts(l *eventLog) []string {
	// The list.
	var out []string
	// Fill it.
	for _, e := range l.entries {
		// One line with its symbol.
		out = append(out, e.Symbol+" "+e.Text)
	} // end of the loop
	// Hand it back.
	return out
} // end of texts

// TestEventLogFirstLine checks the three first lines: online with lists, online without, and offline.
func TestEventLogFirstLine(t *testing.T) {
	// The cases.
	for name, c := range map[string]struct {
		online  bool
		listsOK bool
		loaded  []loadedModel
		want    string
	}{
		// Online, none loaded.
		"online none loaded": {true, true, nil, "● Monitor started: Ollama online, 2 models installed, none loaded"},
		// Online, one loaded.
		"online one loaded": {true, true, load("a:1b"), "● Monitor started: Ollama online, 2 models installed, 1 loaded"},
		// Online, lists not read.
		"online no lists": {true, false, nil, "● Monitor started: Ollama online"},
		// Offline.
		"offline": {false, false, nil, "● Monitor started: Ollama offline (no answer)"},
	} { // end of the cases
		// A new log.
		l := &eventLog{}
		// The first check.
		l.observe(at(17, 16, 2), c.online, "0.34.4", "no answer", c.listsOK, inst("a:1b", "b:1b"), c.loaded)
		// Exactly one line.
		if got := texts(l); len(got) != 1 || got[0] != c.want {
			// Report the problem.
			t.Errorf("%s: %q, want %q", name, got, c.want)
		} // end of the check
	} // end of the loop
	// One model is written in the singular.
	l := &eventLog{}
	// The first check.
	l.observe(at(1, 0, 0), true, "1", "", true, inst("a:1b"), nil)
	// The line.
	if got := texts(l); got[0] != "● Monitor started: Ollama online, 1 model installed, none loaded" {
		// Report the problem.
		t.Errorf("singular: %q", got)
	} // end of the singular check
} // end of TestEventLogFirstLine

// TestEventLogWritesEachChange checks every kind of change, in a fixed order, and that an unchanged check writes nothing.
func TestEventLogWritesEachChange(t *testing.T) {
	// A new log.
	l := &eventLog{}
	// Start: two models, none loaded.
	l.observe(at(17, 0, 0), true, "0.34.3", "", true, inst("a:1b", "b:1b"), nil)
	// Unchanged checks write nothing.
	for i := 1; i <= 5; i++ {
		// Check again.
		l.observe(at(17, 0, i), true, "0.34.3", "", true, inst("a:1b", "b:1b"), nil)
	} // end of the loop
	// Only the first line so far.
	if len(l.entries) != 1 {
		// Stop the test.
		t.Fatalf("unchanged checks wrote lines: %q", texts(l))
	} // end of the quiet check
	// Two models loaded at once, in name order.
	l.observe(at(17, 1, 0), true, "0.34.3", "", true, inst("a:1b", "b:1b"), load("b:1b", "a:1b"))
	// One unloaded.
	l.observe(at(17, 2, 0), true, "0.34.3", "", true, inst("a:1b", "b:1b"), load("b:1b"))
	// Ollama goes offline: no model line, even though the lists are unknown.
	l.observe(at(17, 3, 0), false, "", "no answer within 3 seconds", false, nil, nil)
	// Still offline: nothing new.
	l.observe(at(17, 3, 30), false, "", "no answer within 3 seconds", false, nil, nil)
	// Back online with a new version; the lists are the same as before.
	l.observe(at(17, 4, 0), true, "0.34.4", "", true, inst("a:1b", "b:1b"), load("b:1b"))
	// A model installed and one removed.
	l.observe(at(17, 5, 0), true, "0.34.4", "", true, inst("a:1b", "c:1b"), load("b:1b"))
	// The expected lines, oldest first.
	want := []string{
		"● Monitor started: Ollama online, 2 models installed, none loaded",
		"▲ Model loaded: a:1b (9.6 GB)",
		"▲ Model loaded: b:1b (9.6 GB)",
		"▼ Model unloaded: a:1b",
		"✖ Ollama went offline: no answer within 3 seconds",
		"✔ Ollama is back online (version 0.34.4)",
		"↻ Ollama updated from 0.34.3 to 0.34.4",
		"＋ Model installed: c:1b",
		"－ Model removed: b:1b",
	} // end of the expected lines
	// Compare.
	got := texts(l)
	// The count.
	if len(got) != len(want) {
		// Stop the test.
		t.Fatalf("%d lines, want %d:\n%s", len(got), len(want), strings.Join(got, "\n"))
	} // end of the count check
	// Each line.
	for i := range want {
		// One line.
		if got[i] != want[i] {
			// Report the problem.
			t.Errorf("line %d: %q, want %q", i, got[i], want[i])
		} // end of the check
	} // end of the loop
} // end of TestEventLogWritesEachChange

// TestEventLogIgnoresUnreadLists checks that a failed read of the lists neither writes "unloaded" lines nor loses the starting point.
func TestEventLogIgnoresUnreadLists(t *testing.T) {
	// A new log with one model loaded.
	l := &eventLog{}
	// Start.
	l.observe(at(9, 0, 0), true, "1", "", true, inst("a:1b"), load("a:1b"))
	// Ollama answers the version check but the lists fail.
	l.observe(at(9, 1, 0), true, "1", "", false, nil, nil)
	// The lists work again and nothing changed.
	l.observe(at(9, 2, 0), true, "1", "", true, inst("a:1b"), load("a:1b"))
	// Only the first line.
	if len(l.entries) != 1 {
		// Report the problem.
		t.Errorf("a failed read wrote lines: %q", texts(l))
	} // end of the check
} // end of TestEventLogIgnoresUnreadLists

// TestEventLogViewAndLimits checks the newest-first view, the shown limit, the kept limit and the zone names on every time.
func TestEventLogViewAndLimits(t *testing.T) {
	// A new log.
	l := &eventLog{}
	// Start with nothing loaded.
	l.observe(at(8, 0, 0), true, "1", "", true, inst("a:1b"), nil)
	// Many changes: load and unload in turn.
	for i := 0; i < 250; i++ {
		// A moment.
		moment := at(8, 0, 0).Add(time.Duration(i+1) * time.Minute)
		// Odd checks load, even ones unload.
		if i%2 == 0 {
			// Loaded.
			l.observe(moment, true, "1", "", true, inst("a:1b"), load("a:1b"))
		} else {
			// Unloaded.
			l.observe(moment, true, "1", "", true, inst("a:1b"), nil)
		} // end of the choice
	} // end of the loop
	// The view a minute after the last change.
	v := l.view(at(8, 0, 0).Add(251 * time.Minute))
	// Only the newest are kept, and only some are shown.
	if v.Total != maxEvents || v.Shown != shownEvents || len(v.Rows) != shownEvents {
		// Report the problem.
		t.Errorf("total %d shown %d rows %d", v.Total, v.Shown, len(v.Rows))
	} // end of the limit check
	// The newest line comes first: the last change was an unload.
	if v.Rows[0].Text != "Model unloaded: a:1b" {
		// Report the problem.
		t.Errorf("newest line is %q", v.Rows[0].Text)
	} // end of the order check
	// Every time carries its zone name.
	zone := regexp.MustCompile(`CET$`)
	// Check them all.
	for _, r := range v.Rows {
		// One time.
		if !zone.MatchString(r.Time) {
			// Report the problem.
			t.Errorf("time without a zone: %q", r.Time)
		} // end of the check
	} // end of the loop
	// The start moment is written in full.
	if v.Started != "31 Oct 2026 08:00:00 CET" {
		// Report the problem.
		t.Errorf("started %q", v.Started)
	} // end of the started check
} // end of TestEventLogViewAndLimits

// TestEventTimeShowsTheDayOnlyWhenNotToday checks the two layouts.
func TestEventTimeShowsTheDayOnlyWhenNotToday(t *testing.T) {
	// Now.
	now := at(18, 0, 0)
	// Today: the time only.
	if got := eventTime(at(17, 31, 40), now); got != "17:31:40 CET" {
		// Report the problem.
		t.Errorf("today: %q", got)
	} // end of the today check
	// Yesterday: the day too.
	if got := eventTime(at(17, 31, 40).AddDate(0, 0, -1), now); got != "30 Oct 17:31:40 CET" {
		// Report the problem.
		t.Errorf("yesterday: %q", got)
	} // end of the yesterday check
} // end of TestEventTimeShowsTheDayOnlyWhenNotToday

// TestEventLogManyRequests checks the log is safe when many page requests arrive at once (run with -race).
func TestEventLogManyRequests(t *testing.T) {
	// A new log.
	l := &eventLog{}
	// A group to wait for.
	var wg sync.WaitGroup
	// Many requests.
	for i := 0; i < 100; i++ {
		// One more.
		wg.Add(1)
		// In the background.
		go func(i int) {
			// Done at the end.
			defer wg.Done()
			// Observe and view.
			l.observe(at(10, 0, i%60), true, "1", "", true, inst("a:1b"), load(fmt.Sprintf("m%d:1b", i%3)))
			// Look at it.
			l.view(at(10, 5, 0))
		}(i) // end of the goroutine
	} // end of the loop
	// Wait.
	wg.Wait()
	// The first line exists.
	if len(l.entries) == 0 {
		// Report the problem.
		t.Errorf("no lines")
	} // end of the check
} // end of TestEventLogManyRequests

// TestMainPageShowsTheEventLog checks the panel on the real page: heading and bubble, the start line, a load and an unload in newest-first order, escaping, and the zone names.
func TestMainPageShowsTheEventLog(t *testing.T) {
	// A fake Ollama and a rig; the rig already asked the page once, which wrote the start line.
	f := newPerfFake()
	// Build the rig.
	rig, _ := perfRig(t, f)
	// The page with nothing changed.
	_, _, first := get(t, rig.h, http.MethodGet, "/")
	// The heading, the bubble and the start line.
	for _, want := range []string{">Event log</span>", "What changed: models loaded or unloaded", "Changes seen between two checks, newest first.", "Monitor started: Ollama online, 4 models installed, none loaded"} {
		// Look for it.
		if !strings.Contains(first, want) {
			// Report the gap.
			t.Errorf("the page lacks %q", want)
		} // end of the check
	} // end of the loop
	// A model with a hostile name is loaded.
	f.mu.Lock()
	// In memory.
	f.loaded["<b>x</b>:1b"] = true
	// Release the fake.
	f.mu.Unlock()
	// The next check sees it.
	_, _, second := get(t, rig.h, http.MethodGet, "/")
	// The line is there, with the size, and the name is escaped.
	if !strings.Contains(second, "Model loaded: &lt;b&gt;x&lt;/b&gt;:1b (4.0 GB)") || strings.Contains(second, "<b>x</b>") {
		// Report the problem.
		t.Errorf("the load line is wrong or the name was not escaped")
	} // end of the load check
	// It is unloaded again.
	f.mu.Lock()
	// Gone.
	delete(f.loaded, "<b>x</b>:1b")
	// Release the fake.
	f.mu.Unlock()
	// The next check sees that too.
	_, _, third := get(t, rig.h, http.MethodGet, "/")
	// Newest first: the unload line comes before the load line, which comes before the start line.
	// The tooltip also has an example line, so the hostile name is used to find the real lines.
	u, ld, s := strings.Index(third, "Model unloaded: &lt;b&gt;"), strings.Index(third, "Model loaded: &lt;b&gt;"), strings.Index(third, "Monitor started: Ollama online")
	// The order.
	if !(u >= 0 && u < ld && ld < s) {
		// Report the problem.
		t.Errorf("order wrong: unload %d, load %d, start %d", u, ld, s)
	} // end of the order check
	// Every time in the table carries a zone name.
	cells := regexp.MustCompile(`<tr><td>([^<]*)</td><td><span class="symbol"`).FindAllStringSubmatch(third, -1)
	// There must be three lines.
	if len(cells) != 3 {
		// Stop the test.
		t.Fatalf("%d event rows, want 3", len(cells))
	} // end of the count check
	// Check each time.
	for _, c := range cells {
		// A zone name at the end.
		if !regexp.MustCompile(`[A-Z]{3,4}$`).MatchString(c[1]) {
			// Report the problem.
			t.Errorf("time without a zone: %q", c[1])
		} // end of the check
	} // end of the loop
} // end of TestMainPageShowsTheEventLog
