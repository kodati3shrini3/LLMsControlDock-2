// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes searches the file bytes.
	"bytes"
	// fmt builds expected texts.
	"fmt"
	// regexp reads the drawing instructions back.
	"regexp"
	// strconv reads the numbers back.
	"strconv"
	// strings joins and cleans text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time gives a fixed time for the file.
	"time"
) // end of imports

// pdfTextLine is one drawn line of text read back from a page: where it sits and what it says.
type pdfTextLine struct {
	// Y is the height of the line on the page.
	Y float64
	// Text is the line with the escapes undone.
	Text string
} // end of pdfTextLine

// pdfLineRe finds one drawing instruction of text and captures the height and the string.
var pdfLineRe = regexp.MustCompile(`(?m)^BT /F[12] [0-9.]+ Tf [0-9.]+ ([0-9.]+) Td \((.*)\) Tj ET$`)

// pdfUnescape undoes the escapes of a PDF literal string.
func pdfUnescape(s string) string {
	// The result.
	var b strings.Builder
	// Walk the characters.
	for i := 0; i < len(s); i++ {
		// Not an escape.
		if s[i] != '\\' {
			// Copy it.
			b.WriteByte(s[i])
			// Next.
			continue
		} // end of the plain check
		// An escape needs a next character.
		if i+1 >= len(s) {
			// Stop.
			break
		} // end of the end check
		// An octal escape has three digits.
		if s[i+1] >= '0' && s[i+1] <= '7' && i+4 <= len(s) {
			// Read the code.
			n, err := strconv.ParseUint(s[i+1:i+4], 8, 8)
			// A good code.
			if err == nil {
				// The same code as a Latin-1 character, which is what the tests use.
				b.WriteRune(rune(pdfLatin(byte(n))))
				// Skip the digits.
				i += 3
				// Next.
				continue
			} // end of the code check
		} // end of the octal check
		// A plain escaped character.
		b.WriteByte(s[i+1])
		// Skip it.
		i++
	} // end of the loop
	// The text.
	return b.String()
} // end of pdfUnescape

// pdfLatin turns a WinAnsi code back into the character it stands for.
func pdfLatin(c byte) rune {
	// The extra characters.
	for r, b := range pdfWinAnsi {
		// A match.
		if b == c {
			// The character.
			return r
		} // end of the match check
	} // end of the loop
	// Everything else is the same as Latin-1.
	return rune(c)
} // end of pdfLatin

