// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages the tests use.
	// context is passed to the measuring function.
	"context"
	// net/http gives the method names and status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// os writes test files.
	"os"
	// path/filepath joins file names.
	"path/filepath"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time gives fixed moments.
	"time"
) // end of imports

// fakeSelfReaders replaces the System check, the memory reader and the clock with fixed answers, and puts the real ones back at the end.
func fakeSelfReaders(t *testing.T) {
	// Mark this as a helper.
	t.Helper()
	// Keep the real ones.
	oldReport, oldMem, oldNow := selfReport, selfMemory, selfNow
	// Put them back at the end.
	t.Cleanup(func() { selfReport, selfMemory, selfNow = oldReport, oldMem, oldNow })
	// A computer with 64 GiB and one card.
	selfReport = func(ctx context.Context) hostReport {
		// The fixed report.
		return hostReport{MemBytes: 64 << 30, GPUs: []gpuInfo{{Vendor: "nvidia", Name: "Test Card", MemMiB: 8192}}}
	} // end of the fake report
	// The program holds 256 MiB.
	selfMemory = func() (int64, string) { return 256 << 20, "resident" }
	// A fixed moment (UTC).
	selfNow = func() time.Time { return time.Date(2026, 11, 10, 16, 0, 0, 0, time.UTC) }
} // end of fakeSelfReaders

// TestSizeText checks the size texts, including the "not reported" case.
func TestSizeText(t *testing.T) {
	// The cases.
	for n, want := range map[int64]string{0: "not reported", 500: "500 bytes", 1536: "1.5 KB", 5 << 20: "5.0 MB", 3 << 30: "3.0 GB"} {
		// Compare.
		if got := sizeText(n); got != want {
			// Report.
			t.Errorf("sizeText(%d) = %q, want %q", n, got, want)
		} // end of the check
	} // end of the loop
} // end of TestSizeText

// TestFolderBytesAddsFiles checks the folder size: files in sub-folders count, a missing folder is 0.
func TestFolderBytesAddsFiles(t *testing.T) {
	// A folder with two files.
	dir := t.TempDir()
	// A sub-folder.
	os.MkdirAll(filepath.Join(dir, "sub"), 0o700)
	// Ten bytes.
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("0123456789"), 0o600)
	// Five bytes.
	os.WriteFile(filepath.Join(dir, "sub", "b.txt"), []byte("01234"), 0o600)
	// The sum.
	if got := folderBytes(dir); got != 15 {
		// Report.
		t.Errorf("folderBytes = %d, want 15", got)
	} // end of the sum check
	// A missing folder and an empty name.
	if folderBytes(filepath.Join(dir, "none")) != 0 || folderBytes("") != 0 {
		// Report.
		t.Error("a missing folder must count as 0")
	} // end of the missing check
} // end of TestFolderBytesAddsFiles

// TestMeasureSelfUsesTheSystemCheck checks that the estimate carries the System check's figures and the program's own.
func TestMeasureSelfUsesTheSystemCheck(t *testing.T) {
	// A throw-away data folder with 10 bytes in it.
	isolateFindData(t)
	// Fixed readers.
	fakeSelfReaders(t)
	// A program file of 7 bytes (the tests' own lookup may point elsewhere).
	exe := filepath.Join(t.TempDir(), "prog")
	// Write it.
	os.WriteFile(exe, []byte("1234567"), 0o700)
	// Put the real lookup back at the end.
	oldExe := executablePath
	t.Cleanup(func() { executablePath = oldExe })
	// Use it.
	executablePath = func() (string, error) { return exe, nil }
	// Some saved data.
	os.WriteFile(filepath.Join(dataRoot(), "x.txt"), []byte("0123456789"), 0o600)
	// Measure.
	e := measureSelf(context.Background())
	// The checks.
	if e.MachineRAM != 64<<30 || e.RAMBytes != 256<<20 || e.RAMKind != "resident" || len(e.GPUs) != 1 || !strings.Contains(e.GPUs[0], "Test Card") || e.DataBytes < 10 || e.ExeBytes != 7 || e.FreeDisk <= 0 {
		// Report.
		t.Errorf("estimate %+v", e)
	} // end of the checks
} // end of TestMeasureSelfUsesTheSystemCheck

