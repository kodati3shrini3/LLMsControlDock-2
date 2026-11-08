// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds the CSV and the "saved" page in memory.
	"bytes"
	// embed lets the "saved" page template be stored inside the executable.
	_ "embed"
	// encoding/csv writes correctly quoted CSV.
	"encoding/csv"
	// fmt formats numbers.
	"fmt"
	// html/template builds the "saved" page and escapes every value.
	"html/template"
	// log records that a copy was saved, or why it was not.
	"log"
	// net/http serves the downloads.
	"net/http"
	// os makes the folder and writes the copy.
	"os"
	// path/filepath builds the path of the copy.
	"path/filepath"
	// strings cleans text.
	"strings"
	// time stamps the files.
	"time"
) // end of imports

// pageSymbols are the signs used on the page that the PDF's built-in font cannot draw; the words after them say the same.
var pageSymbols = strings.NewReplacer("✓ ", "", "⚠ ", "")

// footerLine is the line printed under the notice on every page of the PDF.
func footerLine(when time.Time) string {
	// Program, version and time.
	return fmt.Sprintf("LLMsControlDock %s  -  made %s", appVersion, when.UTC().Format("2006-01-02 15:04 UTC"))
} // end of footerLine

// writeNoticeBlock prints the full notice: a line, the heading and every paragraph, kept together at the start.
func writeNoticeBlock(d *pdfDoc, p comparePage) {
	// Keep the line, the heading and the first paragraph together.
	d.keep(80)
	// A line.
	d.rule()
	// Its heading.
	d.text(p.NoticeTitle, 11, true, 0)
	// Each paragraph.
	for _, para := range p.NoticeFull {
		// One paragraph.
		d.text(para, 9, false, 0)
		// A little air.
		d.gap(3)
	} // end of the notice loop
} // end of writeNoticeBlock

