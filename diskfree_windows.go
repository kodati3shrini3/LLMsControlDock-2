//go:build windows

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// syscall loads the Windows library function and converts the folder name.
	"syscall"
	// unsafe passes the address of a number to the Windows function.
	"unsafe"
) // end of imports

// getDiskFreeSpaceEx is the Windows function GetDiskFreeSpaceExW (documented by Microsoft in kernel32), loaded when first used.
var getDiskFreeSpaceEx = syscall.NewLazyDLL("kernel32.dll").NewProc("GetDiskFreeSpaceExW")

// osFreeDiskBytes returns the free space, in bytes, that the current user can use on the disk that holds the folder.
func osFreeDiskBytes(dir string) (uint64, error) {
	// Windows wants the folder name as UTF-16.
	p, err := syscall.UTF16PtrFromString(dir)
	// A name with a zero character cannot be converted.
	if err != nil {
		// Not known.
		return 0, err
	} // end of the name check
	// The three numbers the function fills in: free for this user, total, and total free.
	var free, total, totalFree uint64
	// Call it.
	r, _, callErr := getDiskFreeSpaceEx.Call(uintptr(unsafe.Pointer(p)), uintptr(unsafe.Pointer(&free)), uintptr(unsafe.Pointer(&total)), uintptr(unsafe.Pointer(&totalFree)))
	// A zero result means failure.
	if r == 0 {
		// Not known.
		return 0, callErr
	} // end of the result check
	// The space this user can use.
	return free, nil
} // end of osFreeDiskBytes
