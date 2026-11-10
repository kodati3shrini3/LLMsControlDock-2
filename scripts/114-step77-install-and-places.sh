#!/usr/bin/env bash
# Script 114 (installer, version 0.32.0): adds the optional -install mode as a wrapper around what the program already does. It shows the existing System check and the plan, asks for 'yes', then makes the three folders with the program's own folder code, copies the program to its standard place (~/.local/bin, or %LocalAppData%\Programs\LLMsControlDock on Windows), remembers that copy, and creates the desktop icon with the existing icon code. Nothing about the normal start changes. Uninstall also removes the copy -install placed (only that copy, only unchanged). The About page gets a card 'Where this program keeps its files' (this computer, and Linux, Windows and macOS); the Help page gets the topic 'Install (optional), and where the files go'. Version 0.31.0 -> 0.32.0; README updated. Tests follow.
# Run it on the branch feature/help-performance-guide, after script 113 (uncommitted is fine): cd ~/LLMsControlDock && bash scripts/114-step77-install-and-places.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 113), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["help.go"]="b02424699b4f914a33de672140bb2f33a9ec4cea27cd93eda815a13f34ad2978"
BEFORE["web/app.css"]="2327c582e39b759f149859f230f00ae980911acdbc9dfa2ffd35023d42e159d9"
BEFORE["scripts/test-smoke-load.sh"]="445169a646a56be501255f054eeb5f5fed90c5566a86f5af249c2b9663db714c"
BEFORE["main.go"]="19458dfad25ad5a01d4af1e8ff251378e0b0feb3f7b62474d37eb8cc148a4c23"
BEFORE["about.go"]="483e88b5291d08558cced4c01d89e94fd050b716703d99e4122ce9ae0a0017b8"
BEFORE["syscheck.go"]="e04d9e3e686955ccc6d7322750e069e68f4eb1a372c8c3832692cab35b20e35b"
BEFORE["web/about.html"]="c39ce0430378dd7b84774ac46ca20a42ad7d3725622928690474475330ef2d69"
BEFORE["web/systemcheck.html"]="ee820e04cb6a61c33cc648d22e0e245f5169aef65d215009739be22b991d9219"
BEFORE["README.md"]="a70175a98f9dccbbdcf2bcdc765e2247e932f981bc87b50a8d3ec29473323db3"
AFTER["help.go"]="f4cbe962d0ce357f16504ebb1edfbaecc5a5658ee30fb32be1184918a5da249d"
AFTER["web/app.css"]="23d882f1ab862ee0eb3664d18be15aab414b73922aeb2f66cb49875ceb4462bb"
AFTER["scripts/test-smoke-load.sh"]="53315f32178b0ae3dda464fe3231e5862b65f5cd013a384f6e8d903e4e52f17c"
AFTER["main.go"]="c68dcdec9ed545a24a5bfff15c02dfc13d6d37dec1342104d4d5170ba0c03a38"
AFTER["about.go"]="de4605651b1d79240fc71be283481b0502507d31817cfe717e0bf9f66f21481a"
AFTER["syscheck.go"]="a5c1614e7e23397a4698ff055d18598cc08e4edc7791f5e83e7aad95926468aa"
AFTER["web/about.html"]="a391e38b62493a1130dc31a972048287293d5b7cb685e77fc4d98c8d8be68b81"
AFTER["web/systemcheck.html"]="eec4823d5f81d3dccf1fd2c5949d2fb9a3f215383f69f804a0b66fd3aee3b9e1"
AFTER["README.md"]="735c26400d6e124f23a373d0c3fdb94461bc308fbb569472cb3d051380bc86e2"
AFTER["install.go"]="6ac53c7edf87b22e45a939926c0923398bcb7cbdcd7f354ce9c27dc1a204fd3e"
AFTER["install_test.go"]="bb2824f1bb8dbeca1f4d67004243d76a0c432e4e4ef39ae3cfd54e4c950623ab"
AFTER["places.go"]="ad4a03e50743c2e91b65273f45c294eedf1c8ae3ff14634e738da00c4725b0c6"

# Count of passed checks.
PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/help-performance-guide (git switch feature/help-performance-guide)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 113 must have been applied: the performance reading guide is in help.go.
grep -q 'helpPerfGuideID' help.go || fail "script 113 must be applied first"
# Report it.
pass "script 113 is applied"

# Refuse to run twice: the new file exists when this change was applied before.
if [ -e install.go ]; then fail "install.go already exists: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files to change are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/README.md b/README.md
index f78b230..e131106 100644
--- a/README.md
+++ b/README.md
@@ -2,7 +2,7 @@
 
 A small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, load and unload them, change their settings, test their speed and compare them. It runs on your own computer and needs nothing but Ollama and a web browser.
 
-> **Status: pre-release, version 0.31.0.** Not yet ready for everyday use. See "What is tested" below.
+> **Status: pre-release, version 0.32.0.** Not yet ready for everyday use. See "What is tested" below.
 
 ## What it does
 
@@ -48,6 +48,8 @@ go build -trimpath -o bin\LLMsControlDock.exe .
 
 Then open http://127.0.0.1:8765/ in your browser. On the first start you see a System check of your computer.
 
+Installing is optional: the program runs from wherever you put it and makes its folders when it first needs them. Run it once with `-install` to do everything up front, after it asks you: it shows the System check, makes its folders, copies itself to `~/.local/bin` (Windows: `%LocalAppData%\Programs\LLMsControlDock`) and creates the desktop icon. No administrator rights are needed. The About page shows where the files are.
+
 | Option | Effect |
 |---|---|
 | `-listen host:port` | Where the page listens (default `127.0.0.1:8765`) |
@@ -56,6 +58,7 @@ Then open http://127.0.0.1:8765/ in your browser. On the first start you see a S
 | `-check` | One check, one line; exit code 0 = online, 1 = offline |
 | `-models` | Print the installed and loaded models as tables |
 | `-check-links` | Open every reference address of the comparison page once |
+| `-install` | Install for the current user, after asking (see above) |
 
 The Ollama address can also come from the `LLMSCONTROLDOCK_OLLAMA_URL` environment variable.
 
diff --git a/about.go b/about.go
index a331f8e..90070c3 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of LLMsControlDock; it is raised by hand when a release is made.
-const appVersion = "0.31.0"
+const appVersion = "0.32.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
@@ -146,6 +146,10 @@ type aboutPage struct {
 	Token string
 	// Estimate is the last saved estimate, or nil when there is none.
 	Estimate *estimateView
+	// Places are the places on this computer where the program keeps its files.
+	Places []placeRow
+	// Systems are the same places written for Linux, Windows and macOS.
+	Systems []systemPlaces
 } // end of aboutPage
 
 // revisionFromBuild picks the short revision, the modified flag and the revision date (always shown in UTC) out of the recorded build facts.
