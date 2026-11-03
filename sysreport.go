// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context limits how long a tool may run.
	"context"
	// encoding/json reads the JSON that PowerShell and system_profiler print.
	"encoding/json"
	// fmt builds the sentences of the report.
	"fmt"
	// os reads the operating-system description file and the Windows folder variable.
	"os"
	// os/exec runs the tools that describe the hardware.
	"os/exec"
	// path/filepath joins paths and tells absolute names from bare ones.
	"path/filepath"
	// runtime gives the operating system and the architecture the program was built for.
	"runtime"
	// strings splits and trims text.
	"strings"
	// time sets the limit for each tool.
	"time"
) // end of imports

// gpuInfo describes one graphics card; every figure that the system did not report stays empty or zero and is shown as "not reported", never guessed.
type gpuInfo struct {
	// Vendor is one of nvidia, amd, intel, apple or other.
	Vendor string
	// Name is the card's name as the system reports it.
	Name string
	// MemMiB is the graphics memory in MiB; 0 means not reported (shared-memory cards report none).
	MemMiB int64
	// Driver is the driver version text; empty means not reported.
	Driver string
	// Compute is the NVIDIA compute capability such as "6.1"; empty means not reported.
	Compute string
} // end of gpuInfo

// hostReport is everything the System check shows about this computer.
type hostReport struct {
	// OS is the operating system in words.
	OS string
	// Arch is the architecture the program was built for.
	Arch string
	// CPU is the processor name; empty means not reported.
	CPU string
	// CPUSource names the tool the processor name came from when it is not the usual place ("lscpu"); empty means the usual place.
	CPUSource string
	// CPUNote says where the processor name came from when it is not a product name; empty otherwise.
	CPUNote string
	// Model is the computer's model as the firmware reports it (for example "NVIDIA DGX Spark"); empty means not reported.
	Model string
	// Logical is the number of logical processors.
	Logical int
	// Physical is the number of physical cores; 0 means not reported.
	Physical int
	// MemBytes is the memory in bytes; 0 means not reported.
	MemBytes int64
	// GPUs are the graphics cards that were found.
	GPUs []gpuInfo
} // end of hostReport

// finding is one line of the verdict part: a level (ok, warn or info) and the sentence.
type finding struct {
	// Level is "ok", "warn" or "info".
	Level string
	// Text is the sentence shown to the person.
	Text string
} // end of finding

// The replaceable parts, so a test never runs a real tool.
var (
	// reportOS is the operating system the report is made for.
	reportOS = runtime.GOOS
	// reportArch is the architecture the report is made for.
	reportArch = runtime.GOARCH
	// reportLogical is the number of logical processors.
	reportLogical = runtime.NumCPU
	// dmiDir is the Linux folder where the firmware describes the computer (vendor and product name).
	dmiDir = "/sys/class/dmi/id"
	// osReleasePath is the Linux file that names the distribution.
	osReleasePath = "/etc/os-release"
	// probeRun runs one tool with fixed arguments and returns what it printed; a bare name is searched in the PATH.
	probeRun = realProbe
) // end of the replaceable parts

// realProbe runs a tool with fixed arguments (nothing typed by a person ever reaches it) and waits at most twenty seconds.
func realProbe(ctx context.Context, name string, args ...string) (string, error) {
	// A bare name is looked up in the PATH; a full path is used as it is.
	exe := name
	// Is it a bare name?
	if !filepath.IsAbs(name) {
		// Look for it.
		found, err := exec.LookPath(name)
		// Not installed: the caller shows "not reported".
		if err != nil {
			// Hand the error back.
			return "", err
		} // end of the lookup check
		// Use the full path found.
		exe = found
	} // end of the bare-name case
	// Never wait long.
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	// Release the timer at the end.
	defer cancel()
	// Prepare the command.
	cmd := exec.CommandContext(ctx, exe, args...)
	// Ask for the plain English output, so the labels that the parsers look for never come translated.
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	// Run it and collect its output.
	out, err := cmd.Output()
	// Hand back the text and any error.
	return strings.TrimSpace(string(out)), err
} // end of realProbe

