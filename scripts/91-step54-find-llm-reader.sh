#!/usr/bin/env bash
# Script 91 (Find LLM, slice 1 of 4: the live library reader): adds the code that reads the public Ollama library list page and a model's tags page (abilities, sizes, download size, context length) and keeps the last list for one hour. No screen yet and no change to what you see; version stays 0.31.0. Eight new tests (428 in total); one more test reads the real saved pages when you point it at them.
# Run it from the project folder, on its own new branch (never on main): cd ~/LLMsControlDock && git checkout -b feature/find-llm-reader && bash scripts/91-step54-find-llm-reader.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two new files this script adds.
declare -A AFTER
AFTER["findsite.go"]="590417e6a96dbb2f7ffa468910287a600a313408ccb1cd1d1bb1e6f45f9f550c"
AFTER["findsite_test.go"]="699580c6f684ef343f1a621dce0c544fcbb704f290ccef22e80cd3c6804d1bd8"

# Count of passed checks.
PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git checkout -b feature/find-llm-reader"
# Report the branch.
pass "on branch $BRANCH (not main)"

# The project must be the state after script 89 (merged as PR 40).
[ -e licence_test.go ] && [ -e legacyname.go ] || fail "licence_test.go or legacyname.go is missing: this is not the state after scripts 87 to 89"
# Report it.
pass "the project is in the state after scripts 87 to 89"
# The module name must be the new one.
grep -qx 'module github.com/kodati3shrini3/LLMsControlDock' go.mod || fail "the module line of go.mod is not the new name"
# Report it.
pass "go.mod: module github.com/kodati3shrini3/LLMsControlDock"

