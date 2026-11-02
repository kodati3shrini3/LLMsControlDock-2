// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// strconv turns text into numbers.
	"strconv"
	// strings splits and trims text.
	"strings"
) // end of imports

// memInfo is what the computer says about its memory, in bytes; it has the same shape on every operating system.
type memInfo struct {
	// TotalBytes is all the memory the computer has.
	TotalBytes int64
	// AvailBytes is the memory that programs can still use.
	AvailBytes int64
	// HaveSwap is true when the system reported its swap space at all.
	HaveSwap bool
	// SwapTotalBytes is the swap space in bytes.
	SwapTotalBytes int64
	// SwapUsedBytes is the swap space in use, in bytes.
	SwapUsedBytes int64
} // end of memInfo

// The three readers below are variables so that a test can replace them; the file for each operating system supplies the real one.
var (
	// readMemInfo reads the memory figures; it returns an error when the system does not report them.
	readMemInfo = osMemInfo
	// readCPUName reads the processor name; it returns empty text when the name is not known.
	readCPUName = osCPUName
	// readLoad1 reads the load average of the last minute; it returns -1 when the system has no such figure.
	readLoad1 = osLoad1
) // end of the reader variables

// memoryStatusEx has the layout of the MEMORYSTATUSEX structure that Windows fills in (documented by Microsoft for GlobalMemoryStatusEx); it is declared here, for every system, so that a test can check its size.
type memoryStatusEx struct {
	// Length must be set to the size of the structure before the call.
	Length uint32
	// MemoryLoad is the approximate percentage of memory in use.
	MemoryLoad uint32
	// TotalPhys is the physical memory in bytes.
	TotalPhys uint64
	// AvailPhys is the physical memory that is free for programs, in bytes.
	AvailPhys uint64
	// TotalPageFile is the commit limit (not used by this program).
	TotalPageFile uint64
	// AvailPageFile is the commit still available (not used by this program).
	AvailPageFile uint64
	// TotalVirtual is the size of the user part of the address space (not used).
	TotalVirtual uint64
	// AvailVirtual is the unreserved part of the address space (not used).
	AvailVirtual uint64
	// AvailExtendedVirtual is reserved and always zero.
	AvailExtendedVirtual uint64
} // end of memoryStatusEx

// memoryStatusExSize is the size of memoryStatusEx in bytes: two 4-byte numbers and seven 8-byte numbers.
const memoryStatusExSize = 2*4 + 7*8

// leadingNumber reads the whole number at the start of the text (digits only) and returns it; the second result is false when there is none.
func leadingNumber(s string) (int64, bool) {
	// Count the digits at the start.
	n := 0
	// Walk along while the characters are digits.
	for n < len(s) && s[n] >= '0' && s[n] <= '9' {
		// One more digit.
		n++
	} // end of the digit loop
	// No digits at all.
	if n == 0 {
		// Nothing to read.
		return 0, false
	} // end of the empty check
	// Turn the digits into a number.
	v, err := strconv.ParseInt(s[:n], 10, 64)
	// Too large for a number.
	if err != nil {
		// Unknown.
		return 0, false
	} // end of the number check
	// Hand it back.
	return v, true
} // end of leadingNumber

// pagesValue reads the page count of a vm_stat line such as "Pages free:      12345." and returns it.
func pagesValue(line string) (int64, bool) {
	// Everything after the colon.
	i := strings.Index(line, ":")
	// No colon: not a figure line.
	if i < 0 {
		// Unknown.
		return 0, false
	} // end of the colon check
	// The number starts after the spaces; the line ends with a full stop that leadingNumber ignores.
	return leadingNumber(strings.TrimSpace(line[i+1:]))
} // end of pagesValue

