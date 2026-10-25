// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context lets the graphics-card query be cancelled.
	"context"
	// net/url holds the parsed address type.
	"net/url"
	// os reads the files that describe the machine.
	"os"
	// os/exec runs the graphics-card tool, only when it is already installed.
	"os/exec"
	// path/filepath joins the folder and file names.
	"path/filepath"
	// runtime tells how many processor cores there are.
	"runtime"
	// strconv turns text into numbers.
	"strconv"
	// strings splits and trims text.
	"strings"
	// time limits the graphics-card query.
	"time"
) // end of imports

// machineSnapshot is what the monitor can read about the machine at one moment; every part says whether it was reported.
type machineSnapshot struct {
	// Local is true when Ollama runs on the same computer as the monitor, so the figures below describe the right machine.
	Local bool `json:"local"`
	// Note explains why nothing was read (Ollama on another computer).
	Note string `json:"note,omitempty"`
	// Cores is the number of logical processor cores.
	Cores int `json:"cores,omitempty"`
	// CPUName is the processor name, or empty when the system does not report one.
	CPUName string `json:"cpu_name,omitempty"`
	// Load1 is the load average of the last minute, or -1 when not reported.
	Load1 float64 `json:"load1"`
	// MemTotalGB is the total memory in gigabytes, or 0 when not reported.
	MemTotalGB float64 `json:"mem_total_gb,omitempty"`
	// MemFreeGB is the memory available for new work in gigabytes, or 0 when not reported.
	MemFreeGB float64 `json:"mem_free_gb,omitempty"`
	// SwapTotalGB is the swap space in gigabytes.
	SwapTotalGB float64 `json:"swap_total_gb,omitempty"`
	// SwapUsedGB is the swap space in use in gigabytes, or -1 when not reported.
	SwapUsedGB float64 `json:"swap_used_gb"`
	// GPUName is the graphics card name, or empty when no tool reported one.
	GPUName string `json:"gpu_name,omitempty"`
	// GPUMemory is the graphics memory use as the tool printed it (shared-memory machines print "[N/A]"), or empty.
	GPUMemory string `json:"gpu_memory,omitempty"`
	// GPUUtil is the graphics card's busy percentage at that moment, or -1 when not reported.
	GPUUtil int `json:"gpu_util"`
} // end of machineSnapshot

// procDir is where Linux describes the machine; a test points it at a folder of its own.
var procDir = "/proc"

// gpuQuery asks the graphics-card tool for one CSV line; a test replaces it. The tool is never required.
var gpuQuery = func(ctx context.Context) (string, error) {
	// Look for the tool; a machine without it simply reports nothing.
	exe, err := exec.LookPath("nvidia-smi")
	// Not installed.
	if err != nil {
		// Hand the error back; the caller treats it as "not reported".
		return "", err
	} // end of the lookup check
	// Never wait more than ten seconds for it.
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	// Release the timer at the end.
	defer cancel()
	// Run it with fixed arguments only; nothing typed by a person ever reaches this command.
	out, err := exec.CommandContext(ctx, exe, "--query-gpu=name,memory.used,memory.total,utilization.gpu", "--format=csv,noheader").Output()
	// Hand back the text and any error.
	return strings.TrimSpace(string(out)), err
} // end of gpuQuery

// isLocalAddress reports whether the address points at this same computer.
func isLocalAddress(u *url.URL) bool {
	// The host name without the port.
	h := u.Hostname()
	// The usual names for "this computer".
	return h == "127.0.0.1" || h == "localhost" || h == "::1"
} // end of isLocalAddress

