// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes reads the CSV.
	"bytes"
	// encoding/csv parses the CSV the program wrote.
	"encoding/csv"
	// net/http/httptest records the handler's answer.
	"net/http/httptest"
	// net/http gives the status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// os reads the copies back.
	"os"
	// path/filepath builds paths in the test folder.
	"path/filepath"
	// regexp checks the file name.
	"regexp"
	// strings joins and searches text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time gives a fixed time.
	"time"
) // end of imports

// reportRuns builds the runs of the report tests: two fair chat models, one that is not fair, a lone large model and two embedding models.
func reportRuns() []perfRun {
	// A model that ran partly on the processor.
	odd := okRun("odd:4b", 250)
	// The split.
	odd.GPUBytes = odd.ModelBytes / 2
	// A large model.
	large := okRun("large:27b", 90)
	// Its size.
	large.ParameterSize = "27.4B"
	// The runs.
	return []perfRun{okRun("a:4b", 300), okRun("b:4b", 200), odd, large, embRun("emb-a", 0.04), embRun("emb-b", 0.2)}
} // end of reportRuns

// TestComparePDFCarriesEverything checks the PDF: valid structure, the notice at the start, at the end and in every footer, the groups, the flags, the method and the references.
func TestComparePDFCarriesEverything(t *testing.T) {
	// The page data and the file.
	when := time.Date(2026, 10, 27, 19, 30, 0, 0, time.UTC)
	// Build.
	p := buildCompare(reportRuns(), 0, nil, false)
	// The file.
	data := writeComparePDF(p, when)
	// Validate it.
	bodies, footers := pdfCheck(t, data)
	// The body text.
	body := flat(bodies)
	// The full notice must be there exactly once, at the end of the file.
	for _, para := range noticeFull {
		// Normalise the paragraph the same way.
		want := strings.Join(strings.Fields(para), " ")
		// Once.
		if n := strings.Count(body, want); n != 1 {
			// Report it.
			t.Errorf("notice paragraph %.40q appears %d times, want 1", want, n)
		} // end of the count check
	} // end of the notice loop
	// The heading of the full notice appears once, after the last reference and after every group.
	if n := strings.Count(body, noticeTitle); n != 1 || strings.Index(body, noticeTitle) < strings.LastIndex(body, "References") {
		// Report it.
		t.Errorf("the notice heading appears %d times or not at the end", n)
	} // end of the heading check
	// The first page carries the short notice in its footer, before any figure.
	if len(footers) == 0 || !strings.Contains(flat([][]pdfTextLine{footers[0]}), noticeShort) {
		// Report it.
		t.Errorf("the first page has no short notice in its footer")
	} // end of the first page check
	// A short notice and the page number in every footer.
	for i, f := range footers {
		// The footer text.
		text := flat([][]pdfTextLine{f})
		// The checks.
		if !strings.Contains(text, noticeShort) || !strings.Contains(text, "page "+string(rune('0'+i+1))+" of ") || !strings.Contains(text, "OllamaControlCenter "+appVersion) || !strings.Contains(text, "made 2026-10-27 19:30 UTC") {
			// Report it.
			t.Errorf("footer of page %d: %q", i+1, text)
		} // end of the check
	} // end of the footer loop
	// The content.
	for _, w := range []string{"Model comparison", "What the figures say", "Chat · Small (1B to under 5B)", "Chat · Large (12B to under 36B)", "Embedding models", "Why this group:", "a:4b writes fastest in this group (300 characters per second)", "Characters per second: 300 chars/s", "#2, 1.5× slower", "No: part of the model ran on the processor, not only on the graphics card", "Only model in this group", "emb-a embeds fastest in this group", "How and why this comparison was done", "References", "Loïc Magne", "A web page can change or disappear later."} {
		// Look for it.
		if !strings.Contains(body, w) {
			// Report it.
			t.Errorf("PDF lacks %q", w)
		} // end of the check
	} // end of the loop
	// The symbols that the font cannot draw never appear, and no stray question mark replaces one.
	for _, bad := range []string{"✓", "⚠", "?? "} {
		// Present.
		if strings.Contains(body, bad) {
			// Report it.
			t.Errorf("PDF contains %q", bad)
		} // end of the check
	} // end of the loop
	// Every method answer and every reference address is in the file.
	for _, h := range howRows() {
		// The question and the answer.
		if !strings.Contains(body, h.Question) || !strings.Contains(body, strings.Join(strings.Fields(h.Answer), " ")) {
			// Report it.
			t.Errorf("method row missing: %q", h.Question)
		} // end of the check
	} // end of the method loop
	// The references.
	for _, r := range compareReferences {
		// The address and the title.
		if !strings.Contains(body, r.URL) || !strings.Contains(body, r.Title) {
			// Report it.
			t.Errorf("reference %d missing", r.N)
		} // end of the check
	} // end of the reference loop
	// An empty comparison still gives a valid file with the notice.
	empty := writeComparePDF(buildCompare(nil, 0, nil, false), when)
	// Validate it.
	eb, _ := pdfCheck(t, empty)
	// The notice and the sentence.
	if text := flat(eb); !strings.Contains(text, "No model has been through a performance test yet.") || !strings.Contains(text, "No warranty and no liability.") {
		// Report it.
		t.Errorf("empty PDF: %.80s", text)
	} // end of the empty check
} // end of TestComparePDFCarriesEverything