// archLabel names an architecture the way people say it.
func archLabel(goarch string) string {
	// Pick by name.
	switch goarch {
	// Intel and AMD, 64 bit.
	case "amd64":
		// The common name too.
		return "amd64 (x86-64)"
	// ARM, 64 bit.
	case "arm64":
		// The common name too.
		return "arm64 (ARM64)"
	// Anything else: show what Go says.
	default:
		// Unchanged.
		return goarch
	} // end of the switch
} // end of archLabel

// vendorOf sorts a graphics card by the words in its vendor or name.
func vendorOf(text string) string {
	// Compare in lower case.
	t := strings.ToLower(text)
	// Pick by the first match.
	switch {
	// NVIDIA.
	case strings.Contains(t, "nvidia"):
		// Name it.
		return "nvidia"
	// AMD, also written Advanced Micro Devices or ATI.
	case strings.Contains(t, "amd"), strings.Contains(t, "advanced micro"), strings.Contains(t, "radeon"), strings.Contains(t, "ati "):
		// Name it.
		return "amd"
	// Apple.
	case strings.HasPrefix(t, "apple"), strings.Contains(t, "sppci_vendor_apple"):
		// Name it.
		return "apple"
	// Intel.
	case strings.Contains(t, "intel"):
		// Name it.
		return "intel"
	// Anything else.
	default:
		// Other.
		return "other"
	} // end of the switch
} // end of vendorOf

// parseCompute reads a compute capability such as "6.1" into its two numbers.
func parseCompute(s string) (major, minor int, ok bool) {
	// Split at the dot.
	a, b, found := strings.Cut(strings.TrimSpace(s), ".")
	// Both parts are needed.
	if !found {
		// Not a capability.
		return 0, 0, false
	} // end of the dot check
	// The major number.
	ma, okA := leadingNumber(a)
	// The minor number.
	mi, okB := leadingNumber(b)
	// Both must be numbers, and the text must have no more than digits.
	if !okA || !okB || a != fmt.Sprint(ma) {
		// Not a capability.
		return 0, 0, false
	} // end of the number check
	// Hand both back.
	return int(ma), int(mi), true
} // end of parseCompute

// parseNvidiaCSV reads the lines printed by nvidia-smi --query-gpu=name,memory.total,driver_version[,compute_cap] --format=csv,noheader,nounits.
func parseNvidiaCSV(text string) []gpuInfo {
	// The cards found.
	var out []gpuInfo
	// One card per line.
	for _, line := range strings.Split(text, "\n") {
		// Split at the commas.
		parts := strings.Split(strings.TrimSpace(line), ",")
		// A card line has at least the name, the memory and the driver.
		if len(parts) < 3 {
			// Skip other lines.
			continue
		} // end of the shape check
		// Trim every part.
		for i := range parts {
			// Remove the spaces.
			parts[i] = strings.TrimSpace(parts[i])
		} // end of the trim loop
		// The card; the tool prints "[N/A]" or "Not Supported" for a figure it cannot give.
		g := gpuInfo{Vendor: "nvidia", Name: parts[0]}
		// The memory in MiB.
		if n, ok := leadingNumber(parts[1]); ok {
			// Keep it.
			g.MemMiB = n
		} // end of the memory check
		// The driver: a version starts with a digit.
		if len(parts[2]) > 0 && parts[2][0] >= '0' && parts[2][0] <= '9' {
			// Keep it.
			g.Driver = parts[2]
		} // end of the driver check
		// The compute capability, when the tool gave one.
		if len(parts) >= 4 {
			// Only a real capability is kept.
			if _, _, ok := parseCompute(parts[3]); ok {
				// Keep it.
				g.Compute = parts[3]
			} // end of the capability check
		} // end of the fourth-field check
		// Add the card.
		out = append(out, g)
	} // end of the line loop
	// Hand them back.
	return out
} // end of parseNvidiaCSV

// splitQuoted returns the texts between double quotes in a line of "lspci -mm".
func splitQuoted(line string) []string {
	// The texts.
	var out []string
	// Where the current text starts; -1 means outside quotes.
	start := -1
	// Walk along the line.
	for i, c := range line {
		// A quote mark opens or closes a text.
		if c == '"' {
			// Closing.
			if start >= 0 {
				// Keep the text.
				out = append(out, line[start:i])
				// Outside again.
				start = -1
			} else {
				// Opening: the text starts after the mark.
				start = i + 1
			} // end of the open/close choice
		} // end of the quote check
	} // end of the walk
	// Hand them back.
	return out
} // end of splitQuoted