// pdfCheck validates the structure of a file made by pdfDoc and returns the lines of every page (body and footer apart).
func pdfCheck(t *testing.T, data []byte) (bodies [][]pdfTextLine, footers [][]pdfTextLine) {
	// Mark this as a helper.
	t.Helper()
	// The header and the end.
	if !bytes.HasPrefix(data, []byte("%PDF-1.4\n")) || !bytes.HasSuffix(data, []byte("%%EOF\n")) {
		// Stop the test.
		t.Fatalf("header or end marker wrong")
	} // end of the marker check
	// Where the cross-reference table starts.
	i := bytes.LastIndex(data, []byte("startxref\n"))
	// It must exist.
	if i < 0 {
		// Stop the test.
		t.Fatalf("no startxref")
	} // end of the startxref check
	// The number after it.
	var xref int
	// Read it.
	if _, err := fmt.Sscanf(string(data[i+len("startxref\n"):]), "%d", &xref); err != nil {
		// Stop the test.
		t.Fatalf("startxref number: %v", err)
	} // end of the read check
	// The table starts there.
	if !bytes.HasPrefix(data[xref:], []byte("xref\n0 ")) {
		// Stop the test.
		t.Fatalf("startxref does not point at the table")
	} // end of the table check
	// The number of entries.
	var count int
	// Read it.
	fmt.Sscanf(string(data[xref+len("xref\n0 "):]), "%d", &count)
	// The first entry starts after the line "0 N\n".
	line := bytes.IndexByte(data[xref+5:], '\n') + xref + 5 + 1
	// Entry 0 is the free entry, exactly 20 bytes.
	if string(data[line:line+20]) != "0000000000 65535 f \n" {
		// Stop the test.
		t.Fatalf("free entry wrong: %q", data[line:line+20])
	} // end of the free entry check
	// Every other entry points at its object.
	for n := 1; n < count; n++ {
		// The entry.
		e := data[line+20*n : line+20*n+20]
		// It must have the fixed shape.
		if len(e) != 20 || e[10] != ' ' || e[16] != ' ' || e[17] != 'n' || e[19] != '\n' {
			// Stop the test.
			t.Fatalf("entry %d has the wrong shape: %q", n, e)
		} // end of the shape check
		// The offset.
		off, err := strconv.Atoi(string(e[:10]))
		// A number.
		if err != nil {
			// Stop the test.
			t.Fatalf("entry %d offset: %v", n, err)
		} // end of the number check
		// The object must start there.
		if !bytes.HasPrefix(data[off:], []byte(fmt.Sprintf("%d 0 obj\n", n))) {
			// Stop the test.
			t.Fatalf("object %d is not at offset %d", n, off)
		} // end of the object check
	} // end of the entry loop
	// The trailer's size.
	if !bytes.Contains(data[xref:], []byte(fmt.Sprintf("/Size %d /Root 1 0 R /Info 5 0 R", count))) {
		// Stop the test.
		t.Fatalf("trailer size wrong")
	} // end of the trailer check
	// The page count in the page tree equals the number of page objects.
	pages := bytes.Count(data, []byte("/Type /Page /Parent"))
	// The declared count.
	if !bytes.Contains(data, []byte(fmt.Sprintf("/Count %d >>", pages))) || pages == 0 {
		// Stop the test.
		t.Fatalf("page count %d does not match /Count", pages)
	} // end of the count check
	// Every object is one of the 5 fixed ones plus a page and a content object for each page.
	if count != 1+5+2*pages {
		// Stop the test.
		t.Fatalf("%d entries for %d pages", count, pages)
	} // end of the object count check
	// Every content stream: its declared length equals its real length, and its lines are read back.
	re := regexp.MustCompile(`(?s)<< /Length (\d+) >>\nstream\n(.*?)endstream`)
	// Go through the streams in order.
	for _, m := range re.FindAllSubmatch(data, -1) {
		// The declared length.
		n, _ := strconv.Atoi(string(m[1]))
		// It must match.
		if n != len(m[2]) {
			// Stop the test.
			t.Fatalf("stream length %d, declared %d", len(m[2]), n)
		} // end of the length check
		// Only ASCII is written.
		for _, c := range m[2] {
			// A high or odd byte.
			if c > 126 || (c < 32 && c != '\n') {
				// Stop the test.
				t.Fatalf("stream holds byte %d", c)
			} // end of the byte check
		} // end of the byte loop
		// The lines of this page.
		var body, foot []pdfTextLine
		// Each drawn line.
		for _, l := range pdfLineRe.FindAllSubmatch(m[2], -1) {
			// The height.
			y, _ := strconv.ParseFloat(string(l[1]), 64)
			// The line.
			pl := pdfTextLine{Y: y, Text: pdfUnescape(string(l[2]))}
			// The footer is below the body area.
			if y < pdfBottom-8 {
				// Keep it apart.
				foot = append(foot, pl)
			} else {
				// A body line.
				body = append(body, pl)
			} // end of the area check
		} // end of the line loop
		// Keep both.
		bodies, footers = append(bodies, body), append(footers, foot)
	} // end of the stream loop
	// One stream per page.
	if len(bodies) != pages {
		// Stop the test.
		t.Fatalf("%d streams for %d pages", len(bodies), pages)
	} // end of the stream count check
	// The pages.
	return bodies, footers
} // end of pdfCheck

// flat joins the lines of pages into one text with single spaces.
func flat(pages [][]pdfTextLine) string {
	// The parts.
	var parts []string
	// Each page.
	for _, p := range pages {
		// Each line.
		for _, l := range p {
			// One line.
			parts = append(parts, l.Text)
		} // end of the line loop
	} // end of the page loop
	// One text.
	return strings.Join(strings.Fields(strings.Join(parts, " ")), " ")
} // end of flat