@@ -247,6 +251,10 @@ func aboutHandler(token string) http.HandlerFunc {
 			Token: token,
 			// Go version, system and processor.
 			Platform: runtime.Version() + " on " + runtime.GOOS + "/" + runtime.GOARCH,
+			// The places on this computer, from the same functions that create them.
+			Places: placesHere(),
+			// The same places on each system.
+			Systems: placesBySystem(),
 		} // end of the data
 		// The last saved estimate, if there is one.
 		if e, ok := loadSelfEstimate(); ok {
diff --git a/help.go b/help.go
index c6b6217..715daea 100644
--- a/help.go
+++ b/help.go
@@ -109,6 +109,21 @@ const helpPerfGuideID = "read-performance"
 
 // helpTopics are the topics of the Help page, in the order a person typically meets them (first start, finding and loading a model, tuning, testing, comparing, tidying up, settings, stopping, uninstalling); each one is checked against what the program really does.
 var helpTopics = []helpTopic{
+	{
+		ID:    "install",
+		Title: "Install (optional), and where the files go",
+		Intro: "Installing is optional: the program runs from wherever you put it and makes each folder when it first needs it. Running it once with -install does everything up front, after asking, without administrator rights. The About page shows where every folder is, on this computer and on Linux, Windows and macOS.",
+		Steps: []helpStep{
+			{0, "Run the program once with -install in a terminal."},
+			{1, "Runs the System check and prints it."},
+			{2, "Answers with its version."},
+			{1, "Lists the folders, the program copy and the icon."},
+			{0, "Type yes to agree; anything else stops."},
+			{1, "Creates the three folders."},
+			{1, "Copies the program to its standard place."},
+			{1, "Creates the desktop icon and reports each step."},
+		},
+	},
 	{
 		ID:    "system-check",
 		Title: "System check: what this computer offers",
@@ -320,14 +335,14 @@ var helpTopics = []helpTopic{
 	{
 		ID:    "uninstall",
 		Title: "Uninstall",
-		Intro: "Uninstalling deletes what this tool collected on this computer: its settings, the performance results and saved comparisons, the list of deleted models, the check history and the desktop icon. Ollama, its models and the program file are not touched. A running program cannot delete itself, so you delete the program file yourself.",
+		Intro: "Uninstalling deletes what this tool collected on this computer: its settings, the performance results and saved comparisons, the list of deleted models, the check history and the desktop icon, and the program copy that -install placed. Ollama, its models and a program file you started from anywhere else are not touched; you delete that file yourself.",
 		Steps: []helpStep{
 			{0, "Open System check and press Uninstall this tool."},
 			{1, "Lists what would be removed, and where."},
 			{0, "If data was saved, type uninstall and press OK."},
 			{1, "Deletes those items and stops the program."},
 			{2, "Not touched. Its models stay."},
-			{0, "Delete the program file yourself. The page shows where it is."},
+			{0, "Delete any other program file yourself."},
 		},
 	},
 } // end of helpTopics
diff --git a/install.go b/install.go
new file mode 100644
index 0000000..6cf25ce
--- /dev/null
+++ b/install.go
@@ -0,0 +1,521 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bufio reads the person's answer line by line.
+	"bufio"
+	// context limits how long the System check may take.
+	"context"
+	// crypto/sha256 makes the fingerprint that proves an installed copy is the one -install placed.
+	"crypto/sha256"
+	// encoding/hex writes that fingerprint as text.
+	"encoding/hex"
+	// encoding/json reads and writes the small install record.
+	"encoding/json"
+	// errors builds the plain error messages.
+	"errors"
+	// fmt prints the report.
+	"fmt"
+	// io copies the program file and reads the answer.
+	"io"
+	// net/url carries the Ollama address.
+	"net/url"
+	// os reads and writes files and folders.
+	"os"
+	// path/filepath builds paths the way each system writes them.
+	"path/filepath"
+	// runtime names the system the program runs on.
+	"runtime"
+	// strings compares the answer and lists PATH entries.
+	"strings"
+	// time stamps the install record and limits the check.
+	"time"
+) // end of imports
+
+// installRecordFileName is the small file in the state folder that remembers what -install placed, so Uninstall removes exactly that copy and nothing else.
+const installRecordFileName = "install.json"
+
+// installRecord is what -install remembers about the copy it placed.
+type installRecord struct {
+	// Path is where the copy was placed.
+	Path string `json:"path"`
+	// Version is the version of the copy.
+	Version string `json:"version"`
+	// SHA256 is the fingerprint of the copy, so a changed or replaced file is never removed.
+	SHA256 string `json:"sha256"`
+	// Time is when it was placed.
+	Time time.Time `json:"time"`
+} // end of installRecord
+
+// installTargetFor gives the standard place of the installed program for a system, without administrator rights: ~/.local/bin on Linux and macOS, %LocalAppData%\Programs\LLMsControlDock on Windows.
+func installTargetFor(goos string, getenv func(string) string, home func() (string, error)) (string, error) {
+	// Windows keeps per-user programs under %LocalAppData%\Programs.
+	if goos == "windows" {
+		// The folder of per-user data that is not copied between computers.
+		local := getenv("LocalAppData")
+		// Without it there is no standard place.
+		if local == "" {
+			// Say why.
+			return "", errors.New("%LocalAppData% is not defined")
+		} // end of the variable check
+		// The program's own folder and file.
+		return filepath.Join(local, "Programs", dataFolderName, dataFolderName+".exe"), nil
+	} // end of the Windows case
+	// Linux, macOS and the rest: the user's own program folder.
+	h, err := home()
+	// Without a home folder there is no standard place.
+	if err != nil || h == "" {
+		// Say why.
+		return "", errors.New("$HOME is not defined")
+	} // end of the home check
+	// The file in ~/.local/bin.
+	return filepath.Join(h, ".local", "bin", dataFolderName), nil
+} // end of installTargetFor
+
+// installTarget gives the standard place of the installed program on this computer; it is a variable so tests can point it elsewhere.
+var installTarget = func() (string, error) {
+	// The real system, environment and home folder.
+	return installTargetFor(runtime.GOOS, os.Getenv, os.UserHomeDir)
+} // end of installTarget
+
+// fileSHA256 gives the fingerprint of a file, or an empty text when it cannot be read.
+func fileSHA256(path string) string {
+	// Open the file.
+	f, err := os.Open(path)
+	// Unreadable: no fingerprint.
+	if err != nil {
+		// Empty.
+		return ""
+	} // end of the open check
+	// Close it at the end.
+	defer f.Close()
+	// The hash being built.
+	h := sha256.New()
+	// Feed the whole file.
+	if _, err := io.Copy(h, f); err != nil {
+		// A read error: no fingerprint.
+		return ""
+	} // end of the copy check
+	// The fingerprint as text.
+	return hex.EncodeToString(h.Sum(nil))
+} // end of fileSHA256
+
+// readInstallRecord reads what -install remembered, from the given state folder.
+func readInstallRecord(stateDir string) (installRecord, bool) {
+	// No state folder: nothing was installed.
+	if stateDir == "" {
+		// Nothing.
+		return installRecord{}, false
+	} // end of the folder check
+	// Read the small file.
+	raw, err := os.ReadFile(filepath.Join(stateDir, installRecordFileName))
+	// Missing or unreadable: nothing known.
+	if err != nil {
+		// Nothing.
+		return installRecord{}, false
+	} // end of the read check
+	// The record.
+	var rec installRecord
+	// Decode it; a broken file counts as no record.
+	if err := json.Unmarshal(raw, &rec); err != nil || rec.Path == "" {
+		// Nothing.
+		return installRecord{}, false
+	} // end of the decode check
+	// Found.
+	return rec, true
+} // end of readInstallRecord
+
+// installedCopy says whether the copy that -install placed is still there, unchanged and in the standard place; only then may Uninstall remove it.
+func installedCopy(stateDir string) (string, bool) {
+	// What -install remembered.
+	rec, ok := readInstallRecord(stateDir)
+	// Nothing remembered.
+	if !ok {
+		// Nothing to remove.
+		return "", false
+	} // end of the record check
+	// The standard place now.
+	target, err := installTarget()
+	// It must be exactly the standard place, so a record can never point Uninstall at another file.
+	if err != nil || filepath.Clean(rec.Path) != filepath.Clean(target) {
+		// Not ours.
+		return "", false
+	} // end of the place check
+	// The file must be a plain file (a link is never followed).
+	if info, err := os.Lstat(target); err != nil || !info.Mode().IsRegular() {
+		// Not there, or not a plain file.
+		return "", false
+	} // end of the file check
+	// It must still be the very file that was placed.
+	if fileSHA256(target) != rec.SHA256 {
+		// Changed or replaced: left alone.
+		return "", false
+	} // end of the fingerprint check
+	// It is ours.
+	return target, true
+} // end of installedCopy
+
+// copyProgram copies the program file to its place: into a temporary file first, then renamed, so a half-written program is never left behind.
+func copyProgram(src, dst string) error {
+	// The folder of the target, readable by the person only and by programs that start it.
+	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
+		// Say what failed.
+		return err
+	} // end of the folder check
+	// Open the running program's file.
+	in, err := os.Open(src)
+	// Unreadable.
+	if err != nil {
+		// Say what failed.
+		return err
+	} // end of the open check
+	// Close it at the end.
+	defer in.Close()
+	// The temporary file next to the target.
+	tmp := dst + ".new"
+	// Create it, runnable.
+	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
+	// Not writable.
+	if err != nil {
+		// Say what failed.
+		return err
+	} // end of the create check
+	// Copy every byte.
+	_, copyErr := io.Copy(out, in)
+	// Make sure it reached the disk.
+	syncErr := out.Sync()
+	// Close it.
+	closeErr := out.Close()
+	// Any of the three failed: remove the half copy.
+	if err := errors.Join(copyErr, syncErr, closeErr); err != nil {
+		// Remove it.
+		os.Remove(tmp)
+		// Say what failed.
+		return err
+	} // end of the write check
+	// Replace the target in one step.
+	if err := os.Rename(tmp, dst); err != nil {
+		// Remove the temporary file.
+		os.Remove(tmp)
+		// Windows refuses to replace a program that is running.
+		return fmt.Errorf("%v (if the installed copy is running, stop it first and run -install again)", err)
+	} // end of the rename check
+	// Done.
+	return nil
+} // end of copyProgram
+
+// installStep is one thing -install does, with its plan line and its action.
+type installStep struct {
+	// Plan is the line shown before asking.
+	Plan string
+	// Do performs it and returns a short result.
+	Do func() (string, error)
+} // end of installStep
+
+// installEnv holds what -install reads and writes, so a test can run it on a throw-away folder with a fake Ollama.
+type installEnv struct {
+	// in is where the answer is read from.
+	in io.Reader
+	// out is where the report is written.
+	out io.Writer
+	// ollama is the Ollama address for the System check.
+	ollama *url.URL
+	// exe is the running program's file.
+	exe func() (string, error)
+	// desktop is the desktop icon helper.
+	desktop desktopEnv
+} // end of installEnv
+
+// runInstall is the -install mode: it shows the System check and the plan, asks for permission, and then does exactly the planned steps with the program's own code; it returns the exit code.
+func runInstall(e installEnv) int {
+	// The report goes to the given output.
+	w := e.out
+	// The heading.
+	fmt.Fprintf(w, "LLMsControlDock %s - installation\n\n", appVersion)
+
+	// 1. The existing System check: the computer, then Ollama and the requirements.
+	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
+	// Free the timer at the end.
+	defer cancel()
+	// What the computer reports.
+	rep := collectReport(ctx)
+	// Whether Ollama answers, and its version.
+	res := checkOllama(ctx, e.ollama, defaultCheckTimeout)
+	// The judgements of the hardware and of the versions.
+	findings, env := judgeReport(rep), buildEnvView(res.Online, res.Version, reportOS, reportArch)
+	// The heading of the check.
+	fmt.Fprintln(w, "System check")
+	// Each row of the report.
+	for _, row := range reportRows(rep) {
+		// The label and the value on one line.
+		fmt.Fprintf(w, "  %-22s %s\n", row.Label+":", strings.Join(row.Lines, "; "))
+	} // end of the row loop
+	// Ollama.
+	if res.Online {
+		// It answers.
+		fmt.Fprintf(w, "  %-22s answers at %s, version %s\n", "Ollama:", e.ollama.Redacted(), res.Version)
+	} else {
+		// It does not answer.
+		fmt.Fprintf(w, "  %-22s does not answer at %s (%s)\n", "Ollama:", e.ollama.Redacted(), res.Reason)
+	} // end of the Ollama line
+	// The sentences already printed, so a problem that repeats a judgement is not printed twice.
+	printed := map[string]bool{}
+	// Every judgement, marked so it reads without colour.
+	for _, f := range append(findings, env.OllamaVerdict, env.GoVerdict, env.SystemVerdict) {
+		// Skip empty judgements.
+		if f.Text == "" {
+			continue
+		} // end of the empty check
+		// Remember it.
+		printed[f.Text] = true
+		// The mark: OK, ! for a warning, i for information.
+		mark := map[string]string{"ok": "OK", "warn": " !", "info": " i"}[f.Level]
+		// The line.
+		fmt.Fprintf(w, "  [%s] %s\n", mark, f.Text)
+	} // end of the judgement loop
+	// The problems that need fixing, with their reason.
+	problems := collectProblems(res.Online, e.ollama.Redacted(), reportOS, env, findings)
+	// Each problem.
+	for _, p := range problems {
+		// Already said in a judgement.
+		if printed[p.Why] {
+			continue
+		} // end of the repeat check
+		// Its title and why it matters.
+		fmt.Fprintf(w, "  [ !] %s: %s\n", p.Title, p.Why)
+	} // end of the problem loop
+	// Point to the full report.
+	if len(problems) > 0 {
+		// The steps to fix are on the System check page.
+		fmt.Fprintln(w, "  The steps to fix these are on the System check page of the monitor.")
+	} // end of the problem note
+	// A blank line.
+	fmt.Fprintln(w)
+
+	// 2. The plan.
+	steps, err := installPlan(e)
+	// Something basic is missing (for example no home folder).
+	if err != nil {
+		// Say so; nothing was changed.
+		fmt.Fprintf(w, "Cannot install: %v. Nothing was changed.\n", err)
+		// Failure.
+		return 1
+	} // end of the plan check
+	// The heading.
+	fmt.Fprintln(w, "This installation will:")
+	// Each step.
+	for i, s := range steps {
+		// Numbered.
+		fmt.Fprintf(w, "  %d. %s\n", i+1, s.Plan)
+	} // end of the plan loop
+	// What is never touched.
+	fmt.Fprintln(w, "Not touched: Ollama and your models. Nothing needs administrator rights. You can still run the program from anywhere without installing.")
+	// A blank line.
+	fmt.Fprintln(w)
+
+	// 3. Permission.
+	fmt.Fprint(w, "Type yes to install, or anything else to stop: ")
+	// Read one line.
+	answer, _ := bufio.NewReader(e.in).ReadString('\n')
+	// Only "yes" agrees.
+	if !strings.EqualFold(strings.TrimSpace(answer), "yes") {
+		// Nothing happens.
+		fmt.Fprintln(w, "\nStopped. Nothing was changed.")
+		// Not an error, but not installed either.
+		return 1
+	} // end of the permission check
+	// A blank line.
+	fmt.Fprintln(w)
+
+	// 4. Do it, step by step, and report each result.
+	failed := 0
+	// Each step.
+	for i, s := range steps {
+		// Run it.
+		result, err := s.Do()
+		// A failure is reported and the next steps still run.
+		if err != nil {
+			// Count it.
+			failed++
+			// Report it.
+			fmt.Fprintf(w, "  %d. FAILED: %v\n", i+1, err)
+			// Next step.
+			continue
+		} // end of the failure case
+		// Report the result.
+		fmt.Fprintf(w, "  %d. %s\n", i+1, result)
+	} // end of the step loop
+	// A blank line.
+	fmt.Fprintln(w)
+	// The end.
+	if failed > 0 {
+		// Some steps failed.
+		fmt.Fprintf(w, "Installation finished with %d failed step(s); see above.\n", failed)
+		// Failure.
+		return 1
+	} // end of the failure summary
+	// How to start it.
+	target, _ := installTarget()
+	// Success.
+	fmt.Fprintf(w, "Installed. Start it with the desktop icon, or with: %s\n", target)
+	// On Linux and macOS, say when ~/.local/bin is not in the PATH.
+	if runtime.GOOS != "windows" && !inPath(filepath.Dir(target), os.Getenv("PATH")) {
+		// A hint, not an error.
+		fmt.Fprintf(w, "Note: %s is not in your PATH, so type the full path above (or add the folder to your PATH).\n", filepath.Dir(target))
+	} // end of the PATH note
+	// Success.
+	return 0
+} // end of runInstall
+
+// inPath says whether a folder is one of the folders of a PATH list.
+func inPath(dir, pathList string) bool {
+	// Each folder of the list.
+	for _, p := range filepath.SplitList(pathList) {
+		// A match.
+		if filepath.Clean(p) == filepath.Clean(dir) {
+			// Found.
+			return true
+		} // end of the match
+	} // end of the loop
+	// Not found.
+	return false
+} // end of inPath
+
+// installPlan works out the steps of the installation; it changes nothing.
+func installPlan(e installEnv) ([]installStep, error) {
+	// The three folders, from the same code the program uses when it creates them by itself.
+	folders := []struct{ what, dir string }{{"settings", configRoot()}, {"data (results, saved copies, deleted models)", dataRoot()}, {"state (check history, log)", stateRoot()}}
+	// The steps.
+	var steps []installStep
+	// Each folder.
+	for _, f := range folders {
+		// No standard place on this system.
+		if f.dir == "" {
+			// Cannot install.
+			return nil, fmt.Errorf("no standard place for the %s folder", f.what)
+		} // end of the place check
+		// A copy for the closure below.
+		dir, what := f.dir, f.what
+		// Whether it exists already.
+		state := "create"
+		// It does.
+		if _, err := os.Stat(dir); err == nil {
+			// Nothing to create.
+			state = "keep (it exists already)"
+		} // end of the exists check
+		// The step.
+		steps = append(steps, installStep{Plan: fmt.Sprintf("%s the %s folder: %s", strings.ToUpper(state[:1])+state[1:], what, dir), Do: func() (string, error) {
+			// The same permissions the program uses: the person only.
+			if err := os.MkdirAll(dir, 0o700); err != nil {
+				// Say what failed.
+				return "", err
+			} // end of the create check
+			// Done.
+			return "Folder ready: " + dir, nil
+		}}) // end of the folder step
+	} // end of the folder loop
+	// The running program and the standard place.
+	exe, err := e.exe()
+	// The running program cannot be found.
+	if err != nil {
+		// Cannot install.
+		return nil, fmt.Errorf("the running program file cannot be found: %v", err)
+	} // end of the program check
+	// Follow links, so the real file is copied.
+	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
+		// The real file.
+		exe = resolved
+	} // end of the link check
+	// The standard place.
+	target, err := installTarget()
+	// No standard place.
+	if err != nil {
+		// Cannot install.
+		return nil, err
+	} // end of the target check
+	// The state folder, where the record is kept.
+	state := stateRoot()
+	// The program step.
+	switch {
+	// This already is the installed copy.
+	case filepath.Clean(exe) == filepath.Clean(target):
+		// Nothing to copy; the record is refreshed.
+		steps = append(steps, installStep{Plan: "Keep the program where it is: this already is the installed copy (" + target + ")", Do: func() (string, error) {
+			// Refresh the record.
+			return "Program kept: " + target, writeInstallRecord(state, target)
+		}}) // end of the keep step
+	default:
+		// What is there now.
+		plan := "Copy the program to " + target
+		// Something is there already.
+		if _, err := os.Stat(target); err == nil {
+			// Its version, when -install placed it.
+			old := "an unknown version"
+			// The record names it.
+			if rec, ok := readInstallRecord(state); ok && filepath.Clean(rec.Path) == filepath.Clean(target) {
+				// The version.
+				old = "version " + rec.Version
+			} // end of the version check
+			// Say both versions.
+			plan = fmt.Sprintf("Replace the installed program (%s) with version %s at %s; settings and results are kept", old, appVersion, target)
+		} // end of the replace case
+		// The step.
+		steps = append(steps, installStep{Plan: plan, Do: func() (string, error) {
+			// Copy the file.
+			if err := copyProgram(exe, target); err != nil {
+				// Say what failed.
+				return "", err
+			} // end of the copy check
+			// Remember it, so Uninstall can remove exactly this copy.
+			if err := writeInstallRecord(state, target); err != nil {
+				// Say what failed.
+				return "", err
+			} // end of the record check
+			// Done.
+			return "Program copied: " + target, nil
+		}}) // end of the copy step
+	} // end of the program switch
+	// The desktop icon, made by the existing code, pointing at the installed copy.
+	icon := desktopIcon{env: e.desktop, dir: configRoot(), dataDir: dataRoot()}
+	// The icon starts the installed copy, not the file this was run from.
+	icon.env.exePath = func() (string, error) { return target, nil }
+	// This computer has a desktop the program can use.
+	if _, ok := icon.env.desktopDir(); ok {
+		// The step.
+		steps = append(steps, installStep{Plan: "Create the desktop icon (it starts the installed program)", Do: func() (string, error) {
+			// The same code as the button in Settings.
+			if err := icon.create(); err != nil {
+				// Say what failed.
+				return "", err
+			} // end of the create check
+			// Done.
+			return "Desktop icon created: " + icon.desktopPath(), nil
+		}}) // end of the icon step
+	} else {
+		// No desktop: said in the plan, nothing to do.
+		steps = append(steps, installStep{Plan: "Desktop icon: not possible here (no desktop session, or no Desktop folder); you can create it later in Settings", Do: func() (string, error) {
+			// Nothing done.
+			return "Desktop icon skipped (no desktop here)", nil
+		}}) // end of the no-icon step
+	} // end of the icon choice
+	// The plan.
+	return steps, nil
+} // end of installPlan
+
+// writeInstallRecord remembers the installed copy in the state folder.
+func writeInstallRecord(stateDir, target string) error {
+	// The folder must exist (step 1 made it).
+	if err := os.MkdirAll(stateDir, 0o700); err != nil {
+		// Say what failed.
+		return err
+	} // end of the folder check
+	// The record.
+	raw, err := json.MarshalIndent(installRecord{Path: target, Version: appVersion, SHA256: fileSHA256(target), Time: time.Now().UTC()}, "", "  ")
+	// Cannot happen with these fields, but checked anyway.
+	if err != nil {
+		// Say what failed.
+		return err
+	} // end of the encode check
+	// Write it, readable by the person only.
+	return os.WriteFile(filepath.Join(stateDir, installRecordFileName), raw, 0o600)
+} // end of writeInstallRecord
diff --git a/install_test.go b/install_test.go
new file mode 100644
index 0000000..a9fafed
--- /dev/null
+++ b/install_test.go
@@ -0,0 +1,321 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes collects what -install prints.
+	"bytes"
+	// context is part of the fake tool runner's signature.
+	"context"
+	// encoding/json reads the install record.
+	"encoding/json"
+	// errors makes the fake tool runner fail.
+	"errors"
+	// net/http provides status codes for the fake Ollama.
+	"net/http"
+	// net/url parses the fake Ollama's address.
+	"net/url"
+	// os reads and writes the throw-away files.
+	"os"
+	// path/filepath builds the throw-away paths.
+	"path/filepath"
+	// strings looks for words in the output and the pages.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// TestInstallTargetFor checks the standard place of the installed program on each system, and the error when nothing names it.
+func TestInstallTargetFor(t *testing.T) {
+	// A home folder.
+	home := func() (string, error) { return "/home/a", nil }
+	// No home folder.
+	noHome := func() (string, error) { return "", errors.New("none") }
+	// Windows variables.
+	env := func(name string) string { return map[string]string{"LocalAppData": `C:\Users\a\AppData\Local`}[name] }
+	// Linux and macOS: ~/.local/bin.
+	for _, goos := range []string{"linux", "darwin"} {
+		// The place.
+		got, err := installTargetFor(goos, env, home)
+		// Exactly there.
+		if err != nil || got != filepath.Join("/home/a", ".local", "bin", "LLMsControlDock") {
+			// Report.
+			t.Errorf("%s: %q %v", goos, got, err)
+		} // end of the check
+	} // end of the loop
+	// Windows: %LocalAppData%\Programs\LLMsControlDock\LLMsControlDock.exe.
+	if got, err := installTargetFor("windows", env, home); err != nil || got != filepath.Join(`C:\Users\a\AppData\Local`, "Programs", "LLMsControlDock", "LLMsControlDock.exe") {
+		// Report.
+		t.Errorf("windows: %q %v", got, err)
+	} // end of the Windows check
+	// Missing names give an error, never a guess.
+	if _, err := installTargetFor("windows", func(string) string { return "" }, home); err == nil {
+		// Report.
+		t.Error("windows without LocalAppData gave no error")
+	} // end of the Windows error check
+	// No home folder on Linux.
+	if _, err := installTargetFor("linux", env, noHome); err == nil {
+		// Report.
+		t.Error("linux without HOME gave no error")
+	} // end of the Linux error check
+} // end of TestInstallTargetFor
+
+// TestPlacesBySystem checks the About page's table of places for each system, which is made from the same functions that create the folders.
+func TestPlacesBySystem(t *testing.T) {
+	// The expected table.
+	want := []systemPlaces{
+		// Settings.
+		{"Settings", "~/.config/LLMsControlDock", `%AppData%\LLMsControlDock`, "~/Library/Application Support/LLMsControlDock"},
+		// Data.
+		{"Results, saved copies and deleted models", "~/.local/share/LLMsControlDock", `%LocalAppData%\LLMsControlDock`, "~/Library/Application Support/LLMsControlDock"},
+		// State.
+		{"Check history and log", "~/.local/state/LLMsControlDock", `%LocalAppData%\LLMsControlDock`, "~/Library/Application Support/LLMsControlDock"},
+		// The installed program.
+		{"Installed program (placed by -install)", "~/.local/bin/LLMsControlDock", `%LocalAppData%\Programs\LLMsControlDock\LLMsControlDock.exe`, "~/.local/bin/LLMsControlDock"},
+	} // end of the expected table
+	// The table.
+	got := placesBySystem()
+	// Same length.
+	if len(got) != len(want) {
+		// Stop.
+		t.Fatalf("%d rows, want %d", len(got), len(want))
+	} // end of the length check
+	// Each row.
+	for i := range want {
+		// Equal.
+		if got[i] != want[i] {
+			// Report.
+			t.Errorf("row %d:\n got %+v\nwant %+v", i, got[i], want[i])
+		} // end of the row check
+	} // end of the row loop
+} // end of TestPlacesBySystem
+
+// installRig is a throw-away home folder, program file and Ollama for one -install test.
+type installRig struct {
+	// home is the throw-away home folder.
+	home string
+	// exe is the pretend program file.
+	exe string
+	// target is where the copy goes.
+	target string
+	// ollama is the fake Ollama's address.
+	ollama *url.URL
+} // end of installRig
+
+// newInstallRig makes a throw-away home with no folders yet, a pretend program file, a fake Ollama and no real tools or desktop.
+func newInstallRig(t *testing.T) installRig {
+	// Mark this as a helper.
+	t.Helper()
+	// The throw-away home.
+	home := t.TempDir()
+	// The program's folders follow this home.
+	t.Setenv("HOME", home)
+	// No XDG overrides.
+	for _, n := range []string{"XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"} {
+		// Cleared for this test.
+		t.Setenv(n, "")
+	} // end of the loop
+	// The three base folders point into the throw-away home (the test suite points the settings elsewhere by default), and back at the end.
+	oldCfg, oldData, oldState := userConfigDir, userDataDir, userStateDir
+	// Restore.
+	t.Cleanup(func() { userConfigDir, userDataDir, userStateDir = oldCfg, oldData, oldState })
+	// Settings.
+	userConfigDir = func() (string, error) { return filepath.Join(home, ".config"), nil }
+	// Data.
+	userDataDir = func() (string, error) { return filepath.Join(home, ".local", "share"), nil }
+	// State.
+	userStateDir = func() (string, error) { return filepath.Join(home, ".local", "state"), nil }
+	// The pretend program file, somewhere else.
+	exe := filepath.Join(t.TempDir(), "LLMsControlDock")
+	// Some bytes.
+	if err := os.WriteFile(exe, []byte("pretend program"), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// The copy goes into the home folder's ~/.local/bin.
+	target := filepath.Join(home, ".local", "bin", "LLMsControlDock")
+	// Point -install there, and back at the end.
+	old := installTarget
+	// Restore.
+	t.Cleanup(func() { installTarget = old })
+	// The test place.
+	installTarget = func() (string, error) { return target, nil }
+	// No real tool runs during the System check.
+	oldProbe := probeRun
+	// Restore.
+	t.Cleanup(func() { probeRun = oldProbe })
+	// Every tool "fails", so the report says "not reported".
+	probeRun = func(ctx context.Context, name string, args ...string) (string, error) {
+		return "", errors.New("no tools in tests")
+	}
+	// A fake Ollama that answers.
+	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
+	// Its address.
+	u, _ := url.Parse(srv.URL)
+	// The rig.
+	return installRig{home: home, exe: exe, target: target, ollama: u}
+} // end of newInstallRig
+
+// run runs -install with an answer and returns the exit code and what it printed.
+func (r installRig) run(answer string) (int, string) {
+	// The output.
+	var out bytes.Buffer
+	// Run it with no desktop.
+	code := runInstall(installEnv{in: strings.NewReader(answer), out: &out, ollama: r.ollama, exe: func() (string, error) { return r.exe, nil }, desktop: noDesktopEnv()})
+	// Both.
+	return code, out.String()
+} // end of run
+
+// TestRunInstall checks the whole -install mode: the System check and the plan are shown, a "no" changes nothing, a "yes" makes the folders, copies the program and remembers it, and a second run shows both versions before replacing.
+func TestRunInstall(t *testing.T) {
+	// The rig.
+	r := newInstallRig(t)
+	// Say no.
+	code, out := r.run("no\n")
+	// Refused, with the check and the plan shown first.
+	if code != 1 || !strings.Contains(out, "System check") || !strings.Contains(out, "This installation will:") || !strings.Contains(out, "Nothing was changed") {
+		// Report.
+		t.Fatalf("no: code %d, output:\n%s", code, out)
+	} // end of the refusal check
+	// Nothing was made.
+	for _, p := range []string{configRoot(), dataRoot(), stateRoot(), r.target} {
+		// Must not exist.
+		if _, err := os.Stat(p); err == nil {
+			// Report.
+			t.Errorf("%s exists after a no", p)
+		} // end of the exists check
+	} // end of the loop
+	// Say yes.
+	code, out = r.run("yes\n")
+	// Installed.
+	if code != 0 || !strings.Contains(out, "Installed.") {
+		// Stop.
+		t.Fatalf("yes: code %d, output:\n%s", code, out)
+	} // end of the success check
+	// The three folders exist, for the person only.
+	for _, p := range []string{configRoot(), dataRoot(), stateRoot()} {
+		// Look.
+		info, err := os.Stat(p)
+		// A folder with 0700.
+		if err != nil || !info.IsDir() || info.Mode().Perm() != 0o700 {
+			// Report.
+			t.Errorf("%s: %v %v", p, info, err)
+		} // end of the folder check
+	} // end of the loop
+	// The copy has the same bytes and is runnable.
+	got, err := os.ReadFile(r.target)
+	// Same bytes.
+	if err != nil || string(got) != "pretend program" {
+		// Report.
+		t.Errorf("copy: %q %v", got, err)
+	} // end of the bytes check
+	// Runnable.
+	if info, err := os.Stat(r.target); err != nil || info.Mode().Perm()&0o100 == 0 {
+		// Report.
+		t.Errorf("the copy is not runnable: %v %v", info, err)
+	} // end of the mode check
+	// The record names the copy, the version and its fingerprint.
+	raw, _ := os.ReadFile(filepath.Join(stateRoot(), installRecordFileName))
+	// Decode it.
+	var rec installRecord
+	// It must decode and match.
+	if json.Unmarshal(raw, &rec) != nil || rec.Path != r.target || rec.Version != appVersion || rec.SHA256 != fileSHA256(r.target) {
+		// Report.
+		t.Errorf("record: %s", raw)
+	} // end of the record check
+	// Uninstall may now remove exactly this copy.
+	if p, ok := installedCopy(stateRoot()); !ok || p != r.target {
+		// Report.
+		t.Errorf("installedCopy: %q %v", p, ok)
+	} // end of the installed check
+	// The desktop icon was skipped and said so (no desktop in tests).
+	if !strings.Contains(out, "Desktop icon skipped") {
+		// Report.
+		t.Error("the missing desktop was not reported")
+	} // end of the icon check
+	// A second run shows both versions before replacing.
+	code, out = r.run("no\n")
+	// The plan names the installed version.
+	if code != 1 || !strings.Contains(out, "Replace the installed program (version "+appVersion+") with version "+appVersion) {
+		// Report.
+		t.Errorf("second run plan:\n%s", out)
+	} // end of the second-run check
+} // end of TestRunInstall
+
+// TestUninstallRemovesOnlyTheInstalledCopy checks that Uninstall lists and removes the copy -install placed, and leaves a changed copy alone.
+func TestUninstallRemovesOnlyTheInstalledCopy(t *testing.T) {
+	// The rig.
+	r := newInstallRig(t)
+	// Install.
+	if code, out := r.run("yes\n"); code != 0 {
+		// Stop.
+		t.Fatalf("install failed:\n%s", out)
+	} // end of the install check
+	// The plan of the uninstall, with no desktop.
+	plan := uninstallPlan(desktopIcon{env: noDesktopEnv()})
+	// Find the program item.
+	var item *uninstallItem
+	// Look through the plan.
+	for i := range plan {
+		// The program item.
+		if plan[i].Where == r.target {
+			// Found.
+			item = &plan[i]
+		} // end of the match
+	} // end of the search
+	// It must be listed.
+	if item == nil {
+		// Stop.
+		t.Fatalf("the installed copy is not in the uninstall plan: %+v", plan)
+	} // end of the listed check
+	// Remove it.
+	if err := item.remove(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the remove check
+	// It is gone; the running program file is untouched.
+	if _, err := os.Stat(r.target); err == nil {
+		// Report.
+		t.Error("the installed copy is still there")
+	} // end of the gone check
+	// The running program file stays.
+	if _, err := os.Stat(r.exe); err != nil {
+		// Report.
+		t.Error("the running program file was touched")
+	} // end of the untouched check
+	// Install again, then change the copy: a changed file is never removed.
+	if code, out := r.run("yes\n"); code != 0 {
+		// Stop.
+		t.Fatalf("second install failed:\n%s", out)
+	} // end of the second install check
+	// Change the copy.
+	if err := os.WriteFile(r.target, []byte("someone else's file"), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the change
+	// No longer listed.
+	for _, it := range uninstallPlan(desktopIcon{env: noDesktopEnv()}) {
+		// The program must not be in the plan.
+		if it.Where == r.target {
+			// Report.
+			t.Error("a changed copy is listed for removal")
+		} // end of the match
+	} // end of the loop
+} // end of TestUninstallRemovesOnlyTheInstalledCopy
+
+// TestAboutShowsThePlaces checks the About page's card of places: this computer's three folders with their state, the installed program's place, and the table for each system.
+func TestAboutShowsThePlaces(t *testing.T) {
+	// The rig gives a throw-away home, so the folders do not exist yet.
+	r := newInstallRig(t)
+	// The page.
+	rig := newThemeRig(t)
+	// Fetch it.
+	_, _, body := get(t, rig.h, http.MethodGet, "/about")
+	// The card and its parts.
+	for _, want := range []string{`id="places"`, "Where this program keeps its files", "<code>" + configRoot() + "</code>", "<code>" + dataRoot() + "</code>", "<code>" + stateRoot() + "</code>", "<code>" + r.target + "</code>", "not installed", "not yet: made when you press Continue", "<code>~/.local/bin/LLMsControlDock</code>", `<code>%LocalAppData%\Programs\LLMsControlDock\LLMsControlDock.exe</code>`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the About page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+} // end of TestAboutShowsThePlaces
diff --git a/main.go b/main.go
index 662e97e..f5b6467 100644
--- a/main.go
+++ b/main.go
@@ -121,6 +121,8 @@ func main() {
 	checkFlag := flag.Bool("check", false, "check Ollama once, print one status line, and exit (0 = online, 1 = offline)")
 	// Define a -models switch: false unless given on the command line.
 	modelsFlag := flag.Bool("models", false, "print the installed and loaded models as tables, and exit (0 = printed, 1 = Ollama not reachable)")
+	// Define an -install switch: the optional installation for the current user, after asking.
+	installFlag := flag.Bool("install", false, "install this program for the current user after asking: shows the System check, creates the folders, copies the program to its standard place and creates the desktop icon (no administrator rights needed)")
 	// Define a -check-links switch: opens every reference address of the comparison page once, prints the result, and exits (the only time the program contacts the internet).
 	linksFlag := flag.Bool("check-links", false, "open every reference address of the comparison page once, print which answer, and exit (0 = all answered, 1 = at least one did not)")
 	// Read the command line now, so the variables above receive their values.
@@ -129,7 +131,7 @@ func main() {
 	// The one-shot modes cannot be combined; ask the person to choose one.
 	modes := 0
 	// Count the modes that were given.
-	for _, on := range []bool{*checkFlag, *modelsFlag, *linksFlag, *launchFlag} {
+	for _, on := range []bool{*checkFlag, *modelsFlag, *linksFlag, *launchFlag, *installFlag} {
 		// One more mode.
 		if on {
 			// Count it.
@@ -139,7 +141,7 @@ func main() {
 	// More than one is not allowed.
 	if modes > 1 {
 		// log.Fatal prints the message and exits with code 1.
-		log.Fatal("use only one of -check, -models, -check-links and -launch")
+		log.Fatal("use only one of -check, -models, -check-links, -launch and -install")
 	} // end of the combination check
 
 	// In -check-links mode, no Ollama is needed: open the reference addresses, print the result and leave.
@@ -180,6 +182,12 @@ func main() {
 	// Print the address (any password shown as xxxxx) and which layer supplied it.
 	log.Printf("Ollama address: %s (from %s)", addr.URL.Redacted(), addr.Source)
 
+	// The install mode: the System check, the plan, the question, then the steps.
+	if *installFlag {
+		// Run it with the real input, output, Ollama address, program file and desktop, and leave with its exit code.
+		os.Exit(runInstall(installEnv{in: os.Stdin, out: os.Stdout, ollama: addr.URL, exe: os.Executable, desktop: realDesktopEnv()}))
+	} // end of the install mode
+
 	// In -models mode, print both tables and leave without starting the web page.
 	if *modelsFlag {
 		// Run it and leave with its exit code.
diff --git a/places.go b/places.go
new file mode 100644
index 0000000..c62b3d7
--- /dev/null
+++ b/places.go
@@ -0,0 +1,138 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// os checks whether a folder exists already.
+	"os"
+	// strings changes the separators for Windows.
+	"strings"
+) // end of imports
+
+// placeRow is one place on this computer where the program keeps something: what, where, and whether it exists yet.
+type placeRow struct {
+	// What names it in words.
+	What string
+	// Where is the full path.
+	Where string
+	// State says whether it exists yet, or when it is made.
+	State string
+} // end of placeRow
+
+// systemPlaces is one kind of place, written for each system, so the About page can show where it is on Linux, Windows and macOS.
+type systemPlaces struct {
+	// What names it in words.
+	What string
+	// Linux, Windows and Mac are the paths on each system.
+	Linux, Windows, Mac string
+} // end of systemPlaces
+
+// existsText says in words whether a path exists yet.
+func existsText(path, later string) string {
+	// No path: the system has no standard place.
+	if path == "" {
+		// Say so.
+		return "no standard place on this system"
+	} // end of the empty check
+	// It exists.
+	if _, err := os.Stat(path); err == nil {
+		// Say so.
+		return "exists"
+	} // end of the exists check
+	// Not yet: say when it is made.
+	return "not yet: " + later
+} // end of existsText
+
+// placesHere lists the places on this computer, using the same functions that create them.
+func placesHere() []placeRow {
+	// The running program.
+	exe, _ := executablePath()
+	// The installed copy's standard place.
+	target, _ := installTarget()
+	// Whether -install placed it there.
+	installed := "not installed (optional: run the program once with -install)"
+	// The copy is there and is the one -install placed.
+	if _, ok := installedCopy(stateRoot()); ok {
+		// Say so.
+		installed = "installed"
+	} // end of the installed check
+	// The rows, in the order the program creates them.
+	return []placeRow{
+		// The settings folder.
+		{"Settings", configRoot(), existsText(configRoot(), "made when you press Continue on the System check or save a setting")},
+		// The data folder.
+		{"Results, saved copies and deleted models", dataRoot(), existsText(dataRoot(), "made at the first performance test, saved comparison, deleted model, Find LLM search, estimate or desktop icon")},
+		// The state folder.
+		{"Check history and log", stateRoot(), existsText(stateRoot(), "made when the desktop icon starts the program, or when saving the check history is turned on in Settings")},
+		// The program that is running now.
+		{"This program file (running now)", exe, "exists"},
+		// The standard place of the installed copy.
+		{"Installed program (placed by -install)", target, installed},
+	} // end of the rows
+} // end of placesHere
+
+// placeFor writes where one kind of place is on a system, from the same function the program uses, with ~ and %Name% standing for the person's own folders.
+func placeFor(goos, kind string) string {
+	// The person's folders as placeholders, so the text is the same on every computer.
+	getenv := func(name string) string {
+		// Windows names its folders with variables.
+		if name == "AppData" || name == "LocalAppData" {
+			// The variable as people write it.
+			return "%" + name + "%"
+		} // end of the Windows names
+		// No XDG override: the standard places.
+		return ""
+	} // end of the placeholder lookup
+	// The home folder as people write it.
+	home := func() (string, error) { return "~", nil }
+	// The base folder from the real function.
+	base, err := baseDirFor(goos, kind, getenv, home)
+	// No standard place.
+	if err != nil {
+		// Say so.
+		return "not known"
+	} // end of the base check
+	// Windows writes backslashes.
+	if goos == "windows" {
+		// The base and the program's folder.
+		return strings.ReplaceAll(base, "/", `\`) + `\` + dataFolderName
+	} // end of the Windows case
+	// Linux and macOS write slashes.
+	return base + "/" + dataFolderName
+} // end of placeFor
+
+// installPlaceFor writes the standard place of the installed program on a system, from the same function -install uses.
+func installPlaceFor(goos string) string {
+	// Windows names its folder with a variable.
+	getenv := func(name string) string { return "%" + name + "%" }
+	// The home folder as people write it.
+	home := func() (string, error) { return "~", nil }
+	// The path from the real function.
+	p, err := installTargetFor(goos, getenv, home)
+	// No standard place.
+	if err != nil {
+		// Say so.
+		return "not known"
+	} // end of the error check
+	// The separators of that system (the function used this computer's).
+	if goos == "windows" {
+		// Backslashes.
+		return strings.ReplaceAll(p, "/", `\`)
+	} // end of the Windows case
+	// Slashes.
+	return strings.ReplaceAll(p, `\`, "/")
+} // end of installPlaceFor
+
+// placesBySystem lists every kind of place on Linux, Windows and macOS.
+func placesBySystem() []systemPlaces {
+	// The rows.
+	return []systemPlaces{
+		// The settings folder.
+		{"Settings", placeFor("linux", kindConfig), placeFor("windows", kindConfig), placeFor("darwin", kindConfig)},
+		// The data folder.
+		{"Results, saved copies and deleted models", placeFor("linux", kindData), placeFor("windows", kindData), placeFor("darwin", kindData)},
+		// The state folder.
+		{"Check history and log", placeFor("linux", kindState), placeFor("windows", kindState), placeFor("darwin", kindState)},
+		// The installed program.
+		{"Installed program (placed by -install)", installPlaceFor("linux"), installPlaceFor("windows"), installPlaceFor("darwin")},
+	} // end of the rows
+} // end of placesBySystem
diff --git a/scripts/test-smoke-load.sh b/scripts/test-smoke-load.sh
index 4f3f457..80c925b 100644
--- a/scripts/test-smoke-load.sh
+++ b/scripts/test-smoke-load.sh
@@ -166,10 +166,10 @@ page_check "monitor (home) page" / 200 text/html "LLMsControlDock"
 page_check "About page" /about 200 text/html "About LLMsControlDock"
 # The Help page.
 page_check "Help page" /help 200 text/html "Help"
-# The Help page must carry all twelve topics.
+# The Help page must carry all thirteen topics.
 TOPICS="$(grep -o '<details class="helptopic"' "$WORK/body" | wc -l)"
 # Count them.
-if [ "$TOPICS" = "12" ]; then ok "Help page has 12 topics"; else bad "Help page has 12 topics" "found $TOPICS"; fi
+if [ "$TOPICS" = "13" ]; then ok "Help page has 13 topics"; else bad "Help page has 13 topics" "found $TOPICS"; fi
 # The Settings page.
 page_check "Settings page" /settings 200 text/html "Settings"
 # The Find LLM page (only the choices; this does not search the internet).
diff --git a/syscheck.go b/syscheck.go
index a9f0f86..9604ba0 100644
--- a/syscheck.go
+++ b/syscheck.go
@@ -114,6 +114,8 @@ type uninstallItem struct {
 
 // sysPage is what the System check templates show.
 type sysPage struct {
+	// ProgramGone is true when the running program file was the copy -install placed and the uninstall removed it.
+	ProgramGone bool
 	// Kind is report, uninstall or removed.
 	Kind string
 	// Theme and Size are the saved look.
@@ -236,6 +238,24 @@ func uninstallPlan(d desktopIcon) []uninstallItem {
 		// Add it.
 		items = append(items, uninstallItem{What: "Desktop icon", Where: d.desktopPath(), remove: d.removeFiles})
 	} // end of the icon case
+	// The program copy that -install placed (only that copy, only when it is unchanged and in the standard place).
+	if path, ok := installedCopy(stateRoot()); ok {
+		// Add it, with its own removal.
+		items = append(items, uninstallItem{What: "Installed program (placed by -install)", Where: path, remove: func() error {
+			// Remove the file.
+			if err := os.Remove(path); err != nil {
+				// Windows cannot delete a program while it runs: say what to do.
+				return fmt.Errorf("%v (if this copy is the one running, delete the file after the program has stopped)", err)
+			} // end of the remove check
+			// Its own folder on Windows is removed too when it is empty now (an error just means it is not empty).
+			if filepath.Base(filepath.Dir(path)) == dataFolderName {
+				// Only an empty folder is removed.
+				_ = os.Remove(filepath.Dir(path))
+			} // end of the folder check
+			// Done.
+			return nil
+		}}) // end of the program item
+	} // end of the program case
 	// The three folders; on macOS they are the same folder, so equal paths are joined into one line.
 	type folder struct {
 		// what names it.
@@ -486,8 +506,17 @@ func systemCheckHandlers(addr ollamaAddress, mon *monitor, token string, desktop
 				stopRequest()
 			}() // end of the goroutine
 		}) // end of once
+		// The program file was the installed copy and is gone now: nothing is left to delete by hand.
+		gone := false
+		// Only a known path that no longer exists counts.
+		if exe != "" {
+			// Look for it.
+			_, statErr := os.Stat(exe)
+			// Missing now.
+			gone = statErr != nil
+		} // end of the gone check
 		// Send the result page.
-		send(w, r, sysPage{Kind: "removed", Items: items, Program: exe})
+		send(w, r, sysPage{Kind: "removed", Items: items, Program: exe, ProgramGone: gone})
 		// Send it now, so it reaches the browser before the program ends.
 		if f, ok := w.(http.Flusher); ok {
 			// Flush.
diff --git a/web/about.html b/web/about.html
index 7b474ac..ba676e7 100644
--- a/web/about.html
+++ b/web/about.html
@@ -83,6 +83,32 @@
 {{end}}
 {{/* End of the estimate card. */}}
 </section>
+{{/* Where the program keeps its files: on this computer, and on each system. */}}
+<section id="places" class="estimatecard" aria-labelledby="placestitle">
+{{/* The heading. */}}
+<h2 id="placestitle">Where this program keeps its files</h2>
+{{/* What happens without and with installing. */}}
+<p class="muted">The program makes each folder only when it first needs it, so a folder can be missing until then. Running the program once with <code>-install</code> makes them all at once, after asking, and also places the program and the desktop icon. Uninstall removes them again.</p>
+{{/* The places on this computer. */}}
+<h3>On this computer</h3>
+<table class="settingtable placestable">
+<thead><tr><th scope="col">What</th><th scope="col">Where</th><th scope="col">Now</th></tr></thead>
+<tbody>
+{{range .Places}}<tr><th scope="row">{{.What}}</th><td data-label="Where"><code>{{.Where}}</code></td><td data-label="Now">{{.State}}</td></tr>
+{{end}}</tbody>
+</table>
+{{/* The same places on each system. */}}
+<h3>On each system</h3>
+<table class="settingtable placestable">
+<thead><tr><th scope="col">What</th><th scope="col">Linux</th><th scope="col">Windows</th><th scope="col">macOS</th></tr></thead>
+<tbody>
+{{range .Systems}}<tr><th scope="row">{{.What}}</th><td data-label="Linux"><code>{{.Linux}}</code></td><td data-label="Windows"><code>{{.Windows}}</code></td><td data-label="macOS"><code>{{.Mac}}</code></td></tr>
+{{end}}</tbody>
+</table>
+{{/* The meaning of the short forms. */}}
+<p class="muted"><small><code>~</code> is your home folder. <code>%AppData%</code> and <code>%LocalAppData%</code> are your Windows folders of that name. On Linux, the settings, data and state folders follow <code>$XDG_CONFIG_HOME</code>, <code>$XDG_DATA_HOME</code> and <code>$XDG_STATE_HOME</code> when they are set. On macOS the three are one folder. The desktop icon sits on your Desktop when you choose it.</small></p>
+{{/* End of the places card. */}}
+</section>
 {{/* The dedication, set apart so it stands out. */}}
 <blockquote class="dedication">{{.Dedication}}</blockquote>
 {{/* The developer's company: what it does, and a way to find out more. */}}
diff --git a/web/app.css b/web/app.css
index 2103859..ed724c1 100644
--- a/web/app.css
+++ b/web/app.css
@@ -3069,6 +3069,20 @@ details.helptopic[open] {
   border-left-color: var(--cat-accent);
 } /* end of rule */
 
+/* The tables of places on the About page: as wide as the card, never wider; long paths break anywhere instead of pushing the page sideways. */
+.placestable {
+  /* As wide as the card. */
+  width: 100%;
+  /* Columns share the width instead of growing with the longest path. */
+  table-layout: fixed;
+} /* end of rule */
+
+/* A path inside these tables may break at any character. */
+.placestable code {
+  /* Break long paths. */
+  overflow-wrap: anywhere;
+} /* end of rule */
+
 /* The reading guide of the Help page: its tables fill the width, and a little space separates the parts. */
 .helpguide table {
   /* As wide as the topic. */
diff --git a/web/systemcheck.html b/web/systemcheck.html
index b7d24d3..5c73b16 100644
--- a/web/systemcheck.html
+++ b/web/systemcheck.html
@@ -102,12 +102,13 @@
 <li>your settings (Ollama address, intervals, theme),</li>
 <li>the performance test results and the comparison copies you saved,</li>
 <li>the list of deleted models, and the check history behind the charts,</li>
-<li>the desktop icon.</li>
+<li>the desktop icon,</li>
+<li>the program copy that <code>-install</code> placed, when there is one (it is listed below).</li>
 </ul>
-<p>Not touched: Ollama and your models, and the program file itself. The monitor stops when you confirm.</p>
+<p>Not touched: Ollama and your models, and a program file you started from anywhere else. The monitor stops when you confirm.</p>
 {{else}}
-<p>Nothing has been collected yet. Nothing is deleted until you press OK.</p>
-<p class="muted">Not touched: Ollama and your models, and the program file itself.</p>
+<p>No results or settings have been collected yet. Only what is listed below is deleted, and only when you press OK.</p>
+<p class="muted">Not touched: Ollama and your models, and a program file you started from anywhere else than the place <code>-install</code> uses.</p>
 {{end}}
 {{if .Items}}
 <table class="settingtable"><thead><tr><th scope="col">What</th><th scope="col">Where</th></tr></thead><tbody>
@@ -143,8 +144,8 @@
 {{else}}
 <p>There was nothing to remove.</p>
 {{end}}
-<p>To finish, delete the program file yourself (a running program cannot reliably delete itself):</p>
-{{if .Program}}<p><code>{{.Program}}</code></p>{{else}}<p class="muted">The location of the program file could not be found; it is the file you started.</p>{{end}}
+{{if .ProgramGone}}<p>The program file was the copy that <code>-install</code> placed, and it was removed too.</p>{{else}}<p>To finish, delete the program file yourself (a running program cannot reliably delete itself):</p>
+{{if .Program}}<p><code>{{.Program}}</code></p>{{else}}<p class="muted">The location of the program file could not be found; it is the file you started.</p>{{end}}{{end}}
 <p class="muted">Ollama and its models were not touched.</p>
 {{end}}
 {{/* End of the panel. */}}
OCC_PATCH_94_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched and new files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done


# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and check the About page, the Help page and bin/LLMsControlDock -install (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
