// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context lets a request be cancelled or given a deadline.
	"context"
	// fmt builds formatted text.
	"fmt"
	// net/url holds the parsed address type.
	"net/url"
	// time provides the timestamp type and durations.
	"time"
) // end of imports

// loadedModel is one row of the Loaded table, as returned by /api/ps.
type loadedModel struct {
	// Name is the model name including its tag.
	Name string `json:"name"`
	// Size is the size in bytes that Ollama reports for the running model (it looked like the memory used on the test machine).
	Size int64 `json:"size"`
	// Digest is the model's fingerprint.
	Digest string `json:"digest"`
	// SizeVRAM is how many bytes sit in GPU memory (VRAM, video random-access memory).
	SizeVRAM int64 `json:"size_vram"`
	// ContextLength is the context window of the running model, which can differ from the model's maximum.
	ContextLength int64 `json:"context_length"`
	// ExpiresAt is kept as the original text, so an unexpected format cannot make the whole list fail to decode.
	ExpiresAt string `json:"expires_at"`
} // end of loadedModel

// psReply is the shape of the JSON that /api/ps returns.
type psReply struct {
	// Models is the list of loaded models.
	Models []loadedModel `json:"models"`
} // end of psReply

// installedRow is one row of the Installed table: the installed model plus whether it is loaded right now.
type installedRow struct {
	// Model is the installed model's data.
	Model installedModel
	// Loaded is true when the model is in the loaded list.
	Loaded bool
} // end of installedRow

// fetchLoaded returns the models that are loaded right now (an empty list when none are).
func fetchLoaded(ctx context.Context, base *url.URL, timeout time.Duration) ([]loadedModel, error) {
	// Prepare a place to hold the decoded JSON.
	var reply psReply
	// Fetch /api/ps and decode it (getJSON comes from models.go).
	if err := getJSON(ctx, base, "api/ps", timeout, &reply); err != nil {
		// Pass the safe error on, with no models.
		return nil, err
	} // end of the fetch check
	// Return the list.
	return reply.Models, nil
} // end of fetchLoaded

// expiresTime reads the unload time; the second result is false when the text is missing or in an unknown format.
func (m loadedModel) expiresTime() (time.Time, bool) {
	// An empty text means Ollama did not report a time.
	if m.ExpiresAt == "" {
		// Say "no usable time".
		return time.Time{}, false
	} // end of the empty check
	// Read the text in the standard RFC 3339 format (Request For Comments 3339), with or without fractional seconds.
	t, err := time.Parse(time.RFC3339Nano, m.ExpiresAt)
	// A parse failure means an unknown format.
	if err != nil {
		// Say "no usable time".
		return time.Time{}, false
	} // end of the parse check
	// Return the instant; an offset such as +02:00 or -07:00 is handled by the parser.
	return t, true
} // end of expiresTime

// combine marks every installed model as loaded or not, matching by name; a loaded name that is not installed adds no row.
func combine(installed []installedModel, loaded []loadedModel) []installedRow {
	// Build a lookup of loaded names; a map answers "is this name in there?" in one step.
	isLoaded := make(map[string]bool, len(loaded))
	// Go through every loaded model.
	for _, l := range loaded {
		// Remember its name.
		isLoaded[l.Name] = true
	} // end of the loaded loop
	// Prepare the result with room for every installed model.
	rows := make([]installedRow, 0, len(installed))
	// Go through every installed model, keeping the original order.
	for _, m := range installed {
		// Add a row with the model and its loaded flag.
		rows = append(rows, installedRow{Model: m, Loaded: isLoaded[m.Name]})
	} // end of the installed loop
	// Return the rows.
	return rows
} // end of combine

// stateText is the text for the state column; the symbol and the words always appear together so colour is never the only signal.
func stateText(loaded bool) string {
	// A loaded model gets a filled circle and the word Loaded.
	if loaded {
		// Return the loaded text.
		return "● Loaded"
	} // end of the loaded case
	// Everything else gets an empty circle and the words Not loaded.
	return "○ Not loaded"
} // end of stateText

// formatRemaining turns the time left before unload into readable text; ok is false when no time was reported.
func formatRemaining(now time.Time, expires time.Time, ok bool) string {
	// Without a usable time we say so instead of guessing.
	if !ok {
		// Return the neutral text.
		return "not reported"
	} // end of the no-time case
	// Work out how long is left, rounded to whole seconds.
	left := expires.Sub(now).Round(time.Second)
	// Zero or negative means the unload time has arrived.
	if left <= 0 {
		// Return the text for "now".
		return "unloading now"
	} // end of the past case
	// Count the whole seconds left.
	secs := int(left.Seconds())
	// Split them into hours, minutes and seconds.
	h, m, s := secs/3600, (secs%3600)/60, secs%60
	// With hours, show hours and minutes.
	if h > 0 {
		// Return hours and minutes.
		return fmt.Sprintf("%d h %d min", h, m)
	} // end of the hours case
	// With minutes, show minutes and seconds.
	if m > 0 {
		// Return minutes and seconds.
		return fmt.Sprintf("%d min %d s", m, s)
	} // end of the minutes case
	// Otherwise show only seconds.
	return fmt.Sprintf("%d s", s)
} // end of formatRemaining
