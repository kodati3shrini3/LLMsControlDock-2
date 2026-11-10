// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bufio reads the person's answer line by line.
	"bufio"
	// context limits how long the System check may take.
	"context"
	// crypto/sha256 makes the fingerprint that proves an installed copy is the one -install placed.
	"crypto/sha256"
	// encoding/hex writes that fingerprint as text.
	"encoding/hex"
	// encoding/json reads and writes the small install record.
	"encoding/json"
	// errors builds the plain error messages.
	"errors"
	// fmt prints the report.
	"fmt"
	// io copies the program file and reads the answer.
	"io"
	// net/url carries the Ollama address.
	"net/url"
	// os reads and writes files and folders.
	"os"
	// path/filepath builds paths the way each system writes them.
	"path/filepath"
	// runtime names the system the program runs on.
	"runtime"
	// strings compares the answer and lists PATH entries.
	"strings"
	// time stamps the install record and limits the check.
	"time"
) // end of imports

// installRecordFileName is the small file in the state folder that remembers what -install placed, so Uninstall removes exactly that copy and nothing else.
const installRecordFileName = "install.json"

// installRecord is what -install remembers about the copy it placed.
type installRecord struct {
	// Path is where the copy was placed.
	Path string `json:"path"`
	// Version is the version of the copy.
	Version string `json:"version"`
	// SHA256 is the fingerprint of the copy, so a changed or replaced file is never removed.
	SHA256 string `json:"sha256"`
	// Time is when it was placed.
	Time time.Time `json:"time"`
} // end of installRecord

// installTargetFor gives the standard place of the installed program for a system, without administrator rights: ~/.local/bin on Linux and macOS, %LocalAppData%\Programs\LLMsControlDock on Windows.
func installTargetFor(goos string, getenv func(string) string, home func() (string, error)) (string, error) {
	// Windows keeps per-user programs under %LocalAppData%\Programs.
	if goos == "windows" {
		// The folder of per-user data that is not copied between computers.
		local := getenv("LocalAppData")
		// Without it there is no standard place.
		if local == "" {
			// Say why.
			return "", errors.New("%LocalAppData% is not defined")
		} // end of the variable check
		// The program's own folder and file.
		return filepath.Join(local, "Programs", dataFolderName, dataFolderName+".exe"), nil
	} // end of the Windows case
	// Linux, macOS and the rest: the user's own program folder.
	h, err := home()
	// Without a home folder there is no standard place.
	if err != nil || h == "" {
		// Say why.
		return "", errors.New("$HOME is not defined")
	} // end of the home check
	// The file in ~/.local/bin.
	return filepath.Join(h, ".local", "bin", dataFolderName), nil
} // end of installTargetFor

// installTarget gives the standard place of the installed program on this computer; it is a variable so tests can point it elsewhere.
var installTarget = func() (string, error) {
	// The real system, environment and home folder.
	return installTargetFor(runtime.GOOS, os.Getenv, os.UserHomeDir)
} // end of installTarget

// fileSHA256 gives the fingerprint of a file, or an empty text when it cannot be read.
func fileSHA256(path string) string {
	// Open the file.
	f, err := os.Open(path)
	// Unreadable: no fingerprint.
	if err != nil {
		// Empty.
		return ""
	} // end of the open check
	// Close it at the end.
	defer f.Close()
	// The hash being built.
	h := sha256.New()
	// Feed the whole file.
	if _, err := io.Copy(h, f); err != nil {
		// A read error: no fingerprint.
		return ""
	} // end of the copy check
	// The fingerprint as text.
	return hex.EncodeToString(h.Sum(nil))
} // end of fileSHA256

