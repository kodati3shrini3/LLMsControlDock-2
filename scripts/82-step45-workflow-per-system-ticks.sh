#!/usr/bin/env bash
# Script 82 (workflow with one tick box per system): the manual GitHub workflow now has six tick boxes (Linux x64, Linux arm64, Windows x64, Windows arm64, macOS arm64, macOS x64). Only the ticked systems are built, started and tested, and each system keeps ONE separate download (plus its own small checksum download). Nothing runs unless a person clicks Run workflow.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run on main (every change goes through a branch).
[ "$(git branch --show-current)" != "main" ] || { echo "FAIL  this is main; create a feature branch first"; exit 1; }
# Refuse to run twice.
if grep -q "name: Build and test (manual, per system)" .github/workflows/build.yml 2>/dev/null; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/.github/workflows/build.yml b/.github/workflows/build.yml
index cf97737..7d11b1b 100644
--- a/.github/workflows/build.yml
+++ b/.github/workflows/build.yml
@@ -1,10 +1,41 @@
-# Build and test OllamaControlCenter on GitHub. It runs ONLY when a person clicks "Run workflow" in the Actions tab; it never runs by itself and it never publishes a release.
-name: Build and test (manual)
+# Build and test OllamaControlCenter on GitHub, only for the systems you tick. It runs ONLY when a person clicks "Run workflow" in the Actions tab; it never runs by itself and it never publishes a release.
+name: Build and test (manual, per system)
 
-# The only trigger is the manual button.
+# The only trigger is the manual button; each system has its own tick box, so a run costs only what is ticked (macOS minutes cost about ten times Linux minutes on a private repository).
 on:
-  # A person starts it from the Actions tab (or with: gh workflow run).
+  # A person starts it from the Actions tab (or with: gh workflow run build.yml -f windows-amd64=true).
   workflow_dispatch:
+    inputs:
+      # Linux on an Intel/AMD computer: the cheapest system, ticked by default.
+      linux-amd64:
+        description: "Linux x64 (Intel/AMD): build, start-up check, tests"
+        type: boolean
+        default: true
+      # Linux on an ARM computer (such as the DGX Spark).
+      linux-arm64:
+        description: "Linux arm64 (ARM): build, start-up check, tests"
+        type: boolean
+        default: false
+      # Windows 11 on an Intel/AMD computer.
+      windows-amd64:
+        description: "Windows x64 (Intel/AMD): build, start-up check, tests"
+        type: boolean
+        default: false
+      # Windows 11 on an ARM computer.
+      windows-arm64:
+        description: "Windows arm64 (ARM): build, start-up check, tests"
+        type: boolean
+        default: false
+      # macOS on Apple silicon (the expensive one).
+      darwin-arm64:
+        description: "macOS arm64 (Apple silicon): build, start-up check, tests (costs about 10x Linux)"
+        type: boolean
+        default: false
+      # macOS on an Intel Mac (the expensive one).
+      darwin-amd64:
+        description: "macOS x64 (Intel Mac): build, start-up check, tests (costs about 10x Linux)"
+        type: boolean
+        default: false
 
 # The workflow may only read the repository; it has no secrets and no write rights.
 permissions:
@@ -17,15 +48,61 @@ env:
   GO_VERSION: "1.27"
 
 jobs:
-  # Job 1: check the code on Linux, build every executable and the list of checksums.
-  build:
-    # A Linux machine builds all of them (Go cross-compiles).
+  # Job 1: turn the tick boxes into the list of systems to build (a few seconds on the cheapest machine).
+  plan:
     runs-on: ubuntu-24.04
-    # Never let a stuck job run for hours.
-    timeout-minutes: 20
-    # The version number is handed on to the other jobs.
+    timeout-minutes: 5
     outputs:
