#!/usr/bin/env bash
# Script 69e: the PDF and CSV buttons now write the file straight into the performanceCompare folder (no browser Save-as choice) and show a Saved page with the exact folder and file name; if the folder cannot be written, the file is sent to the browser instead.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/compare-groups" ] || { echo "FAIL  not on feature/compare-groups"; exit 1; }
# Script 69d must be applied already.
grep -q "oldHistoryFolderName" perfstore.go || { echo "FAIL  script 69d was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e web/compare-saved.html ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/compare.go b/compare.go
index 3ca5987..b1e407d 100644
--- a/compare.go
+++ b/compare.go
@@ -430,7 +430,7 @@ func gatherCompare(r *http.Request, addr ollamaAddress, store *perfStore) compar
 	// A file, or the reason there is none.
 	if path != "" {
 		// Say where.
-		data.SaveNote = "The figures come from " + path + ". Each PDF or CSV you download is also saved as a copy in the folder " + filepath.Dir(path) + "."
+		data.SaveNote = "The figures come from " + path + ". Each PDF or CSV you save here is written by the program into the folder " + filepath.Dir(path) + "; the browser asks for no place."
 	} else {
 		// The reason.
 		data.SaveNote = note
diff --git a/compare_test.go b/compare_test.go
index 23e240b..2cc41d7 100644
--- a/compare_test.go
+++ b/compare_test.go
@@ -735,7 +735,7 @@ func TestCompareRoute(t *testing.T) {
 	// The text as a person reads it.
 	body := html.UnescapeString(raw)
 	// The parts of the page.
-	for _, w := range []string{"Compare models", "Important notice.", noticeShort, "Read the full notice", `action="/compare/pdf"`, `action="/compare/csv"`, "Download this comparison (PDF)", "Download the data (CSV)", "What the figures say", "Chat · Small (1B to under 5B)", "Embedding models", "Why this group:", "chat:1b", "embed:1b", ">Fair to rank?<", ">Characters per second<", "How to read this", "How and why this comparison was done", "References", noticeTitle, "Back to the monitor", referencesChecked} {
+	for _, w := range []string{"Compare models", "Important notice.", noticeShort, "Read the full notice", `action="/compare/pdf"`, `action="/compare/csv"`, "Save this comparison as PDF", "Save the data as CSV", "What the figures say", "Chat · Small (1B to under 5B)", "Embedding models", "Why this group:", "chat:1b", "embed:1b", ">Fair to rank?<", ">Characters per second<", "How to read this", "How and why this comparison was done", "References", noticeTitle, "Back to the monitor", referencesChecked} {
 		// Look for it.
 		if !strings.Contains(body, w) {
 			// Report the gap.
diff --git a/compreport.go b/compreport.go
index 262d4df..f934d8c 100644
--- a/compreport.go
+++ b/compreport.go
@@ -2,12 +2,16 @@
 package main
 
 import ( // import lists the standard-library packages this file uses.
-	// bytes builds the CSV in memory.
+	// bytes builds the CSV and the "saved" page in memory.
 	"bytes"
+	// embed lets the "saved" page template be stored inside the executable.
+	_ "embed"
 	// encoding/csv writes correctly quoted CSV.
 	"encoding/csv"
 	// fmt formats numbers.
 	"fmt"
+	// html/template builds the "saved" page and escapes every value.
+	"html/template"
 	// log records that a copy was saved, or why it was not.
 	"log"
 	// net/http serves the downloads.
@@ -288,6 +292,29 @@ func csvEmbedTime(r perfRun) string {
 	return csvNum(r.WarmTotalSec, 3)
 } // end of csvEmbedTime
 
+// savedTemplateText is the page shown after a file was written into the results folder, stored inside the executable at build time.
+//
+//go:embed web/compare-saved.html
+var savedTemplateText string
+
+// savedPage is the data of that page.
+type savedPage struct {
+	// Theme and Size carry the person's display choices.
+	Theme, Size string
+	// Token is the page token for the way back.
+	Token string
+	// Kind is "PDF" or "CSV".
+	Kind string
+	// Folder is the folder the file was written to.
+	Folder string
+	// Name is the file name.
+	Name string
+	// Bytes is the size of the file.
+	Bytes int
+	// NoticeShort is the short notice.
+	NoticeShort string
+} // end of savedPage
+
 // savedCopyFolder is the folder where copies of the downloads are kept: the folder that holds the saved results (performanceCompare next to the project); empty when the results are kept only in memory.
 func savedCopyFolder(store *perfStore) string {
 	// Where the results live.
@@ -321,6 +348,8 @@ func saveCopy(dir, name string, body []byte) (string, error) {
 
 // compareDownloadHandlers return the handlers of the two downloads; both run the same checks as the page and only read the saved figures.
 func compareDownloadHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc) {
+	// The "saved" page, read once.
+	savedTpl := template.Must(template.New("saved").Parse(savedTemplateText))
 	// serve builds one download: the render function turns the page data into the file bytes.
 	serve := func(contentType, extension string, render func(comparePage, time.Time) []byte) http.HandlerFunc {
 		// The handler.
@@ -343,21 +372,44 @@ func compareDownloadHandlers(addr ollamaAddress, token string, store *perfStore)
 			now := time.Now().UTC()
 			// The file.
 			body := render(data, now)
-			// The type.
-			w.Header().Set("Content-Type", contentType)
-			// Ask the browser to save it, under a name that carries the time.
-			w.Header().Set("Content-Disposition", `attachment; filename="OllamaControlCenter-comparison-`+now.Format("20060102-150405Z0700")+`.`+extension+`"`)
-			// Keep a copy next to the saved results; a failure is only logged, because the download itself must still work.
+			// The name carries the time to the second.
+			name := "OllamaControlCenter-comparison-" + now.Format("20060102-150405Z0700") + "." + extension
+			// The file is written by the program into the results folder, so the person never has to choose a place.
 			if dir := savedCopyFolder(store); dir != "" {
 				// Write it.
-				if p, err := saveCopy(dir, "OllamaControlCenter-comparison-"+now.Format("20060102-150405Z0700")+"."+extension, body); err != nil {
-					// Say why there is no copy.
-					log.Printf("could not save a copy of the download: %v", err)
+				p, err := saveCopy(dir, name, body)
+				// A failure is logged and the file is then sent to the browser instead, so nothing is lost.
+				if err != nil {
+					// Say why.
+					log.Printf("could not save the download in the results folder, sending it to the browser instead: %v", err)
 				} else {
 					// Say where it is.
-					log.Printf("saved a copy of the download in %s", p)
+					log.Printf("saved %s", p)
+					// Show the "saved" page.
+					var buf bytes.Buffer
+					// Fill it.
+					err := savedTpl.Execute(&buf, savedPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Kind: strings.ToUpper(extension), Folder: dir, Name: name, Bytes: len(body), NoticeShort: noticeShort})
+					// A template error is a bug.
+					if err != nil {
+						// Log and send a plain error; the file is saved all the same.
+						log.Printf("saved page error: %v", err)
+						// Plain 500.
+						http.Error(w, "the file was saved, but the page could not be built", http.StatusInternalServerError)
+						// Stop here.
+						return
+					} // end of the template check
+					// An HTML page.
+					w.Header().Set("Content-Type", "text/html; charset=utf-8")
+					// Send it.
+					w.Write(buf.Bytes())
+					// Done.
+					return
 				} // end of the save check
 			} // end of the folder check
+			// The fallback: no folder, or it could not be written. The type.
+			w.Header().Set("Content-Type", contentType)
+			// Ask the browser to save it, under the same name.
+			w.Header().Set("Content-Disposition", `attachment; filename="`+name+`"`)
 			// Send it.
 			w.Write(body)
 		} // end of the handler
diff --git a/compreport_test.go b/compreport_test.go
index 277f3c7..e3998b5 100644
--- a/compreport_test.go
+++ b/compreport_test.go
@@ -6,6 +6,8 @@ import ( // import lists the standard-library packages this file uses.
 	"bytes"
 	// encoding/csv parses the CSV the program wrote.
 	"encoding/csv"
+	// net/http/httptest records the handler's answer.
+	"net/http/httptest"
 	// net/http gives the status codes.
 	"net/http"
 	// net/url builds the form values.
@@ -251,6 +253,45 @@ func TestCSVSafe(t *testing.T) {
 	} // end of the loop
 } // end of TestCSVSafe
 
+// savedFileOf reads the "saved" page a PDF or CSV request returns, checks that it names the results folder, and returns the bytes of the file the program wrote there.
+func savedFileOf(t *testing.T, res *http.Response, folder, ext string) []byte {
+	// Mark this as a helper.
+	t.Helper()
+	// The page.
+	page := bodyOf(res)
+	// A normal HTML page, not a file for the browser.
+	if res.StatusCode != http.StatusOK || !strings.HasPrefix(res.Header.Get("Content-Type"), "text/html") || res.Header.Get("Content-Disposition") != "" {
+		// Stop the test.
+		t.Fatalf("%s: status %d, type %q, disposition %q", ext, res.StatusCode, res.Header.Get("Content-Type"), res.Header.Get("Content-Disposition"))
+	} // end of the page check
+	// The folder and the name as the page shows them.
+	m := regexp.MustCompile(`<code class="savedpath">([^<]*)</code>.*<code class="savedname">(OllamaControlCenter-comparison-\d{8}-\d{6}Z\.` + ext + `)</code>`).FindStringSubmatch(strings.ReplaceAll(page, "\n", " "))
+	// Both must be there.
+	if m == nil {
+		// Stop the test.
+		t.Fatalf("%s: the saved page names no folder and file: %.300s", ext, page)
+	} // end of the match check
+	// The folder is the results folder.
+	if m[1] != folder {
+		// Report it.
+		t.Errorf("%s: saved in %q, want %q", ext, m[1], folder)
+	} // end of the folder check
+	// Read what the program wrote.
+	b, err := os.ReadFile(filepath.Join(m[1], m[2]))
+	// It must exist.
+	if err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the read check
+	// The notice travels with the page too.
+	if !strings.Contains(page, noticeShort) || !strings.Contains(page, `action="/compare"`) {
+		// Report it.
+		t.Errorf("%s: the saved page lacks the notice or the way back", ext)
+	} // end of the notice check
+	// The bytes.
+	return b
+} // end of savedFileOf
+
 // TestCompareDownloadRoutes checks both downloads through the real handler: the files, the headers, the form rules and the empty case.
 func TestCompareDownloadRoutes(t *testing.T) {
 	// A fake Ollama and a rig.
@@ -271,20 +312,12 @@ func TestCompareDownloadRoutes(t *testing.T) {
 	perfPost(t, rig, "/performance/run", "chat:1b")
 	// The embedding model.
 	perfPost(t, rig, "/performance/run", "embed:1b")
-	// The PDF.
+	// The PDF is written into the results folder by the program.
 	res := post(t, rig.h, "/compare/pdf", url.Values{"token": {rig.token}}, fromThisPage)
-	// The status and the headers.
-	if res.StatusCode != http.StatusOK || res.Header.Get("Content-Type") != "application/pdf" || res.Header.Get("X-Content-Type-Options") != "nosniff" || res.Header.Get("Cache-Control") != "no-store" {
-		// Stop the test.
-		t.Fatalf("pdf: %d %v", res.StatusCode, res.Header)
-	} // end of the pdf header check
-	// The file name carries the time.
-	if cd := res.Header.Get("Content-Disposition"); !regexp.MustCompile(`^attachment; filename="OllamaControlCenter-comparison-\d{8}-\d{6}Z\.pdf"$`).MatchString(cd) {
-		// Report it.
-		t.Errorf("content disposition %q", cd)
-	} // end of the name check
+	// The saved file.
+	pdfBytes := savedFileOf(t, res, filepath.Dir(histFile), "pdf")
 	// The file is valid and carries the notice and the real model names.
-	bodies, _ := pdfCheck(t, []byte(bodyOf(res)))
+	bodies, _ := pdfCheck(t, pdfBytes)
 	// The text.
 	text := flat(bodies)
 	// The checks.
@@ -300,17 +333,14 @@ func TestCompareDownloadRoutes(t *testing.T) {
 		// Report it.
 		t.Errorf("character speed or secret text: %.200s", text)
 	} // end of the characters check
-	// The CSV.
+	// The CSV is written into the results folder by the program.
 	res = post(t, rig.h, "/compare/csv", url.Values{"token": {rig.token}}, fromThisPage)
-	// The status and the headers.
-	if res.StatusCode != http.StatusOK || res.Header.Get("Content-Type") != "text/csv; charset=utf-8" || !regexp.MustCompile(`filename="OllamaControlCenter-comparison-\d{8}-\d{6}Z\.csv"`).MatchString(res.Header.Get("Content-Disposition")) {
-		// Stop the test.
-		t.Fatalf("csv: %d %v", res.StatusCode, res.Header)
-	} // end of the csv header check
+	// The saved file.
+	csvBytes := savedFileOf(t, res, filepath.Dir(histFile), "csv")
 	// It parses and starts with the notice.
 	recs, err := func() ([][]string, error) {
 		// The body without the mark.
-		b := bytes.TrimPrefix([]byte(bodyOf(res)), []byte("\xef\xbb\xbf"))
+		b := bytes.TrimPrefix(csvBytes, []byte("\xef\xbb\xbf"))
 		// Parse.
 		r := csv.NewReader(bytes.NewReader(b))
 		// Different widths are fine.
@@ -471,3 +501,55 @@ func TestDownloadsAreAlsoSavedAsCopies(t *testing.T) {
 		t.Errorf("folder %q", got)
 	} // end of the folder check
 } // end of TestDownloadsAreAlsoSavedAsCopies
+
+// TestDownloadFallsBackToTheBrowserWithoutAFolder checks that when the results are kept only in memory (no folder to write to), the file is still handed to the browser, so nothing is lost.
+func TestDownloadFallsBackToTheBrowserWithoutAFolder(t *testing.T) {
+	// A fake Ollama.
+	f := newPerfFake()
+	// Its address, parsed the way the program does.
+	addr, err := resolve(f.start(t), "")
+	// A bad address means the test itself is wrong.
+	if err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the address check
+	// A path below a plain file cannot be opened, so the store stays in memory.
+	blocker := filepath.Join(t.TempDir(), "plain-file")
+	// Make the plain file.
+	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the write check
+	// The store.
+	store := openPerfStore(filepath.Join(blocker, "sub", "performance.json"), "")
+	// It must have no folder.
+	if path, _ := store.where(); path != "" {
+		// Stop the test.
+		t.Fatalf("store path %q, want memory only", path)
+	} // end of the memory check
+	// One saved run of the current prompt version.
+	run := okRun("a:4b", 300)
+	// The prompt version the page filters on.
+	run.PromptVersion = perfPromptVersion
+	// Keep it.
+	store.add(run)
+	// The handlers.
+	pdf, _ := compareDownloadHandlers(addr, "0123456789abcdef0123456789abcdef", store)
+	// A request as the page's own form would send it.
+	req := httptest.NewRequest(http.MethodPost, "/compare/pdf", strings.NewReader("token=0123456789abcdef0123456789abcdef"))
+	// The form type.
+	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
+	// From this page.
+	req.Header.Set("Sec-Fetch-Site", "same-origin")
+	// The recorder.
+	rec := httptest.NewRecorder()
+	// Serve.
+	pdf(rec, req)
+	// The file is sent to the browser.
+	if rec.Code != http.StatusOK || rec.Header().Get("Content-Type") != "application/pdf" || !strings.HasPrefix(rec.Header().Get("Content-Disposition"), "attachment; filename=") {
+		// Report it.
+		t.Fatalf("fallback: %d %v", rec.Code, rec.Header())
+	} // end of the fallback check
+	// It is a valid PDF.
+	pdfCheck(t, rec.Body.Bytes())
+} // end of TestDownloadFallsBackToTheBrowserWithoutAFolder
diff --git a/web/compare-saved.html b/web/compare-saved.html
new file mode 100644
index 0000000..930a009
--- /dev/null
+++ b/web/compare-saved.html
@@ -0,0 +1,37 @@
+{{/* Page shown after a PDF or CSV of the comparison was written into the results folder. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Comparison saved - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* A panel that holds the message. */}}
+<section class="panel">
+{{/* The page heading. */}}
+<h1>Comparison saved</h1>
+{{/* What was saved and where; the program wrote the file itself, so the browser asks nothing. */}}
+<p>The {{.Kind}} file was saved on the computer that runs the monitor, in this folder:</p>
+{{/* The folder, shown on its own line. */}}
+<p><code class="savedpath">{{.Folder}}</code></p>
+{{/* The file name and size. */}}
+<p>File name: <code class="savedname">{{.Name}}</code> ({{.Bytes}} bytes)</p>
+{{/* The notice travels with every output. */}}
+<div class="cmpnotice" role="note"><strong>Important notice.</strong> {{.NoticeShort}}</div>
+{{/* The way back: the comparison page is opened with a small form, like everywhere else. */}}
+<form method="post" action="/compare"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Back to the comparison</button></form>
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/web/compare.html b/web/compare.html
index 479a5f8..a6a3bd3 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -26,10 +26,10 @@
 <p>No model has been through a performance test yet. Use the chart icon before a model name on the monitor page to test one, then come back here.</p>
 {{range .Notes}}<p class="muted">{{.}}</p>{{end}}
 {{else}}
-{{/* The two downloads and the jump to the method; each download is a small form that changes nothing. */}}
+{{/* The two saves and the jump to the method; each is a small form, and the program writes the file into the results folder itself. */}}
 <div class="cmpactions">
-<form method="post" action="/compare/pdf"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Download this comparison (PDF)</button></form>
-<form method="post" action="/compare/csv"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Download the data (CSV)</button></form>
+<form method="post" action="/compare/pdf"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Save this comparison as PDF</button></form>
+<form method="post" action="/compare/csv"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Save the data as CSV</button></form>
 <a class="btn-plain" href="#how">How and why this was done</a>
 </div>
 {{/* What the figures say, in plain words. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
1f2d72379ae3c11037cd7da2e489d3e1162726da87c233fa0f547097b5742da9  compare.go
5af87ecb00871ec4bfe49059e160fb10968737bf2a193ddb3f00c7e6e038517b  compare_test.go
93ef7a3bef2e8868643c2c7b5a9b4607184c337e92e7b66f4a14c94cc36f4d14  compreport.go
9b999e9cbe6204dee3f7c2ed27e4c4a096c32cc23e98fafc0605391ddc101461  compreport_test.go
e0ecaa1205f62342bea9ff8ec9324afd260db605eca4dec383e0fcab46a4fce0  web/compare.html
9182e6c8ab437d36f4b6cb9f4f9411d5d7e52ddba8af9910b4778b7c99d827b6  web/compare-saved.html
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
# List the changed files; nothing is committed yet.
git status --short