// TestCompareCSV checks the CSV: the notice first, the header, one row for each model with the right figures, the notice and the references after, and the guard against formulas.
func TestCompareCSV(t *testing.T) {
	// A model whose name would run as a formula in a spreadsheet.
	evil := okRun("=cmd|' /C calc'!A0", 100)
	// The runs.
	runs := append(reportRuns(), evil)
	// The page data and the file.
	when := time.Date(2026, 10, 27, 19, 30, 0, 0, time.UTC)
	// Build.
	data := writeCompareCSV(buildCompare(runs, 0, nil, false), when)
	// The UTF-8 mark.
	if !bytes.HasPrefix(data, []byte("\xef\xbb\xbf")) {
		// Stop the test.
		t.Fatalf("no UTF-8 mark")
	} // end of the mark check
	// Parse it; the records have different lengths on purpose.
	r := csv.NewReader(bytes.NewReader(bytes.TrimPrefix(data, []byte("\xef\xbb\xbf"))))
	// Allow rows of different length.
	r.FieldsPerRecord = -1
	// Read everything.
	recs, err := r.ReadAll()
	// It must parse.
	if err != nil {
		// Stop the test.
		t.Fatalf("not valid CSV: %v", err)
	} // end of the parse check
	// The notice comes first, then who made it, then the header.
	if recs[0][0] != "NOTICE" || recs[0][1] != noticeShort || recs[1][0] != "MADE BY" || !strings.Contains(recs[1][1], "2026-10-27 19:30 UTC") || strings.Join(recs[2], "|") != strings.Join(csvHeader, "|") {
		// Stop the test.
		t.Fatalf("start of file: %v / %v / %v", recs[0], recs[1], recs[2])
	} // end of the start check
	// One data row for each model.
	rows := recs[3 : 3+len(runs)]
	// Every row has the header's width.
	for _, row := range rows {
		// The width.
		if len(row) != len(csvHeader) {
			// Stop the test.
			t.Fatalf("row has %d fields: %v", len(row), row)
		} // end of the width check
	} // end of the loop
	// The row of a:4b by header name.
	col := map[string]int{}
	// Index the header.
	for i, h := range csvHeader {
		// One column.
		col[h] = i
	} // end of the loop
	// Find a row by model name.
	find := func(name string) []string {
		// Look at each row.
		for _, row := range rows {
			// A match.
			if row[col["Model"]] == name {
				// Found.
				return row
			} // end of the match check
		} // end of the loop
		// A missing row is a test failure.
		t.Fatalf("no row for %q", name)
		// Never reached.
		return nil
	} // end of find
	// The fastest model.
	a := find("a:4b")
	// Its figures, worked out by hand.
	for h, want := range map[string]string{"Group": "Chat · Small (1B to under 5B)", "Kind": "chat", "Parameters": "4.3B", "Quantization": "4-bit (Q4_K_M)", "Tested on (UTC)": "2026-10-27 18:04 UTC", "Answer tokens per second": "60.00", "Answer characters per second": "300.00", "Embedding time (s)": "", "Time to first word (s)": "0.300", "Total time (s)": "1.100", "Load time (s)": "3.000", "Memory used (bytes)": "3800000000", "Share on graphics card (%)": "100", "Machine busy": "false", "Rank in group": "1", "Fair to rank": "yes", "Reasons": ""} {
		// The cell.
		if got := a[col[h]]; got != want {
			// Report it.
			t.Errorf("a:4b %q = %q, want %q", h, got, want)
		} // end of the check
	} // end of the loop
	// The model that ran partly on the processor.
	o := find("odd:4b")
	// Not fair, no rank, half on the graphics card, with the reason.
	if o[col["Fair to rank"]] != "no" || o[col["Rank in group"]] != "" || o[col["Share on graphics card (%)"]] != "50" || o[col["Reasons"]] != "part of the model ran on the processor, not only on the graphics card" {
		// Report it.
		t.Errorf("odd row: %v", o)
	} // end of the odd check
	// An embedding model has its time and no characters.
	e := find("emb-a")
	// Its cells.
	if e[col["Kind"]] != "embedding" || e[col["Embedding time (s)"]] != "0.040" || e[col["Answer characters per second"]] != "" || e[col["Group"]] != "Embedding models" || e[col["Rank in group"]] != "1" {
		// Report it.
		t.Errorf("embedding row: %v", e)
	} // end of the embedding check
	// The formula is made harmless.
	if got := find("'=cmd|' /C calc'!A0")[col["Model"]]; !strings.HasPrefix(got, "'=") {
		// Report it.
		t.Errorf("formula not guarded: %q", got)
	} // end of the formula check
	// After the data: the full notice and the references.
	var notices, refs int
	// Count them.
	for _, rec := range recs[3+len(runs):] {
		// Notice rows.
		if rec[0] == "NOTICE" {
			// Count it.
			notices++
		} // end of the notice check
		// Reference rows.
		if rec[0] == "REFERENCE" {
			// Count it, and check it holds the address.
			refs++
			// The address.
			if !strings.Contains(rec[1], compareReferences[refs-1].URL) {
				// Report it.
				t.Errorf("reference row %d: %q", refs, rec[1])
			} // end of the address check
		} // end of the reference check
	} // end of the loop
	// All of them.
	if notices != len(noticeFull) || refs != len(compareReferences) {
		// Report it.
		t.Errorf("%d notice rows, %d reference rows", notices, refs)
	} // end of the count check
} // end of TestCompareCSV

