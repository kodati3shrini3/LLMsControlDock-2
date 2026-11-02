//go:build darwin

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context limits how long a tool may run.
	"context"
	// errors builds fixed error messages.
	"errors"
	// os/exec runs the two tools that ship with macOS.
	"os/exec"
	// strconv turns text into numbers.
	"strconv"
	// strings trims the text the tools print.
	"strings"
	// time sets the limit.
	"time"
) // end of imports

// The two tools below ship with macOS; their full paths are used so that no other program with the same name is ever run.
const (
	// sysctlPath is the tool that reads system values.
	sysctlPath = "/usr/sbin/sysctl"
	// vmStatPath is the tool that prints the virtual-memory page counts.
	vmStatPath = "/usr/bin/vm_stat"
) // end of the tool paths

// runTool runs one of the tools with fixed arguments (nothing typed by a person reaches it) and returns what it printed; it never waits more than three seconds.
func runTool(path string, args ...string) (string, error) {
	// Never wait long.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	// Release the timer at the end.
	defer cancel()
	// Run it and collect its output.
	out, err := exec.CommandContext(ctx, path, args...).Output()
	// Hand back the trimmed text and any error.
	return strings.TrimSpace(string(out)), err
} // end of runTool

// osMemInfo reads the memory figures with sysctl and vm_stat; "available" is an estimate: the free, inactive and speculative pages, which macOS can hand to a program at once.
func osMemInfo() (memInfo, error) {
	// The total memory in bytes.
	out, err := runTool(sysctlPath, "-n", "hw.memsize")
	// The tool failed.
	if err != nil {
		// A fixed message.
		return memInfo{}, errors.New("this system did not report its memory")
	} // end of the total check
	// Read the number.
	total, err := strconv.ParseInt(out, 10, 64)
	// Not a number.
	if err != nil || total <= 0 {
		// A fixed message.
		return memInfo{}, errors.New("the total memory could not be read")
	} // end of the number check
	// The page counts.
	out, err = runTool(vmStatPath)
	// The tool failed.
	if err != nil {
		// A fixed message.
		return memInfo{}, errors.New("the free memory could not be read")
	} // end of the vm_stat check
	// Read the four figures.
	page, free, inactive, speculative, ok := parseVMStat(out)
	// An unknown layout.
	if !ok {
		// A fixed message.
		return memInfo{}, errors.New("the free memory could not be read")
	} // end of the layout check
	// The estimate in bytes.
	mi := memInfo{TotalBytes: total, AvailBytes: (free + inactive + speculative) * page}
	// The swap, when the tool reports it.
	if out, err = runTool(sysctlPath, "-n", "vm.swapusage"); err == nil {
		// Read the two sizes.
		if t, u, ok := parseSwapUsage(out); ok {
			// It was reported.
			mi.HaveSwap, mi.SwapTotalBytes, mi.SwapUsedBytes = true, t, u
		} // end of the swap check
	} // end of the swap tool
	// Hand it back.
	return mi, nil
} // end of osMemInfo

// osCPUName reads the processor name, such as "Apple M2" or an Intel name; it is empty when not known.
func osCPUName() string {
	// Ask sysctl.
	out, err := runTool(sysctlPath, "-n", "machdep.cpu.brand_string")
	// The tool failed.
	if err != nil {
		// Not known.
		return ""
	} // end of the check
	// The name.
	return out
} // end of osCPUName

// osLoad1 reads the one-minute load average from "sysctl vm.loadavg", or returns -1.
func osLoad1() float64 {
	// Ask sysctl.
	out, err := runTool(sysctlPath, "-n", "vm.loadavg")
	// The tool failed.
	if err != nil {
		// Not known.
		return -1
	} // end of the check
	// Read the first number.
	if v, ok := parseLoad1(out); ok {
		// Keep it.
		return v
	} // end of the number check
	// Unreadable.
	return -1
} // end of osLoad1
