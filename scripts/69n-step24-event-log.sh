#!/usr/bin/env bash
# Script 69n: F9, the event log of changes. A new panel under API health lists what changed between two checks, newest first: Ollama offline or back, a new Ollama version, models loaded or unloaded, models installed or removed. The newest 10 are shown, the newest 200 are kept in memory, and the log starts again when the monitor restarts. Version 0.17.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/event-log" ] || { echo "FAIL  not on feature/event-log"; exit 1; }
# Script 69m (reference 2 address) must be applied already (merged into main).
grep -q "llm/metrics\"" references.go || { echo "FAIL  script 69m was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e events.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index 2b43022..5c52473 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.16.0"
+const appVersion = "0.17.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/events.go b/events.go
new file mode 100644
index 0000000..6e9a775
--- /dev/null
+++ b/events.go
@@ -0,0 +1,290 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds the texts of the lines.
+	"fmt"
+	// sort puts the names in a fixed order, so the lines of one check always come in the same order.
+	"sort"
+	// sync keeps two page requests from changing the log at the same moment.
+	"sync"
+	// time holds the moment of each line.
+	"time"
+) // end of imports
+
+// maxEvents is how many lines the log keeps in memory; older ones are dropped.
+const maxEvents = 200
+
+// shownEvents is how many of the newest lines the panel shows.
+const shownEvents = 10
+
+// eventFullLayout is how the start of the monitor is written (date, time and zone name, like every time on every page).
+const eventFullLayout = "2 Jan 2006 15:04:05 MST"
+
+// eventDayLayout is how a line of today is written: the time and the zone name.
+const eventDayLayout = "15:04:05 MST"
+
+// eventOtherDayLayout is how a line of an earlier day is written: the day, the time and the zone name.
+const eventOtherDayLayout = "2 Jan 15:04:05 MST"
+
+// eventEntry is one line of the log.
+type eventEntry struct {
+	// At is the moment the change was seen.
+	At time.Time
+	// Symbol is the small sign in front of the words; the words carry the meaning too.
+	Symbol string
+	// Text says what changed, in plain words.
+	Text string
+} // end of eventEntry
+
+// eventRow is one line as the page draws it.
+type eventRow struct {
+	// Time is the moment with its zone name.
+	Time string
+	// Symbol is the sign in front of the words.
+	Symbol string
+	// Text says what changed.
+	Text string
+} // end of eventRow
+
+// eventsView is the log as the page draws it.
+type eventsView struct {
+	// Rows are the newest lines, newest first.
+	Rows []eventRow
+	// Shown is how many lines are drawn.
+	Shown int
+	// Total is how many lines the log holds.
+	Total int
+	// Started is when the monitor started, with its zone name.
+	Started string
+} // end of eventsView
+
+// eventLog remembers what Ollama looked like at the previous check and writes a line for each difference. It lives in memory only: it starts again when the monitor program starts, and it never holds any text of prompts or answers.
+type eventLog struct {
+	// mu protects every field below.
+	mu sync.Mutex
+	// seen is true after the first check; that check only sets the starting point.
+	seen bool
+	// started is the moment of the first check.
+	started time.Time
+	// online says whether Ollama answered at the previous check.
+	online bool
+	// version is the last version Ollama reported.
+	version string
+	// haveLists is true once the model lists were read at least once.
+	haveLists bool
+	// installed holds the names of the installed models at the last successful read.
+	installed map[string]bool
+	// loaded holds the names of the loaded models at the last successful read.
+	loaded map[string]bool
+	// entries are the lines, oldest first.
+	entries []eventEntry
+} // end of eventLog
+
+// plural writes a count with the word in the right form, for example "1 model" and "6 models".
+func plural(n int, word string) string {
+	// One.
+	if n == 1 {
+		// Singular.
+		return fmt.Sprintf("1 %s", word)
+	} // end of the one check
+	// Any other number.
+	return fmt.Sprintf("%d %ss", n, word)
+} // end of plural
+
+// add appends one line and drops the oldest when there are too many; the caller holds the lock.
+func (l *eventLog) add(at time.Time, symbol, text string) {
+	// The new line.
+	l.entries = append(l.entries, eventEntry{At: at, Symbol: symbol, Text: text})
+	// Too many: keep the newest ones.
+	if len(l.entries) > maxEvents {
+		// Drop the oldest.
+		l.entries = append([]eventEntry(nil), l.entries[len(l.entries)-maxEvents:]...)
+	} // end of the size check
+} // end of add
+
+// names returns the keys of a set in alphabetical order.
+func names(set map[string]bool) []string {
+	// The list.
+	out := make([]string, 0, len(set))
+	// Fill it.
+	for n := range set {
+		// One name.
+		out = append(out, n)
+	} // end of the loop
+	// A fixed order.
+	sort.Strings(out)
+	// Hand it back.
+	return out
+} // end of names
+
+// observe compares what Ollama reports now with what it reported at the previous check, and writes a line for each difference. listsOK is false when the model lists could not be read, and then no model line is written.
+func (l *eventLog) observe(now time.Time, online bool, version, reason string, listsOK bool, installed []installedModel, loaded []loadedModel) {
+	// One at a time.
+	l.mu.Lock()
+	// Release at the end.
+	defer l.mu.Unlock()
+	// The sets of names now, and the sizes of the loaded models for the lines.
+	instNow, loadNow, loadSize := map[string]bool{}, map[string]bool{}, map[string]int64{}
+	// Fill them only when the lists were read.
+	if listsOK {
+		// The installed names.
+		for _, m := range installed {
+			// One name.
+			instNow[m.Name] = true
+		} // end of the installed loop
+		// The loaded names and sizes.
+		for _, m := range loaded {
+			// One name.
+			loadNow[m.Name] = true
+			// Its size.
+			loadSize[m.Name] = m.Size
+		} // end of the loaded loop
+	} // end of the lists check
+	// The first check only sets the starting point and writes the first line.
+	if !l.seen {
+		// Remember it.
+		l.seen, l.started, l.online = true, now, online
+		// The line depends on what is known.
+		switch {
+		// Offline at the start.
+		case !online:
+			// Say so, with the reason.
+			l.add(now, "●", "Monitor started: Ollama offline ("+reason+")")
+		// Online and the lists were read.
+		case listsOK:
+			// The loaded part.
+			state := "none loaded"
+			// Some are loaded.
+			if len(loadNow) > 0 {
+				// Count them.
+				state = fmt.Sprintf("%d loaded", len(loadNow))
+			} // end of the loaded check
+			// Say it.
+			l.add(now, "●", fmt.Sprintf("Monitor started: Ollama online, %s installed, %s", plural(len(instNow), "model"), state))
+		// Online, lists not read.
+		default:
+			// Say so.
+			l.add(now, "●", "Monitor started: Ollama online")
+		} // end of the line choice
+		// Keep the version.
+		if online {
+			// The version.
+			l.version = version
+		} // end of the version check
+		// Keep the starting lists.
+		if listsOK {
+			// Remember them.
+			l.installed, l.loaded, l.haveLists = instNow, loadNow, true
+		} // end of the lists check
+		// Nothing more to compare.
+		return
+	} // end of the first check
+	// Ollama went offline or came back.
+	if online != l.online {
+		// It came back.
+		if online {
+			// Say so, with the version.
+			l.add(now, "✔", "Ollama is back online (version "+version+")")
+		} else { // it went away
+			// Say so, with the reason.
+			l.add(now, "✖", "Ollama went offline: "+reason)
+		} // end of the direction check
+	} // end of the online check
+	// Remember the state.
+	l.online = online
+	// An online Ollama may have been updated.
+	if online && version != "" {
+		// A different version than the last one seen.
+		if l.version != "" && l.version != version {
+			// Say so.
+			l.add(now, "↻", "Ollama updated from "+l.version+" to "+version)
+		} // end of the version check
+		// Remember it.
+		l.version = version
+	} // end of the version block
+	// Model lines only when the lists were read now and before.
+	if listsOK {
+		// A starting point exists.
+		if l.haveLists {
+			// Loaded and unloaded models, in name order.
+			for _, n := range names(loadNow) {
+				// A model that was not loaded before.
+				if !l.loaded[n] {
+					// The size, when Ollama reports one.
+					size := ""
+					// A size is known.
+					if loadSize[n] > 0 {
+						// Write it.
+						size = " (" + formatSize(loadSize[n]) + ")"
+					} // end of the size check
+					// Say so.
+					l.add(now, "▲", "Model loaded: "+n+size)
+				} // end of the new check
+			} // end of the loaded loop
+			// Models that are not loaded any more.
+			for _, n := range names(l.loaded) {
+				// Gone from the list.
+				if !loadNow[n] {
+					// Say so.
+					l.add(now, "▼", "Model unloaded: "+n)
+				} // end of the gone check
+			} // end of the unloaded loop
+			// Installed models.
+			for _, n := range names(instNow) {
+				// A model that was not there before.
+				if !l.installed[n] {
+					// Say so.
+					l.add(now, "＋", "Model installed: "+n)
+				} // end of the new check
+			} // end of the installed loop
+			// Removed models.
+			for _, n := range names(l.installed) {
+				// Gone from the list.
+				if !instNow[n] {
+					// Say so.
+					l.add(now, "－", "Model removed: "+n)
+				} // end of the gone check
+			} // end of the removed loop
+		} // end of the starting point check
+		// Remember the lists for the next check.
+		l.installed, l.loaded, l.haveLists = instNow, loadNow, true
+	} // end of the lists block
+} // end of observe
+
+// eventTime writes the moment of a line: the time of today with its zone name, or the day too for an earlier day.
+func eventTime(at, now time.Time) string {
+	// The same calendar day in the zone of the line.
+	if at.Year() == now.In(at.Location()).Year() && at.YearDay() == now.In(at.Location()).YearDay() {
+		// The time only.
+		return at.Format(eventDayLayout)
+	} // end of the day check
+	// The day and the time.
+	return at.Format(eventOtherDayLayout)
+} // end of eventTime
+
+// view copies the newest lines for the page, newest first.
+func (l *eventLog) view(now time.Time) eventsView {
+	// One at a time.
+	l.mu.Lock()
+	// Release at the end.
+	defer l.mu.Unlock()
+	// The view.
+	v := eventsView{Total: len(l.entries)}
+	// When the monitor started.
+	if l.seen {
+		// With its zone name.
+		v.Started = l.started.Format(eventFullLayout)
+	} // end of the started check
+	// From the newest to older ones, at most the shown number.
+	for i := len(l.entries) - 1; i >= 0 && len(v.Rows) < shownEvents; i-- {
+		// One line.
+		e := l.entries[i]
+		// Add it.
+		v.Rows = append(v.Rows, eventRow{Time: eventTime(e.At, now), Symbol: e.Symbol, Text: e.Text})
+	} // end of the loop
+	// How many are drawn.
+	v.Shown = len(v.Rows)
+	// Hand it back.
+	return v
+} // end of view
diff --git a/events_test.go b/events_test.go
new file mode 100644
index 0000000..3e9cd9d
--- /dev/null
+++ b/events_test.go
@@ -0,0 +1,335 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds names.
+	"fmt"
+	// net/http provides the method name.
+	"net/http"
+	// regexp checks that every time carries its zone name.
+	"regexp"
+	// strings searches the text.
+	"strings"
+	// sync runs the many-requests test.
+	"sync"
+	// testing is Go's test framework.
+	"testing"
+	// time builds the moments.
+	"time"
+) // end of imports
+
+// cet is a fixed zone with the name CET, so the times in the tests do not depend on the machine.
+var cet = time.FixedZone("CET", 3600)
+
+// at builds a moment on 31 October 2026 in CET.
+func at(h, m, s int) time.Time {
+	// The moment.
+	return time.Date(2026, 10, 31, h, m, s, 0, cet)
+} // end of at
+
+// inst builds an installed-models list from names.
+func inst(n ...string) []installedModel {
+	// The list.
+	var out []installedModel
+	// Fill it.
+	for _, name := range n {
+		// One model.
+		out = append(out, installedModel{Name: name})
+	} // end of the loop
+	// Hand it back.
+	return out
+} // end of inst
+
+// load builds a loaded-models list from names, each with a 9.6 GB size.
+func load(n ...string) []loadedModel {
+	// The list.
+	var out []loadedModel
+	// Fill it.
+	for _, name := range n {
+		// One model.
+		out = append(out, loadedModel{Name: name, Size: 9600000000})
+	} // end of the loop
+	// Hand it back.
+	return out
+} // end of load
+
+// texts returns the texts of all lines, oldest first.
+func texts(l *eventLog) []string {
+	// The list.
+	var out []string
+	// Fill it.
+	for _, e := range l.entries {
+		// One line with its symbol.
+		out = append(out, e.Symbol+" "+e.Text)
+	} // end of the loop
+	// Hand it back.
+	return out
+} // end of texts
+
+// TestEventLogFirstLine checks the three first lines: online with lists, online without, and offline.
+func TestEventLogFirstLine(t *testing.T) {
+	// The cases.
+	for name, c := range map[string]struct {
+		online  bool
+		listsOK bool
+		loaded  []loadedModel
+		want    string
+	}{
+		// Online, none loaded.
+		"online none loaded": {true, true, nil, "● Monitor started: Ollama online, 2 models installed, none loaded"},
+		// Online, one loaded.
+		"online one loaded": {true, true, load("a:1b"), "● Monitor started: Ollama online, 2 models installed, 1 loaded"},
+		// Online, lists not read.
+		"online no lists": {true, false, nil, "● Monitor started: Ollama online"},
+		// Offline.
+		"offline": {false, false, nil, "● Monitor started: Ollama offline (no answer)"},
+	} { // end of the cases
+		// A new log.
+		l := &eventLog{}
+		// The first check.
+		l.observe(at(17, 16, 2), c.online, "0.34.4", "no answer", c.listsOK, inst("a:1b", "b:1b"), c.loaded)
+		// Exactly one line.
+		if got := texts(l); len(got) != 1 || got[0] != c.want {
+			// Report the problem.
+			t.Errorf("%s: %q, want %q", name, got, c.want)
+		} // end of the check
+	} // end of the loop
+	// One model is written in the singular.
+	l := &eventLog{}
+	// The first check.
+	l.observe(at(1, 0, 0), true, "1", "", true, inst("a:1b"), nil)
+	// The line.
+	if got := texts(l); got[0] != "● Monitor started: Ollama online, 1 model installed, none loaded" {
+		// Report the problem.
+		t.Errorf("singular: %q", got)
+	} // end of the singular check
+} // end of TestEventLogFirstLine
+
+// TestEventLogWritesEachChange checks every kind of change, in a fixed order, and that an unchanged check writes nothing.
+func TestEventLogWritesEachChange(t *testing.T) {
+	// A new log.
+	l := &eventLog{}
+	// Start: two models, none loaded.
+	l.observe(at(17, 0, 0), true, "0.34.3", "", true, inst("a:1b", "b:1b"), nil)
+	// Unchanged checks write nothing.
+	for i := 1; i <= 5; i++ {
+		// Check again.
+		l.observe(at(17, 0, i), true, "0.34.3", "", true, inst("a:1b", "b:1b"), nil)
+	} // end of the loop
+	// Only the first line so far.
+	if len(l.entries) != 1 {
+		// Stop the test.
+		t.Fatalf("unchanged checks wrote lines: %q", texts(l))
+	} // end of the quiet check
+	// Two models loaded at once, in name order.
+	l.observe(at(17, 1, 0), true, "0.34.3", "", true, inst("a:1b", "b:1b"), load("b:1b", "a:1b"))
+	// One unloaded.
+	l.observe(at(17, 2, 0), true, "0.34.3", "", true, inst("a:1b", "b:1b"), load("b:1b"))
+	// Ollama goes offline: no model line, even though the lists are unknown.
+	l.observe(at(17, 3, 0), false, "", "no answer within 3 seconds", false, nil, nil)
+	// Still offline: nothing new.
+	l.observe(at(17, 3, 30), false, "", "no answer within 3 seconds", false, nil, nil)
+	// Back online with a new version; the lists are the same as before.
+	l.observe(at(17, 4, 0), true, "0.34.4", "", true, inst("a:1b", "b:1b"), load("b:1b"))
+	// A model installed and one removed.
+	l.observe(at(17, 5, 0), true, "0.34.4", "", true, inst("a:1b", "c:1b"), load("b:1b"))
+	// The expected lines, oldest first.
+	want := []string{
+		"● Monitor started: Ollama online, 2 models installed, none loaded",
+		"▲ Model loaded: a:1b (9.6 GB)",
+		"▲ Model loaded: b:1b (9.6 GB)",
+		"▼ Model unloaded: a:1b",
+		"✖ Ollama went offline: no answer within 3 seconds",
+		"✔ Ollama is back online (version 0.34.4)",
+		"↻ Ollama updated from 0.34.3 to 0.34.4",
+		"＋ Model installed: c:1b",
+		"－ Model removed: b:1b",
+	} // end of the expected lines
+	// Compare.
+	got := texts(l)
+	// The count.
+	if len(got) != len(want) {
+		// Stop the test.
+		t.Fatalf("%d lines, want %d:\n%s", len(got), len(want), strings.Join(got, "\n"))
+	} // end of the count check
+	// Each line.
+	for i := range want {
+		// One line.
+		if got[i] != want[i] {
+			// Report the problem.
+			t.Errorf("line %d: %q, want %q", i, got[i], want[i])
+		} // end of the check
+	} // end of the loop
+} // end of TestEventLogWritesEachChange
+
+// TestEventLogIgnoresUnreadLists checks that a failed read of the lists neither writes "unloaded" lines nor loses the starting point.
+func TestEventLogIgnoresUnreadLists(t *testing.T) {
+	// A new log with one model loaded.
+	l := &eventLog{}
+	// Start.
+	l.observe(at(9, 0, 0), true, "1", "", true, inst("a:1b"), load("a:1b"))
+	// Ollama answers the version check but the lists fail.
+	l.observe(at(9, 1, 0), true, "1", "", false, nil, nil)
+	// The lists work again and nothing changed.
+	l.observe(at(9, 2, 0), true, "1", "", true, inst("a:1b"), load("a:1b"))
+	// Only the first line.
+	if len(l.entries) != 1 {
+		// Report the problem.
+		t.Errorf("a failed read wrote lines: %q", texts(l))
+	} // end of the check
+} // end of TestEventLogIgnoresUnreadLists
+
+// TestEventLogViewAndLimits checks the newest-first view, the shown limit, the kept limit and the zone names on every time.
+func TestEventLogViewAndLimits(t *testing.T) {
+	// A new log.
+	l := &eventLog{}
+	// Start with nothing loaded.
+	l.observe(at(8, 0, 0), true, "1", "", true, inst("a:1b"), nil)
+	// Many changes: load and unload in turn.
+	for i := 0; i < 250; i++ {
+		// A moment.
+		moment := at(8, 0, 0).Add(time.Duration(i+1) * time.Minute)
+		// Odd checks load, even ones unload.
+		if i%2 == 0 {
+			// Loaded.
+			l.observe(moment, true, "1", "", true, inst("a:1b"), load("a:1b"))
+		} else {
+			// Unloaded.
+			l.observe(moment, true, "1", "", true, inst("a:1b"), nil)
+		} // end of the choice
+	} // end of the loop
+	// The view a minute after the last change.
+	v := l.view(at(8, 0, 0).Add(251 * time.Minute))
+	// Only the newest are kept, and only some are shown.
+	if v.Total != maxEvents || v.Shown != shownEvents || len(v.Rows) != shownEvents {
+		// Report the problem.
+		t.Errorf("total %d shown %d rows %d", v.Total, v.Shown, len(v.Rows))
+	} // end of the limit check
+	// The newest line comes first: the last change was an unload.
+	if v.Rows[0].Text != "Model unloaded: a:1b" {
+		// Report the problem.
+		t.Errorf("newest line is %q", v.Rows[0].Text)
+	} // end of the order check
+	// Every time carries its zone name.
+	zone := regexp.MustCompile(`CET$`)
+	// Check them all.
+	for _, r := range v.Rows {
+		// One time.
+		if !zone.MatchString(r.Time) {
+			// Report the problem.
+			t.Errorf("time without a zone: %q", r.Time)
+		} // end of the check
+	} // end of the loop
+	// The start moment is written in full.
+	if v.Started != "31 Oct 2026 08:00:00 CET" {
+		// Report the problem.
+		t.Errorf("started %q", v.Started)
+	} // end of the started check
+} // end of TestEventLogViewAndLimits
+
+// TestEventTimeShowsTheDayOnlyWhenNotToday checks the two layouts.
+func TestEventTimeShowsTheDayOnlyWhenNotToday(t *testing.T) {
+	// Now.
+	now := at(18, 0, 0)
+	// Today: the time only.
+	if got := eventTime(at(17, 31, 40), now); got != "17:31:40 CET" {
+		// Report the problem.
+		t.Errorf("today: %q", got)
+	} // end of the today check
+	// Yesterday: the day too.
+	if got := eventTime(at(17, 31, 40).AddDate(0, 0, -1), now); got != "30 Oct 17:31:40 CET" {
+		// Report the problem.
+		t.Errorf("yesterday: %q", got)
+	} // end of the yesterday check
+} // end of TestEventTimeShowsTheDayOnlyWhenNotToday
+
+// TestEventLogManyRequests checks the log is safe when many page requests arrive at once (run with -race).
+func TestEventLogManyRequests(t *testing.T) {
+	// A new log.
+	l := &eventLog{}
+	// A group to wait for.
+	var wg sync.WaitGroup
+	// Many requests.
+	for i := 0; i < 100; i++ {
+		// One more.
+		wg.Add(1)
+		// In the background.
+		go func(i int) {
+			// Done at the end.
+			defer wg.Done()
+			// Observe and view.
+			l.observe(at(10, 0, i%60), true, "1", "", true, inst("a:1b"), load(fmt.Sprintf("m%d:1b", i%3)))
+			// Look at it.
+			l.view(at(10, 5, 0))
+		}(i) // end of the goroutine
+	} // end of the loop
+	// Wait.
+	wg.Wait()
+	// The first line exists.
+	if len(l.entries) == 0 {
+		// Report the problem.
+		t.Errorf("no lines")
+	} // end of the check
+} // end of TestEventLogManyRequests
+
+// TestMainPageShowsTheEventLog checks the panel on the real page: heading and bubble, the start line, a load and an unload in newest-first order, escaping, and the zone names.
+func TestMainPageShowsTheEventLog(t *testing.T) {
+	// A fake Ollama and a rig; the rig already asked the page once, which wrote the start line.
+	f := newPerfFake()
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// The page with nothing changed.
+	_, _, first := get(t, rig.h, http.MethodGet, "/")
+	// The heading, the bubble and the start line.
+	for _, want := range []string{">Event log</span>", "What changed: models loaded or unloaded", "Changes seen between two checks, newest first.", "Monitor started: Ollama online, 4 models installed, none loaded"} {
+		// Look for it.
+		if !strings.Contains(first, want) {
+			// Report the gap.
+			t.Errorf("the page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// A model with a hostile name is loaded.
+	f.mu.Lock()
+	// In memory.
+	f.loaded["<b>x</b>:1b"] = true
+	// Release the fake.
+	f.mu.Unlock()
+	// The next check sees it.
+	_, _, second := get(t, rig.h, http.MethodGet, "/")
+	// The line is there, with the size, and the name is escaped.
+	if !strings.Contains(second, "Model loaded: &lt;b&gt;x&lt;/b&gt;:1b (4.0 GB)") || strings.Contains(second, "<b>x</b>") {
+		// Report the problem.
+		t.Errorf("the load line is wrong or the name was not escaped")
+	} // end of the load check
+	// It is unloaded again.
+	f.mu.Lock()
+	// Gone.
+	delete(f.loaded, "<b>x</b>:1b")
+	// Release the fake.
+	f.mu.Unlock()
+	// The next check sees that too.
+	_, _, third := get(t, rig.h, http.MethodGet, "/")
+	// Newest first: the unload line comes before the load line, which comes before the start line.
+	// The tooltip also has an example line, so the hostile name is used to find the real lines.
+	u, ld, s := strings.Index(third, "Model unloaded: &lt;b&gt;"), strings.Index(third, "Model loaded: &lt;b&gt;"), strings.Index(third, "Monitor started: Ollama online")
+	// The order.
+	if !(u >= 0 && u < ld && ld < s) {
+		// Report the problem.
+		t.Errorf("order wrong: unload %d, load %d, start %d", u, ld, s)
+	} // end of the order check
+	// Every time in the table carries a zone name.
+	cells := regexp.MustCompile(`<tr><td>([^<]*)</td><td><span class="symbol"`).FindAllStringSubmatch(third, -1)
+	// There must be three lines.
+	if len(cells) != 3 {
+		// Stop the test.
+		t.Fatalf("%d event rows, want 3", len(cells))
+	} // end of the count check
+	// Check each time.
+	for _, c := range cells {
+		// A zone name at the end.
+		if !regexp.MustCompile(`[A-Z]{3,4}$`).MatchString(c[1]) {
+			// Report the problem.
+			t.Errorf("time without a zone: %q", c[1])
+		} // end of the check
+	} // end of the loop
+} // end of TestMainPageShowsTheEventLog
diff --git a/tooltips.go b/tooltips.go
index 595d153..69138fd 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -23,7 +23,7 @@ var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Lo
 var gearHeadings = []string{"Set in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}
 
 // healthHeadings are the headings of the Ollama status panel on the main page that have a help bubble; a test checks each has a text.
-var healthHeadings = []string{"API health"}
+var healthHeadings = []string{"API health", "Event log"}
 
 // perfHeadings are the indicator names on the performance page that have a help bubble; a test checks each has a text.
 var perfHeadings = []string{"Answer speed", "Prompt reading speed", "Load time", "Total time", "Time to first word", "Tokens counted", "Embedding time", "Vector length", "Processor split", "Memory used", "Change since the previous run", "CPU cores", "CPU load", "Memory free", "Swap in use", "Other models loaded", "GPU"}
@@ -40,6 +40,15 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Whether Ollama is steady enough to rely on right now.",
 	}, // end of API health
+	// The event log under it.
+	"Event log": {
+		// What it means.
+		Plain: "What changed: models loaded or unloaded, models added or removed, and Ollama going offline or back.",
+		// A real case.
+		Example: "A line Model loaded: gemma4:e4b means that model was just put into memory.",
+		// What it helps with.
+		Decide: "Whether a change explains a slow answer or a missing model.",
+	}, // end of Event log
 	// The model name, shared by both tables.
 	"Model": {
 		// What it means.
diff --git a/web.go b/web.go
index a47f654..9685169 100644
--- a/web.go
+++ b/web.go
@@ -67,6 +67,10 @@ type pageData struct {
 	Health healthView
 	// HealthTip is the help bubble of the panel heading "API health".
 	HealthTip tipView
+	// Events is the newest part of the event log of changes.
+	Events eventsView
+	// EventsTip is the help bubble of the panel heading "Event log".
+	EventsTip tipView
 	// Token is the page token that every form on the page carries.
 	Token string
 	// CompareCount is how many models have a saved performance test that can be compared.
@@ -108,6 +112,10 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	health := &apiHealth{}
 	// The help bubble of the panel heading never changes, so build it once.
 	healthTip := makeTip("tip-health", "API health")
+	// The event log of changes also lives as long as the monitor runs.
+	events := &eventLog{}
+	// The help bubble of its heading never changes either.
+	eventsTip := makeTip("tip-events", "Event log")
 	// Create the page token: an unguessable value that every form on the page carries, so only this page can send a form (requirement S2).
 	token := mustToken()
 	// Create a router for the routes.
@@ -262,6 +270,12 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			// When this page was made.
 			UpdatedAt: time.Now().Format("15:04:05 MST"),
 		} // end of the data
+		// The lists that the event log compares; they stay empty when Ollama cannot be read.
+		var evInstalled []installedModel
+		// The loaded models, the same way.
+		var evLoaded []loadedModel
+		// Whether both lists were read.
+		listsOK := false
 		// Only an online Ollama can be asked for its model lists.
 		if res.Online {
 			// Read the installed models; the request's context cancels the call if the browser goes away.
@@ -284,8 +298,14 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 				data.Table.Deleted = deletedRows(deletedList.list(), installed)
 				// The table can be drawn now.
 				data.HasTable = true
+				// The event log may compare these lists too.
+				evInstalled, evLoaded, listsOK = installed, loaded, true
 			} // end of the error check
 		} // end of the online check
+		// Write a line for every change since the previous check, then take the newest lines for the page.
+		events.observe(time.Now(), res.Online, res.Version, res.Reason, listsOK, evInstalled, evLoaded)
+		// The lines and the bubble of the heading.
+		data.Events, data.EventsTip = events.view(time.Now()), eventsTip
 		// Build the whole page in memory first, so a template error produces a clean 500 and not a half page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/web/index.html b/web/index.html
index 5a5e1cf..749fbcc 100644
--- a/web/index.html
+++ b/web/index.html
@@ -151,6 +151,28 @@
 <p class="muted healthline">{{if .Health.FailedRow}}<span class="symbol" aria-hidden="true">⚠</span> {{end}}Failed checks: <strong>{{.Health.FailedRow}}</strong> in a row, <strong>{{.Health.FailedTotal}}</strong> in total since this monitor started. Last successful check: <strong>{{.Health.LastOK}}</strong>.</p>
 {{/* End of the status panel. */}}
 </section>
+{{/* The event log: what changed between two checks, newest first. */}}
+<section class="panel" aria-labelledby="events-title">
+{{/* The heading with its help bubble. */}}
+<h2 id="events-title"><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.EventsTip.ID}}">{{.EventsTip.Title}}</span><span class="tip" role="tooltip" id="{{.EventsTip.ID}}">{{template "tip" .EventsTip}}</span></span></h2>
+{{/* What the log is and is not. */}}
+<p class="muted">Changes seen between two checks, newest first. Kept in memory until the monitor stops. The monitor started at {{.Events.Started}}.{{if gt .Events.Total .Events.Shown}} Showing the newest {{.Events.Shown}} of {{.Events.Total}}.{{end}}</p>
+{{/* The lines. */}}
+{{if .Events.Rows}}
+<div class="scrollbox" tabindex="0" role="region" aria-label="Event log, scrolls sideways">
+<table class="models comparetable">
+<thead><tr><th scope="col">Time</th><th scope="col">What changed</th></tr></thead>
+<tbody>
+{{range .Events.Rows}}
+<tr><td>{{.Time}}</td><td><span class="symbol" aria-hidden="true">{{.Symbol}}</span> {{.Text}}</td></tr>
+{{end}}
+</tbody>
+</table>
+</div>
+{{else}}
+<p>Nothing seen yet.</p>
+{{end}}
+</section>
 {{/* The Installed models panel. */}}
 <section class="panel" aria-labelledby="installed-title">
 {{/* The panel heading, with the number of models when known. */}}
diff --git a/webtable_test.go b/webtable_test.go
index 3a1447e..1d498a0 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -134,10 +134,10 @@ func TestTablePageRealModels(t *testing.T) {
 func TestTableHelpForEveryHeading(t *testing.T) {
 	// Fake Ollama with the six real models.
 	body := pageFor(t, fullOllama(t, realModels, realPsBody))
-	// Ten column bubbles, two category bubbles and the bubble of the API health heading; the short tips of the row icons are counted apart.
-	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 13 {
+	// Ten column bubbles, two category bubbles and the bubbles of the API health and Event log headings; the short tips of the row icons are counted apart.
+	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 14 {
 		// Report the difference.
-		t.Errorf("%d bubbles, want 13", n)
+		t.Errorf("%d bubbles, want 14", n)
 	} // end of the bubble count
 	// Every column title must be a focusable heading.
 	for _, col := range installedColumns {
@@ -155,9 +155,9 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	// Find every aria-describedby value.
 	refs := regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1)
 	// There must be one per bubble (the row icons have their own, counted apart).
-	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 13 {
+	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 14 {
 		// Report the difference.
-		t.Errorf("%d aria-describedby attributes, want 13", n)
+		t.Errorf("%d aria-describedby attributes, want 14", n)
 	} // end of the reference count
 	// Each one must point at an element that exists.
 	for _, m := range refs {
@@ -180,16 +180,16 @@ func TestTableAccessibility(t *testing.T) {
 		// want is the expected number.
 		want int
 	}{ // the cases follow
-		// Ten column headings.
-		{`scope="col"`, 10},
+		// Ten column headings of the models table and two of the event log.
+		{`scope="col"`, 12},
 		// One row heading per model.
 		{`scope="row"`, 6},
 		// One group heading per non-empty category.
 		{`scope="colgroup"`, 2},
 		// The scroll box is a labelled region that the keyboard can reach.
-		{`role="region"`, 1},
-		// Thirteen headings (ten columns, two categories and API health) plus the scroll box can take the focus.
-		{`tabindex="0"`, 14},
+		{`role="region"`, 2},
+		// Fourteen headings (ten columns, two categories, API health and Event log) plus the two scroll boxes (models and event log) can take the focus.
+		{`tabindex="0"`, 16},
 	} { // end of the list
 		// Count it.
 		if n := strings.Count(body, c.text); n != c.want {
@@ -230,7 +230,7 @@ func TestTableNoModels(t *testing.T) {
 	// Fake Ollama with an empty list.
 	body := pageFor(t, fullOllama(t, nil, `{"models":[]}`))
 	// The note must appear and no table may be drawn.
-	if !strings.Contains(body, "No models are installed.") || strings.Contains(body, "<table") {
+	if !strings.Contains(body, "No models are installed.") || strings.Contains(body, `<table class="models"`) {
 		// Report the problem.
 		t.Errorf("unexpected page for an empty list")
 	} // end of the check
@@ -261,7 +261,7 @@ func TestTableListError(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 	// No table may be drawn.
-	if strings.Contains(body, "<table") {
+	if strings.Contains(body, `<table class="models"`) {
 		// Report the problem.
 		t.Errorf("a table was drawn although the lists failed")
 	} // end of the table check
@@ -272,7 +272,7 @@ func TestTableWhenOffline(t *testing.T) {
 	// Ask the page with nothing listening.
 	_, _, body := get(t, handlerFor(t, "http://"+closedAddress(t)), http.MethodGet, "/")
 	// The note must appear and no table may be drawn.
-	if !strings.Contains(body, "The model tables appear when Ollama answers.") || strings.Contains(body, "<table") {
+	if !strings.Contains(body, "The model tables appear when Ollama answers.") || strings.Contains(body, `<table class="models"`) {
 		// Report the problem.
 		t.Errorf("unexpected page while offline")
 	} // end of the check
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
2551ab404cbd1e9f55096e6e6ac34ad33488bb4a596a40bfb412e51d415ffaac  about.go
7728652b8c2c128369dceb82e16549641ddb412969eed493a69a054c797bf5ee  tooltips.go
cc679d11bbcf3c80198dd4c8effbcdada54eb65fe37a700a6c873086dfe9f5f7  web.go
33c9cc1c62714168035048364a6d2ea6022f6aac23c6ac30f25bd97a0e791db5  web/index.html
7b6eab39b901ef137bcadd898d34cfefad0270f000bcfe49e6b73a38ebc4d442  webtable_test.go
7a83e8e8fccd1d95f02b8e448b6040cd383959a038c4c2cf402ddb8eff9c6255  events.go
25c8b7e9aae6e5d0d5e3680473a2940bcb4eb97d4437ab4f8b5986c9c7edab56  events_test.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# Tell the person how to use the new command.
echo "NEXT  start ./bin/OllamaControlCenter and look for the Event log panel under API health"
# List the changed files; nothing is committed yet.
git status --short
