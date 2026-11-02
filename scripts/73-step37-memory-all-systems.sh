#!/usr/bin/env bash
# Script 73: free memory, total memory, swap, load average and processor name now work on Linux, Windows 10 and later, and macOS (before, only Linux had them). Windows uses the Microsoft call GlobalMemoryStatusEx; macOS uses the tools sysctl and vm_stat that come with it. Linux works as before. The version becomes 0.24.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/memory-all-systems" ] || { echo "FAIL  not on feature/memory-all-systems"; exit 1; }
# Refuse to run twice.
if [ -e sysinfo.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index 05e6252..bb8c05e 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.23.0"
+const appVersion = "0.24.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/machine.go b/machine.go
index 244d5b9..6e8aa06 100644
--- a/machine.go
+++ b/machine.go
@@ -6,12 +6,8 @@ import ( // import lists the standard-library packages this file uses.
 	"context"
 	// net/url holds the parsed address type.
 	"net/url"
-	// os reads the files that describe the machine.
-	"os"
 	// os/exec runs the graphics-card tool, only when it is already installed.
 	"os/exec"
-	// path/filepath joins the folder and file names.
-	"path/filepath"
 	// runtime tells how many processor cores there are.
 	"runtime"
 	// strconv turns text into numbers.
@@ -50,7 +46,7 @@ type machineSnapshot struct {
 	GPUUtil int `json:"gpu_util"`
 } // end of machineSnapshot
 
-// procDir is where Linux describes the machine; a test points it at a folder of its own.
+// procDir is where Linux describes the machine (used only by the Linux reader in sysinfo_linux.go); a test points it at a folder of its own.
 var procDir = "/proc"
 
 // gpuQuery asks the graphics-card tool for one CSV line; a test replaces it. The tool is never required.
@@ -80,36 +76,6 @@ func isLocalAddress(u *url.URL) bool {
 	return h == "127.0.0.1" || h == "localhost" || h == "::1"
 } // end of isLocalAddress
 
-// readKB reads the memory table of /proc/meminfo into a map of kilobytes.
-func readKB() map[string]float64 {
-	// The result.
-	out := map[string]float64{}
-	// Read the file; a missing file gives an empty table.
-	data, err := os.ReadFile(filepath.Join(procDir, "meminfo"))
-	// Not readable.
-	if err != nil {
-		// Nothing to report.
-		return out
-	} // end of the read check
-	// Go through the lines.
-	for _, line := range strings.Split(string(data), "\n") {
-		// A line looks like "MemTotal:  127000 kB".
-		f := strings.Fields(line)
-		// Skip lines of another shape.
-		if len(f) < 2 {
-			// Next line.
-			continue
-		} // end of the shape check
-		// Read the number.
-		if v, err := strconv.ParseFloat(f[1], 64); err == nil {
-			// Store it under the name without the colon.
-			out[strings.TrimSuffix(f[0], ":")] = v
-		} // end of the number check
-	} // end of the loop
-	// Hand back the table.
-	return out
-} // end of readKB
-
 // snapshotMachine reads what the machine says about itself; for Ollama on another computer it reports only that.
 func snapshotMachine(ctx context.Context, local bool) machineSnapshot {
 	// Start with "not reported" values.
@@ -123,44 +89,23 @@ func snapshotMachine(ctx context.Context, local bool) machineSnapshot {
 	} // end of the remote case
 	// The processor count is always known.
 	s.Cores = runtime.NumCPU()
-	// The processor name, when Linux lists one.
-	if data, err := os.ReadFile(filepath.Join(procDir, "cpuinfo")); err == nil {
-		// Look for the first "model name" line.
-		for _, line := range strings.Split(string(data), "\n") {
-			// Found.
-			if strings.HasPrefix(strings.ToLower(line), "model name") {
-				// Keep the text after the colon.
-				if i := strings.Index(line, ":"); i >= 0 {
-					// Trim spaces.
-					s.CPUName = strings.TrimSpace(line[i+1:])
-				} // end of the colon check
-				// Only the first one.
-				break
-			} // end of the name check
-		} // end of the loop
-	} // end of the cpuinfo read
-	// The load average: the first number is the last minute.
-	if data, err := os.ReadFile(filepath.Join(procDir, "loadavg")); err == nil {
-		// Split into numbers.
-		if f := strings.Fields(string(data)); len(f) > 0 {
-			// Read the first.
-			if v, err := strconv.ParseFloat(f[0], 64); err == nil {
-				// Keep it.
-				s.Load1 = v
-			} // end of the number check
-		} // end of the field check
-	} // end of the loadavg read
-	// Memory in kilobytes (1024 bytes each); gigabytes are decimal, like every size the monitor shows (1 GB = 1,000,000,000 bytes).
-	kb := readKB()
-	// Total and available memory.
-	s.MemTotalGB, s.MemFreeGB = kb["MemTotal"]*1024/1e9, kb["MemAvailable"]*1024/1e9
-	// Swap, only when the machine reports a swap total at all.
-	if t, ok := kb["SwapTotal"]; ok {
-		// Total swap.
-		s.SwapTotalGB = t * 1024 / 1e9
-		// Swap in use is total minus free.
-		s.SwapUsedGB = (t - kb["SwapFree"]) * 1024 / 1e9
-	} // end of the swap check
+	// The processor name, when the system gives one.
+	s.CPUName = readCPUName()
+	// The load average of the last minute, when the system has one (Windows has none).
+	if v := readLoad1(); v >= 0 {
+		// Keep it.
+		s.Load1 = v
+	} // end of the load check
+	// The memory figures, read the same way on every system; gigabytes are decimal, like every size the monitor shows (1 GB = 1,000,000,000 bytes).
+	if mi, err := readMemInfo(); err == nil {
+		// Total and available memory.
+		s.MemTotalGB, s.MemFreeGB = float64(mi.TotalBytes)/1e9, float64(mi.AvailBytes)/1e9
+		// Swap, only when the system reported it.
+		if mi.HaveSwap {
+			// Total swap and the part in use.
+			s.SwapTotalGB, s.SwapUsedGB = float64(mi.SwapTotalBytes)/1e9, float64(mi.SwapUsedBytes)/1e9
+		} // end of the swap check
+	} // end of the memory check
 	// The graphics card, when its own tool is already on the machine.
 	if line, err := gpuQuery(ctx); err == nil && line != "" {
 		// The line is "name, memory used, memory total, utilization".
diff --git a/memory.go b/memory.go
index 527b880..157fcc4 100644
--- a/memory.go
+++ b/memory.go
@@ -6,17 +6,12 @@ import ( // import lists the standard-library packages this file uses.
 	"errors"
 	// net/url holds the parsed address type.
 	"net/url"
-	// os reads files.
-	"os"
 	// strconv turns the number text into a number.
 	"strconv"
 	// strings splits the file into lines.
 	"strings"
 ) // end of imports
 
-// meminfoPath is the Linux file that lists the computer's memory.
-const meminfoPath = "/proc/meminfo"
-
 // availableMemoryFunc reads the free memory; it is a variable so tests can replace it.
 var availableMemoryFunc = availableMemory
 
@@ -50,24 +45,22 @@ func parseMemAvailable(text string) (int64, bool) {
 	return 0, false
 } // end of parseMemAvailable
 
-// availableMemory returns how much memory programs can still use on this computer, in bytes (Linux only; other systems report an error).
+// availableMemory returns how much memory programs can still use on this computer, in bytes (Linux, Windows and macOS; other systems report an error).
 func availableMemory() (int64, error) {
-	// Read the file; on systems without it this fails, which is reported as unknown.
-	data, err := os.ReadFile(meminfoPath)
-	// No file.
+	// Read the figures the same way on every system.
+	mi, err := readMemInfo()
+	// The system did not report them.
 	if err != nil {
-		// A fixed message.
-		return 0, errors.New("this system does not report its free memory")
+		// Hand the reason back.
+		return 0, err
 	} // end of the read check
-	// Find the value.
-	n, ok := parseMemAvailable(string(data))
-	// Not found.
-	if !ok {
+	// A zero or negative figure means the value was not found.
+	if mi.AvailBytes <= 0 {
 		// A fixed message.
 		return 0, errors.New("the free memory could not be read")
-	} // end of the parse check
+	} // end of the value check
 	// Hand it back.
-	return n, nil
+	return mi.AvailBytes, nil
 } // end of availableMemory
 
 // ollamaIsLocal says whether the monitored Ollama runs on this same computer, so that this computer's free memory is the right number to show.
diff --git a/sysinfo.go b/sysinfo.go
new file mode 100644
index 0000000..b085e20
--- /dev/null
+++ b/sysinfo.go
@@ -0,0 +1,228 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// strconv turns text into numbers.
+	"strconv"
+	// strings splits and trims text.
+	"strings"
+) // end of imports
+
+// memInfo is what the computer says about its memory, in bytes; it has the same shape on every operating system.
+type memInfo struct {
+	// TotalBytes is all the memory the computer has.
+	TotalBytes int64
+	// AvailBytes is the memory that programs can still use.
+	AvailBytes int64
+	// HaveSwap is true when the system reported its swap space at all.
+	HaveSwap bool
+	// SwapTotalBytes is the swap space in bytes.
+	SwapTotalBytes int64
+	// SwapUsedBytes is the swap space in use, in bytes.
+	SwapUsedBytes int64
+} // end of memInfo
+
+// The three readers below are variables so that a test can replace them; the file for each operating system supplies the real one.
+var (
+	// readMemInfo reads the memory figures; it returns an error when the system does not report them.
+	readMemInfo = osMemInfo
+	// readCPUName reads the processor name; it returns empty text when the name is not known.
+	readCPUName = osCPUName
+	// readLoad1 reads the load average of the last minute; it returns -1 when the system has no such figure.
+	readLoad1 = osLoad1
+) // end of the reader variables
+
+// memoryStatusEx has the layout of the MEMORYSTATUSEX structure that Windows fills in (documented by Microsoft for GlobalMemoryStatusEx); it is declared here, for every system, so that a test can check its size.
+type memoryStatusEx struct {
+	// Length must be set to the size of the structure before the call.
+	Length uint32
+	// MemoryLoad is the approximate percentage of memory in use.
+	MemoryLoad uint32
+	// TotalPhys is the physical memory in bytes.
+	TotalPhys uint64
+	// AvailPhys is the physical memory that is free for programs, in bytes.
+	AvailPhys uint64
+	// TotalPageFile is the commit limit (not used by this program).
+	TotalPageFile uint64
+	// AvailPageFile is the commit still available (not used by this program).
+	AvailPageFile uint64
+	// TotalVirtual is the size of the user part of the address space (not used).
+	TotalVirtual uint64
+	// AvailVirtual is the unreserved part of the address space (not used).
+	AvailVirtual uint64
+	// AvailExtendedVirtual is reserved and always zero.
+	AvailExtendedVirtual uint64
+} // end of memoryStatusEx
+
+// memoryStatusExSize is the size of memoryStatusEx in bytes: two 4-byte numbers and seven 8-byte numbers.
+const memoryStatusExSize = 2*4 + 7*8
+
+// leadingNumber reads the whole number at the start of the text (digits only) and returns it; the second result is false when there is none.
+func leadingNumber(s string) (int64, bool) {
+	// Count the digits at the start.
+	n := 0
+	// Walk along while the characters are digits.
+	for n < len(s) && s[n] >= '0' && s[n] <= '9' {
+		// One more digit.
+		n++
+	} // end of the digit loop
+	// No digits at all.
+	if n == 0 {
+		// Nothing to read.
+		return 0, false
+	} // end of the empty check
+	// Turn the digits into a number.
+	v, err := strconv.ParseInt(s[:n], 10, 64)
+	// Too large for a number.
+	if err != nil {
+		// Unknown.
+		return 0, false
+	} // end of the number check
+	// Hand it back.
+	return v, true
+} // end of leadingNumber
+
+// pagesValue reads the page count of a vm_stat line such as "Pages free:      12345." and returns it.
+func pagesValue(line string) (int64, bool) {
+	// Everything after the colon.
+	i := strings.Index(line, ":")
+	// No colon: not a figure line.
+	if i < 0 {
+		// Unknown.
+		return 0, false
+	} // end of the colon check
+	// The number starts after the spaces; the line ends with a full stop that leadingNumber ignores.
+	return leadingNumber(strings.TrimSpace(line[i+1:]))
+} // end of pagesValue
+
+// parseVMStat reads the text printed by the macOS vm_stat tool and returns the page size in bytes and the number of free, inactive and speculative pages; ok is false when any of the four is missing.
+func parseVMStat(text string) (pageSize, free, inactive, speculative int64, ok bool) {
+	// Which of the four were found.
+	var gotSize, gotFree, gotInactive, gotSpeculative bool
+	// Look at every line.
+	for _, line := range strings.Split(text, "\n") {
+		// Pick the line by its start.
+		switch {
+		// The first line says "(page size of 16384 bytes)".
+		case strings.HasPrefix(line, "Mach Virtual Memory Statistics:"):
+			// Find the words before the number.
+			if i := strings.Index(line, "page size of "); i >= 0 {
+				// Read the number after them.
+				pageSize, gotSize = leadingNumber(line[i+len("page size of "):])
+			} // end of the marker check
+		// The free pages.
+		case strings.HasPrefix(line, "Pages free:"):
+			// Read the count.
+			free, gotFree = pagesValue(line)
+		// The inactive pages.
+		case strings.HasPrefix(line, "Pages inactive:"):
+			// Read the count.
+			inactive, gotInactive = pagesValue(line)
+		// The speculative pages.
+		case strings.HasPrefix(line, "Pages speculative:"):
+			// Read the count.
+			speculative, gotSpeculative = pagesValue(line)
+		} // end of the line switch
+	} // end of the line loop
+	// All four must be there, and the page size must make sense.
+	ok = gotSize && gotFree && gotInactive && gotSpeculative && pageSize > 0
+	// Hand everything back.
+	return pageSize, free, inactive, speculative, ok
+} // end of parseVMStat
+
+// sizeAfter finds the marker (such as "total = ") in the text and reads the size after it, like 2048.00M, into bytes; the second result is false when it is missing or unreadable.
+func sizeAfter(text, marker string) (int64, bool) {
+	// Find the marker.
+	i := strings.Index(text, marker)
+	// Not there.
+	if i < 0 {
+		// Unknown.
+		return 0, false
+	} // end of the marker check
+	// The text after the marker.
+	rest := text[i+len(marker):]
+	// Count the characters of the number (digits and the decimal point).
+	n := 0
+	// Walk along them.
+	for n < len(rest) && ((rest[n] >= '0' && rest[n] <= '9') || rest[n] == '.') {
+		// One more character.
+		n++
+	} // end of the number loop
+	// No number, or no unit letter after it.
+	if n == 0 || n >= len(rest) {
+		// Unknown.
+		return 0, false
+	} // end of the shape check
+	// Read the number.
+	v, err := strconv.ParseFloat(rest[:n], 64)
+	// A bad number.
+	if err != nil || v < 0 {
+		// Unknown.
+		return 0, false
+	} // end of the number check
+	// The unit letter decides the multiplier (powers of 1024).
+	var mult float64
+	// Pick it.
+	switch rest[n] {
+	// Kilobytes.
+	case 'K':
+		// 1024 bytes.
+		mult = 1 << 10
+	// Megabytes.
+	case 'M':
+		// 1024 times 1024 bytes.
+		mult = 1 << 20
+	// Gigabytes.
+	case 'G':
+		// 1024 cubed.
+		mult = 1 << 30
+	// Terabytes.
+	case 'T':
+		// 1024 to the fourth.
+		mult = 1 << 40
+	// Any other letter.
+	default:
+		// Unknown unit: say "unknown" instead of guessing.
+		return 0, false
+	} // end of the unit switch
+	// The size in bytes.
+	return int64(v * mult), true
+} // end of sizeAfter
+
+// parseSwapUsage reads the text printed by "sysctl vm.swapusage" on macOS, such as "total = 2048.00M  used = 1127.50M  free = 920.50M  (encrypted)", and returns the total and used swap in bytes.
+func parseSwapUsage(text string) (total, used int64, ok bool) {
+	// The total.
+	t, okT := sizeAfter(text, "total = ")
+	// The part in use.
+	u, okU := sizeAfter(text, "used = ")
+	// Both must be there, and the used part cannot exceed the total.
+	if !okT || !okU || u > t {
+		// Unknown.
+		return 0, 0, false
+	} // end of the check
+	// Hand both back.
+	return t, u, true
+} // end of parseSwapUsage
+
+// parseLoad1 reads the load average of the last minute from the text of Linux's loadavg file ("0.52 0.58 0.59 ...") or of macOS's "sysctl vm.loadavg" ("{ 1.52 1.61 1.70 }"); it returns false when there is no number.
+func parseLoad1(text string) (float64, bool) {
+	// Go through the words.
+	for _, w := range strings.Fields(text) {
+		// The macOS text starts with a curly bracket that is not a number.
+		if w == "{" {
+			// Next word.
+			continue
+		} // end of the bracket check
+		// The first real word is the last minute.
+		v, err := strconv.ParseFloat(w, 64)
+		// Not a number, or a negative one.
+		if err != nil || v < 0 {
+			// Unknown.
+			return 0, false
+		} // end of the number check
+		// Hand it back.
+		return v, true
+	} // end of the word loop
+	// Nothing to read.
+	return 0, false
+} // end of parseLoad1
diff --git a/sysinfo_darwin.go b/sysinfo_darwin.go
new file mode 100644
index 0000000..5e65bdb
--- /dev/null
+++ b/sysinfo_darwin.go
@@ -0,0 +1,114 @@
+//go:build darwin
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context limits how long a tool may run.
+	"context"
+	// errors builds fixed error messages.
+	"errors"
+	// os/exec runs the two tools that ship with macOS.
+	"os/exec"
+	// strconv turns text into numbers.
+	"strconv"
+	// strings trims the text the tools print.
+	"strings"
+	// time sets the limit.
+	"time"
+) // end of imports
+
+// The two tools below ship with macOS; their full paths are used so that no other program with the same name is ever run.
+const (
+	// sysctlPath is the tool that reads system values.
+	sysctlPath = "/usr/sbin/sysctl"
+	// vmStatPath is the tool that prints the virtual-memory page counts.
+	vmStatPath = "/usr/bin/vm_stat"
+) // end of the tool paths
+
+// runTool runs one of the tools with fixed arguments (nothing typed by a person reaches it) and returns what it printed; it never waits more than three seconds.
+func runTool(path string, args ...string) (string, error) {
+	// Never wait long.
+	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
+	// Release the timer at the end.
+	defer cancel()
+	// Run it and collect its output.
+	out, err := exec.CommandContext(ctx, path, args...).Output()
+	// Hand back the trimmed text and any error.
+	return strings.TrimSpace(string(out)), err
+} // end of runTool
+
+// osMemInfo reads the memory figures with sysctl and vm_stat; "available" is an estimate: the free, inactive and speculative pages, which macOS can hand to a program at once.
+func osMemInfo() (memInfo, error) {
+	// The total memory in bytes.
+	out, err := runTool(sysctlPath, "-n", "hw.memsize")
+	// The tool failed.
+	if err != nil {
+		// A fixed message.
+		return memInfo{}, errors.New("this system did not report its memory")
+	} // end of the total check
+	// Read the number.
+	total, err := strconv.ParseInt(out, 10, 64)
+	// Not a number.
+	if err != nil || total <= 0 {
+		// A fixed message.
+		return memInfo{}, errors.New("the total memory could not be read")
+	} // end of the number check
+	// The page counts.
+	out, err = runTool(vmStatPath)
+	// The tool failed.
+	if err != nil {
+		// A fixed message.
+		return memInfo{}, errors.New("the free memory could not be read")
+	} // end of the vm_stat check
+	// Read the four figures.
+	page, free, inactive, speculative, ok := parseVMStat(out)
+	// An unknown layout.
+	if !ok {
+		// A fixed message.
+		return memInfo{}, errors.New("the free memory could not be read")
+	} // end of the layout check
+	// The estimate in bytes.
+	mi := memInfo{TotalBytes: total, AvailBytes: (free + inactive + speculative) * page}
+	// The swap, when the tool reports it.
+	if out, err = runTool(sysctlPath, "-n", "vm.swapusage"); err == nil {
+		// Read the two sizes.
+		if t, u, ok := parseSwapUsage(out); ok {
+			// It was reported.
+			mi.HaveSwap, mi.SwapTotalBytes, mi.SwapUsedBytes = true, t, u
+		} // end of the swap check
+	} // end of the swap tool
+	// Hand it back.
+	return mi, nil
+} // end of osMemInfo
+
+// osCPUName reads the processor name, such as "Apple M2" or an Intel name; it is empty when not known.
+func osCPUName() string {
+	// Ask sysctl.
+	out, err := runTool(sysctlPath, "-n", "machdep.cpu.brand_string")
+	// The tool failed.
+	if err != nil {
+		// Not known.
+		return ""
+	} // end of the check
+	// The name.
+	return out
+} // end of osCPUName
+
+// osLoad1 reads the one-minute load average from "sysctl vm.loadavg", or returns -1.
+func osLoad1() float64 {
+	// Ask sysctl.
+	out, err := runTool(sysctlPath, "-n", "vm.loadavg")
+	// The tool failed.
+	if err != nil {
+		// Not known.
+		return -1
+	} // end of the check
+	// Read the first number.
+	if v, ok := parseLoad1(out); ok {
+		// Keep it.
+		return v
+	} // end of the number check
+	// Unreadable.
+	return -1
+} // end of osLoad1
diff --git a/sysinfo_linux.go b/sysinfo_linux.go
new file mode 100644
index 0000000..0acd1a4
--- /dev/null
+++ b/sysinfo_linux.go
@@ -0,0 +1,117 @@
+//go:build linux
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// errors builds fixed error messages.
+	"errors"
+	// os reads the files under /proc.
+	"os"
+	// path/filepath joins the folder and file names.
+	"path/filepath"
+	// strconv turns text into numbers.
+	"strconv"
+	// strings splits and trims text.
+	"strings"
+) // end of imports
+
+// readKB reads the memory table of /proc/meminfo into a map of kilobytes.
+func readKB(text string) map[string]float64 {
+	// The result.
+	out := map[string]float64{}
+	// Go through the lines.
+	for _, line := range strings.Split(text, "\n") {
+		// A line looks like "MemTotal:  127000 kB".
+		f := strings.Fields(line)
+		// Skip lines of another shape.
+		if len(f) < 2 {
+			// Next line.
+			continue
+		} // end of the shape check
+		// Read the number.
+		if v, err := strconv.ParseFloat(f[1], 64); err == nil {
+			// Store it under the name without the colon.
+			out[strings.TrimSuffix(f[0], ":")] = v
+		} // end of the number check
+	} // end of the loop
+	// Hand back the table.
+	return out
+} // end of readKB
+
+// osMemInfo reads the memory figures from /proc/meminfo (the folder is procDir so that a test can point it elsewhere).
+func osMemInfo() (memInfo, error) {
+	// Read the file.
+	data, err := os.ReadFile(filepath.Join(procDir, "meminfo"))
+	// Not readable.
+	if err != nil {
+		// A fixed message.
+		return memInfo{}, errors.New("this system does not report its free memory")
+	} // end of the read check
+	// The text and the table made from it.
+	text := string(data)
+	// The table, in kilobytes.
+	kb := readKB(text)
+	// The total is in kibibytes (1024 bytes each).
+	mi := memInfo{TotalBytes: int64(kb["MemTotal"]) * 1024}
+	// The free part, read strictly: an unknown layout counts as "not known".
+	if n, ok := parseMemAvailable(text); ok {
+		// Keep it.
+		mi.AvailBytes = n
+	} // end of the available check
+	// Swap, only when the machine reports a swap total at all.
+	if t, ok := kb["SwapTotal"]; ok {
+		// It was reported.
+		mi.HaveSwap = true
+		// Total swap.
+		mi.SwapTotalBytes = int64(t) * 1024
+		// Swap in use is total minus free.
+		mi.SwapUsedBytes = int64(t-kb["SwapFree"]) * 1024
+	} // end of the swap check
+	// Hand it back.
+	return mi, nil
+} // end of osMemInfo
+
+// osCPUName reads the processor name from /proc/cpuinfo, or returns empty text.
+func osCPUName() string {
+	// Read the file.
+	data, err := os.ReadFile(filepath.Join(procDir, "cpuinfo"))
+	// Not readable.
+	if err != nil {
+		// Not known.
+		return ""
+	} // end of the read check
+	// Look for the first "model name" line.
+	for _, line := range strings.Split(string(data), "\n") {
+		// Found.
+		if strings.HasPrefix(strings.ToLower(line), "model name") {
+			// Keep the text after the colon.
+			if i := strings.Index(line, ":"); i >= 0 {
+				// Trim spaces.
+				return strings.TrimSpace(line[i+1:])
+			} // end of the colon check
+			// A line without a colon: stop looking.
+			return ""
+		} // end of the name check
+	} // end of the loop
+	// Not listed (some ARM machines).
+	return ""
+} // end of osCPUName
+
+// osLoad1 reads the one-minute load average from /proc/loadavg, or returns -1.
+func osLoad1() float64 {
+	// Read the file.
+	data, err := os.ReadFile(filepath.Join(procDir, "loadavg"))
+	// Not readable.
+	if err != nil {
+		// Not known.
+		return -1
+	} // end of the read check
+	// Read the first number.
+	if v, ok := parseLoad1(string(data)); ok {
+		// Keep it.
+		return v
+	} // end of the number check
+	// Unreadable.
+	return -1
+} // end of osLoad1
diff --git a/sysinfo_other.go b/sysinfo_other.go
new file mode 100644
index 0000000..e119c5e
--- /dev/null
+++ b/sysinfo_other.go
@@ -0,0 +1,27 @@
+//go:build !linux && !windows && !darwin
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// errors builds fixed error messages.
+	"errors"
+) // end of imports
+
+// osMemInfo reports that this system (not Linux, Windows or macOS) does not give the memory figures.
+func osMemInfo() (memInfo, error) {
+	// A fixed message.
+	return memInfo{}, errors.New("this system does not report its free memory")
+} // end of osMemInfo
+
+// osCPUName returns empty text: the name is not known here.
+func osCPUName() string {
+	// Not known.
+	return ""
+} // end of osCPUName
+
+// osLoad1 returns -1: the load average is not known here.
+func osLoad1() float64 {
+	// Not known.
+	return -1
+} // end of osLoad1
diff --git a/sysinfo_test.go b/sysinfo_test.go
new file mode 100644
index 0000000..a84ab9b
--- /dev/null
+++ b/sysinfo_test.go
@@ -0,0 +1,211 @@
+// Package main tells Go that this test file belongs to the same program as sysinfo.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// context is needed by the snapshot call.
+	"context"
+	// encoding/binary measures the size of the Windows structure.
+	"encoding/binary"
+	// errors builds the "not reported" error.
+	"errors"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// macVMStat is a vm_stat text as an Apple Silicon Mac prints it (16 KiB pages).
+const macVMStat = `Mach Virtual Memory Statistics: (page size of 16384 bytes)
+Pages free:                               12345.
+Pages active:                            200000.
+Pages inactive:                          190000.
+Pages speculative:                         5000.
+Pages throttled:                              0.
+Pages wired down:                         90000.
+`
+
+// TestParseVMStat checks the macOS page counts, including a layout that is not understood.
+func TestParseVMStat(t *testing.T) {
+	// The normal text.
+	page, free, inactive, spec, ok := parseVMStat(macVMStat)
+	// All four figures must come out right.
+	if !ok || page != 16384 || free != 12345 || inactive != 190000 || spec != 5000 {
+		// Report the problem.
+		t.Errorf("vm_stat: %d %d %d %d %v", page, free, inactive, spec, ok)
+	} // end of the figures check
+	// An Intel Mac prints 4096-byte pages.
+	if p, _, _, _, ok := parseVMStat("Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: 1.\nPages inactive: 2.\nPages speculative: 3.\n"); !ok || p != 4096 {
+		// Report the problem.
+		t.Errorf("intel page size: %d %v", p, ok)
+	} // end of the Intel check
+	// Texts that must give "not known".
+	for _, bad := range []string{
+		// Nothing at all.
+		"",
+		// The page size is missing.
+		"Pages free: 1.\nPages inactive: 2.\nPages speculative: 3.\n",
+		// One line is missing.
+		"Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: 1.\nPages inactive: 2.\n",
+		// A number is missing.
+		"Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: x.\nPages inactive: 2.\nPages speculative: 3.\n",
+		// A page size of zero.
+		"Mach Virtual Memory Statistics: (page size of 0 bytes)\nPages free: 1.\nPages inactive: 2.\nPages speculative: 3.\n",
+	} { // end of the bad texts
+		// It must not be accepted.
+		if _, _, _, _, ok := parseVMStat(bad); ok {
+			// Report the problem.
+			t.Errorf("accepted: %q", bad)
+		} // end of the check
+	} // end of the loop
+} // end of TestParseVMStat
+
+// TestParseSwapUsage checks the macOS swap text, in megabytes and in gigabytes, and the unreadable cases.
+func TestParseSwapUsage(t *testing.T) {
+	// The usual text.
+	total, used, ok := parseSwapUsage("total = 2048.00M  used = 1127.50M  free = 920.50M  (encrypted)")
+	// 2048 MiB and 1127.5 MiB.
+	if !ok || total != 2048<<20 || used != 1127<<20+512<<10 {
+		// Report the problem.
+		t.Errorf("swap in megabytes: %d %d %v", total, used, ok)
+	} // end of the megabyte check
+	// A text in gigabytes.
+	total, used, ok = parseSwapUsage("total = 4.00G  used = 0.50G  free = 3.50G  (encrypted)")
+	// 4 GiB and half a GiB.
+	if !ok || total != 4<<30 || used != 1<<29 {
+		// Report the problem.
+		t.Errorf("swap in gigabytes: %d %d %v", total, used, ok)
+	} // end of the gigabyte check
+	// Texts that must give "not known".
+	for _, bad := range []string{
+		// Nothing.
+		"",
+		// Used is missing.
+		"total = 2048.00M",
+		// An unknown unit.
+		"total = 2048.00X  used = 1.00X",
+		// Used is more than the total.
+		"total = 1.00M  used = 2.00M",
+		// No unit letter at all.
+		"total = 2048.00  used = 1.00",
+	} { // end of the bad texts
+		// It must not be accepted.
+		if _, _, ok := parseSwapUsage(bad); ok {
+			// Report the problem.
+			t.Errorf("accepted: %q", bad)
+		} // end of the check
+	} // end of the loop
+} // end of TestParseSwapUsage
+
+// TestParseLoad1 checks the Linux and the macOS load average texts.
+func TestParseLoad1(t *testing.T) {
+	// The cases and what they must give.
+	for _, tc := range []struct {
+		// text is what the system printed.
+		text string
+		// want is the expected first number.
+		want float64
+		// ok says whether it is readable.
+		ok bool
+	}{
+		// Linux.
+		{"0.52 0.58 0.59 1/466 12345\n", 0.52, true},
+		// macOS.
+		{"{ 1.52 1.61 1.70 }", 1.52, true},
+		// Nothing.
+		{"", 0, false},
+		// Not a number.
+		{"abc", 0, false},
+		// A negative number.
+		{"-1.0 2 3", 0, false},
+	} { // end of the cases
+		// Read it.
+		got, ok := parseLoad1(tc.text)
+		// Compare.
+		if ok != tc.ok || (ok && got != tc.want) {
+			// Report the problem.
+			t.Errorf("parseLoad1(%q) = %v %v", tc.text, got, ok)
+		} // end of the compare
+	} // end of the loop
+} // end of TestParseLoad1
+
+// TestMemoryStatusExSize checks that the Windows structure has the size Windows expects (64 bytes), so that no real Windows machine is needed to catch a wrong field.
+func TestMemoryStatusExSize(t *testing.T) {
+	// binary.Size adds up the sizes of the fixed-size fields; the constant must give the same 64 bytes.
+	if n := binary.Size(memoryStatusEx{}); n != 64 || memoryStatusExSize != 64 {
+		// Report the problem.
+		t.Errorf("memoryStatusEx is %d bytes, want 64", n)
+	} // end of the size check
+} // end of TestMemoryStatusExSize
+
+// TestAvailableMemoryUsesTheReader checks that the free-memory figure of the load page comes from the memory reader, for a system that is not Linux.
+func TestAvailableMemoryUsesTheReader(t *testing.T) {
+	// Put the real reader back at the end.
+	old := readMemInfo
+	// Restore it.
+	t.Cleanup(func() { readMemInfo = old })
+	// A reader that reports 12 GB free.
+	readMemInfo = func() (memInfo, error) { return memInfo{TotalBytes: 32e9, AvailBytes: 12e9}, nil }
+	// Ask.
+	if n, err := availableMemory(); err != nil || n != 12e9 {
+		// Report the problem.
+		t.Errorf("available = %d, %v", n, err)
+	} // end of the success check
+	// A reader that finds no figure.
+	readMemInfo = func() (memInfo, error) { return memInfo{TotalBytes: 32e9}, nil }
+	// It must be "not known".
+	if _, err := availableMemory(); err == nil {
+		// Report the problem.
+		t.Error("a zero figure was accepted")
+	} // end of the zero check
+	// A reader that fails.
+	readMemInfo = func() (memInfo, error) { return memInfo{}, errors.New("no reading") }
+	// The reason must come through.
+	if _, err := availableMemory(); err == nil || err.Error() != "no reading" {
+		// Report the problem.
+		t.Errorf("error = %v", err)
+	} // end of the failure check
+} // end of TestAvailableMemoryUsesTheReader
+
+// TestSnapshotOnWindowsAndMacStyleReaders checks the machine snapshot when the system reports no swap, no load average and no processor name, as Windows does, and when it reports everything, as macOS does.
+func TestSnapshotOnWindowsAndMacStyleReaders(t *testing.T) {
+	// Remember the real readers and the graphics-card query.
+	oldMem, oldCPU, oldLoad, oldGPU := readMemInfo, readCPUName, readLoad1, gpuQuery
+	// Put them back at the end.
+	t.Cleanup(func() { readMemInfo, readCPUName, readLoad1, gpuQuery = oldMem, oldCPU, oldLoad, oldGPU })
+	// No graphics-card tool.
+	gpuQuery = func(ctx context.Context) (string, error) { return "", errors.New("not installed") }
+	// A Windows-style system: memory only.
+	readMemInfo = func() (memInfo, error) { return memInfo{TotalBytes: 20e9, AvailBytes: 8e9}, nil }
+	// A processor name from the environment.
+	readCPUName = func() string { return "Intel64 Family 6" }
+	// No load average.
+	readLoad1 = func() float64 { return -1 }
+	// Read it.
+	s := snapshotMachine(context.Background(), true)
+	// Memory is shown; swap and load stay "not reported".
+	if s.MemTotalGB != 20 || s.MemFreeGB != 8 || s.SwapUsedGB != -1 || s.SwapTotalGB != 0 || s.Load1 != -1 || s.CPUName != "Intel64 Family 6" {
+		// Report the problem.
+		t.Errorf("windows style: %+v", s)
+	} // end of the Windows check
+	// A macOS-style system: everything.
+	readMemInfo = func() (memInfo, error) {
+		// All the figures.
+		return memInfo{TotalBytes: 16e9, AvailBytes: 4e9, HaveSwap: true, SwapTotalBytes: 2e9, SwapUsedBytes: 1e9}, nil
+	} // end of the reader
+	// A load average.
+	readLoad1 = func() float64 { return 1.5 }
+	// Read it again.
+	s = snapshotMachine(context.Background(), true)
+	// All of it is shown.
+	if s.MemTotalGB != 16 || s.MemFreeGB != 4 || s.SwapTotalGB != 2 || s.SwapUsedGB != 1 || s.Load1 != 1.5 {
+		// Report the problem.
+		t.Errorf("mac style: %+v", s)
+	} // end of the macOS check
+	// A system that reports no memory at all leaves the figures at zero.
+	readMemInfo = func() (memInfo, error) { return memInfo{}, errors.New("no") }
+	// Read it a third time.
+	s = snapshotMachine(context.Background(), true)
+	// Nothing is invented.
+	if s.MemTotalGB != 0 || s.MemFreeGB != 0 || s.SwapUsedGB != -1 {
+		// Report the problem.
+		t.Errorf("no memory: %+v", s)
+	} // end of the empty check
+} // end of TestSnapshotOnWindowsAndMacStyleReaders
diff --git a/sysinfo_windows.go b/sysinfo_windows.go
new file mode 100644
index 0000000..9b42fd9
--- /dev/null
+++ b/sysinfo_windows.go
@@ -0,0 +1,48 @@
+//go:build windows
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// errors builds fixed error messages.
+	"errors"
+	// os reads the environment variable that names the processor.
+	"os"
+	// syscall loads kernel32.dll and calls GlobalMemoryStatusEx.
+	"syscall"
+	// unsafe turns the address of the structure into the number the Windows call expects; this is the only place in the program that uses it.
+	"unsafe"
+) // end of imports
+
+// kernel32 is the Windows system library that holds the memory call; Windows always loads it from its own system folder.
+var kernel32 = syscall.NewLazyDLL("kernel32.dll")
+
+// procGlobalMemoryStatusEx is the call that fills a memoryStatusEx (documented by Microsoft; it exists since Windows XP).
+var procGlobalMemoryStatusEx = kernel32.NewProc("GlobalMemoryStatusEx")
+
+// osMemInfo asks Windows for the physical memory; Windows has no "swap" figure that matches the other systems, so swap is left unreported.
+func osMemInfo() (memInfo, error) {
+	// The structure Windows fills in; Length must hold its size.
+	ms := memoryStatusEx{Length: memoryStatusExSize}
+	// Make the call; passing the address as a number inside the call expression is the pattern Go documents for Windows calls.
+	r, _, _ := procGlobalMemoryStatusEx.Call(uintptr(unsafe.Pointer(&ms)))
+	// The call returns zero when it fails.
+	if r == 0 {
+		// A fixed message.
+		return memInfo{}, errors.New("Windows did not report the memory")
+	} // end of the result check
+	// Hand back the physical memory.
+	return memInfo{TotalBytes: int64(ms.TotalPhys), AvailBytes: int64(ms.AvailPhys)}, nil
+} // end of osMemInfo
+
+// osCPUName reads the processor description Windows keeps in an environment variable, such as "Intel64 Family 6 Model 142 Stepping 10, GenuineIntel"; it is empty when missing.
+func osCPUName() string {
+	// Read the variable.
+	return os.Getenv("PROCESSOR_IDENTIFIER")
+} // end of osCPUName
+
+// osLoad1 returns -1: Windows has no load average.
+func osLoad1() float64 {
+	// Not available.
+	return -1
+} // end of osLoad1
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
750bedbe8bf79c14c81773f3c1d2051321d6816003f4b11b39323896d1256ef4  about.go
1f7f554aef00b8836fe97464d3e866c9a8178c3bad7564e0ba899fffc9e1cc13  machine.go
25fb32bfc895d3ca3c5cfc3965dcf08351c89e41c64f41980e3bd838b7f233ed  memory.go
b5c8d4fc390c0beafecff8c2e33d025217685fee990db887e11fbc91493c24cc  sysinfo.go
474e2666d4e5507909d9b23229be9acbc3178789d842631eebc2b6d74a0c9d75  sysinfo_darwin.go
c9d764144046d95ba13163f9abc7026d328d051e4b0240ee0a0c309efa8fb88f  sysinfo_linux.go
ace2c69821741aa0dba7e35c8151d6ccffb3aa0016ca14ea8d3bbfd12deb1281  sysinfo_other.go
4de4625be6cc491284e1859979258e7b77337105bb7abaae365166a71f32ea8b  sysinfo_test.go
7e52bca97555128e4c8075626c4a26454fcecdf5ba117d1a791445f31f052e0a  sysinfo_windows.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build for this computer the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Check that the program also compiles for Windows and macOS (nothing is kept).
for target in windows/amd64 darwin/arm64 darwin/amd64; do
  # Build for one target and throw the file away.
  GOOS="${target%/*}" GOARCH="${target#*/}" CGO_ENABLED=0 go build -trimpath -o /dev/null . || { echo "FAIL  build for $target"; exit 1; }
  # Report it.
  echo "PASS  compiles for $target"
done
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# Tell the person what to look at.
echo "NEXT  start ./bin/OllamaControlCenter, open http://127.0.0.1:8765/ and look at the Machine figures on the Performance page and the Free memory row on the Load page of a model; they must look as before"
# List the changed files; nothing is committed yet.
git status --short
