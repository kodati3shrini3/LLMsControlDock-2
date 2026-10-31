//go:build windows

// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the packages this file uses.
	// os/exec holds the command that is detached.
	"os/exec"
	// syscall holds the process settings of Windows.
	"syscall"
) // end of imports

// detach makes the command a new process group without a window, so it keeps running when the launcher ends (not yet tried on Windows).
func detach(cmd *exec.Cmd) {
	// A new group (0x200) and no window (0x08000000).
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: 0x00000200 | 0x08000000}
} // end of detach
