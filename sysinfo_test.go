// Package main tells Go that this test file belongs to the same program as sysinfo.go.
package main

import ( // import lists the packages this test file uses.
	// context is needed by the snapshot call.
	"context"
	// encoding/binary measures the size of the Windows structure.
	"encoding/binary"
	// errors builds the "not reported" error.
	"errors"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// macVMStat is a vm_stat text as an Apple Silicon Mac prints it (16 KiB pages).
const macVMStat = `Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               12345.
Pages active:                            200000.
Pages inactive:                          190000.
Pages speculative:                         5000.
Pages throttled:                              0.
Pages wired down:                         90000.
`

// TestParseVMStat checks the macOS page counts, including a layout that is not understood.
func TestParseVMStat(t *testing.T) {
	// The normal text.
	page, free, inactive, spec, ok := parseVMStat(macVMStat)
	// All four figures must come out right.
	if !ok || page != 16384 || free != 12345 || inactive != 190000 || spec != 5000 {
		// Report the problem.
		t.Errorf("vm_stat: %d %d %d %d %v", page, free, inactive, spec, ok)
	} // end of the figures check
	// An Intel Mac prints 4096-byte pages.
	if p, _, _, _, ok := parseVMStat("Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: 1.\nPages inactive: 2.\nPages speculative: 3.\n"); !ok || p != 4096 {
		// Report the problem.
		t.Errorf("intel page size: %d %v", p, ok)
	} // end of the Intel check
	// Texts that must give "not known".
	for _, bad := range []string{
		// Nothing at all.
		"",
		// The page size is missing.
		"Pages free: 1.\nPages inactive: 2.\nPages speculative: 3.\n",
		// One line is missing.
		"Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: 1.\nPages inactive: 2.\n",
		// A number is missing.
		"Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: x.\nPages inactive: 2.\nPages speculative: 3.\n",
		// A page size of zero.
		"Mach Virtual Memory Statistics: (page size of 0 bytes)\nPages free: 1.\nPages inactive: 2.\nPages speculative: 3.\n",
	} { // end of the bad texts
		// It must not be accepted.
		if _, _, _, _, ok := parseVMStat(bad); ok {
			// Report the problem.
			t.Errorf("accepted: %q", bad)
		} // end of the check
	} // end of the loop
} // end of TestParseVMStat

// TestParseSwapUsage checks the macOS swap text, in megabytes and in gigabytes, and the unreadable cases.
func TestParseSwapUsage(t *testing.T) {
	// The usual text.
	total, used, ok := parseSwapUsage("total = 2048.00M  used = 1127.50M  free = 920.50M  (encrypted)")
	// 2048 MiB and 1127.5 MiB.
	if !ok || total != 2048<<20 || used != 1127<<20+512<<10 {
		// Report the problem.
		t.Errorf("swap in megabytes: %d %d %v", total, used, ok)
	} // end of the megabyte check
	// A text in gigabytes.
	total, used, ok = parseSwapUsage("total = 4.00G  used = 0.50G  free = 3.50G  (encrypted)")
	// 4 GiB and half a GiB.
	if !ok || total != 4<<30 || used != 1<<29 {
		// Report the problem.
		t.Errorf("swap in gigabytes: %d %d %v", total, used, ok)
	} // end of the gigabyte check
	// Texts that must give "not known".
	for _, bad := range []string{
		// Nothing.
		"",
		// Used is missing.
		"total = 2048.00M",
		// An unknown unit.
		"total = 2048.00X  used = 1.00X",
		// Used is more than the total.
		"total = 1.00M  used = 2.00M",
		// No unit letter at all.
		"total = 2048.00  used = 1.00",
	} { // end of the bad texts
		// It must not be accepted.
		if _, _, ok := parseSwapUsage(bad); ok {
			// Report the problem.
			t.Errorf("accepted: %q", bad)
		} // end of the check
	} // end of the loop
} // end of TestParseSwapUsage

// TestParseLoad1 checks the Linux and the macOS load average texts.
func TestParseLoad1(t *testing.T) {
	// The cases and what they must give.
	for _, tc := range []struct {
		// text is what the system printed.
		text string
		// want is the expected first number.
		want float64
		// ok says whether it is readable.
		ok bool
	}{
		// Linux.
		{"0.52 0.58 0.59 1/466 12345\n", 0.52, true},
		// macOS.
		{"{ 1.52 1.61 1.70 }", 1.52, true},
		// Nothing.
		{"", 0, false},
		// Not a number.
		{"abc", 0, false},
		// A negative number.
		{"-1.0 2 3", 0, false},
	} { // end of the cases
		// Read it.
		got, ok := parseLoad1(tc.text)
		// Compare.
		if ok != tc.ok || (ok && got != tc.want) {
			// Report the problem.
			t.Errorf("parseLoad1(%q) = %v %v", tc.text, got, ok)
		} // end of the compare
	} // end of the loop
} // end of TestParseLoad1

// TestMemoryStatusExSize checks that the Windows structure has the size Windows expects (64 bytes), so that no real Windows machine is needed to catch a wrong field.
func TestMemoryStatusExSize(t *testing.T) {
	// binary.Size adds up the sizes of the fixed-size fields; the constant must give the same 64 bytes.
	if n := binary.Size(memoryStatusEx{}); n != 64 || memoryStatusExSize != 64 {
		// Report the problem.
		t.Errorf("memoryStatusEx is %d bytes, want 64", n)
	} // end of the size check
} // end of TestMemoryStatusExSize

// TestAvailableMemoryUsesTheReader checks that the free-memory figure of the load page comes from the memory reader, for a system that is not Linux.
func TestAvailableMemoryUsesTheReader(t *testing.T) {
	// Put the real reader back at the end.
	old := readMemInfo
	// Restore it.
	t.Cleanup(func() { readMemInfo = old })
	// A reader that reports 12 GB free.
	readMemInfo = func() (memInfo, error) { return memInfo{TotalBytes: 32e9, AvailBytes: 12e9}, nil }
	// Ask.
	if n, err := availableMemory(); err != nil || n != 12e9 {
		// Report the problem.
		t.Errorf("available = %d, %v", n, err)
	} // end of the success check
	// A reader that finds no figure.
	readMemInfo = func() (memInfo, error) { return memInfo{TotalBytes: 32e9}, nil }
	// It must be "not known".
	if _, err := availableMemory(); err == nil {
		// Report the problem.
		t.Error("a zero figure was accepted")
	} // end of the zero check
	// A reader that fails.
	readMemInfo = func() (memInfo, error) { return memInfo{}, errors.New("no reading") }
	// The reason must come through.
	if _, err := availableMemory(); err == nil || err.Error() != "no reading" {
		// Report the problem.
		t.Errorf("error = %v", err)
	} // end of the failure check
} // end of TestAvailableMemoryUsesTheReader

// TestSnapshotOnWindowsAndMacStyleReaders checks the machine snapshot when the system reports no swap, no load average and no processor name, as Windows does, and when it reports everything, as macOS does.
func TestSnapshotOnWindowsAndMacStyleReaders(t *testing.T) {
	// Remember the real readers and the graphics-card query.
	oldMem, oldCPU, oldLoad, oldGPU := readMemInfo, readCPUName, readLoad1, gpuQuery
	// Put them back at the end.
	t.Cleanup(func() { readMemInfo, readCPUName, readLoad1, gpuQuery = oldMem, oldCPU, oldLoad, oldGPU })
	// No graphics-card tool.
	gpuQuery = func(ctx context.Context) (string, error) { return "", errors.New("not installed") }
	// A Windows-style system: memory only.
	readMemInfo = func() (memInfo, error) { return memInfo{TotalBytes: 20e9, AvailBytes: 8e9}, nil }
	// A processor name from the environment.
	readCPUName = func() string { return "Intel64 Family 6" }
	// No load average.
	readLoad1 = func() float64 { return -1 }
	// Read it.
	s := snapshotMachine(context.Background(), true)
	// Memory is shown; swap and load stay "not reported".
	if s.MemTotalGB != 20 || s.MemFreeGB != 8 || s.SwapUsedGB != -1 || s.SwapTotalGB != 0 || s.Load1 != -1 || s.CPUName != "Intel64 Family 6" {
		// Report the problem.
		t.Errorf("windows style: %+v", s)
	} // end of the Windows check
	// A macOS-style system: everything.
	readMemInfo = func() (memInfo, error) {
		// All the figures.
		return memInfo{TotalBytes: 16e9, AvailBytes: 4e9, HaveSwap: true, SwapTotalBytes: 2e9, SwapUsedBytes: 1e9}, nil
	} // end of the reader
	// A load average.
	readLoad1 = func() float64 { return 1.5 }
	// Read it again.
	s = snapshotMachine(context.Background(), true)
	// All of it is shown.
	if s.MemTotalGB != 16 || s.MemFreeGB != 4 || s.SwapTotalGB != 2 || s.SwapUsedGB != 1 || s.Load1 != 1.5 {
		// Report the problem.
		t.Errorf("mac style: %+v", s)
	} // end of the macOS check
	// A system that reports no memory at all leaves the figures at zero.
	readMemInfo = func() (memInfo, error) { return memInfo{}, errors.New("no") }
	// Read it a third time.
	s = snapshotMachine(context.Background(), true)
	// Nothing is invented.
	if s.MemTotalGB != 0 || s.MemFreeGB != 0 || s.SwapUsedGB != -1 {
		// Report the problem.
		t.Errorf("no memory: %+v", s)
	} // end of the empty check
} // end of TestSnapshotOnWindowsAndMacStyleReaders
