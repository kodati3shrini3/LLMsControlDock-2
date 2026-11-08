// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds the file in memory.
	"bytes"
	// fmt formats numbers and text.
	"fmt"
	// strings splits and joins text.
	"strings"
	// time stamps the file.
	"time"
) // end of imports

// The page is A4 portrait, measured in points (1/72 inch), with the origin at the bottom left.
const (
	// pdfPageW is the page width.
	pdfPageW = 595.28
	// pdfPageH is the page height.
	pdfPageH = 841.89
	// pdfMargin is the space left empty on the left, right and top.
	pdfMargin = 56.0
	// pdfBottom is the lowest line of body text; the footer sits under it.
	pdfBottom = 78.0
	// pdfLeading is the line height as a multiple of the font size.
	pdfLeading = 1.3
) // end of the page constants

// pdfWinAnsi maps the few characters beyond plain ASCII and Latin-1 that this program writes to their code in the WinAnsi encoding of the built-in PDF fonts.
var pdfWinAnsi = map[rune]byte{'€': 0x80, '‚': 0x82, 'ƒ': 0x83, '„': 0x84, '…': 0x85, '†': 0x86, '‡': 0x87, 'ˆ': 0x88, '‰': 0x89, 'Š': 0x8A, '‹': 0x8B, 'Œ': 0x8C, 'Ž': 0x8E, '‘': 0x91, '’': 0x92, '“': 0x93, '”': 0x94, '•': 0x95, '–': 0x96, '—': 0x97, '˜': 0x98, '™': 0x99, 'š': 0x9A, '›': 0x9B, 'œ': 0x9C, 'ž': 0x9E, 'Ÿ': 0x9F}

// pdfByte returns the WinAnsi code of a character; characters that cannot be written become a question mark.
func pdfByte(r rune) byte {
	// A tab is written as a space.
	if r == '\t' {
		// One space.
		return ' '
	} // end of the tab check
	// Plain printable ASCII.
	if r >= 32 && r < 127 {
		// The same code.
		return byte(r)
	} // end of the ASCII check
	// Latin-1 letters and signs share their codes with WinAnsi.
	if r >= 0xA0 && r <= 0xFF {
		// The same code.
		return byte(r)
	} // end of the Latin-1 check
	// The extra characters.
	if b, ok := pdfWinAnsi[r]; ok {
		// Their code.
		return b
	} // end of the extra check
	// Anything else cannot be shown.
	return '?'
} // end of pdfByte

// pdfEscape writes text as the inside of a PDF literal string: brackets and the backslash are escaped, and every code above ASCII is written as an octal escape, so the file stays plain ASCII.
func pdfEscape(s string) string {
	// The result.
	var b strings.Builder
	// Go through the characters.
	for _, r := range s {
		// The code in the font.
		c := pdfByte(r)
		// The three characters that have a meaning inside a string.
		switch {
		// A backslash, an opening or a closing bracket.
		case c == '\\' || c == '(' || c == ')':
			// Escape it.
			b.WriteByte('\\')
			// Then the character itself.
			b.WriteByte(c)
		// Anything outside printable ASCII.
		case c < 32 || c > 126:
			// Three octal digits.
			fmt.Fprintf(&b, "\\%03o", c)
		// Everything else is written as it is.
		default:
			// The character.
			b.WriteByte(c)
		} // end of the switch
	} // end of the loop
	// The text.
	return b.String()
} // end of pdfEscape

// pdfWidth returns the width of a text in points at the given size.
func pdfWidth(s string, size float64, bold bool) float64 {
	// The table of the font.
	table := &helveticaWidths
	// The bold font.
	if bold {
		// Its table.
		table = &helveticaBoldWidths
	} // end of the bold check
	// The sum of the widths in thousandths.
	total := 0
	// Go through the characters.
	for _, r := range s {
		// The code in the font.
		c := int(pdfByte(r))
		// Codes below 32 have no width; use the width of a typical letter.
		w := 556
		// A code with a table entry.
		if c >= 32 && table[c-32] > 0 {
			// Its width.
			w = table[c-32]
		} // end of the entry check
		// Add it.
		total += w
	} // end of the loop
	// Scale to the font size.
	return float64(total) * size / 1000
} // end of pdfWidth