// parseVMStat reads the text printed by the macOS vm_stat tool and returns the page size in bytes and the number of free, inactive and speculative pages; ok is false when any of the four is missing.
func parseVMStat(text string) (pageSize, free, inactive, speculative int64, ok bool) {
	// Which of the four were found.
	var gotSize, gotFree, gotInactive, gotSpeculative bool
	// Look at every line.
	for _, line := range strings.Split(text, "\n") {
		// Pick the line by its start.
		switch {
		// The first line says "(page size of 16384 bytes)".
		case strings.HasPrefix(line, "Mach Virtual Memory Statistics:"):
			// Find the words before the number.
			if i := strings.Index(line, "page size of "); i >= 0 {
				// Read the number after them.
				pageSize, gotSize = leadingNumber(line[i+len("page size of "):])
			} // end of the marker check
		// The free pages.
		case strings.HasPrefix(line, "Pages free:"):
			// Read the count.
			free, gotFree = pagesValue(line)
		// The inactive pages.
		case strings.HasPrefix(line, "Pages inactive:"):
			// Read the count.
			inactive, gotInactive = pagesValue(line)
		// The speculative pages.
		case strings.HasPrefix(line, "Pages speculative:"):
			// Read the count.
			speculative, gotSpeculative = pagesValue(line)
		} // end of the line switch
	} // end of the line loop
	// All four must be there, and the page size must make sense.
	ok = gotSize && gotFree && gotInactive && gotSpeculative && pageSize > 0
	// Hand everything back.
	return pageSize, free, inactive, speculative, ok
} // end of parseVMStat

// sizeAfter finds the marker (such as "total = ") in the text and reads the size after it, like 2048.00M, into bytes; the second result is false when it is missing or unreadable.
func sizeAfter(text, marker string) (int64, bool) {
	// Find the marker.
	i := strings.Index(text, marker)
	// Not there.
	if i < 0 {
		// Unknown.
		return 0, false
	} // end of the marker check
	// The text after the marker.
	rest := text[i+len(marker):]
	// Count the characters of the number (digits and the decimal point).
	n := 0
	// Walk along them.
	for n < len(rest) && ((rest[n] >= '0' && rest[n] <= '9') || rest[n] == '.') {
		// One more character.
		n++
	} // end of the number loop
	// No number, or no unit letter after it.
	if n == 0 || n >= len(rest) {
		// Unknown.
		return 0, false
	} // end of the shape check
	// Read the number.
	v, err := strconv.ParseFloat(rest[:n], 64)
	// A bad number.
	if err != nil || v < 0 {
		// Unknown.
		return 0, false
	} // end of the number check
	// The unit letter decides the multiplier (powers of 1024).
	var mult float64
	// Pick it.
	switch rest[n] {
	// Kilobytes.
	case 'K':
		// 1024 bytes.
		mult = 1 << 10
	// Megabytes.
	case 'M':
		// 1024 times 1024 bytes.
		mult = 1 << 20
	// Gigabytes.
	case 'G':
		// 1024 cubed.
		mult = 1 << 30
	// Terabytes.
	case 'T':
		// 1024 to the fourth.
		mult = 1 << 40
	// Any other letter.
	default:
		// Unknown unit: say "unknown" instead of guessing.
		return 0, false
	} // end of the unit switch
	// The size in bytes.
	return int64(v * mult), true
} // end of sizeAfter

// parseSwapUsage reads the text printed by "sysctl vm.swapusage" on macOS, such as "total = 2048.00M  used = 1127.50M  free = 920.50M  (encrypted)", and returns the total and used swap in bytes.
func parseSwapUsage(text string) (total, used int64, ok bool) {
	// The total.
	t, okT := sizeAfter(text, "total = ")
	// The part in use.
	u, okU := sizeAfter(text, "used = ")
	// Both must be there, and the used part cannot exceed the total.
	if !okT || !okU || u > t {
		// Unknown.
		return 0, 0, false
	} // end of the check
	// Hand both back.
	return t, u, true
} // end of parseSwapUsage

// parseLoad1 reads the load average of the last minute from the text of Linux's loadavg file ("0.52 0.58 0.59 ...") or of macOS's "sysctl vm.loadavg" ("{ 1.52 1.61 1.70 }"); it returns false when there is no number.
func parseLoad1(text string) (float64, bool) {
	// Go through the words.
	for _, w := range strings.Fields(text) {
		// The macOS text starts with a curly bracket that is not a number.
		if w == "{" {
			// Next word.
			continue
		} // end of the bracket check
		// The first real word is the last minute.
		v, err := strconv.ParseFloat(w, 64)
		// Not a number, or a negative one.
		if err != nil || v < 0 {
			// Unknown.
			return 0, false
		} // end of the number check
		// Hand it back.
		return v, true
	} // end of the word loop
	// Nothing to read.
	return 0, false
} // end of parseLoad1
