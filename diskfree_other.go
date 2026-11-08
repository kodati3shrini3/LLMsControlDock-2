//go:build !linux && !darwin && !windows

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors makes the "not supported" error.
	"errors"
) // end of imports

// osFreeDiskBytes reports that this system has no reader; the page then asks the person to type the figure.
func osFreeDiskBytes(dir string) (uint64, error) {
	// Not known.
	return 0, errors.New("free disk space cannot be read on this system")
} // end of osFreeDiskBytes
