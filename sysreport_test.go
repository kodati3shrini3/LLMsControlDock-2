// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this test uses.
	// context is passed to the detection.
	"context"
	// errors builds the failure of a missing tool.
	"errors"
	// os writes the fake os-release file.
	"os"
	// path/filepath joins the fake file path.
	"path/filepath"
	// strings searches the verdict texts.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestParseNvidiaCSV checks the card lines, including figures the tool cannot give.
func TestParseNvidiaCSV(t *testing.T) {
	// A normal card with the capability, and a shared-memory card with unsupported figures.
	got := parseNvidiaCSV("NVIDIA GeForce GTX 1050, 4096, 576.80, 6.1\nNVIDIA GB10, [N/A], 580.95.05, 12.1\n")
	// Two cards.
	if len(got) != 2 {
		// Report it.
		t.Fatalf("got %d cards, want 2", len(got))
	} // end of the count check
	// The first card.
	if g := got[0]; g.Name != "NVIDIA GeForce GTX 1050" || g.MemMiB != 4096 || g.Driver != "576.80" || g.Compute != "6.1" || g.Vendor != "nvidia" {
		// Report it.
		t.Errorf("first card = %+v", g)
	} // end of the first-card check
	// The shared-memory card has no memory figure.
	if got[1].MemMiB != 0 || got[1].Compute != "12.1" {
		// Report it.
		t.Errorf("second card = %+v", got[1])
	} // end of the second-card check
	// A line without the capability field, and a "Not Supported" driver.
	old := parseNvidiaCSV("Some Card, 8192, Not Supported")
	// One card, no driver, no capability.
	if len(old) != 1 || old[0].Driver != "" || old[0].Compute != "" {
		// Report it.
		t.Errorf("old-style line = %+v", old)
	} // end of the old-style check
	// Rubbish gives nothing.
	if len(parseNvidiaCSV("NVIDIA-SMI has failed because it couldn't communicate")) != 0 {
		// Report it.
		t.Errorf("an error text must not give a card")
	} // end of the rubbish check
} // end of TestParseNvidiaCSV

// TestParseCompute checks the capability reader.
func TestParseCompute(t *testing.T) {
	// Good values.
	if a, b, ok := parseCompute("6.1"); !ok || a != 6 || b != 1 {
		// Report it.
		t.Errorf("6.1 -> %d %d %v", a, b, ok)
	} // end of the good case
	// Bad values.
	for _, s := range []string{"", "[N/A]", "6", "x.1", "6.x", "Not Supported"} {
		// Each is refused.
		if _, _, ok := parseCompute(s); ok {
			// Report it.
			t.Errorf("%q must not parse", s)
		} // end of the check
	} // end of the loop
} // end of TestParseCompute

// TestParseLspci checks that only display adapters are kept and the vendors are told apart.
func TestParseLspci(t *testing.T) {
	// A sample in the format of lspci -mm.
	text := `00:00.0 "Host bridge" "Intel Corporation" "Device 1234" -r07 "Dell" "Device 0001"
00:02.0 "VGA compatible controller" "Intel Corporation" "UHD Graphics 620" -r07 "Dell" "Device 0002"
01:00.0 "3D controller" "NVIDIA Corporation" "GP107M [GeForce GTX 1050 Mobile]" -ra1 "Dell" "Device 0003"
02:00.0 "Display controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Vega 8" "Dell" "Device 0004"
`
	// Read it.
	got := parseLspci(text)
	// Three adapters.
	if len(got) != 3 {
		// Report it.
		t.Fatalf("got %d adapters: %+v", len(got), got)
	} // end of the count check
	// The vendors, in order.
	want := []string{"intel", "nvidia", "amd"}
	// Compare.
	for i, w := range want {
		// One vendor.
		if got[i].Vendor != w {
			// Report it.
			t.Errorf("adapter %d vendor = %q, want %q", i, got[i].Vendor, w)
		} // end of the vendor check
	} // end of the loop
	// The name joins vendor and device.
	if got[0].Name != "Intel UHD Graphics 620" {
		// Report it.
		t.Errorf("name = %q", got[0].Name)
	} // end of the name check
} // end of TestParseLspci