// pdfWrap breaks a text into lines that fit the width; a word longer than a line (such as a web address) is broken where it must be.
func pdfWrap(text string, size float64, bold bool, width float64) []string {
	// The lines.
	var lines []string
	// The line being built.
	cur := ""
	// Go through the words.
	for _, word := range strings.Fields(text) {
		// A word that is too long for any line is cut into pieces.
		for pdfWidth(word, size, bold) > width {
			// Make room: the current line is finished first.
			if cur != "" {
				// Keep it.
				lines = append(lines, cur)
				// Start again.
				cur = ""
			} // end of the flush check
			// Find how many characters fit.
			n := 0
			// Grow until the width is reached.
			for n < len(word) && pdfWidth(word[:n+1], size, bold) <= width {
				// One more fits.
				n++
			} // end of the fit loop
			// At least one character per line, so the loop always ends.
			if n == 0 {
				// Force one.
				n = 1
			} // end of the minimum check
			// Keep the piece.
			lines = append(lines, word[:n])
			// The rest of the word.
			word = word[n:]
		} // end of the long-word loop
		// The candidate line with the word added.
		next := word
		// With a space when the line is not empty.
		if cur != "" {
			// Join them.
			next = cur + " " + word
		} // end of the join check
		// It fits.
		if pdfWidth(next, size, bold) <= width {
			// Keep it.
			cur = next
		} else {
			// Finish the line and start a new one.
			lines = append(lines, cur)
			// The word starts the next line.
			cur = word
		} // end of the fit check
	} // end of the word loop
	// The last line.
	if cur != "" {
		// Keep it.
		lines = append(lines, cur)
	} // end of the last-line check
	// The lines.
	return lines
} // end of pdfWrap

// pdfDoc builds a small text-only PDF using the standard library alone.
type pdfDoc struct {
	// title is the document title stored in the file.
	title string
	// subject is the notice stored in the file's properties.
	subject string
	// footerNotice is printed at the foot of every page.
	footerNotice string
	// footerLine is printed under it, before the page number.
	footerLine string
	// created is the time stamp stored in the file.
	created time.Time
	// pages holds the drawing instructions of each finished page and of the current one.
	pages []*bytes.Buffer
	// y is the height of the next line on the current page.
	y float64
} // end of pdfDoc

// newPDF starts a document with its first page.
func newPDF(title, subject, footerNotice, footerLine string, created time.Time) *pdfDoc {
	// The document.
	d := &pdfDoc{title: title, subject: subject, footerNotice: footerNotice, footerLine: footerLine, created: created.UTC()}
	// The first page.
	d.newPage()
	// Hand it back.
	return d
} // end of newPDF

// newPage starts a new page.
func (d *pdfDoc) newPage() {
	// A fresh list of instructions.
	d.pages = append(d.pages, &bytes.Buffer{})
	// The first line goes under the top margin.
	d.y = pdfPageH - pdfMargin
} // end of newPage

// line draws one line of text at the current height and moves down.
func (d *pdfDoc) line(s string, size float64, bold bool, indent float64) {
	// The step down.
	step := size * pdfLeading
	// Not enough room: a new page.
	if d.y-step < pdfBottom {
		// Start it.
		d.newPage()
	} // end of the room check
	// The font name inside the page.
	font := "F1"
	// The bold font.
	if bold {
		// Its name.
		font = "F2"
	} // end of the bold check
	// Move down to the baseline.
	d.y -= step
	// The drawing instruction: begin text, font and size, position, show, end text.
	fmt.Fprintf(d.pages[len(d.pages)-1], "BT /%s %.1f Tf %.2f %.2f Td (%s) Tj ET\n", font, size, pdfMargin+indent, d.y, pdfEscape(s))
} // end of line

// text writes a paragraph, wrapped to the page width.
func (d *pdfDoc) text(s string, size float64, bold bool, indent float64) {
	// The width available.
	width := pdfPageW - 2*pdfMargin - indent
	// Each paragraph break in the text starts its own paragraph.
	for _, para := range strings.Split(s, "\n") {
		// An empty paragraph is a blank line.
		if strings.TrimSpace(para) == "" {
			// A gap.
			d.gap(size * 0.6)
			// Next.
			continue
		} // end of the blank check
		// The lines of the paragraph.
		for _, l := range pdfWrap(para, size, bold, width) {
			// Draw each.
			d.line(l, size, bold, indent)
		} // end of the line loop
	} // end of the paragraph loop
} // end of text

// keep starts a new page when less than the given height is left, so a heading is never left alone at the foot of a page.
func (d *pdfDoc) keep(points float64) {
	// Not enough room for the heading and the first lines under it.
	if d.y-points < pdfBottom {
		// Start the next page.
		d.newPage()
	} // end of the room check
} // end of keep

