// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context limits how long the System check may take.
	"context"
	// encoding/json writes and reads the saved estimate.
	"encoding/json"
	// fmt builds the size texts.
	"fmt"
	// io limits how much of a file is read.
	"io"
	// io/fs lets the folder walk skip what it cannot read.
	"io/fs"
	// log writes the reason when saving fails.
	"log"
	// net/http provides requests and status codes.
	"net/http"
	// os reads, writes and measures files.
	"os"
	// path/filepath joins folder and file names for any operating system.
	"path/filepath"
	// runtime reports the memory the program holds.
	"runtime"
	// strconv turns the numbers in the memory file into integers.
	"strconv"
	// strings splits and trims text.
	"strings"
	// time stamps the estimate.
	"time"
) // end of imports

// selfEstimateFile is the file that keeps the last estimate, inside the program's data folder.
const selfEstimateFile = "selfestimate.json"

// maxSelfEstimateFile is the largest saved estimate that is read (a real one is under 2 KiB).
const maxSelfEstimateFile = 64 * 1024

// The readers below are variables so that a test can replace them.
var (
	// selfReport runs the System check (the same function the System check page uses).
	selfReport = collectReport
	// selfMemory reads the memory this program holds now, in bytes, and says which kind of figure it is.
	selfMemory = osSelfMemory
	// selfNow gives the current time.
	selfNow = time.Now
) // end of the reader variables

// selfEstimate is one estimate of what this program uses; every figure is an estimate from one run, not a promise.
type selfEstimate struct {
	// At is the moment of the run.
	At time.Time `json:"at"`
	// RAMBytes is the memory this program held at that moment; 0 means not reported.
	RAMBytes int64 `json:"ram_bytes"`
	// RAMKind says what kind of figure RAMBytes is: "resident" (the memory the operating system says this program occupies) or "runtime" (the memory the Go runtime asked from the system, used where the first is not available).
	RAMKind string `json:"ram_kind"`
	// ExeBytes is the size of the program file; 0 means not reported.
	ExeBytes int64 `json:"exe_bytes"`
	// DataBytes is the size of the saved data (results, copies, snapshots, settings and logs).
	DataBytes int64 `json:"data_bytes"`
	// MachineRAM is the memory of this computer as the System check reported it; 0 means not reported.
	MachineRAM int64 `json:"machine_ram"`
	// FreeDisk is the free disk space where the data is kept; 0 means not reported.
	FreeDisk int64 `json:"free_disk"`
	// GPUs are the graphics cards the System check found, as lines of text.
	GPUs []string `json:"gpus"`
} // end of selfEstimate

// osSelfMemory reads the memory this program holds now: on Linux the resident size from the operating system, elsewhere (or when that cannot be read) the memory the Go runtime obtained from the system.
func osSelfMemory() (int64, string) {
	// Linux keeps the figure in a text file.
	if runtime.GOOS == "linux" {
		// Read the file.
		if data, err := os.ReadFile("/proc/self/status"); err == nil {
			// Look at every line.
			for _, line := range strings.Split(string(data), "\n") {
				// The resident size line looks like "VmRSS:   12345 kB".
				if strings.HasPrefix(line, "VmRSS:") {
					// The words after the name.
					f := strings.Fields(strings.TrimPrefix(line, "VmRSS:"))
					// A number and a unit.
					if len(f) >= 1 {
						// Read the number (kibibytes).
						if kb, err := strconv.ParseInt(f[0], 10, 64); err == nil && kb > 0 {
							// In bytes.
							return kb * 1024, "resident"
						} // end of the number check
					} // end of the words check
				} // end of the line check
			} // end of the line loop
		} // end of the read check
	} // end of the Linux case
	// The Go runtime's own count.
	var ms runtime.MemStats
	// Fill it in.
	runtime.ReadMemStats(&ms)
	// Its total obtained from the system.
	return int64(ms.Sys), "runtime"
} // end of osSelfMemory

// folderBytes adds up the sizes of the files in a folder and below it; what cannot be read is skipped, and a missing folder counts as 0.
func folderBytes(dir string) int64 {
	// No folder given.
	if dir == "" {
		// Nothing.
		return 0
	} // end of the empty check
	// The sum.
	var total int64
	// Walk the folder.
	filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		// Skip what cannot be read.
		if err != nil {
			// Carry on with the rest.
			return nil
		} // end of the error check
		// Only files have a size to add.
		if !d.IsDir() {
			// Its information.
			if info, err := d.Info(); err == nil {
				// Add it.
				total += info.Size()
			} // end of the information check
		} // end of the file check
		// Carry on.
		return nil
	}) // end of the walk
	// The sum.
	return total
} // end of folderBytes