# Refuse to run twice: the new file exists when the change was applied before.
if [ -e findsite.go ] || [ -e findsite_test.go ]; then fail "findsite.go or findsite_test.go exists: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_91_END'
diff --git a/findsite.go b/findsite.go
new file mode 100644
index 0000000..de69046
--- /dev/null
+++ b/findsite.go
@@ -0,0 +1,370 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context lets a request be cancelled when the browser goes away.
+	"context"
+	// errors makes the named errors the pages can show.
+	"errors"
+	// fmt builds the error texts.
+	"fmt"
+	// html turns entities such as &amp; back into plain characters.
+	"html"
+	// io reads a limited part of the reply.
+	"io"
+	// net/http sends the read-only requests to the public library website.
+	"net/http"
+	// regexp finds the parts of the page.
+	"regexp"
+	// strconv turns the number text of a download size into a number.
+	"strconv"
+	// strings splits and trims text.
+	"strings"
+	// sync keeps the saved answer safe when two pages ask at once.
+	"sync"
+	// time limits how long a request may take and says how old the saved answer is.
+	"time"
+) // end of imports
+
+// ollamaSite is the address of the public Ollama website; a variable so tests can point it at a fake and never touch the real network.
+var ollamaSite = "https://ollama.com"
+
+// findTimeout is how long one request to the website may take; a slow or missing connection must not freeze the page.
+const findTimeout = 10 * time.Second
+
+// findMaxPage is the biggest page that is read; the real list page is about 1 MB and the biggest tags page under 1 MB.
+const findMaxPage = 4 << 20
+
+// findCacheTTL is how long the last answer of the list page is reused, so repeated clicks do not ask the website again and again.
+const findCacheTTL = time.Hour
+
+// errLayout is returned when a page does not look the way the reader expects (the website may have changed); nothing is guessed then.
+var errLayout = errors.New("the page does not look as expected, so nothing was read from it")
+
+// siteModel is one model as the library list page shows it.
+type siteModel struct {
+	// Name is the library name, for example "qwen3".
+	Name string
+	// Description is the one-line description from the page.
+	Description string
+	// Abilities are the ability labels the page shows: tools, vision, thinking, embedding, audio.
+	Abilities []string
+	// Sizes are the size labels the page shows, for example "0.6b" or "350m".
+	Sizes []string
+	// Cloud is true when the page marks the model as cloud: it runs on Ollama's servers, not on this computer.
+	Cloud bool
+	// Other holds any label the reader does not know; shown as it is, never interpreted.
+	Other []string
+	// Pulls is the download count as the page writes it, for example "120.9M".
+	Pulls string
+} // end of siteModel
+
+// siteTag is one downloadable version of a model as its tags page shows it.
+type siteTag struct {
+	// Tag is the full name to download, for example "granite4:1b-h".
+	Tag string
+	// SizeText is the download size as the page writes it, for example "1.6GB".
+	SizeText string
+	// SizeBytes is that size in bytes (decimal units, as the page's own numbers are rounded); 0 when the page showed none.
+	SizeBytes int64
+	// Context is the context length as the page writes it, for example "128K"; empty when not shown.
+	Context string
+	// Input is what the version accepts, as the page writes it, for example "Text input"; empty when not shown.
+	Input string
+} // end of siteTag
+
+// listSplit cuts the list page at the start of every model entry.
+var listSplit = regexp.MustCompile(`<li\s+class="flex items-baseline`)
+
+// entryName finds the library name inside one entry.
+var entryName = regexp.MustCompile(`href="/library/([A-Za-z0-9._-]+)"`)
+
+// entryDesc finds the one-line description inside one entry.
+var entryDesc = regexp.MustCompile(`(?s)<p class="max-w-lg[^>]*>(.*?)</p>`)
+
+// entryBadge finds every label (ability or size) inside one entry.
+var entryBadge = regexp.MustCompile(`<span\s+class="inline-flex[^"]*"[^>]*>([^<]+)</span>`)
+
+// entryPulls finds the download count inside one entry.
+var entryPulls = regexp.MustCompile(`<span >([^<]+)</span>\s*<span class="hidden sm:flex">&nbsp;Pulls`)
+
+// sizeLabel recognises a size label such as 0.6b, 350m, 8b or e4b.
+var sizeLabel = regexp.MustCompile(`^e?[0-9]+(\.[0-9]+)?[mb]$`)
+
+// knownAbility is the set of ability labels the reader understands.
+var knownAbility = map[string]bool{"tools": true, "vision": true, "thinking": true, "embedding": true, "audio": true}
+
+// parseSiteList reads the library list page; it returns errLayout when no entry can be read, and an entry without a name is an error too, so a changed page is noticed instead of half-read.
+func parseSiteList(page string) ([]siteModel, error) {
+	// Cut the page into entries; the first piece is everything before the first entry.
+	pieces := listSplit.Split(page, -1)
+	// No entry at all means the page is not the list page.
+	if len(pieces) < 2 {
+		// Say so.
+		return nil, errLayout
+	} // end of the entry check
+	// The result.
+	var out []siteModel
+	// Read each entry.
+	for _, p := range pieces[1:] {
+		// The name is required.
+		nm := entryName.FindStringSubmatch(p)
+		// No name: the layout is not what we expect.
+		if nm == nil {
+			// Stop, rather than return half the list.
+			return nil, errLayout
+		} // end of the name check
+		// Start the model.
+		m := siteModel{Name: nm[1]}
+		// The description is optional.
+		if d := entryDesc.FindStringSubmatch(p); d != nil {
+			// Plain text without entities and extra spaces.
+			m.Description = strings.Join(strings.Fields(html.UnescapeString(d[1])), " ")
+		} // end of the description
+		// The labels.
+		for _, b := range entryBadge.FindAllStringSubmatch(p, -1) {
+			// The label text.
+			label := strings.TrimSpace(html.UnescapeString(b[1]))
+			// Decide what kind of label it is.
+			switch {
+			// A cloud model.
+			case label == "cloud":
+				// Mark it.
+				m.Cloud = true
+			// A known ability.
+			case knownAbility[label]:
+				// Keep it.
+				m.Abilities = append(m.Abilities, label)
+			// A size.
+			case sizeLabel.MatchString(label):
+				// Keep it.
+				m.Sizes = append(m.Sizes, label)
+			// Anything else is kept as it is.
+			default:
+				// Keep it.
+				m.Other = append(m.Other, label)
+			} // end of the label switch
+		} // end of the label loop
+		// The download count is optional.
+		if pl := entryPulls.FindStringSubmatch(p); pl != nil {
+			// As written.
+			m.Pulls = strings.TrimSpace(pl[1])
+		} // end of the pulls
+		// Add the model.
+		out = append(out, m)
+	} // end of the entry loop
+	// The finished list.
+	return out, nil
+} // end of parseSiteList
+
+// tagBlock finds the compact block the tags page writes for every version.
+var tagBlock = regexp.MustCompile(`(?s)<a href="/library/([A-Za-z0-9._:-]+)" class="md:hidden[^>]*>(.*?)</a>`)
+
+// htmlTag finds any HTML tag, to strip it from a block.
+var htmlTag = regexp.MustCompile(`<[^>]+>`)
+
+// tagSize finds a download size such as 708MB or 3.3GB.
+var tagSize = regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?)\s*(KB|MB|GB|TB)`)
+
+// tagContext finds a context length such as 128K or 1M.
+var tagContext = regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?[KM]?) context window`)
+
+// tagInput finds the input kinds such as "Text input" or "Text, Image input".
+var tagInput = regexp.MustCompile(`((?:Text|Image|Audio|Video)(?:, (?:Text|Image|Audio|Video))* input)`)
+
+// sizeBytes turns a number and a unit into bytes (decimal units); an unknown unit gives 0.
+func sizeBytes(number, unit string) int64 {
+	// Read the number.
+	f, err := strconv.ParseFloat(number, 64)
+	// An unreadable number gives 0.
+	if err != nil {
+		// Nothing known.
+		return 0
+	} // end of the number check
+	// The multiplier for the unit.
+	var mult float64
+	// Choose by unit.
+	switch unit {
+	// Kilobytes.
+	case "KB":
+		// One thousand.
+		mult = 1e3
+	// Megabytes.
+	case "MB":
+		// One million.
+		mult = 1e6
+	// Gigabytes.
+	case "GB":
+		// One billion.
+		mult = 1e9
+	// Terabytes.
+	case "TB":
+		// One trillion.
+		mult = 1e12
+	// Anything else.
+	default:
+		// Nothing known.
+		return 0
+	} // end of the unit switch
+	// Round to a whole byte.
+	return int64(f*mult + 0.5)
+} // end of sizeBytes
+
+// parseSiteTags reads a tags page; it returns errLayout when no version can be read.
+func parseSiteTags(page string) ([]siteTag, error) {
+	// Every compact block.
+	blocks := tagBlock.FindAllStringSubmatch(page, -1)
+	// None: not a tags page.
+	if len(blocks) == 0 {
+		// Say so.
+		return nil, errLayout
+	} // end of the block check
+	// The result, and the names already seen (a version may be written twice).
+	var out []siteTag
+	// The seen set.
+	seen := map[string]bool{}
+	// Read each block.
+	for _, b := range blocks {
+		// The full tag name.
+		name := b[1]
+		// Skip a repeat.
+		if seen[name] {
+			// Already read.
+			continue
+		} // end of the repeat check
+		// Remember it.
+		seen[name] = true
+		// The block as plain text on one line.
+		text := strings.Join(strings.Fields(html.UnescapeString(htmlTag.ReplaceAllString(b[2], " "))), " ")
+		// Start the version.
+		t := siteTag{Tag: name}
+		// The download size.
+		if s := tagSize.FindStringSubmatch(text); s != nil {
+			// As written.
+			t.SizeText = s[1] + s[2]
+			// In bytes.
+			t.SizeBytes = sizeBytes(s[1], s[2])
+		} // end of the size
+		// The context length.
+		if c := tagContext.FindStringSubmatch(text); c != nil {
+			// As written.
+			t.Context = c[1]
+		} // end of the context
+		// The input kinds.
+		if in := tagInput.FindStringSubmatch(text); in != nil {
+			// As written.
+			t.Input = in[1]
+		} // end of the input
+		// Add the version.
+		out = append(out, t)
+	} // end of the block loop
+	// The finished list.
+	return out, nil
+} // end of parseSiteTags
+
+// fetchSitePage reads one page of the public website, read-only; only the address leaves this computer, and nothing about the person or their selections.
+func fetchSitePage(ctx context.Context, path string) (string, error) {
+	// A request that stops with the caller's context or after the timeout.
+	ctx, cancel := context.WithTimeout(ctx, findTimeout)
+	// Release the timer at the end.
+	defer cancel()
+	// Create the request.
+	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ollamaSite+path, nil)
+	// A failure here means the address could not be built.
+	if err != nil {
+		// Report it.
+		return "", err
+	} // end of the request check
+	// Say who is asking, and nothing else.
+	req.Header.Set("User-Agent", "LLMsControlDock")
+	// Send it.
+	resp, err := http.DefaultClient.Do(req)
+	// No answer: no internet, or the website is down.
+	if err != nil {
+		// Report it.
+		return "", err
+	} // end of the send check
+	// Close the reply at the end.
+	defer resp.Body.Close()
+	// Anything but a normal answer is a failure.
+	if resp.StatusCode != http.StatusOK {
+		// Report the status.
+		return "", fmt.Errorf("the website answered %d", resp.StatusCode)
+	} // end of the status check
+	// Read the page, but never more than the limit.
+	data, err := io.ReadAll(io.LimitReader(resp.Body, findMaxPage+1))
+	// A broken reply.
+	if err != nil {
+		// Report it.
+		return "", err
+	} // end of the read check
+	// An oversized reply is not read at all.
+	if len(data) > findMaxPage {
+		// Report it.
+		return "", errors.New("the page is larger than expected, so it was not read")
+	} // end of the size check
+	// The page text.
+	return string(data), nil
+} // end of fetchSitePage
+
+// fetchSiteTags reads the tags page of one library model; the name must be plain, so nothing odd is ever put into an address.
+func fetchSiteTags(ctx context.Context, model string) ([]siteTag, error) {
+	// Only plain names are asked for.
+	if !namePart.MatchString(model) {
+		// Never build an address from it.
+		return nil, errors.New("not a plain model name")
+	} // end of the name check
+	// Read the page.
+	page, err := fetchSitePage(ctx, "/library/"+model+"/tags")
+	// A failure.
+	if err != nil {
+		// Report it.
+		return nil, err
+	} // end of the fetch check
+	// Read the versions.
+	return parseSiteTags(page)
+} // end of fetchSiteTags
+
+// listCache keeps the last answer of the list page for a while.
+type listCache struct {
+	// mu keeps two pages from changing it at the same time.
+	mu sync.Mutex
+	// at is when the answer was read.
+	at time.Time
+	// models is the answer.
+	models []siteModel
+} // end of listCache
+
+// theListCache is the one saved answer of the program.
+var theListCache listCache
+
+// liveSiteList returns the current library list: the saved answer if it is younger than an hour, otherwise a fresh read; it also says when the answer was read.
+func liveSiteList(ctx context.Context, now func() time.Time) ([]siteModel, time.Time, error) {
+	// Only one caller at a time.
+	theListCache.mu.Lock()
+	// Let go at the end.
+	defer theListCache.mu.Unlock()
+	// A young enough saved answer is reused.
+	if theListCache.models != nil && now().Sub(theListCache.at) < findCacheTTL {
+		// Return it with its real age.
+		return theListCache.models, theListCache.at, nil
+	} // end of the cache check
+	// Read the page.
+	page, err := fetchSitePage(ctx, "/library")
+	// A failure keeps the older answer untouched.
+	if err != nil {
+		// Report it.
+		return nil, time.Time{}, err
+	} // end of the fetch check
+	// Read the models.
+	models, err := parseSiteList(page)
+	// A page that does not look right keeps the older answer untouched.
+	if err != nil {
+		// Report it.
+		return nil, time.Time{}, err
+	} // end of the parse check
+	// Keep the answer and its time.
+	theListCache.models, theListCache.at = models, now()
+	// Hand it back.
+	return models, theListCache.at, nil
+} // end of liveSiteList
diff --git a/findsite_test.go b/findsite_test.go
new file mode 100644
index 0000000..6d32892
--- /dev/null
+++ b/findsite_test.go
@@ -0,0 +1,405 @@
+// Package main tells Go that this test file belongs to the same program as findsite.go.
+package main
+
+import ( // import lists the standard-library packages this test file uses.
+	// context gives the requests their context.
+	"context"
+	// net/http gives the fake website its handler type and the status codes.
+	"net/http"
+	// net/http/httptest makes a fake website, so no test touches the real network.
+	"net/http/httptest"
+	// os reads the optional real pages.
+	"os"
+	// path/filepath joins the folder of the real pages with a file name.
+	"path/filepath"
+	// reflect compares lists.
+	"reflect"
+	// strings builds and searches test pages.
+	"strings"
+	// sync/atomic counts requests safely.
+	"sync/atomic"
+	// testing is Go's built-in test framework.
+	"testing"
+	// time gives the fake clock.
+	"time"
+) // end of imports
+
+// listEntry writes one entry the way the library list page does (same structure, invented content), with the given labels.
+func listEntry(name, desc string, labels ...string) string {
+	// The start of the entry, as the real page writes it.
+	s := "<li  class=\"flex items-baseline border-b\">\n<a href=\"/library/" + name + "\" class=\"group\">\n<div  title=\"" + name + "\">\n<h2><span>" + name + "</span></h2>\n<p class=\"max-w-lg break-words text-neutral-800 text-md\">" + desc + "</p>\n</div>\n<div class=\"flex flex-wrap space-x-2\">\n"
+	// Every label.
+	for _, l := range labels {
+		// One label.
+		s += "<span  class=\"inline-flex items-center rounded-md bg-indigo-50 px-2\">" + l + "</span>\n"
+	} // end of the label loop
+	// The download count and the end of the entry.
+	return s + "<span class=\"flex items-center\"><span >1.5M</span>\n<span class=\"hidden sm:flex\">&nbsp;Pulls</span></span>\n</a>\n</li>\n"
+} // end of listEntry
+
+// tagEntry writes one version block the way the tags page does (same structure, invented content).
+func tagEntry(tag, size, context string) string {
+	// The compact block with the pieces separated by bullets, as the real page writes them.
+	body := "<span>" + tag + "</span>\n<span class=\"font-mono\">abc123def456</span> • " + size
+	// The context part is optional.
+	if context != "" {
+		// Add it.
+		body += " • " + context + " context window"
+	} // end of the context part
+	// The input part and the end of the block.
+	return "<a href=\"/library/" + tag + "\" class=\"md:hidden flex flex-col\">\n" + body + " • Text input • 1 year ago\n</a>\n"
+} // end of tagEntry
+
+// TestParseSiteListReadsNamesAbilitiesSizesAndCloud checks what one list page gives.
+func TestParseSiteListReadsNamesAbilitiesSizesAndCloud(t *testing.T) {
+	// A page with three entries: a normal one, an embedding one without sizes, and a cloud one with an unknown label.
+	page := "<html><ul>" + listEntry("alpha", "A &amp; B model.", "tools", "thinking", "0.6b", "8b") + listEntry("beta-embed", "Turns text into numbers.", "embedding") + listEntry("gamma", "Runs far away.", "cloud", "decision", "e4b", "vision") + "</ul></html>"
+	// Read it.
+	got, err := parseSiteList(page)
+	// It must work.
+	if err != nil {
+		// Report.
+		t.Fatalf("parseSiteList: %v", err)
+	} // end of the error check
+	// Three entries.
+	if len(got) != 3 {
+		// Report.
+		t.Fatalf("got %d models, want 3", len(got))
+	} // end of the count check
+	// The first entry in full.
+	want0 := siteModel{Name: "alpha", Description: "A & B model.", Abilities: []string{"tools", "thinking"}, Sizes: []string{"0.6b", "8b"}, Pulls: "1.5M"}
+	// Compare.
+	if !reflect.DeepEqual(got[0], want0) {
+		// Report.
+		t.Errorf("first model = %+v, want %+v", got[0], want0)
+	} // end of the first check
+	// The embedding model has no sizes and one ability.
+	if !reflect.DeepEqual(got[1].Abilities, []string{"embedding"}) || len(got[1].Sizes) != 0 {
+		// Report.
+		t.Errorf("second model = %+v", got[1])
+	} // end of the second check
+	// The cloud model is marked, keeps its unknown label apart, and counts e4b as a size.
+	if !got[2].Cloud || !reflect.DeepEqual(got[2].Other, []string{"decision"}) || !reflect.DeepEqual(got[2].Sizes, []string{"e4b"}) || !reflect.DeepEqual(got[2].Abilities, []string{"vision"}) {
+		// Report.
+		t.Errorf("third model = %+v", got[2])
+	} // end of the third check
+} // end of TestParseSiteListReadsNamesAbilitiesSizesAndCloud
+
+// TestParseSiteListRefusesAChangedLayout checks that a page without entries, or with an entry without a name, is an error and not a short list.
+func TestParseSiteListRefusesAChangedLayout(t *testing.T) {
+	// A page with no entries at all.
+	if _, err := parseSiteList("<html>nothing here</html>"); err != errLayout {
+		// Report.
+		t.Errorf("empty page: err = %v, want errLayout", err)
+	} // end of the empty check
+	// An entry that has no library link.
+	if _, err := parseSiteList("<li  class=\"flex items-baseline\"><p>no link</p></li>"); err != errLayout {
+		// Report.
+		t.Errorf("nameless entry: err = %v, want errLayout", err)
+	} // end of the nameless check
+} // end of TestParseSiteListRefusesAChangedLayout
+
+// TestParseSiteTagsReadsSizeContextAndInput checks what one tags page gives.
+func TestParseSiteTagsReadsSizeContextAndInput(t *testing.T) {
+	// A page with a repeated version and one without a context length.
+	page := "<html>" + tagEntry("m:1b", "3.3GB", "128K") + tagEntry("m:350m", "708MB", "32K") + tagEntry("m:1b", "3.3GB", "128K") + tagEntry("m:odd", "12KB", "") + "</html>"
+	// Read it.
+	got, err := parseSiteTags(page)
+	// It must work.
+	if err != nil {
+		// Report.
+		t.Fatalf("parseSiteTags: %v", err)
+	} // end of the error check
+	// The repeat is dropped.
+	if len(got) != 3 {
+		// Report.
+		t.Fatalf("got %d tags, want 3: %+v", len(got), got)
+	} // end of the count check
+	// The first version in full.
+	want0 := siteTag{Tag: "m:1b", SizeText: "3.3GB", SizeBytes: 3300000000, Context: "128K", Input: "Text input"}
+	// Compare.
+	if got[0] != want0 {
+		// Report.
+		t.Errorf("first tag = %+v, want %+v", got[0], want0)
+	} // end of the first check
+	// The second version.
+	if got[1].SizeBytes != 708000000 || got[1].Context != "32K" {
+		// Report.
+		t.Errorf("second tag = %+v", got[1])
+	} // end of the second check
+	// A missing context stays empty and is not invented.
+	if got[2].Context != "" || got[2].SizeBytes != 12000 {
+		// Report.
+		t.Errorf("third tag = %+v", got[2])
+	} // end of the third check
+	// A page without versions is a layout error.
+	if _, err := parseSiteTags("<html></html>"); err != errLayout {
+		// Report.
+		t.Errorf("empty tags page: err = %v, want errLayout", err)
+	} // end of the empty check
+} // end of TestParseSiteTagsReadsSizeContextAndInput
+
+// TestSizeBytesUnits checks the unit conversion, including the rounding and an unknown unit.
+func TestSizeBytesUnits(t *testing.T) {
+	// The cases.
+	for _, c := range []struct {
+		// number and unit are the inputs.
+		number, unit string
+		// want is the expected bytes.
+		want int64
+	}{{"708", "MB", 708000000}, {"3.3", "GB", 3300000000}, {"1.5", "GB", 1500000000}, {"12", "KB", 12000}, {"1.2", "TB", 1200000000000}, {"5", "XB", 0}, {"x", "GB", 0}} {
+		// Convert.
+		if got := sizeBytes(c.number, c.unit); got != c.want {
+			// Report.
+			t.Errorf("sizeBytes(%q, %q) = %d, want %d", c.number, c.unit, got, c.want)
+		} // end of the compare
+	} // end of the case loop
+} // end of TestSizeBytesUnits
+
+// fakeSite starts a fake website with the given pages and points ollamaSite at it for the test; hits counts the requests it receives.
+func fakeSite(t *testing.T, pages map[string]string) (hits *int32) {
+	// Mark this as a helper.
+	t.Helper()
+	// The counter.
+	hits = new(int32)
+	// The fake server.
+	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+		// Count the request.
+		atomic.AddInt32(hits, 1)
+		// The reader must say who it is.
+		if r.Header.Get("User-Agent") != "LLMsControlDock" {
+			// Refuse an unknown client.
+			http.Error(w, "unknown client", http.StatusForbidden)
+			// Stop.
+			return
+		} // end of the client check
+		// Find the page.
+		body, ok := pages[r.URL.Path]
+		// Unknown path.
+		if !ok {
+			// A normal "not found".
+			http.NotFound(w, r)
+			// Stop.
+			return
+		} // end of the path check
+		// Send the page.
+		_, _ = w.Write([]byte(body))
+	}))
+	// Stop it at the end of the test.
+	t.Cleanup(srv.Close)
+	// Point the reader at it, and restore the real address afterwards.
+	old := ollamaSite
+	// Use the fake.
+	ollamaSite = srv.URL
+	// Put the real address back.
+	t.Cleanup(func() { ollamaSite = old })
+	// The counter.
+	return hits
+} // end of fakeSite
+
+// TestFetchSiteTagsAndErrors checks the tags fetch, a missing page, a bad name that never reaches the network, and an oversized page.
+func TestFetchSiteTagsAndErrors(t *testing.T) {
+	// A fake website with one tags page and one oversized page.
+	hits := fakeSite(t, map[string]string{
+		// A normal tags page.
+		"/library/granite4/tags": tagEntry("granite4:1b-h", "1.6GB", "1M"),
+		// A page above the limit.
+		"/library/huge/tags": strings.Repeat("x", findMaxPage+10),
+	})
+	// A normal read.
+	tags, err := fetchSiteTags(context.Background(), "granite4")
+	// It must work and give the version.
+	if err != nil || len(tags) != 1 || tags[0].Tag != "granite4:1b-h" || tags[0].SizeText != "1.6GB" {
+		// Report.
+		t.Fatalf("fetchSiteTags = %+v, %v", tags, err)
+	} // end of the normal check
+	// A model the website does not have.
+	if _, err := fetchSiteTags(context.Background(), "nothere"); err == nil || !strings.Contains(err.Error(), "404") {
+		// Report.
+		t.Errorf("missing model: err = %v, want a 404 error", err)
+	} // end of the missing check
+	// An oversized page is refused.
+	if _, err := fetchSiteTags(context.Background(), "huge"); err == nil || !strings.Contains(err.Error(), "larger") {
+		// Report.
+		t.Errorf("oversized page: err = %v", err)
+	} // end of the size check
+	// Remember the number of requests so far.
+	before := atomic.LoadInt32(hits)
+	// A bad name must not reach the network.
+	if _, err := fetchSiteTags(context.Background(), "a/b;c"); err == nil {
+		// Report.
+		t.Error("a bad name was accepted")
+	} // end of the bad-name check
+	// No request was made for it.
+	if atomic.LoadInt32(hits) != before {
+		// Report.
+		t.Error("a bad name reached the network")
+	} // end of the network check
+} // end of TestFetchSiteTagsAndErrors
+
+// TestLiveSiteListUsesTheSavedAnswerForAnHour checks the one-hour reuse and the refresh after it.
+func TestLiveSiteListUsesTheSavedAnswerForAnHour(t *testing.T) {
+	// Start with an empty saved answer, and leave it empty afterwards.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake website with a small list page.
+	hits := fakeSite(t, map[string]string{"/library": listEntry("alpha", "d", "tools")})
+	// The fake clock.
+	clock := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
+	// A clock function that returns the current fake time.
+	now := func() time.Time { return clock }
+	// First call: a real read.
+	m, at, err := liveSiteList(context.Background(), now)
+	// It must work and say when it was read.
+	if err != nil || len(m) != 1 || !at.Equal(clock) {
+		// Report.
+		t.Fatalf("first call = %+v, %v, %v", m, at, err)
+	} // end of the first check
+	// Thirty minutes later: the saved answer, with its original time, and no new request.
+	clock = clock.Add(30 * time.Minute)
+	// Ask again.
+	_, at2, err := liveSiteList(context.Background(), now)
+	// It must be the saved one.
+	if err != nil || at2.Equal(clock) || atomic.LoadInt32(hits) != 1 {
+		// Report.
+		t.Fatalf("second call: at=%v err=%v hits=%d", at2, err, atomic.LoadInt32(hits))
+	} // end of the second check
+	// Two hours after the start: a fresh read.
+	clock = clock.Add(90 * time.Minute)
+	// Ask again.
+	_, at3, err := liveSiteList(context.Background(), now)
+	// It must be new.
+	if err != nil || !at3.Equal(clock) || atomic.LoadInt32(hits) != 2 {
+		// Report.
+		t.Fatalf("third call: at=%v err=%v hits=%d", at3, err, atomic.LoadInt32(hits))
+	} // end of the third check
+} // end of TestLiveSiteListUsesTheSavedAnswerForAnHour
+
+// TestLiveSiteListKeepsTheOldAnswerWhenTheWebsiteFails checks that a failed or changed page does not wipe the saved answer.
+func TestLiveSiteListKeepsTheOldAnswerWhenTheWebsiteFails(t *testing.T) {
+	// Start empty and leave empty.
+	theListCache = listCache{}
+	// Clear at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake website whose list page is first good.
+	pages := map[string]string{"/library": listEntry("alpha", "d", "tools")}
+	// Start it.
+	fakeSite(t, pages)
+	// The fake clock.
+	clock := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
+	// The clock function.
+	now := func() time.Time { return clock }
+	// A good first read.
+	if _, _, err := liveSiteList(context.Background(), now); err != nil {
+		// Report.
+		t.Fatalf("first read: %v", err)
+	} // end of the first check
+	// The website now changes its layout.
+	pages["/library"] = "<html>redesigned</html>"
+	// Two hours later the saved answer is too old, so a new read is tried.
+	clock = clock.Add(2 * time.Hour)
+	// Ask again.
+	if _, _, err := liveSiteList(context.Background(), now); err != errLayout {
+		// Report.
+		t.Fatalf("changed layout: err = %v, want errLayout", err)
+	} // end of the layout check
+	// The old answer is still stored, so the caller can show it labelled with its date.
+	if len(theListCache.models) != 1 || !theListCache.at.Equal(time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)) {
+		// Report.
+		t.Errorf("the saved answer was lost: %d models, read at %v", len(theListCache.models), theListCache.at)
+	} // end of the stored check
+} // end of TestLiveSiteListKeepsTheOldAnswerWhenTheWebsiteFails
+
+// TestRealPagesIfProvided reads the real pages saved by script 90, when the folder is named in FINDLLM_PAGES; it is skipped otherwise, so no test needs the pages and none are stored in the project.
+func TestRealPagesIfProvided(t *testing.T) {
+	// The folder of the saved pages.
+	dir := os.Getenv("FINDLLM_PAGES")
+	// Not given: skip.
+	if dir == "" {
+		// Say why.
+		t.Skip("FINDLLM_PAGES is not set")
+	} // end of the skip
+	// Read the list page.
+	list, err := os.ReadFile(filepath.Join(dir, "_listing.model.html"))
+	// It must exist.
+	if err != nil {
+		// Report.
+		t.Fatalf("list page: %v", err)
+	} // end of the read check
+	// Parse it.
+	models, err := parseSiteList(string(list))
+	// It must work.
+	if err != nil || len(models) < 100 {
+		// Report.
+		t.Fatalf("real list page: %d models, %v", len(models), err)
+	} // end of the parse check
+	// Find the two helper models.
+	var granite, qwen *siteModel
+	// Look at each.
+	for i := range models {
+		// Granite.
+		if models[i].Name == "granite4" {
+			// Keep it.
+			granite = &models[i]
+		} // end of granite
+		// Qwen3.
+		if models[i].Name == "qwen3" {
+			// Keep it.
+			qwen = &models[i]
+		} // end of qwen
+	} // end of the look
+	// Both must be there.
+	if granite == nil || qwen == nil {
+		// Report.
+		t.Fatal("granite4 or qwen3 is missing from the real list page")
+	} // end of the presence check
+	// Granite lists a 1b size and the tools ability.
+	if !contains(granite.Sizes, "1b") || !contains(granite.Abilities, "tools") {
+		// Report.
+		t.Errorf("granite4 = %+v", *granite)
+	} // end of the granite check
+	// Read the Granite tags page.
+	tagsPage, err := os.ReadFile(filepath.Join(dir, "granite4.tags.html"))
+	// It must exist.
+	if err != nil {
+		// Report.
+		t.Fatalf("tags page: %v", err)
+	} // end of the read check
+	// Parse it.
+	tags, err := parseSiteTags(string(tagsPage))
+	// It must work.
+	if err != nil {
+		// Report.
+		t.Fatalf("real tags page: %v", err)
+	} // end of the parse check
+	// The version chosen as the default helper must be there with its size.
+	found := false
+	// Look at each version.
+	for _, tg := range tags {
+		// The chosen one.
+		if tg.Tag == "granite4:1b-h" && tg.SizeText == "1.6GB" && tg.Context == "1M" {
+			// Found it.
+			found = true
+		} // end of the compare
+	} // end of the look
+	// It must be found.
+	if !found {
+		// Report.
+		t.Errorf("granite4:1b-h with 1.6GB and 1M was not found in %+v", tags)
+	} // end of the found check
+} // end of TestRealPagesIfProvided
+
+// contains reports whether the list holds the word.
+func contains(list []string, want string) bool {
+	// Look at each.
+	for _, s := range list {
+		// A match.
+		if s == want {
+			// Found.
+			return true
+		} // end of the match
+	} // end of the loop
+	// Not found.
+	return false
+} // end of contains
OCC_PATCH_91_END

# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The new files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "both new files have the expected sha256"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# The extra test on the real pages saved by script 90 runs only when that folder is there (the newest one in the home folder).
REAL="$(ls -d "$HOME"/findllm-collect-*/ 2>/dev/null | sort | tail -1 || true)"
# When the folder exists, run the real-page test and show its result line.
if [ -n "$REAL" ] && [ -f "$REAL/_listing.model.html" ]; then
  # Run only that test, verbosely, pointing it at the folder.
  FINDLLM_PAGES="$REAL" go test -count=1 -run TestRealPagesIfProvided -v . | grep -E '^(--- |ok|FAIL)' || fail "the real-page test failed"
  # Report it.
  pass "real-page test on $REAL"
# End of the optional check.
fi

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  nothing changes on screen yet; commit and pull request come next (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