// TestParseLscpuAndOSRelease checks the core count and the distribution name.
func TestParseLscpuAndOSRelease(t *testing.T) {
	// Eight logical processors on four cores (two threads each).
	text := "# comment\n0,0\n1,0\n2,0\n3,0\n0,0\n1,0\n2,0\n3,0\n"
	// Four cores.
	if n := parseLscpuCores(text); n != 4 {
		// Report it.
		t.Errorf("cores = %d, want 4", n)
	} // end of the core check
	// Nothing to count.
	if n := parseLscpuCores("# only a comment\n"); n != 0 {
		// Report it.
		t.Errorf("cores = %d, want 0", n)
	} // end of the empty check
	// The name.
	if n := osReleaseName("NAME=\"Ubuntu\"\nPRETTY_NAME=\"Ubuntu 24.04.3 LTS\"\nID=ubuntu\n"); n != "Ubuntu 24.04.3 LTS" {
		// Report it.
		t.Errorf("name = %q", n)
	} // end of the name check
	// A missing name.
	if n := osReleaseName("ID=x\n"); n != "" {
		// Report it.
		t.Errorf("name = %q, want empty", n)
	} // end of the missing check
} // end of TestParseLscpuAndOSRelease

// TestParseWindowsReport checks the PowerShell JSON, with a list, a single entry and the 4 GiB cap.
func TestParseWindowsReport(t *testing.T) {
	// Two controllers; the second one reports the capped value, which means "not reported".
	text := `{"os":"Microsoft Windows 11 Pro","cpu":"Intel(R) Core(TM) i7-8550U CPU @ 1.80GHz","cores":4,"gpus":[{"name":"NVIDIA GeForce GTX 1050","ram":4293918720},{"name":"Intel(R) UHD Graphics 620","ram":1073741824}]}`
	// Read it.
	osName, cpu, cores, gpus, ok := parseWindowsReport(text)
	// It must read.
	if !ok || osName != "Microsoft Windows 11 Pro" || cores != 4 || !strings.HasPrefix(cpu, "Intel") {
		// Report it.
		t.Fatalf("got %q %q %d %v", osName, cpu, cores, ok)
	} // end of the basic check
	// Two cards.
	if len(gpus) != 2 || gpus[0].Vendor != "nvidia" || gpus[0].MemMiB != 0 || gpus[1].Vendor != "intel" || gpus[1].MemMiB != 1024 {
		// Report it.
		t.Errorf("gpus = %+v", gpus)
	} // end of the card check
	// A single entry without list brackets, as PowerShell may print it.
	_, _, _, one, ok := parseWindowsReport(`{"os":"Windows","gpus":{"name":"AMD Radeon RX 580","ram":null}}`)
	// One card.
	if !ok || len(one) != 1 || one[0].Vendor != "amd" {
		// Report it.
		t.Errorf("single = %+v %v", one, ok)
	} // end of the single check
	// Rubbish.
	if _, _, _, _, ok := parseWindowsReport("not json"); ok {
		// Report it.
		t.Errorf("rubbish must not parse")
	} // end of the rubbish check
} // end of TestParseWindowsReport

// TestParseMacDisplays checks the system_profiler JSON.
func TestParseMacDisplays(t *testing.T) {
	// An Apple Silicon sample.
	got := parseMacDisplays(`{"SPDisplaysDataType":[{"sppci_model":"Apple M2","spdisplays_vendor":"sppci_vendor_Apple"}]}`)
	// One Apple card.
	if len(got) != 1 || got[0].Vendor != "apple" || got[0].Name != "Apple M2" {
		// Report it.
		t.Errorf("got %+v", got)
	} // end of the check
	// Rubbish.
	if len(parseMacDisplays("nope")) != 0 {
		// Report it.
		t.Errorf("rubbish must give nothing")
	} // end of the rubbish check
} // end of TestParseMacDisplays

// TestArchLabel checks the architecture words.
func TestArchLabel(t *testing.T) {
	// The cases.
	for in, want := range map[string]string{"amd64": "amd64 (x86-64)", "arm64": "arm64 (ARM64)", "riscv64": "riscv64"} {
		// One case.
		if got := archLabel(in); got != want {
			// Report it.
			t.Errorf("archLabel(%q) = %q, want %q", in, got, want)
		} // end of the check
	} // end of the loop
} // end of TestArchLabel

