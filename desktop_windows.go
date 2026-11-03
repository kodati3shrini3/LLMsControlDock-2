//go:build windows

// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors builds fixed error messages.
	"errors"
	// os checks that the folder exists.
	"os"
	// syscall loads the Windows libraries and holds the GUID type.
	"syscall"
	// unsafe reads the text Windows hands back; this is one of the two places that use it.
	"unsafe"
) // end of imports

// The Windows library calls used to find the Desktop folder (documented by Microsoft: SHGetKnownFolderPath returns the path of a Known Folder, and CoTaskMemFree frees the text it allocated).
var (
	// shell32 holds SHGetKnownFolderPath.
	shell32 = syscall.NewLazyDLL("shell32.dll")
	// ole32 holds CoTaskMemFree.
	ole32 = syscall.NewLazyDLL("ole32.dll")
	// procSHGetKnownFolderPath finds a Known Folder.
	procSHGetKnownFolderPath = shell32.NewProc("SHGetKnownFolderPath")
	// procCoTaskMemFree frees the text.
	procCoTaskMemFree = ole32.NewProc("CoTaskMemFree")
) // end of the library calls

// folderIDDesktop is the Known Folder ID of the Desktop, {B4BFCC3A-DB2C-424C-B029-7FE99A87C641}; it follows the person's Desktop even when Windows moved it (for example into OneDrive).
var folderIDDesktop = syscall.GUID{Data1: 0xB4BFCC3A, Data2: 0xDB2C, Data3: 0x424C, Data4: [8]byte{0xB0, 0x29, 0x7F, 0xE9, 0x9A, 0x87, 0xC6, 0x41}}

// osKnownDesktop asks Windows for the Desktop folder of the person who runs the program.
func osKnownDesktop() (string, error) {
	// Windows fills in a pointer to text that it allocated.
	var p *uint16
	// The call: the folder ID, no flags, the current person (no token), and where to put the pointer.
	r, _, _ := procSHGetKnownFolderPath.Call(uintptr(unsafe.Pointer(&folderIDDesktop)), 0, 0, uintptr(unsafe.Pointer(&p)))
	// The text must be freed, whatever the result.
	if p != nil {
		// Free it at the end.
		defer procCoTaskMemFree.Call(uintptr(unsafe.Pointer(p)))
	} // end of the free check
	// A non-zero result is a failure.
	if r != 0 || p == nil {
		// A fixed message.
		return "", errors.New("Windows did not report the Desktop folder")
	} // end of the result check
	// Read the text up to its end (at most 32,768 characters, the longest path Windows allows).
	var chars []uint16
	// Walk along it.
	for i := 0; i < 32768; i++ {
		// The next character.
		c := *(*uint16)(unsafe.Add(unsafe.Pointer(p), i*2))
		// The end.
		if c == 0 {
			// Stop.
			break
		} // end of the end check
		// Keep it.
		chars = append(chars, c)
	} // end of the walk
	// Make a Go string.
	dir := syscall.UTF16ToString(chars)
	// It must be a folder that exists.
	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
		// A fixed message.
		return "", errors.New("the Desktop folder does not exist")
	} // end of the folder check
	// Found.
	return dir, nil
} // end of osKnownDesktop