// TestSelfEstimateSaveLoadAndDamaged checks that a saved estimate comes back and that a damaged file is ignored.
func TestSelfEstimateSaveLoadAndDamaged(t *testing.T) {
	// A throw-away data folder.
	isolateFindData(t)
	// Nothing saved yet.
	if _, ok := loadSelfEstimate(); ok {
		// Report.
		t.Fatal("an estimate exists before any was saved")
	} // end of the empty check
	// Save one.
	at := time.Date(2026, 11, 10, 16, 0, 0, 0, time.UTC)
	// The save.
	saveSelfEstimate(selfEstimate{At: at, RAMBytes: 123, RAMKind: "runtime"})
	// Read it back.
	e, ok := loadSelfEstimate()
	// The checks.
	if !ok || e.RAMBytes != 123 || !e.At.Equal(at) {
		// Report.
		t.Errorf("loaded %+v, %v", e, ok)
	} // end of the check
	// Damage the file.
	os.WriteFile(filepath.Join(dataRoot(), selfEstimateFile), []byte("{not json"), 0o600)
	// A damaged file is never shown.
	if _, ok := loadSelfEstimate(); ok {
		// Report.
		t.Error("a damaged file was accepted")
	} // end of the damaged check
} // end of TestSelfEstimateSaveLoadAndDamaged

// TestAboutEstimateButtonAndResult checks the whole round trip on the About page: the button and the "no estimate yet" text first, a refused wrong token, then a run that saves the result and shows it with the word "estimate" and the time.
func TestAboutEstimateButtonAndResult(t *testing.T) {
	// A throw-away data folder.
	isolateFindData(t)
	// Fixed readers.
	fakeSelfReaders(t)
	// The rig.
	rig := newThemeRig(t)
	// The page before any estimate.
	_, _, first := get(t, rig.h, http.MethodGet, "/about")
	// The button, the explanation and the empty state; no script.
	for _, want := range []string{`action="/about/estimate"`, "Estimate what this program uses", "No estimate has been made yet.", "based on that one run"} {
		// Look for it.
		if !strings.Contains(first, want) {
			// Report.
			t.Errorf("the About page lacks %q", want)
		} // end of the look
	} // end of the loop
	// No script on the About page.
	if strings.Contains(first, "<script") {
		// Report.
		t.Error("the About page carries a script")
	} // end of the script check
	// A wrong token is refused and saves nothing.
	if res := post(t, rig.h, "/about/estimate", url.Values{"token": {"wrong"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
		// Report.
		t.Errorf("wrong token = %d, want 403", res.StatusCode)
	} // end of the token check
	// Nothing was saved.
	if _, ok := loadSelfEstimate(); ok {
		// Report.
		t.Error("a refused request saved an estimate")
	} // end of the refused check
	// A real run redirects back to the estimate.
	res := post(t, rig.h, "/about/estimate", url.Values{"token": {rig.token}}, fromThisPage)
	// The redirect.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/about#estimate" {
		// Report.
		t.Fatalf("estimate = %d to %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the redirect check
	// The page now shows the figures.
	_, _, after := get(t, rig.h, http.MethodGet, "/about")
	// What must be there.
	for _, want := range []string{"Memory (estimated)", "256.0 MB", "about 0.4% of the 64.0 GB", "Disk space (estimated)", "Graphics card (estimated)", "None used by this program itself", "Test Card", "Estimated on ", "from the System check run at that moment", "Estimate again"} {
		// Look for it.
		if !strings.Contains(after, want) {
			// Report.
			t.Errorf("the estimate lacks %q", want)
		} // end of the look
	} // end of the loop
} // end of TestAboutEstimateButtonAndResult
