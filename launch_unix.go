//go:build !windows

// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the packages this file uses.
	// os/exec holds the command that is detached.
	"os/exec"
	// syscall holds the process settings of Linux and macOS.
	"syscall"
) // end of imports

// detach makes the command a session of its own, so it keeps running when the launcher ends.
func detach(cmd *exec.Cmd) {
	// A new session.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
} // end of detach