// TestPDFEscapeAndEncoding checks the escapes and the character mapping.
func TestPDFEscapeAndEncoding(t *testing.T) {
	// The cases.
	for in, want := range map[string]string{
		// Brackets and the backslash are escaped.
		"a(b)c\\d": `a\(b\)c\\d`,
		// Latin-1 and WinAnsi characters become octal escapes.
		"±·×": `\261\267\327`,
		// The en dash and the typographic quotes.
		"–“”’": `\226\223\224\222`,
		// A tab is a space; a letter with an accent is Latin-1.
		"a\tb": "a b", "Loïc": `Lo\357c`,
		// A character the font cannot draw becomes a question mark.
		"✓⚠": "??",
	} {
		// Escape it.
		if got := pdfEscape(in); got != want {
			// Report it.
			t.Errorf("pdfEscape(%q) = %q, want %q", in, got, want)
		} // end of the check
	} // end of the loop
	// Reading it back gives the original for everything the font can draw.
	for _, s := range []string{"(termgate.com)", "1.5× slower", "Chat · Small", "Loïc", "a\\b"} {
		// Round trip.
		if got := pdfUnescape(pdfEscape(s)); got != s {
			// Report it.
			t.Errorf("round trip %q gave %q", s, got)
		} // end of the check
	} // end of the loop
} // end of TestPDFEscapeAndEncoding

// TestPDFWidthsMatchTheFontMetrics checks the width tables against well-known Helvetica values.
func TestPDFWidthsMatchTheFontMetrics(t *testing.T) {
	// The cases: text, bold, and the width of one character in 1/1000.
	for _, c := range []struct {
		// The character.
		s string
		// Bold or not.
		bold bool
		// The width.
		want float64
	}{
		// Regular letters, a space and a digit.
		{"A", false, 667}, {" ", false, 278}, {"i", false, 222}, {"0", false, 556}, {"W", false, 944},
		// Bold letters.
		{"A", true, 722}, {"i", true, 278}, {"W", true, 944},
		// Signs.
		{"±", false, 584}, {"·", false, 278}, {"×", false, 584},
	} {
		// Measured at size 1000, so the result is the table value.
		if got := pdfWidth(c.s, 1000, c.bold); got != c.want {
			// Report it.
			t.Errorf("width of %q (bold %v) = %v, want %v", c.s, c.bold, got, c.want)
		} // end of the check
	} // end of the loop
	// The tables have one entry for every code from 32 to 255.
	if len(helveticaWidths) != 224 || len(helveticaBoldWidths) != 224 {
		// Report it.
		t.Errorf("table sizes %d, %d", len(helveticaWidths), len(helveticaBoldWidths))
	} // end of the size check
	// The size scales the width.
	if got := pdfWidth("AA", 10, false); got != 13.34 {
		// Report it.
		t.Errorf("AA at 10 = %v", got)
	} // end of the scale check
} // end of TestPDFWidthsMatchTheFontMetrics

// TestPDFWrapKeepsEveryWordWithinTheWidth checks the line breaking, including a long address.
func TestPDFWrapKeepsEveryWordWithinTheWidth(t *testing.T) {
	// A text with a long unbreakable address in it.
	text := "See https://example.org/" + strings.Repeat("abcdefghij", 20) + " for the full text of the notice and the way it is written."
	// Wrap at 200 points.
	lines := pdfWrap(text, 9, false, 200)
	// Every line fits.
	for _, l := range lines {
		// Too wide.
		if w := pdfWidth(l, 9, false); w > 200.001 {
			// Report it.
			t.Errorf("line %q is %.1f wide", l, w)
		} // end of the check
	} // end of the loop
	// Nothing is lost: all characters are still there, in order.
	if got, want := strings.ReplaceAll(strings.Join(lines, ""), " ", ""), strings.ReplaceAll(text, " ", ""); got != want {
		// Report it.
		t.Errorf("text changed by wrapping")
	} // end of the content check
	// An empty text gives no lines.
	if len(pdfWrap("   ", 9, false, 200)) != 0 {
		// Report it.
		t.Errorf("blank text gave lines")
	} // end of the blank check
	// A width smaller than one letter still ends.
	if got := pdfWrap("abc", 9, false, 1); len(got) != 3 {
		// Report it.
		t.Errorf("tiny width gave %v", got)
	} // end of the tiny check
} // end of TestPDFWrapKeepsEveryWordWithinTheWidth

