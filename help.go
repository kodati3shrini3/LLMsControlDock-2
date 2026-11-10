// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds the page in memory.
	"bytes"
	// embed lets the page template be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// fmt builds the path texts of the arrows.
	"fmt"
	// html/template fills the page and escapes every value.
	"html/template"
	// log writes the reason when the page cannot be built.
	"log"
	// net/http provides requests and status codes.
	"net/http"
	// strings splits text into lines.
	"strings"
) // end of imports

// helpTemplateText holds the Help page, stored inside the executable at build time.
//
//go:embed web/help.html
var helpTemplateText string

// helpLanes are the lanes (rows of who does what) every diagram uses, in this order.
var helpLanes = []string{"You", "LLMsControlDock", "Ollama", "ollama.com"}

// helpStep is one step of a topic: the lane that does it (an index into helpLanes) and what is done, in one short sentence.
type helpStep struct {
	// Lane is the index of the lane in helpLanes.
	Lane int
	// Text is what happens in this step.
	Text string
} // end of helpStep

// helpTopic is one help topic: a title, a plain introduction and the steps of its swimlane diagram.
type helpTopic struct {
	// ID is the name used for the link to this topic on the page.
	ID string
	// Title is the heading of the topic.
	Title string
	// Intro is one or two plain sentences before the diagram.
	Intro string
	// Steps are the steps, in order.
	Steps []helpStep
} // end of helpTopic

// helpTopics are the topics of the Help page; each one is checked against what the program really does.
var helpTopics = []helpTopic{
	{
		ID:    "find-llm",
		Title: "Find LLM: from your needs to a model you can install",
		Intro: "Find LLM lists the models of the official Ollama library that fit what you tick and what this computer has. It never installs anything: you copy a command and run it yourself. If ollama.com cannot be reached, a saved copy of the list is shown with its date and without versions.",
		Steps: []helpStep{
			{0, "Open Find LLM from the monitor."},
			{1, "Shows the choices, with free disk and memory filled in."},
			{0, "Tick what you need and press Find LLM."},
			{1, "Asks ollama.com for the library list."},
			{3, "Sends the public list. Your choices are not sent."},
			{1, "Keeps matching models, asks for each one's versions."},
			{3, "Sends sizes, context lengths and update ages."},
			{1, "Asks Ollama which models are installed."},
			{2, "Lists the installed models."},
			{1, "Checks every version against your limits and lists them."},
			{0, "Copy the command of a version that fits."},
			{2, "Downloads the model when you run the command."},
		},
	},
} // end of helpTopics

// The measures of a diagram, in the units of its drawing area.
const (
	// helpLaneW is the width of one lane.
	helpLaneW = 190
	// helpHeaderH is the height of the lane names at the top.
	helpHeaderH = 36
	// helpBoxW is the width of a step box.
	helpBoxW = 170
	// helpBoxH is the height of a step box (three lines of text).
	helpBoxH = 64
	// helpGap is the space between two boxes, where the arrow runs.
	helpGap = 30
	// helpWrap is the longest line of text inside a box, in characters.
	helpWrap = 23
	// helpMaxLines is the most lines a box can hold.
	helpMaxLines = 3
) // end of the measures

// helpLine is one line of text inside a box.
type helpLine struct {
	// X and Y are the place of the line.
	X, Y int
	// Text is the words.
	Text string
} // end of helpLine

// helpBox is one step as drawn.
type helpBox struct {
	// X, Y, W and H are the place and size of the box.
	X, Y, W, H int
	// Lines are the lines of text.
	Lines []helpLine
	// Arrow is the path of the arrow that leaves this box towards the next one; empty for the last.
	Arrow string
} // end of helpBox

// helpLaneView is one lane as drawn.
type helpLaneView struct {
	// Name is the lane's name.
	Name string
	// X is the left edge and W the width.
	X, W int
	// NameX and NameY are where the name is written.
	NameX, NameY int
	// Odd is true for every second lane, which gets a tinted background.
	Odd bool
} // end of helpLaneView

// helpListItem is one step as the numbered list under the diagram shows it.
type helpListItem struct {
	// Lane is the lane's name.
	Lane string
	// Text is the step's sentence.
	Text string
} // end of helpListItem

// helpTopicView is one topic ready for the page.
type helpTopicView struct {
	// ID, Title and Intro come from the topic.
	ID, Title, Intro string
	// Width and Height are the size of the drawing area.
	Width, Height int
	// Lanes are the lanes.
	Lanes []helpLaneView
	// Boxes are the steps.
	Boxes []helpBox
	// List is the same steps as text, for people who cannot see the picture.
	List []helpListItem
	// Description is a sentence for screen readers that says what the picture is.
	Description string
} // end of helpTopicView

