#!/usr/bin/env bash
# Script 117 (release preparation, version 0.33.0): the README for the first public release, the release notes file, the version number 0.33.0 and the About page without the 'private repository' words. After this is merged, the only step left on release day is making the repository public (plus the tag and release page).
# Run it on a new branch (never main): cd ~/LLMsControlDock-2 && git switch -c feature/release-0.33.0-preparation && bash scripts/117-step80-release-0.33.0-preparation.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the three files BEFORE the change (as on main after script 116), and of all four files AFTER it.
declare -A BEFORE AFTER
BEFORE["README.md"]="735c26400d6e124f23a373d0c3fdb94461bc308fbb569472cb3d051380bc86e2"
BEFORE["about.go"]="f9112465be2d34a9546851cd040a176aebfe4e653f11a1093b7d0c756e1e9d1a"
BEFORE["web/about.html"]="a391e38b62493a1130dc31a972048287293d5b7cb685e77fc4d98c8d8be68b81"
AFTER["README.md"]="0b9298999ae1474270d5a2541930ec3330a078b0460344fa8ded7ed72663dd9e"
AFTER["about.go"]="94ab8585d1c0b8e33a11042dc1d0a8fb032bfdf3b7937978d891782120025217"
AFTER["web/about.html"]="3c158e54bac80bb023f63e38bdace8a2aa332709a3ef2263256c7497d77f182c"
AFTER["RELEASE-NOTES-0.33.0.md"]="4799fd9b85d0d9be333e1db5d3a6ad271f7b01daddc52fc3ba7ac5cff921757e"

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
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git switch -c feature/release-0.33.0-preparation"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 116 must be in: the repository name in about.go is the new one.
grep -q 'kodati3shrini3/LLMsControlDock-2' about.go || fail "script 116 (repository name) is not in: about.go lacks LLMsControlDock-2"
# Report it.
pass "script 116 is in (new repository name)"

# Refuse to run twice: version 0.33.0 is already in about.go when this change was applied before.
if grep -q 'appVersion = "0.33.0"' about.go; then fail "about.go already says 0.33.0: this script was already applied"; fi
# The release notes file must not exist yet.
[ ! -e RELEASE-NOTES-0.33.0.md ] || fail "RELEASE-NOTES-0.33.0.md exists already"
# Report it.
pass "this change is not applied yet"

# Each file to change must be exactly the version the patch was made against.
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
index e131106..c1f8b6a 100644
--- a/README.md
+++ b/README.md
@@ -2,7 +2,7 @@
 
 A small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, load and unload them, change their settings, test their speed and compare them. It runs on your own computer and needs nothing but Ollama and a web browser.
 
-> **Status: pre-release, version 0.32.0.** Not yet ready for everyday use. See "What is tested" below.
+> **Status: pre-release, version 0.33.0 (first public release).** Early software, tested on two systems only. See "What is tested" below.
 
 ## What it does
 