// TestJudgeNvidia checks the published minimums: capability 5.0 or higher; driver 550 or higher, 570 or higher for capabilities 5.0 to 6.2.
func TestJudgeNvidia(t *testing.T) {
	// The cases.
	for _, tc := range []struct {
		// name describes the case.
		name string
		// g is the card.
		g gpuInfo
		// supported is the expected answer.
		supported bool
		// level is the expected level.
		level string
	}{
		{"GTX 1050 with a new driver", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "6.1", Driver: "576.80"}, true, "ok"},
		{"GTX 1050 with driver 560 (needs 570)", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "6.1", Driver: "560.10"}, false, "warn"},
		{"capability 8.6 with driver 555 (needs 550)", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "8.6", Driver: "555.1"}, true, "ok"},
		{"capability 6.3 with driver 550", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "6.3", Driver: "550.1"}, true, "ok"},
		{"capability 6.2 with driver 550 (needs 570)", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "6.2", Driver: "550.1"}, false, "warn"},
		{"capability 3.5", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "3.5", Driver: "576.80"}, false, "warn"},
		{"capability not reported", gpuInfo{Vendor: "nvidia", Name: "A", Driver: "576.80"}, false, "info"},
		{"driver not reported", gpuInfo{Vendor: "nvidia", Name: "A", Compute: "8.6"}, false, "info"},
	} {
		// One case.
		ok, f := judgeNvidia(tc.g)
		// Compare.
		if ok != tc.supported || f.Level != tc.level {
			// Report it.
			t.Errorf("%s: supported=%v level=%s (%s)", tc.name, ok, f.Level, f.Text)
		} // end of the check
	} // end of the loop
} // end of TestJudgeNvidia

// TestJudgeReport checks the whole verdict, including the warning when no card is confirmed.
func TestJudgeReport(t *testing.T) {
	// A confirmed card gives no warning.
	good := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.9", Driver: "560.1"}}})
	// Look at the levels.
	for _, f := range good {
		// No warning.
		if f.Level == "warn" {
			// Report it.
			t.Errorf("unexpected warning: %s", f.Text)
		} // end of the check
	} // end of the loop
	// An AMD card is not judged, so the "nothing confirmed" warning appears; the text must say so honestly.
	amd := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "amd", Name: "Radeon X"}}})
	// Collect the text.
	var all string
	// Join it.
	for _, f := range amd {
		// Add it.
		all += f.Level + ":" + f.Text + "\n"
	} // end of the join
	// Both the note and the warning.
	if !strings.Contains(all, "info:Radeon X") || !strings.Contains(all, "warn:No graphics card could be confirmed") || !strings.Contains(all, "ROCm v7") {
		// Report it.
		t.Errorf("amd verdict:\n%s", all)
	} // end of the check
	// No cards at all also warns.
	none := judgeReport(hostReport{})
	// One warning.
	if len(none) != 1 || none[0].Level != "warn" {
		// Report it.
		t.Errorf("no-card verdict = %+v", none)
	} // end of the none check
	// Apple counts as confirmed.
	apple := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "apple", Name: "Apple M2"}}})
	// One ok line.
	if len(apple) != 1 || apple[0].Level != "ok" {
		// Report it.
		t.Errorf("apple verdict = %+v", apple)
	} // end of the apple check
} // end of TestJudgeReport

// fakeProbes replaces the tool runner with answers from a map (key: the tool name); a missing key is a missing tool.
func fakeProbes(t *testing.T, answers map[string]string) {
	// Mark this as a helper.
	t.Helper()
	// Remember the real ones.
	oldRun, oldOS, oldArch, oldLogical, oldRel := probeRun, reportOS, reportArch, reportLogical, osReleasePath
	// Put them back at the end.
	t.Cleanup(func() {
		probeRun, reportOS, reportArch, reportLogical, osReleasePath = oldRun, oldOS, oldArch, oldLogical, oldRel
	})
	// The fake runner.
	probeRun = func(ctx context.Context, name string, args ...string) (string, error) {
		// The key is the base name of the tool (cut at either kind of slash, so a Windows path works on any system).
		if out, ok := answers[name[strings.LastIndexAny(name, `/\\`)+1:]]; ok {
			// The canned answer.
			return out, nil
		} // end of the answer check
		// A missing tool.
		return "", errors.New("not installed")
	} // end of the fake runner
	// Eight logical processors.
	reportLogical = func() int { return 8 }
} // end of fakeProbes

