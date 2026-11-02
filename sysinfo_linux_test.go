//go:build linux

// Package main tells Go that this test file belongs to the same program as sysinfo_linux.go.
package main

import ( // import lists the packages this test file uses.
	// os writes the fixture files.
	"os"
	// path/filepath joins file names.
	"path/filepath"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestLinuxReadersUseProcFiles checks the Linux readers against a folder that plays the role of /proc.
func TestLinuxReadersUseProcFiles(t *testing.T) {
	// A folder that plays the role of /proc.
	dir := t.TempDir()
	// The files.
	for name, text := range map[string]string{
		// A named processor.
		"cpuinfo": "processor\t: 0\nmodel name\t: Test Processor 9000\n",
		// A load of 0.5.
		"loadavg": "0.50 0.40 0.30 1/200 123\n",
		// 16 GB total, 8 GB free, swap 2 GB with 1 GB free (in kilobytes).
		"meminfo": "MemTotal:       16000000 kB\nMemAvailable:    8000000 kB\nSwapTotal:       2000000 kB\nSwapFree:        1000000 kB\n",
	} { // end of the files
		// Write each.
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o600); err != nil {
			// Stop the test.
			t.Fatalf("fixture: %v", err)
		} // end of the write check
	} // end of the loop
	// Use the fixtures and restore the real folder afterwards.
	old := procDir
	// Restore.
	t.Cleanup(func() { procDir = old })
	// Point at the fixtures.
	procDir = dir
	// The memory figures.
	mi, err := osMemInfo()
	// Compare (kilobytes are kibibytes: 1024 bytes).
	if err != nil || mi.TotalBytes != 16_384_000_000 || mi.AvailBytes != 8_192_000_000 || !mi.HaveSwap || mi.SwapTotalBytes != 2_048_000_000 || mi.SwapUsedBytes != 1_024_000_000 {
		// Report the problem.
		t.Errorf("osMemInfo: %+v, %v", mi, err)
	} // end of the memory check
	// The processor name.
	if n := osCPUName(); n != "Test Processor 9000" {
		// Report the problem.
		t.Errorf("osCPUName = %q", n)
	} // end of the name check
	// The load.
	if l := osLoad1(); l != 0.5 {
		// Report the problem.
		t.Errorf("osLoad1 = %v", l)
	} // end of the load check
} // end of TestLinuxReadersUseProcFiles