// TestCSVSafe checks the guard against spreadsheet formulas.
func TestCSVSafe(t *testing.T) {
	// The cases.
	for in, want := range map[string]string{"=1+1": "'=1+1", "+1": "'+1", "-1": "'-1", "@x": "'@x", "\tx": "'\tx", "\rx": "'\rx", "plain": "plain", "": "", "a=b": "a=b"} {
		// Guard it.
		if got := csvSafe(in); got != want {
			// Report it.
			t.Errorf("csvSafe(%q) = %q, want %q", in, got, want)
		} // end of the check
	} // end of the loop
} // end of TestCSVSafe

// savedFileOf reads the "saved" page a PDF or CSV request returns, checks that it names the results folder, and returns the bytes of the file the program wrote there.
func savedFileOf(t *testing.T, res *http.Response, folder, ext string) []byte {
	// Mark this as a helper.
	t.Helper()
	// The page.
	page := bodyOf(res)
	// A normal HTML page, not a file for the browser.
	if res.StatusCode != http.StatusOK || !strings.HasPrefix(res.Header.Get("Content-Type"), "text/html") || res.Header.Get("Content-Disposition") != "" {
		// Stop the test.
		t.Fatalf("%s: status %d, type %q, disposition %q", ext, res.StatusCode, res.Header.Get("Content-Type"), res.Header.Get("Content-Disposition"))
	} // end of the page check
	// The folder and the name as the page shows them.
	m := regexp.MustCompile(`<code class="savedpath">([^<]*)</code>.*<code class="savedname">(OllamaControlCenter-comparison-\d{8}-\d{6}Z\.` + ext + `)</code>`).FindStringSubmatch(strings.ReplaceAll(page, "\n", " "))
	// Both must be there.
	if m == nil {
		// Stop the test.
		t.Fatalf("%s: the saved page names no folder and file: %.300s", ext, page)
	} // end of the match check
	// The folder is the results folder.
	if m[1] != folder {
		// Report it.
		t.Errorf("%s: saved in %q, want %q", ext, m[1], folder)
	} // end of the folder check
	// Read what the program wrote.
	b, err := os.ReadFile(filepath.Join(m[1], m[2]))
	// It must exist.
	if err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the read check
	// The notice travels with the page too.
	if !strings.Contains(page, noticeShort) || !strings.Contains(page, `action="/compare"`) {
		// Report it.
		t.Errorf("%s: the saved page lacks the notice or the way back", ext)
	} // end of the notice check
	// The bytes.
	return b
} // end of savedFileOf