// measureSelf runs the System check and then reads the figures of this program; it is read-only and changes nothing.
func measureSelf(ctx context.Context) selfEstimate {
	// The moment of the run.
	e := selfEstimate{At: selfNow()}
	// The System check: the computer's memory and graphics cards.
	rep := selfReport(ctx)
	// The computer's memory.
	e.MachineRAM = rep.MemBytes
	// The graphics cards, as lines.
	for _, g := range rep.GPUs {
		// One line each.
		e.GPUs = append(e.GPUs, describeGPU(g))
	} // end of the card loop
	// The memory this program holds now.
	e.RAMBytes, e.RAMKind = selfMemory()
	// The program file.
	if exe, err := executablePath(); err == nil {
		// Its size.
		if info, err := os.Stat(exe); err == nil {
			// Keep it.
			e.ExeBytes = info.Size()
		} // end of the size check
	} // end of the program check
	// The saved data: the data folder and the state folder (they may be the same one).
	data, state := dataRoot(), stateRoot()
	// The data folder.
	e.DataBytes = folderBytes(data)
	// The state folder, when it is another one.
	if state != data {
		// Add it.
		e.DataBytes += folderBytes(state)
	} // end of the state check
	// The free space where the data is kept.
	if data != "" {
		// Ask the system.
		if free, err := osFreeDiskBytes(nearestFolder(data)); err == nil {
			// Keep it.
			e.FreeDisk = int64(free)
		} // end of the free check
	} // end of the data check
	// The finished estimate.
	return e
} // end of measureSelf

// nearestFolder returns the folder itself, or the nearest folder above it that exists (the data folder may not have been made yet).
func nearestFolder(dir string) string {
	// Go up until a folder exists.
	for dir != "" {
		// Does it exist?
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			// Found.
			return dir
		} // end of the exist check
		// One level up.
		up := filepath.Dir(dir)
		// The top was reached.
		if up == dir {
			// Give up.
			return dir
		} // end of the top check
		// Try the next one.
		dir = up
	} // end of the loop
	// Nothing.
	return dir
} // end of nearestFolder

// saveSelfEstimate keeps the estimate in the data folder; a failure is logged and the page still shows the result of this run.
func saveSelfEstimate(e selfEstimate) {
	// The folder.
	dir := dataRoot()
	// No folder known.
	if dir == "" {
		// Nothing to write.
		return
	} // end of the folder check
	// Make the folder when it does not exist yet.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		// Log it.
		log.Printf("About: the estimate could not be saved: %v", err)
		// Stop.
		return
	} // end of the folder creation
	// The text of the file.
	body, err := json.Marshal(e)
	// A failure here is a bug.
	if err != nil {
		// Log it.
		log.Printf("About: the estimate could not be written: %v", err)
		// Stop.
		return
	} // end of the encoding check
	// Write to a temporary file first, so a power cut never leaves half a file.
	tmp, err := os.CreateTemp(dir, "selfestimate-*.tmp")
	// A failure.
	if err != nil {
		// Log it.
		log.Printf("About: the estimate could not be started: %v", err)
		// Stop.
		return
	} // end of the temp check
	// Remove the temporary file if something below fails.
	defer os.Remove(tmp.Name())
	// Write it.
	if _, err := tmp.Write(body); err != nil {
		// Close it.
		tmp.Close()
		// Log it.
		log.Printf("About: the estimate could not be written: %v", err)
		// Stop.
		return
	} // end of the write check
	// Finish the file.
	if err := tmp.Close(); err != nil {
		// Log it.
		log.Printf("About: the estimate could not be finished: %v", err)
		// Stop.
		return
	} // end of the close check
	// Private to this person; not fatal on systems without file modes.
	os.Chmod(tmp.Name(), 0o600)
	// Put it in place in one step.
	if err := os.Rename(tmp.Name(), filepath.Join(dir, selfEstimateFile)); err != nil {
		// Log it.
		log.Printf("About: the estimate could not be put in place: %v", err)
	} // end of the rename check
} // end of saveSelfEstimate

// loadSelfEstimate reads the saved estimate; ok is false when there is none or the file is damaged (a damaged file is never shown).
func loadSelfEstimate() (selfEstimate, bool) {
	// The folder.
	dir := dataRoot()
	// No folder known.
	if dir == "" {
		// None.
		return selfEstimate{}, false
	} // end of the folder check
	// Open the file.
	f, err := os.Open(filepath.Join(dir, selfEstimateFile))
	// Missing.
	if err != nil {
		// None.
		return selfEstimate{}, false
	} // end of the open check
	// Close it at the end.
	defer f.Close()
	// Read it, with a limit.
	body, err := io.ReadAll(io.LimitReader(f, maxSelfEstimateFile))
	// A failure.
	if err != nil {
		// None.
		return selfEstimate{}, false
	} // end of the read check
	// Decode it.
	var e selfEstimate
	// Damaged, or without a time.
	if err := json.Unmarshal(body, &e); err != nil || e.At.IsZero() {
		// None.
		return selfEstimate{}, false
	} // end of the decode check
	// The estimate.
	return e, true
} // end of loadSelfEstimate

