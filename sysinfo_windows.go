//go:build windows

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors builds fixed error messages.
	"errors"
	// os reads the environment variable that names the processor.
	"os"
	// syscall loads kernel32.dll and calls GlobalMemoryStatusEx.
	"syscall"
	// unsafe turns the address of the structure into the number the Windows call expects; this is the only place in the program that uses it.
	"unsafe"
) // end of imports

// kernel32 is the Windows system library that holds the memory call; Windows always loads it from its own system folder.
var kernel32 = syscall.NewLazyDLL("kernel32.dll")

// procGlobalMemoryStatusEx is the call that fills a memoryStatusEx (documented by Microsoft; it exists since Windows XP).
var procGlobalMemoryStatusEx = kernel32.NewProc("GlobalMemoryStatusEx")

// osMemInfo asks Windows for the physical memory; Windows has no "swap" figure that matches the other systems, so swap is left unreported.
func osMemInfo() (memInfo, error) {
	// The structure Windows fills in; Length must hold its size.
	ms := memoryStatusEx{Length: memoryStatusExSize}
	// Make the call; passing the address as a number inside the call expression is the pattern Go documents for Windows calls.
	r, _, _ := procGlobalMemoryStatusEx.Call(uintptr(unsafe.Pointer(&ms)))
	// The call returns zero when it fails.
	if r == 0 {
		// A fixed message.
		return memInfo{}, errors.New("Windows did not report the memory")
	} // end of the result check
	// Hand back the physical memory.
	return memInfo{TotalBytes: int64(ms.TotalPhys), AvailBytes: int64(ms.AvailPhys)}, nil
} // end of osMemInfo

// osCPUName reads the processor description Windows keeps in an environment variable, such as "Intel64 Family 6 Model 142 Stepping 10, GenuineIntel"; it is empty when missing.
func osCPUName() string {
	// Read the variable.
	return os.Getenv("PROCESSOR_IDENTIFIER")
} // end of osCPUName

// osLoad1 returns -1: Windows has no load average.
func osLoad1() float64 {
	// Not available.
	return -1
} // end of osLoad1
