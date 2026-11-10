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

// helpTopics are the topics of the Help page, in the order a person typically meets them (first start, finding and loading a model, tuning, testing, comparing, tidying up, settings, stopping, uninstalling); each one is checked against what the program really does.
var helpTopics = []helpTopic{
	{
		ID:    "system-check",
		Title: "System check: what this computer offers",
		Intro: "The first time the program starts, it shows this report before the monitor. It lists the processors, memory and graphics cards of this computer, checks that Ollama is found and states what the tool needs. If a problem stops the tool from working fully, an alert lists the steps to fix it. The report stays available later in the footer bar.",
		Steps: []helpStep{
			{0, "Start LLMsControlDock for the first time."},
			{1, "Opens the System check before the monitor."},
			{1, "Reads this computer: processors, memory, graphics cards."},
			{1, "Asks Ollama for its version."},
			{2, "Answers with its version, or does not answer."},
			{1, "Shows the report. A problem opens an alert with the fixes."},
			{0, "Read it and press Continue to the monitor."},
			{1, "Remembers the answer and opens the monitor."},
		},
	},
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
	{
		ID:    "load-model",
		Title: "Load a model into memory",
		Intro: "Loading puts an installed model into memory, so that it answers quickly. Nothing is loaded until you confirm. If the free memory is short or close to what the model needs, the page warns you first.",
		Steps: []helpStep{
			{0, "Press Load on the model's row in the monitor."},
			{1, "Shows the free memory and the memory the model needs."},
			{0, "Choose how long it stays loaded and confirm."},
			{1, "Asks Ollama to load the model."},
			{2, "Reads the model from disk into memory."},
			{1, "Asks Ollama until the model is listed as loaded."},
			{2, "Reports its loaded models."},
			{1, "Shows the result and the time before Ollama unloads it."},
		},
	},
	{
		ID:    "tune-model",
		Title: "Tune a model: inference parameters",
		Intro: "Inference parameters are stored inside the model in Ollama, so every program that loads the model without a value of its own uses them. The model must not be loaded: a loaded model keeps the settings it was loaded with. A saved setting can be changed but never emptied. The Modelfile button only shows the model's Modelfile, read-only.",
		Steps: []helpStep{
			{0, "Press the inference parameters icon on an unloaded model."},
			{1, "Shows the saved values and a field for each new one."},
			{0, "Type the new values and press Review the changes."},
			{1, "Shows now and after saving, and warns that the model changes."},
			{0, "Press Yes, save them into the model."},
			{1, "Asks Ollama to save the values in the model."},
			{2, "Stores them inside the model."},
			{1, "Asks Ollama again what it reports and shows the result."},
		},
	},
	{
		ID:    "performance-test",
		Title: "Performance test of a model",
		Intro: "The test measures how fast a model runs on this machine. It uses the same fixed prompt every time and saves only numbers, never any text. Do not run it while the model is in use: a loaded model is refused, and the page warns when the machine looks busy.",
		Steps: []helpStep{
			{0, "Press Performance on an unloaded model's row."},
			{1, "Shows the cautions, the steps of the test and its time."},
			{0, "Make sure nobody uses the model and press Run."},
			{1, "Sends a warm-up request; its load time is the cold figure."},
			{2, "Loads the model from disk and answers."},
			{1, "Sends three timed requests and keeps the median."},
			{2, "Answers each timed request."},
			{1, "Reads Ollama's report and the machine; saves numbers only."},
			{2, "Unloads the model, so memory is left as it was found."},
			{1, "Shows the speed and the tests saved for this model."},
		},
	},
	{
		ID:    "compare-models",
		Title: "Compare tested models, and re-test",
		Intro: "Compare lists the models that already went through a performance test, in groups, with the reason for each group and how to read the figures. A re-test adds new results for a group and keeps the old ones. A loaded model is left alone, because it may be in use.",
		Steps: []helpStep{
			{0, "Press Compare tested models on the monitor."},
			{1, "Groups the tested models and shows their figures."},
			{0, "Read the groups. Save a PDF or CSV if you wish."},
			{0, "Press Re-test this group to add new results."},
			{1, "Shows which models will be tested. Nothing runs yet."},
			{0, "Press Yes, re-test."},
			{1, "Tests the models one after another, as in a performance test."},
			{2, "Loads each model, answers, and unloads it."},
			{1, "Saves a new result for each model. Old results stay."},
			{0, "Press Show the comparison to see the new figures."},
		},
	},
	{
		ID:    "unload-model",
		Title: "Unload a model from memory",
		Intro: "Unloading frees the memory of a loaded model. The monitor cannot see whether a model is working on a request right now, so the page warns you first. If you do nothing, Ollama unloads the model by itself after its time runs out.",
		Steps: []helpStep{
			{0, "Press Unload on a loaded model's row."},
			{1, "Warns that it cannot see whether the model is in use."},
			{0, "Press Yes, unload it now, only if nothing uses the model."},
			{1, "Asks Ollama to unload the model now."},
			{2, "Unloads the model."},
			{1, "Checks that it left the loaded list and tells you."},
		},
	},
	{
		ID:    "delete-restore",
		Title: "Delete a model, and restore it later",
		Intro: "Delete removes a model from this computer and frees its disk space; the tuning you made is lost. Restore downloads the latest version of the same name again. A model you made yourself, from a Modelfile or an import, cannot be downloaded again. A loaded model asks for a hold, or for its name typed to force the delete.",
		Steps: []helpStep{
			{0, "Press Delete on the model's row."},
			{1, "Explains what you lose and how much space it frees."},
			{0, "Press Yes, delete it."},
			{1, "Saves a snapshot of the model's inference parameters."},
			{1, "Asks Ollama to delete the model."},
			{2, "Removes the model and frees the disk space."},
			{1, "Remembers name, size and time; greys the row out."},
			{0, "Press Restore when you want the model back."},
			{1, "Shows the pull command for each way Ollama runs."},
			{0, "Run the command where Ollama runs."},
			{3, "Sends the latest version of that name."},
			{2, "Stores it; the greyed row disappears."},
		},
	},
	{
		ID:    "settings",
		Title: "Settings",
		Intro: "Settings holds the Ollama address, the check interval, the timeout, the chart history and the access from other machines. Values marked restart are used the next time the monitor starts; the others apply at once. The desktop icon is created, updated or removed on the same page.",
		Steps: []helpStep{
			{0, "Press Settings in the monitor's top bar."},
			{1, "Shows each setting: in use now, new value and default."},
			{0, "Change what you need and press Save settings."},
			{1, "Checks every value. A wrong one is refused with a reason."},
			{1, "Saves the values in the settings folder."},
			{1, "Applies at once what is not marked restart."},
			{0, "Stop and start the program for settings marked restart."},
		},
	},
	{
		ID:    "stop-program",
		Title: "Stop the program",
		Intro: "Stopping closes LLMsControlDock. Ollama and its models are not touched: whatever is loaded stays loaded.",
		Steps: []helpStep{
			{0, "Press Stop in the monitor's top bar."},
			{1, "Asks first, and says what is running right now."},
			{0, "Press Yes, stop the monitor."},
			{1, "Closes the program."},
			{2, "Stays as it was. Loaded models stay loaded."},
			{0, "Start the program again when you need it."},
		},
	},
	{
		ID:    "uninstall",
		Title: "Uninstall",
		Intro: "Uninstalling deletes what this tool collected on this computer: its settings, the performance results and saved comparisons, the list of deleted models, the check history and the desktop icon. Ollama, its models and the program file are not touched. A running program cannot delete itself, so you delete the program file yourself.",
		Steps: []helpStep{
			{0, "Open System check and press Uninstall this tool."},
			{1, "Lists what would be removed, and where."},
			{0, "If data was saved, type uninstall and press OK."},
			{1, "Deletes those items and stops the program."},
			{2, "Not touched. Its models stay."},
			{0, "Delete the program file yourself. The page shows where it is."},
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
		// The page runs the monitor's own small script file, and nothing else.
		w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of the handler
} // end of helpHandler