// readInstallRecord reads what -install remembered, from the given state folder.
func readInstallRecord(stateDir string) (installRecord, bool) {
	// No state folder: nothing was installed.
	if stateDir == "" {
		// Nothing.
		return installRecord{}, false
	} // end of the folder check
	// Read the small file.
	raw, err := os.ReadFile(filepath.Join(stateDir, installRecordFileName))
	// Missing or unreadable: nothing known.
	if err != nil {
		// Nothing.
		return installRecord{}, false
	} // end of the read check
	// The record.
	var rec installRecord
	// Decode it; a broken file counts as no record.
	if err := json.Unmarshal(raw, &rec); err != nil || rec.Path == "" {
		// Nothing.
		return installRecord{}, false
	} // end of the decode check
	// Found.
	return rec, true
} // end of readInstallRecord

// installedCopy says whether the copy that -install placed is still there, unchanged and in the standard place; only then may Uninstall remove it.
func installedCopy(stateDir string) (string, bool) {
	// What -install remembered.
	rec, ok := readInstallRecord(stateDir)
	// Nothing remembered.
	if !ok {
		// Nothing to remove.
		return "", false
	} // end of the record check
	// The standard place now.
	target, err := installTarget()
	// It must be exactly the standard place, so a record can never point Uninstall at another file.
	if err != nil || filepath.Clean(rec.Path) != filepath.Clean(target) {
		// Not ours.
		return "", false
	} // end of the place check
	// The file must be a plain file (a link is never followed).
	if info, err := os.Lstat(target); err != nil || !info.Mode().IsRegular() {
		// Not there, or not a plain file.
		return "", false
	} // end of the file check
	// It must still be the very file that was placed.
	if fileSHA256(target) != rec.SHA256 {
		// Changed or replaced: left alone.
		return "", false
	} // end of the fingerprint check
	// It is ours.
	return target, true
} // end of installedCopy

// copyProgram copies the program file to its place: into a temporary file first, then renamed, so a half-written program is never left behind.
func copyProgram(src, dst string) error {
	// The folder of the target, readable by the person only and by programs that start it.
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		// Say what failed.
		return err
	} // end of the folder check
	// Open the running program's file.
	in, err := os.Open(src)
	// Unreadable.
	if err != nil {
		// Say what failed.
		return err
	} // end of the open check
	// Close it at the end.
	defer in.Close()
	// The temporary file next to the target.
	tmp := dst + ".new"
	// Create it, runnable.
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
	// Not writable.
	if err != nil {
		// Say what failed.
		return err
	} // end of the create check
	// Copy every byte.
	_, copyErr := io.Copy(out, in)
	// Make sure it reached the disk.
	syncErr := out.Sync()
	// Close it.
	closeErr := out.Close()
	// Any of the three failed: remove the half copy.
	if err := errors.Join(copyErr, syncErr, closeErr); err != nil {
		// Remove it.
		os.Remove(tmp)
		// Say what failed.
		return err
	} // end of the write check
	// Replace the target in one step.
	if err := os.Rename(tmp, dst); err != nil {
		// Remove the temporary file.
		os.Remove(tmp)
		// Windows refuses to replace a program that is running.
		return fmt.Errorf("%v (if the installed copy is running, stop it first and run -install again)", err)
	} // end of the rename check
	// Done.
	return nil
} // end of copyProgram

// installStep is one thing -install does, with its plan line and its action.
type installStep struct {
	// Plan is the line shown before asking.
	Plan string
	// Do performs it and returns a short result.
	Do func() (string, error)
} // end of installStep

// installEnv holds what -install reads and writes, so a test can run it on a throw-away folder with a fake Ollama.
type installEnv struct {
	// in is where the answer is read from.
	in io.Reader
	// out is where the report is written.
	out io.Writer
	// ollama is the Ollama address for the System check.
	ollama *url.URL
	// exe is the running program's file.
	exe func() (string, error)
	// desktop is the desktop icon helper.
	desktop desktopEnv
} // end of installEnv

