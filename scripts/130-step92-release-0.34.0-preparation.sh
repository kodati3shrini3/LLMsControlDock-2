#!/usr/bin/env bash
# Script 130 (release 0.34.0 preparation): raises appVersion in about.go to 0.34.0, changes the README status line to "pre-release, version 0.34.0" (a test requires the README to name the program's version), and adds RELEASE-NOTES-0.34.0.md, the text of the release page. Nothing is published by this script: the release, its tag and the executables come later, after the owner's confirmation.
# Run it on a NEW branch made from the updated main (never main): cd ~/LLMsControlDock-2 && git switch main && git pull && git switch -c feature/release-0.34.0-preparation && bash scripts/130-step92-release-0.34.0-preparation.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two existing files BEFORE the change (as on main after pull request 61) and of all three files AFTER it (the third, RELEASE-NOTES-0.34.0.md, is new).
declare -A BEFORE AFTER
BEFORE["about.go"]="94ab8585d1c0b8e33a11042dc1d0a8fb032bfdf3b7937978d891782120025217"
BEFORE["README.md"]="8aa78b1a3a98921ac932c87fc7ccb1cd99940a07717735f9dab9c178771f1be5"
AFTER["about.go"]="2801e8e9e1c23459a6625f195bb5c9c6fbaaaecb8c4863144f08daacada43800"
AFTER["README.md"]="2b81246dd43b44d35b746494b89fa63d830483192417a916f207c9c681ae5efa"
AFTER["RELEASE-NOTES-0.34.0.md"]="0cb833bc7a207ee106f0fe9fe2bd0f2bf46e9d1450e46fcbbaa4b0b99d8b5b8b"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/release-0.34.0-preparation"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Pull requests 60 and 61 must be in (the update order and the Help test are their signs).
grep -q 'func sortOrder' findllm.go && grep -q 'TestHelpFindLLMIntroNamesTheNewBehaviour' help_test.go || fail "pull requests 60 and 61 are not in this branch; run git pull on main first"
# Report it.
pass "pull requests 60 and 61 are in"

# Refuse to run twice: the new release notes file is the sign.
if [ -e RELEASE-NOTES-0.34.0.md ]; then fail "RELEASE-NOTES-0.34.0.md exists: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every existing file must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the file is not the expected version.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} existing files are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_130_END'
diff --git a/README.md b/README.md
index 6f6adb0..1886ff6 100644
--- a/README.md
+++ b/README.md
@@ -2,7 +2,7 @@
 
 A small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, load and unload them, change their settings, test their speed and compare them. It runs on your own computer and needs nothing but Ollama and a web browser.
 
-> **Status: pre-release, version 0.33.0 (first public release).** Early software, tested on two systems only. See "What is tested" below.
+> **Status: pre-release, version 0.34.0.** Early software, tested on two systems only. See "What is tested" below.
 
 ## What it does
 