-      version: ${{ steps.version.outputs.version }}
+      # The list of ticked systems, as JSON for the matrix below.
+      matrix: ${{ steps.plan.outputs.matrix }}
+      # "true" when at least one system is ticked.
+      any: ${{ steps.plan.outputs.any }}
+    steps:
+      # Build the list; the ticks arrive as the words true or false in environment variables, never inside the script text.
+      - name: List the ticked systems
+        id: plan
+        env:
+          LINUX_AMD64: ${{ inputs.linux-amd64 }}
+          LINUX_ARM64: ${{ inputs.linux-arm64 }}
+          WINDOWS_AMD64: ${{ inputs.windows-amd64 }}
+          WINDOWS_ARM64: ${{ inputs.windows-arm64 }}
+          DARWIN_ARM64: ${{ inputs.darwin-arm64 }}
+          DARWIN_AMD64: ${{ inputs.darwin-amd64 }}
+        run: |
+          set -eu
+          # One JSON line per system: the label, the machine to run on, and the system and processor names Go uses.
+          all='
+          {"system":"linux-amd64","runner":"ubuntu-24.04","goos":"linux","goarch":"amd64","ext":"","on":"'"$LINUX_AMD64"'"}
+          {"system":"linux-arm64","runner":"ubuntu-24.04-arm","goos":"linux","goarch":"arm64","ext":"","on":"'"$LINUX_ARM64"'"}
+          {"system":"windows-amd64","runner":"windows-2025","goos":"windows","goarch":"amd64","ext":".exe","on":"'"$WINDOWS_AMD64"'"}
+          {"system":"windows-arm64","runner":"windows-11-arm","goos":"windows","goarch":"arm64","ext":".exe","on":"'"$WINDOWS_ARM64"'"}
+          {"system":"darwin-arm64","runner":"macos-15","goos":"darwin","goarch":"arm64","ext":"","on":"'"$DARWIN_ARM64"'"}
+          {"system":"darwin-amd64","runner":"macos-15-intel","goos":"darwin","goarch":"amd64","ext":"","on":"'"$DARWIN_AMD64"'"}
+          '
+          # Keep only the ticked ones and drop the tick field.
+          matrix="$(printf '%s' "$all" | jq -c -s '[.[] | select(.on == "true") | del(.on)]')"
+          echo "matrix=$matrix" >> "$GITHUB_OUTPUT"
+          # Say whether anything is ticked.
+          if [ "$matrix" = "[]" ]; then
+            echo "any=false" >> "$GITHUB_OUTPUT"
+            echo "### Nothing was ticked, so nothing was built. Run the workflow again and tick at least one system." >> "$GITHUB_STEP_SUMMARY"
+          else
+            echo "any=true" >> "$GITHUB_OUTPUT"
+            echo "### Systems to build: $(printf '%s' "$matrix" | jq -r 'map(.system) | join(", ")')" >> "$GITHUB_STEP_SUMMARY"
+          fi
+
+  # Job 2: one job for each ticked system. Each one builds its own executable, starts it, runs the tests and keeps ONE separate download for that system.
+  system:
+    needs: plan
+    # Skip everything when nothing is ticked.
+    if: needs.plan.outputs.any == 'true'
+    # One failing system must not hide the results of the others.
+    strategy:
+      fail-fast: false
+      matrix:
+        include: ${{ fromJSON(needs.plan.outputs.matrix) }}
+    runs-on: ${{ matrix.runner }}
+    timeout-minutes: 25
     steps:
       # Get the code, without leaving the access token in the folder.
       - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
@@ -39,71 +116,37 @@ jobs:
       # Read the version number from the program's own source.
       - name: Read the version
         id: version
+        shell: bash
         run: |
           version="$(sed -n 's/^const appVersion = "\(.*\)"$/\1/p' about.go)"
           test -n "$version"
           echo "version=$version" >> "$GITHUB_OUTPUT"
-          echo "Building version $version with $(go version)"
-      # Go's own checker for suspicious code.
+          echo "Building version $version with $(go version) on ${{ matrix.system }}"
+      # Go's own checker for suspicious code, on this very system.
       - name: go vet