@@ -10,7 +10,9 @@ A small program that watches an [Ollama](https://ollama.com) server and lets you
 - Shows the loaded and the installed models, with their memory use.
 - Loads and unloads a model (it asks first, and warns about memory).
 - Shows and changes a model's settings, and shows its Modelfile.
-- Tests a model's speed with one fixed built-in prompt, and compares the tested models (PDF and CSV).
+- Finds models: **Find LLM** reads the public Ollama model list, lets you search and sort it, and shows which models you already have.
+- Tests a model's speed with one fixed built-in prompt, and compares the tested models (PDF and CSV). A built-in guide explains each figure in plain words.
+- Has a Help page with 13 topics, each drawn as a swimlane diagram of who does what (You, LLMsControlDock, Ollama, ollama.com).
 - Deletes a model and helps you restore it later (it shows the commands; you run them yourself).
 - Checks your computer on the first start (processor, memory, graphics cards) and says plainly if it is not enough for running models.
 
@@ -26,12 +28,16 @@ A small program that watches an [Ollama](https://ollama.com) server and lets you
 | System | Tested with | Status |
 |---|---|---|
 | Linux arm64 (NVIDIA DGX Spark) | Ollama 0.34.4 | Tested |
-| Windows 11 x64 | Ollama 0.21.2 | Tested in part; a fix for the model categories awaits a re-test |
+| Windows 11 x64 | Ollama 0.21.2 | Tested on three computers; `-install` not yet tested on Windows |
 | Linux x64, Windows arm64, macOS arm64 and x64 | none | Builds without errors; **not tested** |
 
 ## Start it
 
-There are no ready-made downloads yet; the first release will be a 0.x version with one file per system. Until then, build it yourself. You need [Go](https://go.dev/doc/install) (the version named in `go.mod`) only to build, not to run.
+**Download:** each [release](https://github.com/kodati3shrini3/LLMsControlDock-2/releases) has one file per system and a `SHA256SUMS` file. Check the checksum before you run a file. The programs are not code-signed, so Windows SmartScreen may warn (macOS has not been tested). Or build it yourself: you need [Go](https://go.dev/doc/install) (the version named in `go.mod`) only to build, not to run.
+
+```bash
+git clone https://github.com/kodati3shrini3/LLMsControlDock-2.git && cd LLMsControlDock-2
+```
 
 ```bash
 # Linux and macOS
diff --git a/about.go b/about.go
index 47793d0..4eeb113 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of LLMsControlDock; it is raised by hand when a release is made.
-const appVersion = "0.32.0"
+const appVersion = "0.33.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
@@ -49,7 +49,7 @@ const appLicence = "Apache License 2.0"
 // appLicenceURL is where the licence text is: the LICENSE file in the repository.
 const appLicenceURL = appRepository + "/blob/main/LICENSE"
 
-// appRepository is the address of the source code; the repository is private, so only its owner can open it.
+// appRepository is the address of the source code (the GitHub repository).
 const appRepository = "https://github.com/kodati3shrini3/LLMsControlDock-2"
 
 // companyName is the developer's company, shown in the header, the footer bar and the About page.
diff --git a/web/about.html b/web/about.html
index ba676e7..0e28668 100644
--- a/web/about.html
+++ b/web/about.html
@@ -40,7 +40,7 @@
 {{/* The platform. */}}
 <tr><th scope="row">Built with</th><td>Go standard library only, no third-party code ({{.Platform}})</td></tr>
 {{/* Where the source lives. */}}
-<tr><th scope="row">Source code</th><td><a href="{{.Repository}}" target="_blank" rel="noopener noreferrer">{{.Repository}}<span class="sr-only"> (opens in a new window)</span></a> (private repository; opens only for its owner)</td></tr>
+<tr><th scope="row">Source code</th><td><a href="{{.Repository}}" target="_blank" rel="noopener noreferrer">{{.Repository}}<span class="sr-only"> (opens in a new window)</span></a></td></tr>
 {{/* Where the data goes. */}}
 <tr><th scope="row">Privacy</th><td>Runs only on this computer. The requests to the outside are read-only and go to the public Ollama website only: the optional check of a model's name before it is deleted, and, when you press Find LLM, a read of the public model list and of the version lists of the first ten models. The model list is also kept in this program's data folder on this computer, so that Find LLM can show it, with its date, when the website cannot be reached. Nothing about you or your choices is sent. Links to the developer's sites open in a new window only when you click them; nothing is sent to them before that.</td></tr>
 {{/* The licence. */}}
diff --git a/RELEASE-NOTES-0.33.0.md b/RELEASE-NOTES-0.33.0.md
new file mode 100644
index 0000000..2d8464e
--- /dev/null
+++ b/RELEASE-NOTES-0.33.0.md
@@ -0,0 +1,74 @@
+# LLMsControlDock 0.33.0: first public release (pre-release)
+
+LLMsControlDock is a small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, find and manage models, change their settings, test their speed and compare them. It runs on your own computer, needs nothing but Ollama and a web browser, and is one file with no other dependencies (Go standard library only).
+
+Earlier version numbers were development builds and were not published. This is the first release anyone can download, so expect rough edges (see "Known limits").
+
+## What you can do
+
+| Task | What the program does |
+|---|---|
+| Check your computer | A System check on first start looks at processor, memory and graphics cards and says plainly if the machine is not enough for running models. |
+| Watch Ollama | Online or offline, response time and version, with charts and an event log. |
+| Find a model | **Find LLM** reads the public Ollama model list, lets you search and sort, and shows which models you already have. The list is also kept locally, so it can be shown (dated) when the website cannot be reached. |
+| Load and unload | Asks first and warns about memory. |
+| Tune a model | Shows a model's saved settings and its Modelfile; a change is reviewed before it is saved. |
+| Test speed | One fixed built-in prompt: a warm-up request loads the model (reported as the cold figure), then three timed requests; each result is the median of the three. Only numbers are saved, never text. |
+| Compare models | Side by side, with fairness flags, a re-test of a group, and PDF and CSV export. |
+| Read the results | A built-in guide explains each figure in plain words. |
+| Delete and restore | Asks first and, for a deleted model, shows how to get it back. |
+| Get help | 13 Help topics, each drawn as a swimlane diagram (You, LLMsControlDock, Ollama, ollama.com) with the same steps listed in text. |
+| Install (optional) | `LLMsControlDock -install` shows the plan, asks, then makes the folders, copies the program and creates a desktop icon. No administrator rights. Uninstall removes only what it placed. |
+
+## Downloads
+
+Each file is one program for one system. Pick the one that matches your computer.
+
+| System | File | Tested |
+|---|---|---|
+| Linux, ARM64 (Ubuntu on NVIDIA DGX Spark) | `LLMsControlDock-linux-arm64` | **Yes** |
+| Windows 11, x86-64 | `LLMsControlDock-windows-amd64.exe` | **Yes** (`-install` not yet tested on Windows) |
+| Linux, x86-64 | `LLMsControlDock-linux-amd64` | No, builds without errors |
+| Windows, ARM64 | `LLMsControlDock-windows-arm64.exe` | No, builds without errors |
+| macOS, Apple silicon | `LLMsControlDock-darwin-arm64` | No, builds without errors |
+| macOS, Intel | `LLMsControlDock-darwin-amd64` | No, builds without errors |
+
+`SHA256SUMS` lists the checksum of every file. Check yours before running it:
+
+```bash
+# Linux and macOS: run in the folder with the downloaded files
+sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS
+```
+
+```powershell
+# Windows (PowerShell): compare the printed value with the line in SHA256SUMS
+(Get-FileHash .\LLMsControlDock-windows-amd64.exe -Algorithm SHA256).Hash
+```
+
+## First start
+
+1. Start the program; it prints the address (default `http://127.0.0.1:8765/`) and you open it in your browser.
+2. The System check page opens first. Press **Continue**.
+3. The executables are **not code-signed**. Windows SmartScreen may warn that the publisher is unknown: choose "More info" and "Run anyway" only if the checksum matched. macOS may also block an unsigned program; this has not been tested.
+
+## Verified so far
+
+- An automated suite of about 490 tests runs on every change.
+- A 39-check smoke and load test and a 54-check functional regression test (every page and button, checked against Ollama's own API) pass on the DGX Spark. These two are developer tools and are not part of the download.
+- Used by hand on Ubuntu ARM64 (DGX Spark) and on Windows 11 x86-64.
+
+## Known limits
+
+- Tested on two systems only (table above). The other four builds compile but have never been run.
+- The executables are unsigned (see "First start").
+- `-install` has been tested on Linux only.
+- The speed-test limits (for example the 1000 ms response-time limit used in the load test) are the author's own choice, not a standard.
+- Memory use grew from 15 MB to 19 MB over about 14,700 requests in one run. One run cannot show whether that is a leak.
+
+## Important
+
+LLMsControlDock monitors and controls Ollama. It is not a medical device and it does not check what a model says. Anything a model writes that you use for health or other critical decisions must be checked against an official source. It is an independent tool, not affiliated with, endorsed by or sponsored by Ollama Inc.
+
+## Licence
+
+Apache License 2.0. Copyright 2026 termGate Consulting Limited. Developed by Shrinivas Kodati, termGate Consulting Limited, with Claude (Anthropic) as an assistant.
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

# No unfinished marker may be left in the two documents.
if grep -n -E 'CONFIRM|DRAFT' README.md RELEASE-NOTES-0.33.0.md; then fail "an unfinished marker is left in the lines above"; fi
# Report it.
pass "README and release notes hold no unfinished markers"

# The About page must not say that the repository is private any more.
if grep -n -i 'private repository' web/about.html about.go; then fail "the About page still says private repository"; fi
# Report it.
pass "the About page does not mention a private repository"

# The old version number must be gone everywhere outside scripts/.
if git grep -n -F '0.32.0' -- . ':!scripts'; then fail "0.32.0 is still used in the lines above"; fi
# Report it.
pass "version 0.32.0 is not used outside scripts/"

# The new version must be in the program and in the README.
grep -q 'appVersion = "0.33.0"' about.go && grep -q 'version 0.33.0' README.md || fail "0.33.0 is missing in about.go or README.md"
# Report it.
pass "version 0.33.0 is in about.go and README.md"

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
echo "NEXT  start bin/LLMsControlDock, open the About page and check the version and the Source code row (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