// TestPDFStructureAndPaging checks a document of many lines: valid structure, several pages, a footer with the notice and the page number on each.
func TestPDFStructureAndPaging(t *testing.T) {
	// A document with a fixed time.
	d := newPDF("Title (with brackets)", "Subject", "Informational only. Notice words.", "Program line", time.Date(2026, 10, 27, 19, 30, 5, 0, time.UTC))
	// A heading and a lot of lines.
	d.text("Heading", 18, true, 0)
	// Many paragraphs.
	for i := 0; i < 150; i++ {
		// One paragraph.
		d.text(fmt.Sprintf("Line number %d of the long document, written to fill the pages.", i), 10, false, 0)
	} // end of the loop
	// A rule.
	d.rule()
	// The file.
	data := d.bytes()
	// Validate it.
	bodies, footers := pdfCheck(t, data)
	// Several pages.
	if len(bodies) < 3 {
		// Stop the test.
		t.Fatalf("%d pages, want at least 3", len(bodies))
	} // end of the page check
	// The footer of every page.
	for i, f := range footers {
		// Its text.
		text := flat([][]pdfTextLine{f})
		// The notice and the page number.
		if !strings.Contains(text, "Informational only. Notice words.") || !strings.Contains(text, fmt.Sprintf("page %d of %d", i+1, len(bodies))) || !strings.Contains(text, "Program line") {
			// Report it.
			t.Errorf("footer of page %d: %q", i+1, text)
		} // end of the check
	} // end of the loop
	// Every line of every body is inside the margins.
	for _, p := range bodies {
		// Each line.
		for _, l := range p {
			// Below the top margin and above the bottom.
			if l.Y < pdfBottom || l.Y > pdfPageH-pdfMargin {
				// Report it.
				t.Errorf("line %q at height %.1f is outside the body area", l.Text, l.Y)
			} // end of the check
		} // end of the line loop
	} // end of the page loop
	// All 150 lines are present, in order.
	all := flat(bodies)
	// Each one.
	last := -1
	// Check the order.
	for i := 0; i < 150; i++ {
		// Find it after the previous one.
		at := strings.Index(all, fmt.Sprintf("Line number %d of the long document", i))
		// Missing or out of order.
		if at < 0 || at <= last {
			// Stop the test.
			t.Fatalf("line %d missing or out of order", i)
		} // end of the check
		// Remember.
		last = at
	} // end of the loop
	// The properties are in the file, with the brackets escaped.
	if !bytes.Contains(data, []byte(`/Title (Title \(with brackets\))`)) || !bytes.Contains(data, []byte("/CreationDate (D:20261027193005Z)")) || !bytes.Contains(data, []byte("/Producer (OllamaControlCenter "+appVersion+")")) {
		// Report it.
		t.Errorf("document information wrong")
	} // end of the information check
	// The same document made twice is identical.
	d2 := newPDF("Title (with brackets)", "Subject", "Informational only. Notice words.", "Program line", time.Date(2026, 10, 27, 19, 30, 5, 0, time.UTC))
	// The same content.
	d2.text("Heading", 18, true, 0)
	// Many paragraphs.
	for i := 0; i < 150; i++ {
		// One paragraph.
		d2.text(fmt.Sprintf("Line number %d of the long document, written to fill the pages.", i), 10, false, 0)
	} // end of the loop
	// A rule.
	d2.rule()
	// Identical.
	if !bytes.Equal(data, d2.bytes()) {
		// Report it.
		t.Errorf("the same document gave different files")
	} // end of the identical check
} // end of TestPDFStructureAndPaging