// wrapText cuts a sentence into lines of at most width characters, breaking only between words; a word longer than the width stays whole.
func wrapText(s string, width int) []string {
	// The lines.
	var lines []string
	// The line being built.
	cur := ""
	// Each word.
	for _, w := range strings.Fields(s) {
		// The first word of a line.
		if cur == "" {
			// Start it.
			cur = w
			// Next word.
			continue
		} // end of the start check
		// It still fits on the line.
		if len(cur)+1+len(w) <= width {
			// Add it.
			cur += " " + w
		} else {
			// Close the line and start the next.
			lines = append(lines, cur)
			// The word starts the next line.
			cur = w
		} // end of the fit check
	} // end of the word loop
	// The last line.
	if cur != "" {
		// Keep it.
		lines = append(lines, cur)
	} // end of the last-line check
	// The lines.
	return lines
} // end of wrapText

// buildHelpTopic works out where every lane, box, line of text and arrow goes.
func buildHelpTopic(t helpTopic) helpTopicView {
	// The basic facts.
	v := helpTopicView{ID: t.ID, Title: t.Title, Intro: t.Intro, Width: helpLaneW * len(helpLanes)}
	// The height: the header, a margin, and every step with its gap.
	top := helpHeaderH + 14
	// The total height.
	v.Height = top + len(t.Steps)*(helpBoxH+helpGap)
	// The lanes.
	for i, name := range helpLanes {
		// One lane.
		v.Lanes = append(v.Lanes, helpLaneView{Name: name, X: i * helpLaneW, W: helpLaneW, NameX: i*helpLaneW + helpLaneW/2, NameY: 23, Odd: i%2 == 1})
	} // end of the lane loop
	// The steps.
	for i, s := range t.Steps {
		// The box: centred in its lane.
		b := helpBox{X: s.Lane*helpLaneW + (helpLaneW-helpBoxW)/2, Y: top + i*(helpBoxH+helpGap), W: helpBoxW, H: helpBoxH}
		// The words, with the step number in front.
		for j, line := range wrapText(fmt.Sprintf("%d. %s", i+1, s.Text), helpWrap) {
			// One line, centred in the box.
			b.Lines = append(b.Lines, helpLine{X: b.X + b.W/2, Y: b.Y + 21 + j*16, Text: line})
		} // end of the line loop
		// The arrow to the next step.
		if i+1 < len(t.Steps) {
			// Where it starts: the middle of the bottom edge.
			x1, y1 := b.X+b.W/2, b.Y+b.H
			// Where it ends: the middle of the next box's top edge.
			x2, y2 := t.Steps[i+1].Lane*helpLaneW+helpLaneW/2, top+(i+1)*(helpBoxH+helpGap)
			// The same lane: straight down.
			if x1 == x2 {
				// A vertical line.
				b.Arrow = fmt.Sprintf("M%d %d V%d", x1, y1, y2)
			} else {
				// Down, across, down.
				b.Arrow = fmt.Sprintf("M%d %d V%d H%d V%d", x1, y1, y1+helpGap/2, x2, y2)
			} // end of the lane check
		} // end of the arrow check
		// Keep the box.
		v.Boxes = append(v.Boxes, b)
		// And the list item.
		v.List = append(v.List, helpListItem{Lane: helpLanes[s.Lane], Text: s.Text})
	} // end of the step loop
	// The sentence for screen readers.
	v.Description = fmt.Sprintf("Swimlane diagram with %d lanes (%s) and %d numbered steps from top to bottom; the same steps are listed below it.", len(helpLanes), strings.Join(helpLanes, ", "), len(t.Steps))
	// The finished view.
	return v
} // end of buildHelpTopic

// helpPage is what the Help template needs.
type helpPage struct {
	// Theme is the saved colour theme, or empty to follow the system.
	Theme string
	// Size is the saved text size, or empty for the browser's own size.
	Size string
	// Topics are the topics to show.
	Topics []helpTopicView
} // end of helpPage

// helpHandler builds the handler of the read-only Help page; it changes nothing and needs no token.
func helpHandler() http.HandlerFunc {
	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
	page := template.Must(template.New("help").Parse(helpTemplateText))
	// The topics are fixed, so their drawings are worked out once.
	var topics []helpTopicView
	// Each topic.
	for _, t := range helpTopics {
		// Its drawing.
		topics = append(topics, buildHelpTopic(t))
	} // end of the topic loop
	// The handler itself.
	return func(w http.ResponseWriter, r *http.Request) {
		// What the template shows.
		data := helpPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Topics: topics}
		// Build the page in memory first, so a template error produces a clean 500 and not a half page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason.
			log.Printf("help page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of the handler
} // end of helpHandler