// TestCollectReportLinux checks the Linux path end to end with fake tools.
func TestCollectReportLinux(t *testing.T) {
	// A calm machine.
	quietMachine(t)
	// The tools.
	fakeProbes(t, map[string]string{"nvidia-smi": "NVIDIA GeForce GTX 1050, 4096, 576.80, 6.1", "lscpu": "0,0\n1,0\n0,0\n1,0\n", "lspci": `00:02.0 "VGA compatible controller" "Intel Corporation" "UHD Graphics 620" -r07 "Dell" "x"` + "\n" + `01:00.0 "3D controller" "NVIDIA Corporation" "GP107M" -ra1 "Dell" "y"`})
	// The system.
	reportOS, reportArch = "linux", "amd64"
	// The distribution file.
	rel := filepath.Join(t.TempDir(), "os-release")
	// Write it.
	if err := os.WriteFile(rel, []byte("PRETTY_NAME=\"Ubuntu 24.04\"\n"), 0o600); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// Use it.
	osReleasePath = rel
	// Collect.
	r := collectReport(context.Background())
	// The facts.
	if r.OS != "Ubuntu 24.04" || r.Arch != "amd64 (x86-64)" || r.Physical != 2 || r.Logical != 8 || r.CPU != "Test Processor 9000" || r.MemBytes != 16_384_000_000 {
		// Report it.
		t.Errorf("report = %+v", r)
	} // end of the facts check
	// The NVIDIA card appears once (the tool's detailed entry wins over the lspci entry), plus the Intel one.
	if len(r.GPUs) != 2 || r.GPUs[0].Compute != "6.1" || r.GPUs[1].Vendor != "intel" {
		// Report it.
		t.Errorf("gpus = %+v", r.GPUs)
	} // end of the card check
} // end of TestCollectReportLinux

// TestCollectReportWindowsAndMac checks the other two paths with fake tools.
func TestCollectReportWindowsAndMac(t *testing.T) {
	// A calm machine.
	quietMachine(t)
	// Windows: no NVIDIA tool, one PowerShell answer.
	fakeProbes(t, map[string]string{"powershell.exe": `{"os":"Microsoft Windows 11 Home","cpu":"Intel i7","cores":4,"gpus":[{"name":"NVIDIA GeForce GTX 1050","ram":null}]}`})
	// The system.
	reportOS, reportArch = "windows", "amd64"
	// Collect.
	w := collectReport(context.Background())
	// The facts.
	if w.OS != "Microsoft Windows 11 Home" || w.Physical != 4 || w.CPU != "Intel i7" || len(w.GPUs) != 1 {
		// Report it.
		t.Errorf("windows report = %+v", w)
	} // end of the Windows check
	// Without nvidia-smi the capability is unknown, so the verdict is "cannot be judged", never a guess.
	if f := judgeReport(w); f[0].Level != "info" {
		// Report it.
		t.Errorf("windows verdict = %+v", f)
	} // end of the verdict check
	// macOS.
	fakeProbes(t, map[string]string{"sw_vers": "x", "sysctl": "8", "system_profiler": `{"SPDisplaysDataType":[{"sppci_model":"Apple M2","spdisplays_vendor":"sppci_vendor_Apple"}]}`})
	// The system.
	reportOS, reportArch = "darwin", "arm64"
	// Collect.
	m := collectReport(context.Background())
	// The facts.
	if m.Physical != 8 || len(m.GPUs) != 1 || m.GPUs[0].Vendor != "apple" || m.Arch != "arm64 (ARM64)" {
		// Report it.
		t.Errorf("mac report = %+v", m)
	} // end of the Mac check
} // end of TestCollectReportWindowsAndMac

// TestReportRows checks the words in the table, including "not reported".
func TestReportRows(t *testing.T) {
	// An empty report.
	rows := reportRows(hostReport{OS: "X", Arch: "amd64 (x86-64)", Logical: 4})
	// Join all lines.
	var all string
	// Collect them.
	for _, r := range rows {
		// Add the row.
		all += r.Label + "=" + strings.Join(r.Lines, "|") + "\n"
	} // end of the join
	// The unknown figures are named, never guessed.
	for _, want := range []string{"Processor=not reported", "4 logical (physical cores not reported)", "Memory=not reported", "Graphics cards=none reported"} {
		// Each must be there.
		if !strings.Contains(all, want) {
			// Report it.
			t.Errorf("missing %q in:\n%s", want, all)
		} // end of the check
	} // end of the loop
	// A full report.
	rows = reportRows(hostReport{OS: "X", Logical: 8, Physical: 4, MemBytes: 20 << 30, CPU: "P", GPUs: []gpuInfo{{Name: "G", MemMiB: 4096, Compute: "6.1", Driver: "576.80"}}})
	// Look at the lines.
	all = ""
	// Collect them.
	for _, r := range rows {
		// Add the row.
		all += strings.Join(r.Lines, "|") + "\n"
	} // end of the join
	// The figures.
	for _, want := range []string{"8 logical (4 physical)", "20 GB", "1 found:", "G, 4 GB, compute capability 6.1, driver 576.80"} {
		// Each must be there.
		if !strings.Contains(all, want) {
			// Report it.
			t.Errorf("missing %q in:\n%s", want, all)
		} // end of the check
	} // end of the loop
} // end of TestReportRows