// parseLspci reads the output of "lspci -mm" and returns the display adapters.
func parseLspci(text string) []gpuInfo {
	// The cards found.
	var out []gpuInfo
	// One device per line.
	for _, line := range strings.Split(text, "\n") {
		// The quoted fields: class, vendor, device, and more.
		f := splitQuoted(line)
		// A device line has at least these three.
		if len(f) < 3 {
			// Skip other lines.
			continue
		} // end of the shape check
		// The class decides whether it is a display adapter.
		class := strings.ToLower(f[0])
		// Not a display adapter.
		if !strings.Contains(class, "vga") && !strings.Contains(class, "3d controller") && !strings.Contains(class, "display controller") {
			// Skip it.
			continue
		} // end of the class check
		// The vendor without the company suffix.
		vendor := strings.TrimSpace(strings.NewReplacer(" Corporation", "", " Corp.", "").Replace(f[1]))
		// Add the card.
		out = append(out, gpuInfo{Vendor: vendorOf(f[1]), Name: strings.TrimSpace(vendor + " " + f[2])})
	} // end of the line loop
	// Hand them back.
	return out
} // end of parseLspci

// parseLscpuCores counts the physical cores from "lscpu -p=CORE,SOCKET" (each different pair is one core); 0 means not reported.
func parseLscpuCores(text string) int {
	// The pairs seen.
	seen := map[string]bool{}
	// One logical processor per line.
	for _, line := range strings.Split(text, "\n") {
		// Trim the line.
		line = strings.TrimSpace(line)
		// Skip comments and empty lines.
		if line == "" || strings.HasPrefix(line, "#") {
			// Next line.
			continue
		} // end of the skip check
		// Remember the pair.
		seen[line] = true
	} // end of the line loop
	// The number of different pairs.
	return len(seen)
} // end of parseLscpuCores

// parseLscpuModels reads the "Model name:" lines of the plain "lscpu" output and joins the different names; computers with two kinds of core (such as the DGX Spark, with Cortex-X925 and Cortex-A725 cores) print one such line per kind, and ARM computers have no name in /proc/cpuinfo at all.
func parseLscpuModels(text string) string {
	// The names in the order found.
	var names []string
	// The names already seen.
	seen := map[string]bool{}
	// One line at a time.
	for _, line := range strings.Split(text, "\n") {
		// Split at the first colon.
		k, v, ok := strings.Cut(line, ":")
		// Only the model name lines count.
		if !ok || strings.TrimSpace(k) != "Model name" {
			// Next line.
			continue
		} // end of the key check
		// The name.
		v = strings.TrimSpace(v)
		// Skip empty and repeated names.
		if v == "" || seen[v] {
			// Next line.
			continue
		} // end of the skip check
		// Remember it.
		seen[v] = true
		// Keep it.
		names = append(names, v)
	} // end of the line loop
	// Join the kinds with a plus sign.
	return strings.Join(names, " + ")
} // end of parseLscpuModels

// dmiModel reads the vendor and product name that the firmware reports; placeholder texts that makers leave in are ignored.
func dmiModel() string {
	// One value from a file.
	read := func(name string) string {
		// Read it.
		data, err := os.ReadFile(filepath.Join(dmiDir, name))
		// Not readable.
		if err != nil {
			// Not reported.
			return ""
		} // end of the read check
		// The text.
		v := strings.TrimSpace(string(data))
		// Texts that mean nothing.
		switch strings.ToLower(v) {
		// The usual placeholders.
		case "", "unknown", "default string", "system product name", "system manufacturer", "to be filled by o.e.m.", "not specified", "none":
			// Not reported.
			return ""
		} // end of the placeholder check
		// The value.
		return v
	} // end of read
	// The two parts.
	vendor, product := read("sys_vendor"), read("product_name")
	// No product: nothing useful.
	if product == "" {
		// Not reported.
		return ""
	} // end of the product check
	// The product already starts with the vendor name (for example "NVIDIA DGX Spark").
	if vendor == "" || strings.HasPrefix(strings.ToLower(product), strings.ToLower(vendor)) {
		// Just the product.
		return product
	} // end of the vendor check
	// Both.
	return vendor + " " + product
} // end of dmiModel

