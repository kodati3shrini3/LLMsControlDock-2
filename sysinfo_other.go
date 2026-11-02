//go:build !linux && !windows && !darwin

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors builds fixed error messages.
	"errors"
) // end of imports

// osMemInfo reports that this system (not Linux, Windows or macOS) does not give the memory figures.
func osMemInfo() (memInfo, error) {
	// A fixed message.
	return memInfo{}, errors.New("this system does not report its free memory")
} // end of osMemInfo

// osCPUName returns empty text: the name is not known here.
func osCPUName() string {
	// Not known.
	return ""
} // end of osCPUName

// osLoad1 returns -1: the load average is not known here.
func osLoad1() float64 {
	// Not known.
	return -1
} // end of osLoad1