+        shell: bash
         run: go vet ./...
-      # All tests (they assume Linux, so they run here).
-      - name: go test
-        run: go test -count=1 ./...
-      # Build one file for each system, then the checksum list.
-      - name: Build every executable
+      # Build the executable for this system on this system.
+      - name: Build the executable
+        shell: bash
+        env:
+          FILE: OllamaControlCenter-${{ matrix.system }}${{ matrix.ext }}
         run: |
+          set -eu
           mkdir dist
-          for target in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
-            os="${target%/*}"; arch="${target#*/}"; ext=""
-            if [ "$os" = "windows" ]; then ext=".exe"; fi
-            GOOS="$os" GOARCH="$arch" go build -trimpath -o "dist/OllamaControlCenter-$os-$arch$ext" .
-          done
+          go build -trimpath -o "dist/$FILE" .
           cd dist
-          sha256sum OllamaControlCenter-* > SHA256SUMS
+          if command -v sha256sum > /dev/null; then sha256sum "$FILE" > SHA256SUMS; else shasum -a 256 "$FILE" > SHA256SUMS; fi
           cat SHA256SUMS
-      # Keep the files for 14 days so they can be downloaded and tested.
-      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
-        with:
-          name: OllamaControlCenter-${{ steps.version.outputs.version }}-executables
-          path: dist/
-          if-no-files-found: error
-          retention-days: 14
-
-  # Job 2: start each executable on a real machine of its own kind and ask it for its pages.
-  run-on-each-system:
-    needs: build
-    # One failing system must not hide the results of the others.
-    strategy:
-      fail-fast: false
-      matrix:
-        include:
-          - { runner: ubuntu-24.04,     file: OllamaControlCenter-linux-amd64 }
-          - { runner: ubuntu-24.04-arm, file: OllamaControlCenter-linux-arm64 }
-          - { runner: windows-2025,     file: OllamaControlCenter-windows-amd64.exe }
-          - { runner: windows-11-arm,   file: OllamaControlCenter-windows-arm64.exe }
-          - { runner: macos-15,         file: OllamaControlCenter-darwin-arm64 }
-          - { runner: macos-15-intel,   file: OllamaControlCenter-darwin-amd64 }
-    runs-on: ${{ matrix.runner }}
-    timeout-minutes: 10
-    steps:
-      # Get the files built in job 1.
-      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
-        with:
-          name: OllamaControlCenter-${{ needs.build.outputs.version }}-executables
-          path: dist
       # Start the program and check its pages (no Ollama is installed on these machines, so the pages must say so and still answer).
       - name: Start-up check
         shell: bash
         env:
-          FILE: ${{ matrix.file }}
-          VERSION: ${{ needs.build.outputs.version }}
+          FILE: OllamaControlCenter-${{ matrix.system }}${{ matrix.ext }}
+          VERSION: ${{ steps.version.outputs.version }}
         run: |
           set -eu
           cd dist
-          # The file must match its checksum.
-          grep " ${FILE}\$" SHA256SUMS > one.sum
-          if command -v sha256sum > /dev/null; then sha256sum -c one.sum; else shasum -a 256 -c one.sum; fi
           chmod +x "./$FILE"
           # Start it in the background on its normal address.
           "./$FILE" > run.log 2>&1 &
@@ -123,32 +166,29 @@ jobs:
           curl -fsS -o /dev/null http://127.0.0.1:8765/settings
           echo "PASS: $FILE answered on $RUNNER_OS $RUNNER_ARCH"
           cat run.log