// runInstall is the -install mode: it shows the System check and the plan, asks for permission, and then does exactly the planned steps with the program's own code; it returns the exit code.
func runInstall(e installEnv) int {
	// The report goes to the given output.
	w := e.out
	// The heading.
	fmt.Fprintf(w, "LLMsControlDock %s - installation\n\n", appVersion)

	// 1. The existing System check: the computer, then Ollama and the requirements.
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	// Free the timer at the end.
	defer cancel()
	// What the computer reports.
	rep := collectReport(ctx)
	// Whether Ollama answers, and its version.
	res := checkOllama(ctx, e.ollama, defaultCheckTimeout)
	// The judgements of the hardware and of the versions.
	findings, env := judgeReport(rep), buildEnvView(res.Online, res.Version, reportOS, reportArch)
	// The heading of the check.
	fmt.Fprintln(w, "System check")
	// Each row of the report.
	for _, row := range reportRows(rep) {
		// The label and the value on one line.
		fmt.Fprintf(w, "  %-22s %s\n", row.Label+":", joinReportLines(row.Lines))
	} // end of the row loop
	// Ollama.
	if res.Online {
		// It answers.
		fmt.Fprintf(w, "  %-22s answers at %s, version %s\n", "Ollama:", e.ollama.Redacted(), res.Version)
	} else {
		// It does not answer.
		fmt.Fprintf(w, "  %-22s does not answer at %s (%s)\n", "Ollama:", e.ollama.Redacted(), res.Reason)
	} // end of the Ollama line
	// The sentences already printed, so a problem that repeats a judgement is not printed twice.
	printed := map[string]bool{}
	// Every judgement, marked so it reads without colour.
	for _, f := range append(findings, env.OllamaVerdict, env.GoVerdict, env.SystemVerdict) {
		// Skip empty judgements.
		if f.Text == "" {
			continue
		} // end of the empty check
		// Remember it.
		printed[f.Text] = true
		// The mark: OK, ! for a warning, i for information.
		mark := map[string]string{"ok": "OK", "warn": " !", "info": " i"}[f.Level]
		// The line.
		fmt.Fprintf(w, "  [%s] %s\n", mark, f.Text)
	} // end of the judgement loop
	// The problems that need fixing, with their reason.
	problems := collectProblems(res.Online, e.ollama.Redacted(), reportOS, env, findings)
	// Each problem.
	for _, p := range problems {
		// Already said in a judgement.
		if printed[p.Why] {
			continue
		} // end of the repeat check
		// Its title and why it matters.
		fmt.Fprintf(w, "  [ !] %s: %s\n", p.Title, p.Why)
	} // end of the problem loop
	// Point to the full report.
	if len(problems) > 0 {
		// The steps to fix are on the System check page.
		fmt.Fprintln(w, "  The steps to fix these are on the System check page of the monitor.")
	} // end of the problem note
	// A blank line.
	fmt.Fprintln(w)

	// 2. The plan.
	steps, err := installPlan(e)
	// Something basic is missing (for example no home folder).
	if err != nil {
		// Say so; nothing was changed.
		fmt.Fprintf(w, "Cannot install: %v. Nothing was changed.\n", err)
		// Failure.
		return 1
	} // end of the plan check
	// The heading.
	fmt.Fprintln(w, "This installation will:")
	// Each step.
	for i, s := range steps {
		// Numbered.
		fmt.Fprintf(w, "  %d. %s\n", i+1, s.Plan)
	} // end of the plan loop
	// What is never touched.
	fmt.Fprintln(w, "Not touched: Ollama and your models. Nothing needs administrator rights. You can still run the program from anywhere without installing.")
	// A blank line.
	fmt.Fprintln(w)

	// 3. Permission.
	fmt.Fprint(w, "Type yes to install, or anything else to stop: ")
	// Read one line.
	answer, _ := bufio.NewReader(e.in).ReadString('\n')
	// Only "yes" agrees.
	if !strings.EqualFold(strings.TrimSpace(answer), "yes") {
		// Nothing happens.
		fmt.Fprintln(w, "\nStopped. Nothing was changed.")
		// Not an error, but not installed either.
		return 1
	} // end of the permission check
	// A blank line.
	fmt.Fprintln(w)

	// 4. Do it, step by step, and report each result.
	failed := 0
	// Each step.
	for i, s := range steps {
		// Run it.
		result, err := s.Do()
		// A failure is reported and the next steps still run.
		if err != nil {
			// Count it.
			failed++
			// Report it.
			fmt.Fprintf(w, "  %d. FAILED: %v\n", i+1, err)
			// Next step.
			continue
		} // end of the failure case
		// Report the result.
		fmt.Fprintf(w, "  %d. %s\n", i+1, result)
	} // end of the step loop
	// A blank line.
	fmt.Fprintln(w)
	// The end.
	if failed > 0 {
		// Some steps failed.
		fmt.Fprintf(w, "Installation finished with %d failed step(s); see above.\n", failed)
		// Failure.
		return 1
	} // end of the failure summary
	// How to start it.
	target, _ := installTarget()
	// Success.
	fmt.Fprintf(w, "Installed. Start it with the desktop icon, or with: %s\n", target)
	// On Linux and macOS, say when ~/.local/bin is not in the PATH.
	if runtime.GOOS != "windows" && !inPath(filepath.Dir(target), os.Getenv("PATH")) {
		// A hint, not an error.
		fmt.Fprintf(w, "Note: %s is not in your PATH, so type the full path above (or add the folder to your PATH).\n", filepath.Dir(target))
	} // end of the PATH note
	// Success.
	return 0
} // end of runInstall

