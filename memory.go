// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors builds fixed error messages.
	"errors"
	// net/url holds the parsed address type.
	"net/url"
	// strconv turns the number text into a number.
	"strconv"
	// strings splits the file into lines.
	"strings"
) // end of imports

// availableMemoryFunc reads the free memory; it is a variable so tests can replace it.
var availableMemoryFunc = availableMemory

// parseMemAvailable finds the MemAvailable line in the text of /proc/meminfo and returns its value in bytes; the second result is false when the line is missing or unreadable.
func parseMemAvailable(text string) (int64, bool) {
	// Look at every line.
	for _, line := range strings.Split(text, "\n") {
		// The line looks like "MemAvailable:   12345678 kB".
		if !strings.HasPrefix(line, "MemAvailable:") {
			// Not the line we want.
			continue
		} // end of the prefix check
		// Split it into words: the name, the number and the unit.
		f := strings.Fields(line)
		// There must be a number and the unit kB.
		if len(f) != 3 || f[2] != "kB" {
			// An unknown layout: say "unknown" instead of guessing.
			return 0, false
		} // end of the layout check
		// Read the number.
		kb, err := strconv.ParseInt(f[1], 10, 64)
		// A bad number or a negative one.
		if err != nil || kb < 0 {
			// Unknown.
			return 0, false
		} // end of the number check
		// The file counts in kibibytes (1024 bytes).
		return kb * 1024, true
	} // end of the line loop
	// The line was not found.
	return 0, false
} // end of parseMemAvailable

// availableMemory returns how much memory programs can still use on this computer, in bytes (Linux, Windows and macOS; other systems report an error).
func availableMemory() (int64, error) {
	// Read the figures the same way on every system.
	mi, err := readMemInfo()
	// The system did not report them.
	if err != nil {
		// Hand the reason back.
		return 0, err
	} // end of the read check
	// A zero or negative figure means the value was not found.
	if mi.AvailBytes <= 0 {
		// A fixed message.
		return 0, errors.New("the free memory could not be read")
	} // end of the value check
	// Hand it back.
	return mi.AvailBytes, nil
} // end of availableMemory

// ollamaIsLocal says whether the monitored Ollama runs on this same computer, so that this computer's free memory is the right number to show.
func ollamaIsLocal(u *url.URL) bool {
	// The host name without the port.
	switch u.Hostname() {
	// The three names a computer uses for itself.
	case "127.0.0.1", "localhost", "::1":
		// Same computer.
		return true
	} // end of the switch
	// Anything else may be another computer.
	return false
} // end of ollamaIsLocal