// osReleaseName reads PRETTY_NAME from the text of /etc/os-release.
func osReleaseName(text string) string {
	// One setting per line.
	for _, line := range strings.Split(text, "\n") {
		// The line we want.
		if v, ok := strings.CutPrefix(line, "PRETTY_NAME="); ok {
			// Remove the quotes.
			return strings.Trim(strings.TrimSpace(v), `"'`)
		} // end of the prefix check
	} // end of the line loop
	// Not there.
	return ""
} // end of osReleaseName

// winProbeScript is the one PowerShell command that describes a Windows computer; it only reads and prints JSON.
const winProbeScript = `$o=Get-CimInstance Win32_OperatingSystem;$c=@(Get-CimInstance Win32_Processor);$g=@(Get-CimInstance Win32_VideoController);` +
	`[pscustomobject]@{os=$o.Caption;cpu=$c[0].Name;cores=($c|Measure-Object NumberOfCores -Sum).Sum;` +
	`gpus=@($g|ForEach-Object{[pscustomobject]@{name=$_.Name;ram=$_.AdapterRAM}})}|ConvertTo-Json -Depth 4 -Compress`

// winGPU is one video controller in the PowerShell JSON.
type winGPU struct {
	// Name is the controller's name.
	Name string `json:"name"`
	// RAM is the AdapterRAM figure in bytes; Windows caps it at 4 GiB, so a large or zero value means "not reported".
	RAM *int64 `json:"ram"`
} // end of winGPU

// winReport is the JSON that winProbeScript prints.
type winReport struct {
	// OS is the Windows edition in words.
	OS string `json:"os"`
	// CPU is the processor name.
	CPU string `json:"cpu"`
	// Cores is the number of physical cores over all processors.
	Cores *int `json:"cores"`
	// GPUs is a list (PowerShell may print a single entry without the list brackets).
	GPUs json.RawMessage `json:"gpus"`
} // end of winReport

// winRAMLimit is the value from which Windows' AdapterRAM can no longer be trusted (it is a 32-bit figure).
const winRAMLimit = 4293918720

// parseWindowsReport reads the JSON of winProbeScript.
func parseWindowsReport(text string) (osName, cpu string, cores int, gpus []gpuInfo, ok bool) {
	// Skip anything printed before the JSON starts.
	i := strings.Index(text, "{")
	// No JSON at all.
	if i < 0 {
		// Nothing to read.
		return "", "", 0, nil, false
	} // end of the start check
	// Decode.
	var w winReport
	// A damaged text gives nothing.
	if err := json.Unmarshal([]byte(text[i:]), &w); err != nil {
		// Nothing to read.
		return "", "", 0, nil, false
	} // end of the decode check
	// The cards: a list or a single entry.
	var list []winGPU
	// Try the list first.
	if err := json.Unmarshal(w.GPUs, &list); err != nil {
		// Then a single entry.
		var one winGPU
		// Keep it when it reads.
		if json.Unmarshal(w.GPUs, &one) == nil && one.Name != "" {
			// A list of one.
			list = []winGPU{one}
		} // end of the single-entry case
	} // end of the list attempt
	// Convert every card.
	for _, g := range list {
		// Skip nameless entries.
		if strings.TrimSpace(g.Name) == "" {
			// Next card.
			continue
		} // end of the name check
		// The card.
		gi := gpuInfo{Vendor: vendorOf(g.Name), Name: strings.TrimSpace(g.Name)}
		// A trustworthy memory figure.
		if g.RAM != nil && *g.RAM > 0 && *g.RAM < winRAMLimit {
			// In MiB.
			gi.MemMiB = *g.RAM >> 20
		} // end of the memory check
		// Add it.
		gpus = append(gpus, gi)
	} // end of the card loop
	// The core count, when reported.
	if w.Cores != nil && *w.Cores > 0 {
		// Keep it.
		cores = *w.Cores
	} // end of the cores check
	// Hand everything back.
	return strings.TrimSpace(w.OS), strings.TrimSpace(w.CPU), cores, gpus, true
} // end of parseWindowsReport