// readKB reads the memory table of /proc/meminfo into a map of kilobytes.
func readKB() map[string]float64 {
	// The result.
	out := map[string]float64{}
	// Read the file; a missing file gives an empty table.
	data, err := os.ReadFile(filepath.Join(procDir, "meminfo"))
	// Not readable.
	if err != nil {
		// Nothing to report.
		return out
	} // end of the read check
	// Go through the lines.
	for _, line := range strings.Split(string(data), "\n") {
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

// snapshotMachine reads what the machine says about itself; for Ollama on another computer it reports only that.
func snapshotMachine(ctx context.Context, local bool) machineSnapshot {
	// Start with "not reported" values.
	s := machineSnapshot{Local: local, Load1: -1, SwapUsedGB: -1, GPUUtil: -1}
	// Ollama is elsewhere: these figures would describe the wrong computer.
	if !local {
		// Say so.
		s.Note = "Ollama is on another computer, so this computer's figures would not describe it."
		// Stop here.
		return s
	} // end of the remote case
	// The processor count is always known.
	s.Cores = runtime.NumCPU()
	// The processor name, when Linux lists one.
	if data, err := os.ReadFile(filepath.Join(procDir, "cpuinfo")); err == nil {
		// Look for the first "model name" line.
		for _, line := range strings.Split(string(data), "\n") {
			// Found.
			if strings.HasPrefix(strings.ToLower(line), "model name") {
				// Keep the text after the colon.
				if i := strings.Index(line, ":"); i >= 0 {
					// Trim spaces.
					s.CPUName = strings.TrimSpace(line[i+1:])
				} // end of the colon check
				// Only the first one.
				break
			} // end of the name check
		} // end of the loop
	} // end of the cpuinfo read
	// The load average: the first number is the last minute.
	if data, err := os.ReadFile(filepath.Join(procDir, "loadavg")); err == nil {
		// Split into numbers.
		if f := strings.Fields(string(data)); len(f) > 0 {
			// Read the first.
			if v, err := strconv.ParseFloat(f[0], 64); err == nil {
				// Keep it.
				s.Load1 = v
			} // end of the number check
		} // end of the field check
	} // end of the loadavg read
	// Memory in kilobytes (1024 bytes each); gigabytes are decimal, like every size the monitor shows (1 GB = 1,000,000,000 bytes).
	kb := readKB()
	// Total and available memory.
	s.MemTotalGB, s.MemFreeGB = kb["MemTotal"]*1024/1e9, kb["MemAvailable"]*1024/1e9
	// Swap, only when the machine reports a swap total at all.
	if t, ok := kb["SwapTotal"]; ok {
		// Total swap.
		s.SwapTotalGB = t * 1024 / 1e9
		// Swap in use is total minus free.
		s.SwapUsedGB = (t - kb["SwapFree"]) * 1024 / 1e9
	} // end of the swap check
	// The graphics card, when its own tool is already on the machine.
	if line, err := gpuQuery(ctx); err == nil && line != "" {
		// The line is "name, memory used, memory total, utilization".
		parts := strings.Split(strings.SplitN(line, "\n", 2)[0], ",")
		// Trim each part.
		for i := range parts {
			// Remove spaces around it.
			parts[i] = strings.TrimSpace(parts[i])
		} // end of the trim loop
		// The name.
		s.GPUName = parts[0]
		// The memory: used and total, as printed.
		if len(parts) >= 3 {
			// Shared-memory machines print [N/A] for both.
			s.GPUMemory = parts[1] + " of " + parts[2]
		} // end of the memory check
		// The busy percentage, like "96 %".
		if len(parts) >= 4 {
			// Remove the percent sign and spaces.
			if v, err := strconv.Atoi(strings.TrimSpace(strings.TrimSuffix(parts[3], "%"))); err == nil {
				// Keep it.
				s.GPUUtil = v
			} // end of the number check
		} // end of the util check
	} // end of the GPU query
	// Hand back everything that was read.
	return s
} // end of snapshotMachine

// busyReason says why the machine looked busy before the test, or returns an empty text when it did not.
func busyReason(s machineSnapshot) string {
	// Figures from another computer say nothing about this one.
	if !s.Local {
		// Not judged.
		return ""
	} // end of the remote case
	// The graphics card was working.
	if s.GPUUtil > 10 {
		// Say so with the figure.
		return "the graphics card was " + strconv.Itoa(s.GPUUtil) + "% busy before the test"
	} // end of the GPU check
	// The processor had a lot to do: the one-minute load above half the cores.
	if s.Cores > 0 && s.Load1 > float64(s.Cores)/2 {
		// Say so with the figures.
		return "the processor load (" + strconv.FormatFloat(s.Load1, 'f', 1, 64) + ") was above half of its " + strconv.Itoa(s.Cores) + " cores before the test"
	} // end of the load check
	// Nothing unusual.
	return ""
} // end of busyReason
