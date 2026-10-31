// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the texts.
	"fmt"
	// sort puts the largest model first.
	"sort"
	// time gives the moment for the unload timers.
	"time"
) // end of imports

// memBarWidth is the width of a memory bar in drawing units; the picture scales to the box.
const memBarWidth = 300

// memBarHeight is the height of a memory bar in drawing units.
const memBarHeight = 10

// memRow is one loaded model in the memory part of the Charts box.
type memRow struct {
	// Name is the model name, never shortened.
	Name string
	// Size is the size Ollama reports for the running model, as text.
	Size string
	// Fill is the length of the filled part of the bar, in drawing units.
	Fill int
	// Percent is the same length as a share of the largest loaded model, for the text alternative.
	Percent int
	// Where says how much of the model sits in GPU memory.
	Where string
	// Timer says when Ollama will unload the model, as of the moment the page was made.
	Timer string
} // end of memRow

// memView is what the memory part of the Charts box shows.
type memView struct {
	// Message explains why there is no list (offline, unreadable, nothing loaded); empty when there are rows.
	Message string
	// Rows are the loaded models, largest first.
	Rows []memRow
	// Total is the sum of the sizes as text, shown when there are rows.
	Total string
	// BarWidth and BarHeight are the size of one bar drawing.
	BarWidth, BarHeight int
} // end of memView

// whereText says how much of a model sits in GPU memory, using only what Ollama reports.
func whereText(m loadedModel) string {
	// Without a size there is nothing to compare.
	if m.Size <= 0 {
		// Say so.
		return "memory split not reported"
	} // end of the size check
	// All of it in GPU memory.
	if m.SizeVRAM >= m.Size {
		// All.
		return "all in GPU memory"
	} // end of the all-in-GPU case
	// None of it in GPU memory.
	if m.SizeVRAM <= 0 {
		// None.
		return "none in GPU memory (all in processor memory)"
	} // end of the none case
	// A share, rounded to a whole percent.
	pct := int(float64(m.SizeVRAM)*100/float64(m.Size) + 0.5)
	// The rest is in processor memory.
	return fmt.Sprintf("%d %% in GPU memory, %d %% in processor memory", pct, 100-pct)
} // end of whereText

// unloadText says in plain words when Ollama will unload the model, as of the given moment.
func unloadText(m loadedModel, now time.Time) string {
	// The same rules as the table's timer.
	text, _, _ := timerFor(m, now)
	// Fixed texts first.
	switch text {
	// Set to stay loaded.
	case longKeepText:
		// Say it.
		return "stays loaded (no unload time)"
	// Ollama gave no time.
	case "not reported":
		// Say it.
		return "unload time not reported"
	// The time has arrived.
	case "unloading now":
		// Say it.
		return "unloading now"
	} // end of the switch
	// A normal countdown.
	return "unloads in " + text
} // end of unloadText

// buildMemory turns the loaded models into the memory part of the Charts box; online and listsOK say whether the list could be read at all.
func buildMemory(loaded []loadedModel, online, listsOK bool, now time.Time) memView {
	// The sizes of the drawings.
	v := memView{BarWidth: memBarWidth, BarHeight: memBarHeight}
	// Ollama does not answer: the loaded models are not known.
	if !online {
		// Say so.
		v.Message = "Ollama is not answering, so the loaded models are not known."
		// Done.
		return v
	} // end of the offline case
	// The list could not be read just now.
	if !listsOK {
		// Say so.
		v.Message = "The list of loaded models could not be read just now."
		// Done.
		return v
	} // end of the unreadable case
	// Nothing loaded.
	if len(loaded) == 0 {
		// Say so.
		v.Message = "No model is loaded."
		// Done.
		return v
	} // end of the empty case
	// A sorted copy, so the caller's list stays as it was: the largest first, then by name.
	sorted := append([]loadedModel(nil), loaded...)
	// Sort.
	sort.SliceStable(sorted, func(i, j int) bool {
		// The larger first.
		if sorted[i].Size != sorted[j].Size {
			// Larger first.
			return sorted[i].Size > sorted[j].Size
		} // end of the size check
		// Same size: by name.
		return sorted[i].Name < sorted[j].Name
	}) // end of the sort
	// The largest and the sum.
	largest, sum := sorted[0].Size, int64(0)
	// Add up.
	for _, m := range sorted {
		// A negative size counts as nothing.
		if m.Size > 0 {
			// Add it.
			sum += m.Size
		} // end of the size check
	} // end of the loop
	// One row per model.
	for _, m := range sorted {
		// The share of the largest, as a whole percent; nothing when no size is known.
		pct := 0
		// Only with a known size.
		if m.Size > 0 && largest > 0 {
			// Round to a whole percent, and keep at least 1 so a small model still shows a sliver.
			pct = int(float64(m.Size)*100/float64(largest) + 0.5)
			// A sliver.
			if pct < 1 {
				// At least one percent.
				pct = 1
			} // end of the sliver check
		} // end of the share
		// The size text.
		size := "size not reported"
		// With a size.
		if m.Size > 0 {
			// Write it.
			size = formatSize(m.Size)
		} // end of the size text
		// Add the row.
		v.Rows = append(v.Rows, memRow{Name: m.Name, Size: size, Fill: pct * memBarWidth / 100, Percent: pct, Where: whereText(m), Timer: unloadText(m, now)})
	} // end of the loop
	// The sum.
	v.Total = formatSize(sum)
	// Hand it back.
	return v
} // end of buildMemory
