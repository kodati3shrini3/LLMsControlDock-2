//go:build linux || darwin

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// syscall asks the system for the free space of the disk that holds a folder.
	"syscall"
) // end of imports

// osFreeDiskBytes returns the free space, in bytes, that a normal program can use on the disk that holds the folder.
func osFreeDiskBytes(dir string) (uint64, error) {
	// The system fills this in.
	var st syscall.Statfs_t
	// Ask about the folder; a failure is handed back.
	if err := syscall.Statfs(dir, &st); err != nil {
		// Not known.
		return 0, err
	} // end of the call check
	// Free blocks for a normal program times the size of a block.
	return uint64(st.Bavail) * uint64(st.Bsize), nil
} // end of osFreeDiskBytes