// sizeText writes a number of bytes in the unit that reads best (powers of 1024, as the operating systems show them); 0 reads as "not reported".
func sizeText(n int64) string {
	// Nothing known.
	if n <= 0 {
		// Say so.
		return "not reported"
	} // end of the empty check
	// Bytes.
	if n < 1<<10 {
		// As bytes.
		return fmt.Sprintf("%d bytes", n)
	} // end of the byte case
	// Kilobytes.
	if n < 1<<20 {
		// One decimal.
		return fmt.Sprintf("%.1f KB", float64(n)/float64(1<<10))
	} // end of the kilobyte case
	// Megabytes.
	if n < 1<<30 {
		// One decimal.
		return fmt.Sprintf("%.1f MB", float64(n)/float64(1<<20))
	} // end of the megabyte case
	// Gigabytes.
	return fmt.Sprintf("%.1f GB", float64(n)/float64(1<<30))
} // end of sizeText

// estimateView is the estimate as the About page shows it.
type estimateView struct {
	// When is the moment of the run, with its time zone.
	When string
	// RAM is the memory this program held, as text.
	RAM string
	// RAMKind explains which kind of figure the memory is.
	RAMKind string
	// RAMShare is the memory as a share of the computer's memory, or empty.
	RAMShare string
	// Exe is the size of the program file.
	Exe string
	// Data is the size of the saved data.
	Data string
	// Disk is the program file and the saved data together, with the free space.
	Disk string
	// GPUs are the cards the System check found.
	GPUs []string
} // end of estimateView

// viewOfEstimate turns a saved estimate into the texts of the page.
func viewOfEstimate(e selfEstimate) estimateView {
	// The time, in the computer's own zone, with the zone's name and offset.
	v := estimateView{When: e.At.Local().Format("2006-01-02 15:04:05 MST (UTC-07:00)")}
	// The memory.
	v.RAM = sizeText(e.RAMBytes)
	// Which kind of figure it is.
	if e.RAMKind == "resident" {
		// The operating system's figure.
		v.RAMKind = "the memory the operating system says this program occupies"
	} else {
		// The Go runtime's figure.
		v.RAMKind = "the memory the Go runtime obtained from the system (this system gives no closer figure)"
	} // end of the kind choice
	// The share of the computer's memory.
	if e.RAMBytes > 0 && e.MachineRAM > 0 {
		// One decimal.
		v.RAMShare = fmt.Sprintf("about %.1f%% of the %s this computer has", float64(e.RAMBytes)*100/float64(e.MachineRAM), sizeText(e.MachineRAM))
	} // end of the share check
	// The program file.
	v.Exe = sizeText(e.ExeBytes)
	// The saved data; an empty folder is 0 bytes, which is a real figure.
	if e.DataBytes > 0 {
		// The size.
		v.Data = sizeText(e.DataBytes)
	} else {
		// A real zero.
		v.Data = "none yet"
	} // end of the data choice
	// Both together, with the free space.
	total := e.ExeBytes + e.DataBytes
	// The text.
	v.Disk = sizeText(total)
	// The free space.
	if e.FreeDisk > 0 {
		// Add it.
		v.Disk += ", on a disk with " + sizeText(e.FreeDisk) + " free"
	} // end of the free check
	// The cards.
	v.GPUs = e.GPUs
	// The finished view.
	return v
} // end of viewOfEstimate

// selfEstimateHandler runs the System check, measures this program, saves the result and goes back to the About page; only the page's own form may start it.
func selfEstimateHandler(token string) http.HandlerFunc {
	// The handler itself.
	return func(w http.ResponseWriter, r *http.Request) {
		// Only the page's own form may do this.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "forbidden", http.StatusForbidden)
			// Stop.
			return
		} // end of the token check
		// The System check may take a few seconds; stop it after the limit.
		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		// Release the timer at the end.
		defer cancel()
		// Measure and keep.
		saveSelfEstimate(measureSelf(ctx))
		// Back to the estimate; a redirect keeps a reload from running it again.
		http.Redirect(w, r, "/about#estimate", http.StatusSeeOther)
	} // end of the handler
} // end of selfEstimateHandler