// gap leaves some empty space.
func (d *pdfDoc) gap(points float64) {
	// Move down; a page break happens by itself at the next line.
	d.y -= points
} // end of gap

// rule draws a thin line across the page.
func (d *pdfDoc) rule() {
	// Room for the line.
	if d.y-6 < pdfBottom {
		// A new page.
		d.newPage()
	} // end of the room check
	// Move down a little.
	d.y -= 4
	// The drawing instruction: line width, move, line, stroke.
	fmt.Fprintf(d.pages[len(d.pages)-1], "0.5 w %.2f %.2f m %.2f %.2f l S\n", pdfMargin, d.y, pdfPageW-pdfMargin, d.y)
	// Move down a little more.
	d.y -= 4
} // end of rule

// footer draws the notice and the page number at the foot of one page.
func (d *pdfDoc) footer(page *bytes.Buffer, n, total int) {
	// The line above the footer.
	fmt.Fprintf(page, "0.5 w %.2f 64 m %.2f 64 l S\n", pdfMargin, pdfPageW-pdfMargin)
	// The notice, wrapped; at most three lines fit.
	y := 54.0
	// Go through its lines.
	for _, l := range pdfWrap(d.footerNotice, 7, false, pdfPageW-2*pdfMargin) {
		// One line.
		fmt.Fprintf(page, "BT /F1 7 Tf %.2f %.2f Td (%s) Tj ET\n", pdfMargin, y, pdfEscape(l))
		// Move down.
		y -= 9
	} // end of the line loop
	// The program, the time and the page number.
	fmt.Fprintf(page, "BT /F1 7 Tf %.2f %.2f Td (%s) Tj ET\n", pdfMargin, y-2, pdfEscape(fmt.Sprintf("%s  -  page %d of %d", d.footerLine, n, total)))
} // end of footer

// bytes finishes the document and returns the file.
func (d *pdfDoc) bytes() []byte {
	// The finished file.
	var out bytes.Buffer
	// Where each numbered object starts, for the cross-reference table.
	var offsets []int
	// obj writes one numbered object and remembers where it started.
	obj := func(body string) {
		// The start.
		offsets = append(offsets, out.Len())
		// The object, numbered from 1.
		fmt.Fprintf(&out, "%d 0 obj\n%s\nendobj\n", len(offsets), body)
	} // end of obj
	// The header, with a comment of high bytes so tools treat the file as binary.
	out.WriteString("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
	// The number of pages.
	n := len(d.pages)
	// Object 1: the catalog.
	obj("<< /Type /Catalog /Pages 2 0 R /Lang (en) >>")
	// The page objects come after the fixed objects 1 to 5: page i is object 6+2i, its content 7+2i.
	var kids []string
	// Collect the references.
	for i := 0; i < n; i++ {
		// One page.
		kids = append(kids, fmt.Sprintf("%d 0 R", 6+2*i))
	} // end of the loop
	// Object 2: the list of pages.
	obj(fmt.Sprintf("<< /Type /Pages /Kids [%s] /Count %d >>", strings.Join(kids, " "), n))
	// Object 3: the regular font.
	obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
	// Object 4: the bold font.
	obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
	// Object 5: the document information.
	obj(fmt.Sprintf("<< /Title (%s) /Subject (%s) /Producer (LLMsControlDock %s) /Creator (LLMsControlDock) /CreationDate (D:%s) >>", pdfEscape(d.title), pdfEscape(d.subject), appVersion, d.created.Format("20060102150405Z0700")))
	// Each page and its content.
	for i, page := range d.pages {
		// The footer on this page.
		d.footer(page, i+1, n)
		// The page object: size, fonts and the content.
		obj(fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents %d 0 R >>", pdfPageW, pdfPageH, 7+2*i))
		// The content stream object.
		obj(fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", page.Len(), page.String()))
	} // end of the page loop
	// Where the cross-reference table starts.
	xref := out.Len()
	// The table: one entry of exactly 20 bytes for each object, and the free entry 0.
	fmt.Fprintf(&out, "xref\n0 %d\n0000000000 65535 f \n", len(offsets)+1)
	// The entries.
	for _, off := range offsets {
		// Ten digits, a generation number, and "n" for in use.
		fmt.Fprintf(&out, "%010d 00000 n \n", off)
	} // end of the loop
	// The trailer points at the catalog and the information, and at the table.
	fmt.Fprintf(&out, "trailer\n<< /Size %d /Root 1 0 R /Info 5 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(offsets)+1, xref)
	// The file.
	return out.Bytes()
} // end of bytes