-
-  # Job 3: run the tests on the other systems too. The tests were written on Linux, so failures are EXPECTED on Windows and macOS for now: they are reported, they do not stop the workflow, and they become the list of tests to make portable.
-  tests-on-each-system:
-    strategy:
-      fail-fast: false
-      matrix:
-        runner: [ubuntu-24.04-arm, windows-2025, windows-11-arm, macos-15, macos-15-intel]
-    runs-on: ${{ matrix.runner }}
-    continue-on-error: true
-    timeout-minutes: 20
-    steps:
-      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
+      # Keep this system's file for 14 days so it can be downloaded and tested; the name carries the version and the system, so every system has its own download.
+      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
         with:
-          persist-credentials: false
-      - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
+          name: OllamaControlCenter-${{ steps.version.outputs.version }}-${{ matrix.system }}
+          path: dist/OllamaControlCenter-${{ matrix.system }}${{ matrix.ext }}
+          if-no-files-found: error
+          retention-days: 14
+      # The checksum goes next to it in its own small download, so the executable's download is just the one file.
+      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
         with:
-          go-version: ${{ env.GO_VERSION }}
-          cache: false
-      # Run every test and list the failing ones in the summary of the run.
+          name: OllamaControlCenter-${{ steps.version.outputs.version }}-${{ matrix.system }}-SHA256SUMS
+          path: dist/SHA256SUMS
+          if-no-files-found: error
+          retention-days: 14
+      # Run every test and list the failing ones in the summary of the run. The tests were written on Linux, so on Linux x64 a failure stops the run, and on every other system a failure is reported but does not turn the run red (it becomes the list of tests to make portable).
       - name: go test
         shell: bash
+        continue-on-error: ${{ matrix.system != 'linux-amd64' }}
         run: |
           go test -count=1 ./... 2>&1 | tee test.log
           status="${PIPESTATUS[0]}"
           {
-            echo "### Tests on ${{ matrix.runner }}: exit code $status"
+            echo "### Tests on ${{ matrix.system }}: exit code $status"
             grep -E '^--- FAIL' test.log | sort -u || true
           } >> "$GITHUB_STEP_SUMMARY"
           exit "$status"
PATCH_END
# Check that the patch fits the current file, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit this file"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprint (sha256) the file must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
3939dc8652296181485b32c1cdf61861e993e2cb2d84c075753fd010098ea866  .github/workflows/build.yml
SUMS_END
# Compare the real fingerprint with the expected one.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The file is exactly as prepared.
  echo "PASS  the file is exactly the prepared version"
else
  # Something differs; stop.
  echo "FAIL  the file differs from the prepared version"; exit 1
fi
# Check that the file is valid YAML and has the six tick boxes and both jobs (needs python3 with PyYAML; skipped with a note when it is missing).
if python3 -c "import yaml" 2>/dev/null; then
  # Parse the file and check its shape.
  python3 - <<'PY'
# Read the YAML parser.
import yaml
# Load the workflow.
d = yaml.safe_load(open(".github/workflows/build.yml"))
# The trigger key may be read as the word on or as True.
on = d.get("on") or d.get(True)
# The six systems that must have a tick box.
want = {"linux-amd64", "linux-arm64", "windows-amd64", "windows-arm64", "darwin-arm64", "darwin-amd64"}
# Compare with the real tick boxes.
assert set(on["workflow_dispatch"]["inputs"]) == want, "tick boxes differ"
# Both jobs must exist.
assert set(d["jobs"]) == {"plan", "system"}, "jobs differ"
# Report it.
print("PASS  the workflow file is valid YAML with six tick boxes and two jobs")
PY
else
  # Say that the check was skipped.
  echo "NOTE  python3 with PyYAML is not installed, so the YAML check was skipped"
fi
# Run every test of the program (the workflow file does not change the program).
go test ./...
# Report the check.
echo "PASS  tests"
# Tell the person what to do next.
echo "NEXT  commit and push; the workflow itself can only be tried on GitHub: Actions tab, Build and test (manual, per system), Run workflow, tick ONE cheap system first (for example Linux x64)"
# List the changed files; nothing is committed yet.
git status --short