// writeComparePDF turns the comparison page into a PDF; the full notice is printed once, at the end, and a short notice is at the foot of every page.
func writeComparePDF(p comparePage, when time.Time) []byte {
	// The document.
	d := newPDF("LLMsControlDock model comparison", p.NoticeShort, p.NoticeShort, footerLine(when), when)
	// The title.
	d.text("Model comparison", 18, true, 0)
	// The origin.
	d.text(fmt.Sprintf("Made by LLMsControlDock %s on %s, from tests saved on this computer.", appVersion, when.UTC().Format("2006-01-02 15:04 UTC")), 9, false, 0)
	// A little air.
	d.gap(6)
	// The full notice is printed once, at the end; the short notice is at the foot of every page, so it is on the first page too.
	d.rule()
	// Nothing saved.
	if p.Empty {
		// Say so.
		d.text("No model has been through a performance test yet.", 10, false, 0)
		// The full notice is still printed, once, at the end.
		d.gap(8)
		// The notice.
		writeNoticeBlock(d, p)
		// The finished file.
		return d.bytes()
	} // end of the empty check
	// The sentences read out of the figures.
	d.gap(4)
	// Keep the heading with its first lines.
	d.keep(60)
	// The heading.
	d.text("What the figures say", 12, true, 0)
	// Each sentence.
	for _, f := range p.Findings {
		// A bullet.
		d.text("- "+pageSymbols.Replace(f), 9, false, 8)
	} // end of the findings loop
	// Every group.
	for _, g := range p.Groups {
		// Air above the group.
		d.gap(8)
		// Keep the heading with the reason under it.
		d.keep(70)
		// Its heading.
		d.text(g.Title, 12, true, 0)
		// Why it exists.
		d.text("Why this group: "+g.Why, 9, false, 0)
		// The fastest model.
		if g.Headline != "" {
			// In bold.
			d.text(g.Headline, 9, true, 0)
		} // end of the headline check
		// The notes.
		for _, n := range g.Notes {
			// One note.
			d.text(n, 9, false, 0)
		} // end of the note loop
		// Every model.
		for _, r := range g.Rows {
			// Air between models.
			d.gap(4)
			// Keep the name with its figures.
			d.keep(60)
			// The name in bold.
			d.text(pageSymbols.Replace(r.Cells[0]), 10, true, 0)
			// The other columns as "heading: value".
			var parts []string
			// Go through the columns after the name.
			for i := 1; i < len(r.Cells) && i < len(g.Cols); i++ {
				// One pair.
				parts = append(parts, g.Cols[i].Title+": "+pageSymbols.Replace(r.Cells[i]))
			} // end of the column loop
			// Written as one wrapped paragraph.
			d.text(strings.Join(parts, "  |  "), 8.5, false, 8)
		} // end of the model loop
	} // end of the group loop
	// The cautions.
	d.gap(8)
	// Keep the heading with its first line.
	d.keep(50)
	// The heading.
	d.text("How to read this", 12, true, 0)
	// Each caution.
	for _, n := range p.Notes {
		// A bullet.
		d.text("- "+n, 9, false, 8)
	} // end of the notes loop
	// The method.
	d.gap(8)
	// Keep the heading with the first question.
	d.keep(70)
	// The heading.
	d.text("How and why this comparison was done", 12, true, 0)
	// Each question.
	for _, h := range p.How {
		// The question.
		d.gap(3)
		// Keep the question with the start of its answer.
		d.keep(48)
		// In bold.
		d.text(h.Question, 9.5, true, 0)
		// The answer.
		d.text(h.Answer, 9, false, 8)
	} // end of the method loop
	// The references.
	d.gap(8)
	// Keep the heading with the first entry.
	d.keep(70)
	// The heading.
	d.text("References", 12, true, 0)
	// Each source.
	for _, r := range p.Refs {
		// Air.
		d.gap(3)
		// Keep an entry together with its first lines.
		d.keep(36)
		// The entry.
		d.text(fmt.Sprintf("[%d] %s. %s. %s. %s  Used here for: %s", r.N, r.Authors, r.Title, r.Where, r.URL, r.Used), 8.5, false, 0)
	} // end of the reference loop
	// When they were read.
	d.gap(3)
	// The sentence.
	d.text("The addresses were opened and read on "+p.RefsChecked+". A web page can change or disappear later.", 8.5, false, 0)
	// The full notice, once, at the end.
	d.gap(8)
	// The notice.
	writeNoticeBlock(d, p)
	// The finished file.
	return d.bytes()
} // end of writeComparePDF

// csvSafe stops a spreadsheet from running a cell as a formula: a cell that starts with one of the formula signs gets a quote in front.
func csvSafe(s string) string {
	// Nothing to guard.
	if s == "" {
		// As it is.
		return s
	} // end of the empty check
	// The signs that start a formula in common spreadsheets.
	switch s[0] {
	// Equals, plus, minus, at sign, tab or carriage return.
	case '=', '+', '-', '@', '\t', '\r':
		// A quote in front makes it plain text.
		return "'" + s
	} // end of the switch
	// As it is.
	return s
} // end of csvSafe

// csvHeader is the header row of the data rows in the CSV, in order.
var csvHeader = []string{"Group", "Model", "Kind", "Parameters", "Quantization", "Tested on (UTC)", "Answer tokens per second", "Answer characters per second", "Embedding time (s)", "Time to first word (s)", "Total time (s)", "Load time (s)", "Memory used (bytes)", "Share on graphics card (%)", "Machine busy", "Rank in group", "Fair to rank", "Reasons"}