// TestCompareDownloadRoutes checks both downloads through the real handler: the files, the headers, the form rules and the empty case.
func TestCompareDownloadRoutes(t *testing.T) {
	// A fake Ollama and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, histFile := perfRig(t, f)
	// With nothing saved there is nothing to download.
	for _, path := range []string{"/compare/pdf", "/compare/csv"} {
		// Ask.
		res := post(t, rig.h, path, url.Values{"token": {rig.token}}, fromThisPage)
		// A conflict, with a plain message.
		if res.StatusCode != http.StatusConflict || !strings.Contains(bodyOf(res), "nothing to download") {
			// Report it.
			t.Errorf("%s empty = %d", path, res.StatusCode)
		} // end of the check
	} // end of the loop
	// Two real tests.
	perfPost(t, rig, "/performance/run", "chat:1b")
	// The embedding model.
	perfPost(t, rig, "/performance/run", "embed:1b")
	// The PDF is written into the results folder by the program.
	res := post(t, rig.h, "/compare/pdf", url.Values{"token": {rig.token}}, fromThisPage)
	// The saved file.
	pdfBytes := savedFileOf(t, res, filepath.Dir(histFile), "pdf")
	// The file is valid and carries the notice and the real model names.
	bodies, _ := pdfCheck(t, pdfBytes)
	// The text.
	text := flat(bodies)
	// The checks.
	for _, w := range []string{"chat:1b", "embed:1b", "Chat · Small (1B to under 5B)", "Embedding models", noticeFull[1]} {
		// Missing.
		if !strings.Contains(text, strings.Join(strings.Fields(w), " ")) {
			// Report it.
			t.Errorf("downloaded PDF lacks %q", w)
		} // end of the check
	} // end of the loop
	// The characters of the fake's answer were counted: 18 characters in 1.6 s is 11.25 a second, and nothing of the answer text is in the file.
	if !strings.Contains(text, "Characters per second: 11 chars/s") || strings.Contains(text, secretText) {
		// Report it.
		t.Errorf("character speed or secret text: %.200s", text)
	} // end of the characters check
	// The CSV is written into the results folder by the program.
	res = post(t, rig.h, "/compare/csv", url.Values{"token": {rig.token}}, fromThisPage)
	// The saved file.
	csvBytes := savedFileOf(t, res, filepath.Dir(histFile), "csv")
	// It parses and starts with the notice.
	recs, err := func() ([][]string, error) {
		// The body without the mark.
		b := bytes.TrimPrefix(csvBytes, []byte("\xef\xbb\xbf"))
		// Parse.
		r := csv.NewReader(bytes.NewReader(b))
		// Different widths are fine.
		r.FieldsPerRecord = -1
		// Read.
		return r.ReadAll()
	}()
	// A valid file with the notice first.
	if err != nil || recs[0][0] != "NOTICE" || recs[0][1] != noticeShort {
		// Stop the test.
		t.Fatalf("csv start: %v %v", err, recs[:1])
	} // end of the csv check
	// The refusals are the same as for the page.
	for _, path := range []string{"/compare/pdf", "/compare/csv"} {
		// A wrong token.
		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
			// Report it.
			t.Errorf("%s wrong token = %d", path, res.StatusCode)
		} // end of the token check
		// A request from another site.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
			// Report it.
			t.Errorf("%s cross-site = %d", path, res.StatusCode)
		} // end of the origin check
		// A plain GET.
		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
			// Report it.
			t.Errorf("GET %s = %d", path, status)
		} // end of the GET check
	} // end of the loop
	// The page offers exactly one of each button.
	_, _, page := func() (int, http.Header, string) {
		// Ask for the page.
		r := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
		// The parts.
		return r.StatusCode, r.Header, bodyOf(r)
	}()
	// Count them.
	if strings.Count(page, `action="/compare/pdf"`) != 1 || strings.Count(page, `action="/compare/csv"`) != 1 {
		// Report it.
		t.Errorf("download buttons: %d / %d", strings.Count(page, `action="/compare/pdf"`), strings.Count(page, `action="/compare/csv"`))
	} // end of the button check
	// Each download left a copy next to the saved results.
	var pdfs, csvs int
	// Look through the folder of the results.
	_ = filepath.WalkDir(filepath.Dir(histFile), func(p string, d os.DirEntry, err error) error {
		// Count by ending.
		if err == nil && strings.HasPrefix(d.Name(), "OllamaControlCenter-comparison-") {
			// A PDF copy.
			if strings.HasSuffix(d.Name(), ".pdf") {
				// Count it.
				pdfs++
			} // end of the PDF check
			// A CSV copy.
			if strings.HasSuffix(d.Name(), ".csv") {
				// Count it.
				csvs++
			} // end of the CSV check
		} // end of the name check
		// Keep walking.
		return nil
	}) // end of the walk
	// At least one of each.
	if pdfs < 1 || csvs < 1 {
		// Report it.
		t.Errorf("copies saved: %d PDF, %d CSV", pdfs, csvs)
	} // end of the copies check
} // end of TestCompareDownloadRoutes

// TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage builds the report with many different lengths, so headings land at every height, and checks that no page ends with a heading, a question or a model name.
func TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage(t *testing.T) {
	// The report with a growing number of chat models.
	for extra := 0; extra < 90; extra++ {
		for pad := 0; pad < 6; pad++ { // finer steps: extra lines of padding move every heading by one line at a time
			// The runs.
			runs := reportRuns()
			// More chat models of one group.
			for i := 0; i < extra; i++ {
				// A model with a name of its own.
				runs = append(runs, okRun("filler-"+strings.Repeat("x", i%7)+string(rune('a'+i%26))+":4b", float64(100+i)))
			} // end of the filler loop
			// The page data and the file.
			p := buildCompare(runs, 0, nil, false)
			// Padding lines under the last group move every later heading down by one line each.
			for k := 0; k < pad && len(p.Groups) > 0; k++ {
				// One more short note.
				p.Groups[len(p.Groups)-1].Notes = append(p.Groups[len(p.Groups)-1].Notes, "padding line")
			} // end of the padding loop
			// Validate and read it.
			bodies, _ := pdfCheck(t, writeComparePDF(p, time.Date(2026, 10, 27, 19, 30, 0, 0, time.UTC)))
			// The texts that are headings, questions or model names.
			heads := map[string]bool{"What the figures say": true, "How to read this": true, "How and why this comparison was done": true, "References": true, noticeTitle: true}
			// The group titles.
			for _, g := range p.Groups {
				// One title.
				heads[g.Title] = true
				// Every model name.
				for _, r := range g.Rows {
					// One name.
					heads[r.Cells[0]] = true
				} // end of the row loop
			} // end of the group loop
			// The questions.
			for _, h := range p.How {
				// One question.
				heads[h.Question] = true
			} // end of the question loop
			// The last line of each page.
			for i, page := range bodies {
				// An empty page is not expected.
				if len(page) == 0 {
					// Report it.
					t.Errorf("extra %d pad "+string(rune(48+pad))+": page %d is empty", extra, i+1)
					// Next.
					continue
				} // end of the empty check
				// The last line.
				if last := page[len(page)-1].Text; heads[last] {
					// Report it.
					t.Errorf("extra %d pad "+string(rune(48+pad))+": page %d ends with the heading %q", extra, i+1, last)
				} // end of the check
			} // end of the page loop
		} // end of the padding loop
	} // end of the loop
} // end of TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage

// TestDownloadsAreAlsoSavedAsCopies checks that the folder of the results receives a copy of each download, that the copy equals the download, and that it is readable only by its owner.
func TestDownloadsAreAlsoSavedAsCopies(t *testing.T) {
	// A folder for the copy.
	dir := t.TempDir()
	// The copy.
	p, err := saveCopy(filepath.Join(dir, "performanceCompare"), "a.csv", []byte("x,y\n"))
	// It must work, creating the folder.
	if err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the error check
	// Read it back.
	b, err := os.ReadFile(p)
	// The same bytes.
	if err != nil || string(b) != "x,y\n" {
		// Report it.
		t.Fatalf("copy %q err %v", b, err)
	} // end of the read check
	// Only the owner may read it.
	if st, _ := os.Stat(p); modesApply() && st.Mode().Perm() != 0o600 {
		// Report it.
		t.Errorf("mode %v", st.Mode().Perm())
	} // end of the mode check
	// A store without a file has no folder, so nothing is written.
	if got := savedCopyFolder(openPerfStore("", "memory only")); got != "" {
		// Report it.
		t.Errorf("folder %q for a memory-only store", got)
	} // end of the memory check
	// A store with a file uses the folder of that file.
	if got := savedCopyFolder(openPerfStore(filepath.Join(dir, "performanceCompare", "performance.json"), "")); got != filepath.Join(dir, "performanceCompare") {
		// Report it.
		t.Errorf("folder %q", got)
	} // end of the folder check
} // end of TestDownloadsAreAlsoSavedAsCopies

// TestDownloadFallsBackToTheBrowserWithoutAFolder checks that when the results are kept only in memory (no folder to write to), the file is still handed to the browser, so nothing is lost.
func TestDownloadFallsBackToTheBrowserWithoutAFolder(t *testing.T) {
	// A fake Ollama.
	f := newPerfFake()
	// Its address, parsed the way the program does.
	addr, err := resolve(f.start(t), "")
	// A bad address means the test itself is wrong.
	if err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the address check
	// A path below a plain file cannot be opened, so the store stays in memory.
	blocker := filepath.Join(t.TempDir(), "plain-file")
	// Make the plain file.
	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the write check
	// The store.
	store := openPerfStore(filepath.Join(blocker, "sub", "performance.json"), "")
	// It must have no folder.
	if path, _ := store.where(); path != "" {
		// Stop the test.
		t.Fatalf("store path %q, want memory only", path)
	} // end of the memory check
	// One saved run of the current prompt version.
	run := okRun("a:4b", 300)
	// The prompt version the page filters on.
	run.PromptVersion = perfPromptVersion
	// Keep it.
	store.add(run)
	// The handlers.
	pdf, _ := compareDownloadHandlers(addr, "0123456789abcdef0123456789abcdef", store)
	// A request as the page's own form would send it.
	req := httptest.NewRequest(http.MethodPost, "/compare/pdf", strings.NewReader("token=0123456789abcdef0123456789abcdef"))
	// The form type.
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	// From this page.
	req.Header.Set("Sec-Fetch-Site", "same-origin")
	// The recorder.
	rec := httptest.NewRecorder()
	// Serve.
	pdf(rec, req)
	// The file is sent to the browser.
	if rec.Code != http.StatusOK || rec.Header().Get("Content-Type") != "application/pdf" || !strings.HasPrefix(rec.Header().Get("Content-Disposition"), "attachment; filename=") {
		// Report it.
		t.Fatalf("fallback: %d %v", rec.Code, rec.Header())
	} // end of the fallback check
	// It is a valid PDF.
	pdfCheck(t, rec.Body.Bytes())
} // end of TestDownloadFallsBackToTheBrowserWithoutAFolder
