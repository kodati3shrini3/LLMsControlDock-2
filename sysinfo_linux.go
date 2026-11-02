//go:build linux

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors builds fixed error messages.
	"errors"
	// os reads the files under /proc.
	"os"
	// path/filepath joins the folder and file names.
	"path/filepath"
	// strconv turns text into numbers.
	"strconv"
	// strings splits and trims text.
	"strings"
) // end of imports

// readKB reads the memory table of /proc/meminfo into a map of kilobytes.
func readKB(text string) map[string]float64 {
	// The result.
	out := map[string]float64{}
	// Go through the lines.
	for _, line := range strings.Split(text, "\n") {
		// A line looks like "MemTotal:  127000 kB".
		f := strings.Fields(line)
		// Skip lines of another shape.
		if len(f) < 2 {
			// Next line.
			continue
		} // end of the shape check
		// Read the number.
		if v, err := strconv.ParseFloat(f[1], 64); err == nil {
			// Store it under the name without the colon.
			out[strings.TrimSuffix(f[0], ":")] = v
		} // end of the number check
	} // end of the loop
	// Hand back the table.
	return out
} // end of readKB

// osMemInfo reads the memory figures from /proc/meminfo (the folder is procDir so that a test can point it elsewhere).
func osMemInfo() (memInfo, error) {
	// Read the file.
	data, err := os.ReadFile(filepath.Join(procDir, "meminfo"))
	// Not readable.
	if err != nil {
		// A fixed message.
		return memInfo{}, errors.New("this system does not report its free memory")
	} // end of the read check
	// The text and the table made from it.
	text := string(data)
	// The table, in kilobytes.
	kb := readKB(text)
	// The total is in kibibytes (1024 bytes each).
	mi := memInfo{TotalBytes: int64(kb["MemTotal"]) * 1024}
	// The free part, read strictly: an unknown layout counts as "not known".
	if n, ok := parseMemAvailable(text); ok {
		// Keep it.
		mi.AvailBytes = n
	} // end of the available check
	// Swap, only when the machine reports a swap total at all.
	if t, ok := kb["SwapTotal"]; ok {
		// It was reported.
		mi.HaveSwap = true
		// Total swap.
		mi.SwapTotalBytes = int64(t) * 1024
		// Swap in use is total minus free.
		mi.SwapUsedBytes = int64(t-kb["SwapFree"]) * 1024
	} // end of the swap check
	// Hand it back.
	return mi, nil
} // end of osMemInfo

// osCPUName reads the processor name from /proc/cpuinfo, or returns empty text.
func osCPUName() string {
	// Read the file.
	data, err := os.ReadFile(filepath.Join(procDir, "cpuinfo"))
	// Not readable.
	if err != nil {
		// Not known.
		return ""
	} // end of the read check
	// Look for the first "model name" line.
	for _, line := range strings.Split(string(data), "\n") {
		// Found.
		if strings.HasPrefix(strings.ToLower(line), "model name") {
			// Keep the text after the colon.
			if i := strings.Index(line, ":"); i >= 0 {
				// Trim spaces.
				return strings.TrimSpace(line[i+1:])
			} // end of the colon check
			// A line without a colon: stop looking.
			return ""
		} // end of the name check
	} // end of the loop
	// Not listed (some ARM machines).
	return ""
} // end of osCPUName

// osLoad1 reads the one-minute load average from /proc/loadavg, or returns -1.
func osLoad1() float64 {
	// Read the file.
	data, err := os.ReadFile(filepath.Join(procDir, "loadavg"))
	// Not readable.
	if err != nil {
		// Not known.
		return -1
	} // end of the read check
	// Read the first number.
	if v, ok := parseLoad1(string(data)); ok {
		// Keep it.
		return v
	} // end of the number check
	// Unreadable.
	return -1
} // end of osLoad1