// writeCompareCSV writes the comparison as CSV: the short notice first, then the header and one row for each model, then the full notice and the references. The file starts with a UTF-8 mark so spreadsheets read the characters correctly.
func writeCompareCSV(p comparePage, when time.Time) []byte {
	// The file.
	var buf bytes.Buffer
	// The UTF-8 mark.
	buf.WriteString("\xef\xbb\xbf")
	// The writer.
	w := csv.NewWriter(&buf)
	// A first record that carries the notice, so it travels with the data.
	w.Write([]string{"NOTICE", csvSafe(p.NoticeShort)})
	// Where the file comes from.
	w.Write([]string{"MADE BY", "LLMsControlDock " + appVersion + " on " + when.UTC().Format("2006-01-02 15:04 UTC")})
	// The header row.
	w.Write(csvHeader)
	// Every group.
	for _, g := range p.Data {
		// Every model.
		for _, m := range g.Models {
			// The run.
			r := m.Run
			// The kind in words.
			kind := "chat"
			// An embedding model.
			if r.Kind == "embedding" {
				// Its kind.
				kind = "embedding"
			} // end of the kind check
			// The share on the graphics card, empty when unknown.
			gpu := ""
			// Work it out.
			if r.ModelBytes > 0 {
				// A percentage.
				gpu = fmt.Sprintf("%.0f", float64(r.GPUBytes)/float64(r.ModelBytes)*100)
			} // end of the share check
			// The rank, empty when not ranked.
			rank := ""
			// A ranked model.
			if m.Rank > 0 {
				// The place.
				rank = fmt.Sprint(m.Rank)
			} // end of the rank check
			// Fair or not.
			fair := "yes"
			// A model with reasons.
			if len(m.Reasons) > 0 {
				// Not fair.
				fair = "no"
			} // end of the fair check
			// The row; text cells are guarded against formulas.
			w.Write([]string{csvSafe(g.Title), csvSafe(m.Name), kind, csvSafe(m.Params), csvSafe(m.Quant), r.Time.UTC().Format("2006-01-02 15:04 UTC"),
				csvNum(r.AnswerSpeed, 2), csvNum(r.CharSpeed, 2), csvEmbedTime(r), csvNum(r.WarmFirstWordSec, 3), csvNum(r.WarmTotalSec, 3), csvNum(r.ColdLoadSec, 3),
				fmt.Sprint(r.ModelBytes), gpu, fmt.Sprint(r.Busy), rank, fair, csvSafe(strings.Join(m.Reasons, "; "))})
		} // end of the model loop
	} // end of the group loop
	// The full notice after the data.
	for _, para := range p.NoticeFull {
		// One paragraph.
		w.Write([]string{"NOTICE", csvSafe(para)})
	} // end of the notice loop
	// The references.
	for _, r := range p.Refs {
		// One source.
		w.Write([]string{"REFERENCE", fmt.Sprintf("[%d] %s. %s. %s. %s", r.N, r.Authors, r.Title, r.Where, r.URL)})
	} // end of the reference loop
	// Flush what is buffered.
	w.Flush()
	// The file.
	return buf.Bytes()
} // end of writeCompareCSV

// csvNum writes a number with a fixed number of decimals, or nothing when it is zero (not available).
func csvNum(v float64, decimals int) string {
	// Not available.
	if v <= 0 {
		// Empty.
		return ""
	} // end of the check
	// The number.
	return fmt.Sprintf("%.*f", decimals, v)
} // end of csvNum

// csvEmbedTime writes the embedding time for an embedding model and nothing for a chat model.
func csvEmbedTime(r perfRun) string {
	// Only for embedding models.
	if r.Kind != "embedding" {
		// Empty.
		return ""
	} // end of the kind check
	// The time.
	return csvNum(r.WarmTotalSec, 3)
} // end of csvEmbedTime

// savedTemplateText is the page shown after a file was written into the results folder, stored inside the executable at build time.
//
//go:embed web/compare-saved.html
var savedTemplateText string

// savedPage is the data of that page.
type savedPage struct {
	// Theme and Size carry the person's display choices.
	Theme, Size string
	// Token is the page token for the way back.
	Token string
	// Kind is "PDF" or "CSV".
	Kind string
	// Folder is the folder the file was written to.
	Folder string
	// Name is the file name.
	Name string
	// Bytes is the size of the file.
	Bytes int
	// NoticeShort is the short notice.
	NoticeShort string
} // end of savedPage