// parseMacDisplays reads "system_profiler SPDisplaysDataType -json"; fields that are missing stay empty.
func parseMacDisplays(text string) []gpuInfo {
	// The shape of the JSON that we use.
	var d struct {
		// Items are the graphics adapters.
		Items []struct {
			// Model is the adapter's name.
			Model string `json:"sppci_model"`
			// Vendor is the vendor code such as sppci_vendor_Apple.
			Vendor string `json:"spdisplays_vendor"`
		} `json:"SPDisplaysDataType"`
	} // end of the shape
	// Skip anything before the JSON.
	i := strings.Index(text, "{")
	// No JSON.
	if i < 0 {
		// Nothing.
		return nil
	} // end of the start check
	// Decode.
	if err := json.Unmarshal([]byte(text[i:]), &d); err != nil {
		// Nothing.
		return nil
	} // end of the decode check
	// The cards.
	var out []gpuInfo
	// Convert each.
	for _, it := range d.Items {
		// Skip nameless entries.
		if strings.TrimSpace(it.Model) == "" {
			// Next.
			continue
		} // end of the name check
		// The vendor comes from the code or from the name.
		v := vendorOf(it.Vendor + " " + it.Model)
		// Add it.
		out = append(out, gpuInfo{Vendor: v, Name: strings.TrimSpace(it.Model)})
	} // end of the loop
	// Hand them back.
	return out
} // end of parseMacDisplays

// powershellPath is the full path of Windows PowerShell, so no other program with that name is ever run.
func powershellPath() string {
	// The Windows folder.
	root := os.Getenv("SystemRoot")
	// Unset: the usual place.
	if root == "" {
		// The default.
		root = `C:\Windows`
	} // end of the default
	// The standard place of Windows PowerShell 5.1.
	return root + `\System32\WindowsPowerShell\v1.0\powershell.exe`
} // end of powershellPath

// mergeGPUs adds the cards from the general list that the NVIDIA tool did not already describe (the tool gives more detail, so it wins).
func mergeGPUs(detailed, general []gpuInfo) []gpuInfo {
	// Start with the detailed ones.
	out := append([]gpuInfo{}, detailed...)
	// Is there an NVIDIA card with detail?
	haveNvidia := len(detailed) > 0
	// Go through the general list.
	for _, g := range general {
		// The same NVIDIA cards are already described.
		if haveNvidia && g.Vendor == "nvidia" {
			// Skip.
			continue
		} // end of the duplicate check
		// Add it.
		out = append(out, g)
	} // end of the loop
	// Hand the list back.
	return out
} // end of mergeGPUs

// nvidiaCards asks nvidia-smi for the cards; older drivers do not know the compute_cap field, so the question is asked again without it.
func nvidiaCards(ctx context.Context) []gpuInfo {
	// With the capability.
	out, err := probeRun(ctx, "nvidia-smi", "--query-gpu=name,memory.total,driver_version,compute_cap", "--format=csv,noheader,nounits")
	// An old driver, or a failure: ask again without it.
	if err != nil {
		// Without the capability.
		out, err = probeRun(ctx, "nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader,nounits")
	} // end of the retry
	// No tool, or it failed again: nothing is known from it.
	if err != nil {
		// Nothing.
		return nil
	} // end of the second check
	// Read the lines.
	return parseNvidiaCSV(out)
} // end of nvidiaCards

