//go:build !windows

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors builds fixed error messages.
	"errors"
) // end of imports

// osKnownDesktop reports that the Windows Known Folders do not exist on this system.
func osKnownDesktop() (string, error) {
	// A fixed message.
	return "", errors.New("Known Folders exist on Windows only")
} // end of osKnownDesktop