diff --git a/RELEASE-NOTES-0.34.0.md b/RELEASE-NOTES-0.34.0.md
new file mode 100644
index 0000000..fa95d15
--- /dev/null
+++ b/RELEASE-NOTES-0.34.0.md
@@ -0,0 +1,82 @@
+# LLMsControlDock 0.34.0 (pre-release)
+
+LLMsControlDock is a small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, find and manage models, change their settings, test their speed and compare them. It runs on your own computer, needs nothing but Ollama and a web browser, and is one file with no other dependencies (Go standard library only).
+
+This release builds on 0.33.0 and mostly improves **Find LLM**. It is still a pre-release: early software, used by hand on two systems only (see "Known limits").
+
+## What is new
+
+| Where | What you see |
+|---|---|
+| Find LLM, Sort by | A new choice, **Updated: new to old**, is the first choice and the default. It lists the model that ollama.com updated most recently first. **Most downloaded** and **Name A to Z** are still there. |
+| Find LLM, each result | A line "Matched your choices" says which of your choices made the model qualify. |
+| Find LLM, newer Ollama | The program reads each listed model's page. When the page says the model needs a newer Ollama than yours, the result shows a warning symbol, "Fits, after you update Ollama", and a folded "How to update Ollama" with the steps for Windows and macOS, Linux and Docker. |
+| Find LLM, sizes | A folded table, "Compare sizes", puts the sizes of one model side by side (download size, context, and whether it fits on this computer). |
+| Find LLM, decision models | A new tick finds decision models. They classify text, answer yes or no, or score text, and they do not chat. They need Ollama 0.35.0 or newer. |
+| Find LLM, labels | Mixed sizes such as 8x7b are now counted as their total (56 billion). A label that ollama.com shows and this program does not know yet is named in a notice, with a request to report it. |
+| Docker and Kubernetes | The commands on Find LLM and on the Delete page now use `-it` (`docker exec -it`, `kubectl exec -it`), so they work in a terminal. |
+| Help and README | The Find LLM Help topic and the README describe the changes above. |
+| Behind the scenes | The README links straight to the issues page. The GitHub start-up check follows the first-start redirect to the System check. Four automated tests that failed on Windows in 0.33.0 are fixed. |
+
+## Things to know about the new Find LLM features
+
+- **The update order uses rounded words.** ollama.com writes how long ago a model was updated in rounded words such as "6 days ago" or "1 month ago", not as a date. Models with the same words are listed by name A to Z, and a model without such words is listed last. A note under the results says so.
+- **The newer-Ollama warning depends on the wording of the model page.** The program looks for a sentence such as "requires Ollama 0.35.1 or later". A model whose page does not say this gets no warning, even if it needs a newer Ollama. Only a few pages were checked by hand.
+- **One more internet request per listed model.** Find LLM now also reads the public page of each listed model, and asks your own Ollama server which version it is. The request carries only the model's name in the address; your choices are not sent.
+
+## Downloads
+
+Each file is one program for one system. Pick the one that matches your computer.
+
+| System | File | Tested |
+|---|---|---|
+| Linux, ARM64 (Ubuntu on NVIDIA DGX Spark) | `LLMsControlDock-linux-arm64` | **Used by hand**, including the Find LLM changes of this release |
+| Windows 11, x86-64 | `LLMsControlDock-windows-amd64.exe` | Used by hand with 0.33.0; the changes of this release have **not** been tried by hand on Windows |
+| Linux, x86-64 | `LLMsControlDock-linux-amd64` | Not used by hand |
+| Windows, ARM64 | `LLMsControlDock-windows-arm64.exe` | Not used by hand |
+| macOS, Apple silicon | `LLMsControlDock-darwin-arm64` | Not used by hand |
+| macOS, Intel | `LLMsControlDock-darwin-amd64` | Not used by hand |
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
+1. Linux and macOS only: make the file runnable once, for example `chmod +x LLMsControlDock-linux-arm64` (use the name of your file).
+2. Start the program; it prints the address (default `http://127.0.0.1:8765/`) and you open it in your browser.
+3. The System check page opens first. Press **Continue**.
+4. The executables are **not code-signed**. Windows SmartScreen may warn that the publisher is unknown: choose "More info" and "Run anyway" only if the checksum matched. macOS may also block an unsigned program; this has not been tested.
+
+## Verified so far
+
+- An automated suite of about 510 tests passes on Linux ARM64 (DGX Spark) for the final code of this release, and the program compiles for all six systems (Linux, Windows and macOS, each for x86-64 and ARM64 or Apple silicon).
+- The GitHub start-up check, which also runs the automated tests, passed on all six systems for an earlier state of this version (run `43981980700`). It has **not** been run on the final files of this release.
+- Used by hand on Ubuntu ARM64 (DGX Spark): the Find LLM changes of this release. Used by hand on Windows 11 x86-64 with 0.33.0.
+- The 39-check smoke and load test and the 54-check functional regression test were run for 0.33.0. They have not been re-run for this release.
+- The files in this release were built on the author's computer.
+
+## Known limits
+
+- Used by hand on two systems only (table above). The other four have not been used with a real Ollama by anyone.
+- The executables are unsigned (see "First start").
+- `-install` has been tested by hand on Linux only.
+- The speed-test limits (for example the 1000 ms response-time limit used in the load test) are the author's own choice, not a standard.
+- From 0.33.0: memory use grew from 15 MB to 19 MB over about 14,700 requests in one run. One run cannot show whether that is a leak.
+- The new Find LLM limits are described above ("Things to know about the new Find LLM features").
+
+## Important
+
+LLMsControlDock monitors and controls Ollama. It is not a medical device and it does not check what a model says. Anything a model writes that you use for health or other critical decisions must be checked against an official source. It is an independent tool, not affiliated with, endorsed by or sponsored by Ollama Inc.
+
+## Licence
+
+Apache License 2.0. Copyright 2026 termGate Consulting Limited. Developed by Shrinivas Kodati, termGate Consulting Limited, with Claude (Anthropic) as an assistant.
diff --git a/about.go b/about.go
index 4eeb113..83a0b2d 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of LLMsControlDock; it is raised by hand when a release is made.
-const appVersion = "0.33.0"
+const appVersion = "0.34.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
OCC_PATCH_130_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# Only the two expected tracked files may be changed.
CHANGED="$(git diff --name-only | LC_ALL=C sort | tr '\n' ' ')"
# The expected list.
EXPECTED="README.md about.go "
# Anything else is a failure.
[ "$CHANGED" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED"
# Report it.
pass "only README.md and about.go changed, plus the new RELEASE-NOTES-0.34.0.md"

# The key lines must be in place.
grep -q '^const appVersion = "0.34.0"$' about.go && grep -q 'version 0.34.0' README.md || fail "a key line of the change is missing"
# Report it.
pass "appVersion and the README status line say 0.34.0"

# The word the owner does not want in documents must not be in the new text.
if grep -q 'KISS' RELEASE-NOTES-0.34.0.md README.md; then fail "the forbidden word is in the release notes or README"; fi
# Report it.
pass "the release notes and README do not use the forbidden word"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code (and compiles the tests).
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once; a timing failure of TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel is reported and not hidden.
go test -count=1 ./... || fail "go test failed (if only TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel failed, run the tests once more and tell Claude)"
# Report it.
pass "go test: all tests pass"

# Build the program for all six systems.
for TARGET in linux/amd64 linux/arm64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Build to nowhere (/dev/null) just to see that it compiles.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -o /dev/null . || fail "build for $TARGET failed"
  # Report it.
  pass "program builds for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  read RELEASE-NOTES-0.34.0.md and check the About page by hand (instructions follow in the chat), then commit and push."
# Show what changed in the project folder.
git status --short