// collectReport asks the system what it can; whatever it cannot tell stays empty and is shown as "not reported".
func collectReport(ctx context.Context) hostReport {
	// The facts that are always known.
	r := hostReport{Arch: archLabel(reportArch), Logical: reportLogical(), OS: reportOS}
	// The memory, from the reader the monitor already uses.
	if mi, err := readMemInfo(); err == nil {
		// Keep the total.
		r.MemBytes = mi.TotalBytes
	} // end of the memory check
	// The processor name, from the reader the monitor already uses.
	r.CPU = readCPUName()
	// The detailed NVIDIA cards.
	nv := nvidiaCards(ctx)
	// The general list of cards.
	var general []gpuInfo
	// Each system describes itself in its own way.
	switch reportOS {
	// Linux.
	case "linux":
		// The distribution name.
		if data, err := os.ReadFile(osReleasePath); err == nil {
			// Use it when it has a name.
			if n := osReleaseName(string(data)); n != "" {
				// Keep it.
				r.OS = n
			} // end of the name check
		} // end of the file check
		// The computer model from the firmware.
		r.Model = dmiModel()
		// The physical cores.
		if out, err := probeRun(ctx, "lscpu", "-p=CORE,SOCKET"); err == nil {
			// Count them.
			r.Physical = parseLscpuCores(out)
		} // end of the lscpu check
		// No processor name in /proc/cpuinfo (ARM computers): take it from lscpu.
		if r.CPU == "" {
			// Ask lscpu.
			if out, err := probeRun(ctx, "lscpu"); err == nil {
				// Use the names it prints.
				r.CPU = parseLscpuModels(out)
				// Say where it came from, so the page can mark it.
				if r.CPU != "" {
					// The tool.
					r.CPUSource = "lscpu"
				} // end of the source mark
				// Say where the name comes from, because it is a core design and not a product name.
				if r.CPU != "" {
					// The note.
					r.CPUNote = "Core designs as reported by the operating system (lscpu). This computer does not report a product name for its processor."
				} // end of the note check
			} // end of the lscpu check
		} // end of the missing-name case
		// The display adapters.
		if out, err := probeRun(ctx, "lspci", "-mm"); err == nil {
			// Read them.
			general = parseLspci(out)
		} // end of the lspci check
	// Windows: one PowerShell call.
	case "windows":
		// Run the script without a profile and without questions.
		if out, err := probeRun(ctx, powershellPath(), "-NoProfile", "-NonInteractive", "-Command", winProbeScript); err == nil {
			// Read the JSON.
			if name, cpu, cores, gpus, ok := parseWindowsReport(out); ok {
				// The edition, when reported.
				if name != "" {
					// Keep it.
					r.OS = name
				} // end of the name check
				// The processor name from Windows is better than the short identifier.
				if cpu != "" {
					// Keep it.
					r.CPU = cpu
				} // end of the cpu check
				// The physical cores.
				r.Physical = cores
				// The cards.
				general = gpus
			} // end of the parse check
		} // end of the PowerShell check
	// macOS.
	case "darwin":
		// The system name and version.
		if name, err := probeRun(ctx, "/usr/bin/sw_vers", "-productName"); err == nil && name != "" {
			// The version.
			ver, _ := probeRun(ctx, "/usr/bin/sw_vers", "-productVersion")
			// Both together.
			r.OS = strings.TrimSpace(name + " " + ver)
		} // end of the name check
		// The physical cores.
		if out, err := probeRun(ctx, "/usr/sbin/sysctl", "-n", "hw.physicalcpu"); err == nil {
			// Read the number.
			if n, ok := leadingNumber(out); ok {
				// Keep it.
				r.Physical = int(n)
			} // end of the number check
		} // end of the sysctl check
		// The graphics adapters.
		if out, err := probeRun(ctx, "/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"); err == nil {
			// Read them.
			general = parseMacDisplays(out)
		} // end of the profiler check
	} // end of the system switch
	// Join the two lists of cards.
	r.GPUs = mergeGPUs(nv, general)
	// Hand the report back.
	return r
} // end of collectReport

// gigabytes writes a size in MiB or bytes as "4 GB" or "20.0 GB" (powers of 1024, as the operating systems show them).
func gigabytes(bytes int64) string {
	// Under 1 GB: show megabytes.
	if bytes < 1<<30 {
		// Whole megabytes.
		return fmt.Sprintf("%d MB", bytes>>20)
	} // end of the small case
	// A whole number of GB reads better without the decimal.
	if bytes%(1<<30) == 0 {
		// Whole.
		return fmt.Sprintf("%d GB", bytes>>30)
	} // end of the whole case
	// One decimal.
	return fmt.Sprintf("%.1f GB", float64(bytes)/float64(1<<30))
} // end of gigabytes

// describeGPU writes one card as a line; unknown figures are left out and the line says so once.
func describeGPU(g gpuInfo) string {
	// The name first.
	parts := []string{g.Name}
	// The memory.
	if g.MemMiB > 0 {
		// Keep it.
		parts = append(parts, gigabytes(g.MemMiB<<20))
	} else {
		// Say so.
		parts = append(parts, "graphics memory not reported")
	} // end of the memory choice
	// The compute capability (NVIDIA only).
	if g.Compute != "" {
		// Keep it.
		parts = append(parts, "compute capability "+g.Compute)
	} // end of the capability check
	// The driver.
	if g.Driver != "" {
		// Keep it.
		parts = append(parts, "driver "+g.Driver)
	} // end of the driver check
	// Join with commas.
	return strings.Join(parts, ", ")
} // end of describeGPU