// TestParseLscpuModels checks the processor names of a computer with two kinds of core, and of one kind.
func TestParseLscpuModels(t *testing.T) {
	// Two kinds of core, each with its own Model name line (indented, as lscpu prints them).
	two := "Architecture: aarch64\nVendor ID: ARM\n  Model name: Cortex-X925\n  Core(s) per socket: 10\n  Model name: Cortex-A725\n  Core(s) per socket: 10\n"
	// Joined in order.
	if got := parseLscpuModels(two); got != "Cortex-X925 + Cortex-A725" {
		// Report it.
		t.Errorf("two kinds = %q", got)
	} // end of the two-kinds check
	// The same name twice is shown once.
	if got := parseLscpuModels("Model name: Cortex-A76\nModel name: Cortex-A76\n"); got != "Cortex-A76" {
		// Report it.
		t.Errorf("repeated = %q", got)
	} // end of the repeat check
	// No such line: nothing.
	if got := parseLscpuModels("Architecture: x\n"); got != "" {
		// Report it.
		t.Errorf("none = %q", got)
	} // end of the none check
} // end of TestParseLscpuModels

// TestCollectReportArmProcessorName checks that a Linux computer without a name in /proc/cpuinfo gets its processor name from lscpu.
func TestCollectReportArmProcessorName(t *testing.T) {
	// A calm machine, then no name from the normal reader.
	quietMachine(t)
	// The ARM case: /proc/cpuinfo has no name.
	readCPUName = func() string { return "" }
	// The tools.
	fakeProbes(t, map[string]string{"lscpu": "Model name: Cortex-X925\nModel name: Cortex-A725\n"})
	// Linux on ARM.
	reportOS, reportArch = "linux", "arm64"
	// Collect.
	r := collectReport(context.Background())
	// The note says the name is a core design, not a product name.
	if !strings.Contains(r.CPUNote, "Core designs") {
		// Report it.
		t.Errorf("note = %q", r.CPUNote)
	} // end of the note check
	// The name comes from lscpu.
	if r.CPU != "Cortex-X925 + Cortex-A725" || r.CPUSource != "lscpu" {
		// Report it.
		t.Errorf("cpu = %q", r.CPU)
	} // end of the name check
} // end of TestCollectReportArmProcessorName

// TestDmiModel checks the computer model from the firmware, and that placeholders are ignored.
func TestDmiModel(t *testing.T) {
	// Put the folder back at the end.
	old := dmiDir
	// Restore.
	t.Cleanup(func() { dmiDir = old })
	// A fake folder.
	dmiDir = t.TempDir()
	// Write one value.
	put := func(name, v string) {
		// Write the file.
		if err := os.WriteFile(filepath.Join(dmiDir, name), []byte(v+"\n"), 0o600); err != nil {
			// Stop.
			t.Fatal(err)
		} // end of the write check
	} // end of put
	// The product already holds the vendor.
	put("sys_vendor", "NVIDIA")
	// The product.
	put("product_name", "NVIDIA DGX Spark")
	// Only the product.
	if got := dmiModel(); got != "NVIDIA DGX Spark" {
		// Report it.
		t.Errorf("model = %q", got)
	} // end of the check
	// Vendor and product are joined when the product lacks the vendor.
	put("sys_vendor", "Dell Inc.")
	// The product.
	put("product_name", "XPS 15")
	// Joined.
	if got := dmiModel(); got != "Dell Inc. XPS 15" {
		// Report it.
		t.Errorf("model = %q", got)
	} // end of the join check
	// A placeholder is ignored.
	put("product_name", "To Be Filled By O.E.M.")
	// Nothing.
	if got := dmiModel(); got != "" {
		// Report it.
		t.Errorf("placeholder = %q", got)
	} // end of the placeholder check
} // end of TestDmiModel