// savedCopyFolder is the folder where copies of the downloads are kept: the folder that holds the saved results (performanceCompare next to the project); empty when the results are kept only in memory.
func savedCopyFolder(store *perfStore) string {
	// Where the results live.
	path, _ := store.where()
	// Memory only: no folder.
	if path == "" {
		// Nothing to do.
		return ""
	} // end of the memory check
	// The folder of the results file.
	return filepath.Dir(path)
} // end of savedCopyFolder

// saveCopy writes one downloaded file into the folder, readable only by the person who runs the monitor, and returns its path.
func saveCopy(dir, name string, body []byte) (string, error) {
	// Make the folder when it is not there yet.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		// Give up with the reason.
		return "", err
	} // end of the folder check
	// The full path of the file.
	p := filepath.Join(dir, name)
	// Write it (the name carries the time to the second, so it does not clash with an earlier copy).
	if err := os.WriteFile(p, body, 0o600); err != nil {
		// Give up with the reason.
		return "", err
	} // end of the write check
	// Done.
	return p, nil
} // end of saveCopy

// compareDownloadHandlers return the handlers of the two downloads; both run the same checks as the page and only read the saved figures.
func compareDownloadHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc) {
	// The "saved" page, read once.
	savedTpl := template.Must(template.New("saved").Parse(savedTemplateText))
	// serve builds one download: the render function turns the page data into the file bytes.
	serve := func(contentType, extension string, render func(comparePage, time.Time) []byte) http.HandlerFunc {
		// The handler.
		return func(w http.ResponseWriter, r *http.Request) {
			// The shared checks.
			if !compareForm(w, r, token) {
				// A refusal was sent.
				return
			} // end of the checks
			// The figures.
			data := gatherCompare(r, addr, store)
			// Nothing to download.
			if data.Empty {
				// Say so plainly.
				http.Error(w, "no test results are saved yet, so there is nothing to download", http.StatusConflict)
				// Stop here.
				return
			} // end of the empty check
			// The time of the file.
			now := time.Now().UTC()
			// The file.
			body := render(data, now)
			// The name carries the time to the second.
			name := "LLMsControlDock-comparison-" + now.Format("20060102-150405Z0700") + "." + extension
			// The file is written by the program into the results folder, so the person never has to choose a place.
			if dir := savedCopyFolder(store); dir != "" {
				// Write it.
				p, err := saveCopy(dir, name, body)
				// A failure is logged and the file is then sent to the browser instead, so nothing is lost.
				if err != nil {
					// Say why.
					log.Printf("could not save the download in the results folder, sending it to the browser instead: %v", err)
				} else {
					// Say where it is.
					log.Printf("saved %s", p)
					// Show the "saved" page.
					var buf bytes.Buffer
					// Fill it.
					err := savedTpl.Execute(&buf, savedPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Kind: strings.ToUpper(extension), Folder: dir, Name: name, Bytes: len(body), NoticeShort: noticeShort})
					// A template error is a bug.
					if err != nil {
						// Log and send a plain error; the file is saved all the same.
						log.Printf("saved page error: %v", err)
						// Plain 500.
						http.Error(w, "the file was saved, but the page could not be built", http.StatusInternalServerError)
						// Stop here.
						return
					} // end of the template check
					// An HTML page.
					w.Header().Set("Content-Type", "text/html; charset=utf-8")
					// Send it.
					w.Write(buf.Bytes())
					// Done.
					return
				} // end of the save check
			} // end of the folder check
			// The fallback: no folder, or it could not be written. The type.
			w.Header().Set("Content-Type", contentType)
			// Ask the browser to save it, under the same name.
			w.Header().Set("Content-Disposition", `attachment; filename="`+name+`"`)
			// Send it.
			w.Write(body)
		} // end of the handler
	} // end of serve
	// The PDF and the CSV.
	return serve("application/pdf", "pdf", writeComparePDF), serve("text/csv; charset=utf-8", "csv", writeCompareCSV)
} // end of compareDownloadHandlers