// ollamaGPUSource is the page the verdicts come from.
const ollamaGPUSource = "Ollama documentation, GPU page (docs.ollama.com/gpu)"

// judgeNvidia judges one NVIDIA card against the published minimums: compute capability 5.0 or higher, and driver 550 or higher (570 or higher for capabilities from 5.0 to 6.2).
func judgeNvidia(g gpuInfo) (supported bool, f finding) {
	// The capability must be known to judge.
	maj, min, ok := parseCompute(g.Compute)
	// Not reported.
	if !ok {
		// Say so; no guess.
		return false, finding{"info", g.Name + ": the compute capability was not reported, so it cannot be judged against Ollama's published minimum (5.0 or higher)."}
	} // end of the capability check
	// Below the minimum.
	if maj < 5 {
		// A clear problem.
		return false, finding{"warn", fmt.Sprintf("%s: compute capability %d.%d is below the published minimum of 5.0.", g.Name, maj, min)}
	} // end of the minimum check
	// Cards from 5.0 to 6.2 need the newer driver.
	need := 550
	// Is it one of them?
	if maj < 6 || (maj == 6 && min <= 2) {
		// The higher driver.
		need = 570
	} // end of the driver choice
	// The driver must be known to judge.
	drv, okD := leadingNumber(g.Driver)
	// Not reported.
	if !okD {
		// Say so; no guess.
		return false, finding{"info", fmt.Sprintf("%s: compute capability %d.%d is high enough, but the driver version was not reported (the published minimum is %d).", g.Name, maj, min, need)}
	} // end of the driver check
	// Too old.
	if int(drv) < need {
		// A clear problem.
		return false, finding{"warn", fmt.Sprintf("%s: driver %s is older than the published minimum of %d for a card with compute capability %d.%d.", g.Name, g.Driver, need, maj, min)}
	} // end of the old-driver case
	// All good.
	return true, finding{"ok", fmt.Sprintf("%s: compute capability %d.%d is at least 5.0, and driver %s is at least %d.", g.Name, maj, min, g.Driver, need)}
} // end of judgeNvidia

// judgeReport turns the report into the lines of the verdict part; it uses Ollama's published facts only.
func judgeReport(r hostReport) []finding {
	// The lines.
	var out []finding
	// How many cards were confirmed.
	supported := 0
	// Judge each card.
	for _, g := range r.GPUs {
		// By vendor.
		switch g.Vendor {
		// NVIDIA has published numbers.
		case "nvidia":
			// Judge it.
			ok, f := judgeNvidia(g)
			// Count a confirmed card.
			if ok {
				// One more.
				supported++
			} // end of the count
			// Keep the line.
			out = append(out, f)
		// Apple: Ollama lists Metal; no minimum is published.
		case "apple":
			// One more confirmed.
			supported++
			// The line.
			out = append(out, finding{"ok", g.Name + ": Ollama lists Apple Metal as supported. It publishes no minimum for it."})
		// AMD: the published list is a driver stack, not a simple number.
		case "amd":
			// Not judged.
			out = append(out, finding{"info", g.Name + ": Ollama supports AMD cards through the ROCm v7 driver stack (Linux and Windows). This tool does not judge AMD cards; check the card list on the GPU page."})
		// Others.
		default:
			// Not judged.
			out = append(out, finding{"info", g.Name + ": not judged (Ollama publishes no minimum for this kind of card here)."})
		} // end of the vendor switch
	} // end of the card loop
	// Nothing confirmed.
	if supported == 0 {
		// The main warning.
		out = append(out, finding{"warn", "No graphics card could be confirmed as meeting Ollama's published GPU minimum, so Ollama may run models on the processor, which is much slower. This tool is then less useful, because the speed you measure will not be the speed of a supported graphics card."})
	} // end of the nothing-confirmed case
	// Hand the lines back.
	return out
} // end of judgeReport