// joinReportLines puts the lines of one report row on one line: a line that ends with a colon (such as "1 found:") is followed by a space, every other line by "; ".
func joinReportLines(lines []string) string {
	// The line being built.
	var b strings.Builder
	// Each line.
	for i, l := range lines {
		// Between two lines.
		if i > 0 {
			// After a colon, a space; otherwise a semicolon and a space.
			if strings.HasSuffix(lines[i-1], ":") {
				// A space.
				b.WriteString(" ")
			} else {
				// A semicolon and a space.
				b.WriteString("; ")
			} // end of the separator choice
		} // end of the separator check
		// The line itself.
		b.WriteString(l)
	} // end of the loop
	// The joined text.
	return b.String()
} // end of joinReportLines

// inPath says whether a folder is one of the folders of a PATH list.
func inPath(dir, pathList string) bool {
	// Each folder of the list.
	for _, p := range filepath.SplitList(pathList) {
		// A match.
		if filepath.Clean(p) == filepath.Clean(dir) {
			// Found.
			return true
		} // end of the match
	} // end of the loop
	// Not found.
	return false
} // end of inPath

// installPlan works out the steps of the installation; it changes nothing.
func installPlan(e installEnv) ([]installStep, error) {
	// The three folders, from the same code the program uses when it creates them by itself.
	folders := []struct{ what, dir string }{{"settings", configRoot()}, {"data (results, saved copies, deleted models)", dataRoot()}, {"state (check history, log)", stateRoot()}}
	// The steps.
	var steps []installStep
	// Each folder.
	for _, f := range folders {
		// No standard place on this system.
		if f.dir == "" {
			// Cannot install.
			return nil, fmt.Errorf("no standard place for the %s folder", f.what)
		} // end of the place check
		// A copy for the closure below.
		dir, what := f.dir, f.what
		// The plan line when the folder is new.
		plan := fmt.Sprintf("Create the %s folder: %s", what, dir)
		// It exists already.
		if _, err := os.Stat(dir); err == nil {
			// Nothing to create; say so.
			plan = fmt.Sprintf("%s folder exists already, kept: %s", strings.ToUpper(what[:1])+what[1:], dir)
		} // end of the exists check
		// The step.
		steps = append(steps, installStep{Plan: plan, Do: func() (string, error) {
			// The same permissions the program uses: the person only.
			if err := os.MkdirAll(dir, 0o700); err != nil {
				// Say what failed.
				return "", err
			} // end of the create check
			// Done.
			return "Folder ready: " + dir, nil
		}}) // end of the folder step
	} // end of the folder loop
	// The running program and the standard place.
	exe, err := e.exe()
	// The running program cannot be found.
	if err != nil {
		// Cannot install.
		return nil, fmt.Errorf("the running program file cannot be found: %v", err)
	} // end of the program check
	// Follow links, so the real file is copied.
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		// The real file.
		exe = resolved
	} // end of the link check
	// The standard place.
	target, err := installTarget()
	// No standard place.
	if err != nil {
		// Cannot install.
		return nil, err
	} // end of the target check
	// The state folder, where the record is kept.
	state := stateRoot()
	// The program step.
	switch {
	// This already is the installed copy.
	case filepath.Clean(exe) == filepath.Clean(target):
		// Nothing to copy; the record is refreshed.
		steps = append(steps, installStep{Plan: "Keep the program where it is: this already is the installed copy (" + target + ")", Do: func() (string, error) {
			// Refresh the record.
			return "Program kept: " + target, writeInstallRecord(state, target)
		}}) // end of the keep step
	default:
		// What is there now.
		plan := "Copy the program to " + target
		// Something is there already.
		if _, err := os.Stat(target); err == nil {
			// Its version, when -install placed it.
			old := "an unknown version"
			// The record names it.
			if rec, ok := readInstallRecord(state); ok && filepath.Clean(rec.Path) == filepath.Clean(target) {
				// The version.
				old = "version " + rec.Version
			} // end of the version check
			// Say both versions.
			plan = fmt.Sprintf("Replace the installed program (%s) with version %s at %s; settings and results are kept", old, appVersion, target)
		} // end of the replace case
		// The step.
		steps = append(steps, installStep{Plan: plan, Do: func() (string, error) {
			// Copy the file.
			if err := copyProgram(exe, target); err != nil {
				// Say what failed.
				return "", err
			} // end of the copy check
			// Remember it, so Uninstall can remove exactly this copy.
			if err := writeInstallRecord(state, target); err != nil {
				// Say what failed.
				return "", err
			} // end of the record check
			// Done.
			return "Program copied: " + target, nil
		}}) // end of the copy step
	} // end of the program switch
	// The desktop icon, made by the existing code, pointing at the installed copy.
	icon := desktopIcon{env: e.desktop, dir: configRoot(), dataDir: dataRoot()}
	// The icon starts the installed copy, not the file this was run from.
	icon.env.exePath = func() (string, error) { return target, nil }
	// This computer has a desktop the program can use.
	if _, ok := icon.env.desktopDir(); ok {
		// The step.
		steps = append(steps, installStep{Plan: "Create the desktop icon (it starts the installed program)", Do: func() (string, error) {
			// The same code as the button in Settings.
			if err := icon.create(); err != nil {
				// Say what failed.
				return "", err
			} // end of the create check
			// Done.
			return "Desktop icon created: " + icon.desktopPath(), nil
		}}) // end of the icon step
	} else {
		// No desktop: said in the plan, nothing to do.
		steps = append(steps, installStep{Plan: "Desktop icon: not possible here (no desktop session, or no Desktop folder); you can create it later in Settings", Do: func() (string, error) {
			// Nothing done.
			return "Desktop icon skipped (no desktop here)", nil
		}}) // end of the no-icon step
	} // end of the icon choice
	// The plan.
	return steps, nil
} // end of installPlan

// writeInstallRecord remembers the installed copy in the state folder.
func writeInstallRecord(stateDir, target string) error {
	// The folder must exist (step 1 made it).
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		// Say what failed.
		return err
	} // end of the folder check
	// The record.
	raw, err := json.MarshalIndent(installRecord{Path: target, Version: appVersion, SHA256: fileSHA256(target), Time: time.Now().UTC()}, "", "  ")
	// Cannot happen with these fields, but checked anyway.
	if err != nil {
		// Say what failed.
		return err
	} // end of the encode check
	// Write it, readable by the person only.
	return os.WriteFile(filepath.Join(stateDir, installRecordFileName), raw, 0o600)
} // end of writeInstallRecord
