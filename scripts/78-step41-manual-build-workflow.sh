#!/usr/bin/env bash
# Script 78 (manual build workflow): adds .github/workflows/build.yml, a GitHub Actions workflow that runs ONLY when a person presses "Run workflow" on the Actions tab. It builds six executables (Linux, Windows and macOS; arm64 and amd64 where offered) with Go 1.27, writes a SHA256SUMS list, starts each executable on a real machine of its own kind and asks it for its pages, and runs the tests on the other systems. It has read-only rights, no secrets, publishes nothing, and every borrowed action is pinned to an exact commit. The program itself is not changed (version stays 0.27.0).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/manual-build-workflow" ] || { echo "FAIL  not on feature/manual-build-workflow"; exit 1; }
# Refuse to run twice.
if [ -e .github/workflows/build.yml ]; then
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
new file mode 100644
index 0000000..cf97737
--- /dev/null
+++ b/.github/workflows/build.yml
@@ -0,0 +1,154 @@
+# Build and test OllamaControlCenter on GitHub. It runs ONLY when a person clicks "Run workflow" in the Actions tab; it never runs by itself and it never publishes a release.
+name: Build and test (manual)
+
+# The only trigger is the manual button.
+on:
+  # A person starts it from the Actions tab (or with: gh workflow run).
+  workflow_dispatch:
+
+# The workflow may only read the repository; it has no secrets and no write rights.
+permissions:
+  contents: read
+
+# The program uses no C code, so every build is one self-contained file.
+env:
+  CGO_ENABLED: "0"
+  # The Go version used for building: the newest line that Go still supports (see https://go.dev/doc/devel/release).
+  GO_VERSION: "1.27"
+
+jobs:
+  # Job 1: check the code on Linux, build every executable and the list of checksums.
+  build:
+    # A Linux machine builds all of them (Go cross-compiles).
+    runs-on: ubuntu-24.04
+    # Never let a stuck job run for hours.
+    timeout-minutes: 20
+    # The version number is handed on to the other jobs.
+    outputs:
+      version: ${{ steps.version.outputs.version }}
+    steps:
+      # Get the code, without leaving the access token in the folder.
+      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
+        with:
+          persist-credentials: false
+      # Install Go.
+      - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
+        with:
+          go-version: ${{ env.GO_VERSION }}
+          cache: false
+      # Read the version number from the program's own source.
+      - name: Read the version
+        id: version
+        run: |
+          version="$(sed -n 's/^const appVersion = "\(.*\)"$/\1/p' about.go)"
+          test -n "$version"
+          echo "version=$version" >> "$GITHUB_OUTPUT"
+          echo "Building version $version with $(go version)"
+      # Go's own checker for suspicious code.
+      - name: go vet
+        run: go vet ./...
+      # All tests (they assume Linux, so they run here).
+      - name: go test
+        run: go test -count=1 ./...
+      # Build one file for each system, then the checksum list.
+      - name: Build every executable
+        run: |
+          mkdir dist
+          for target in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
+            os="${target%/*}"; arch="${target#*/}"; ext=""
+            if [ "$os" = "windows" ]; then ext=".exe"; fi
+            GOOS="$os" GOARCH="$arch" go build -trimpath -o "dist/OllamaControlCenter-$os-$arch$ext" .
+          done
+          cd dist
+          sha256sum OllamaControlCenter-* > SHA256SUMS
+          cat SHA256SUMS
+      # Keep the files for 14 days so they can be downloaded and tested.
+      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
+        with:
+          name: OllamaControlCenter-${{ steps.version.outputs.version }}-executables
+          path: dist/
+          if-no-files-found: error
+          retention-days: 14
+
+  # Job 2: start each executable on a real machine of its own kind and ask it for its pages.
+  run-on-each-system:
+    needs: build
+    # One failing system must not hide the results of the others.
+    strategy:
+      fail-fast: false
+      matrix:
+        include:
+          - { runner: ubuntu-24.04,     file: OllamaControlCenter-linux-amd64 }
+          - { runner: ubuntu-24.04-arm, file: OllamaControlCenter-linux-arm64 }
+          - { runner: windows-2025,     file: OllamaControlCenter-windows-amd64.exe }
+          - { runner: windows-11-arm,   file: OllamaControlCenter-windows-arm64.exe }
+          - { runner: macos-15,         file: OllamaControlCenter-darwin-arm64 }
+          - { runner: macos-15-intel,   file: OllamaControlCenter-darwin-amd64 }
+    runs-on: ${{ matrix.runner }}
+    timeout-minutes: 10
+    steps:
+      # Get the files built in job 1.
+      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
+        with:
+          name: OllamaControlCenter-${{ needs.build.outputs.version }}-executables
+          path: dist
+      # Start the program and check its pages (no Ollama is installed on these machines, so the pages must say so and still answer).
+      - name: Start-up check
+        shell: bash
+        env:
+          FILE: ${{ matrix.file }}
+          VERSION: ${{ needs.build.outputs.version }}
+        run: |
+          set -eu
+          cd dist
+          # The file must match its checksum.
+          grep " ${FILE}\$" SHA256SUMS > one.sum
+          if command -v sha256sum > /dev/null; then sha256sum -c one.sum; else shasum -a 256 -c one.sum; fi
+          chmod +x "./$FILE"
+          # Start it in the background on its normal address.
+          "./$FILE" > run.log 2>&1 &
+          pid=$!
+          # Stop it when this step ends, however it ends.
+          trap 'kill "$pid" 2> /dev/null || true' EXIT
+          # Wait up to 30 seconds for the main page.
+          ok=0
+          for i in $(seq 1 30); do
+            if curl -fsS -o main.html http://127.0.0.1:8765/ 2> /dev/null; then ok=1; break; fi
+            sleep 1
+          done
+          if [ "$ok" != "1" ]; then echo "The program did not answer within 30 seconds"; cat run.log; exit 1; fi
+          # The main page names the program, the About page carries the version, the Settings page answers.
+          grep -q "<title>OllamaControlCenter</title>" main.html
+          curl -fsS http://127.0.0.1:8765/about | grep -q "$VERSION"
+          curl -fsS -o /dev/null http://127.0.0.1:8765/settings
+          echo "PASS: $FILE answered on $RUNNER_OS $RUNNER_ARCH"
+          cat run.log
+
+  # Job 3: run the tests on the other systems too. The tests were written on Linux, so failures are EXPECTED on Windows and macOS for now: they are reported, they do not stop the workflow, and they become the list of tests to make portable.
+  tests-on-each-system:
+    strategy:
+      fail-fast: false
+      matrix:
+        runner: [ubuntu-24.04-arm, windows-2025, windows-11-arm, macos-15, macos-15-intel]
+    runs-on: ${{ matrix.runner }}
+    continue-on-error: true
+    timeout-minutes: 20
+    steps:
+      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
+        with:
+          persist-credentials: false
+      - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
+        with:
+          go-version: ${{ env.GO_VERSION }}
+          cache: false
+      # Run every test and list the failing ones in the summary of the run.
+      - name: go test
+        shell: bash
+        run: |
+          go test -count=1 ./... 2>&1 | tee test.log
+          status="${PIPESTATUS[0]}"
+          {
+            echo "### Tests on ${{ matrix.runner }}: exit code $status"
+            grep -E '^--- FAIL' test.log | sort -u || true
+          } >> "$GITHUB_STEP_SUMMARY"
+          exit "$status"
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprint (sha256) the file must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
c89a1c613405157a1e1153acf4576ed32aac07b507e999700b67e2c8946ec30b  .github/workflows/build.yml
SUMS_END
# Compare the real fingerprint with the expected one.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The file is exactly as tested.
  echo "PASS  the file is exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  the file differs from the tested version"; exit 1
fi
# Every borrowed action must be pinned to a full 40-character commit (no moving version tags).
if grep -E '^\s*-?\s*uses:' .github/workflows/build.yml | grep -vE '@[0-9a-f]{40}( |$)'; then
  # An unpinned line was printed above.
  echo "FAIL  an action is not pinned to a commit"; exit 1
fi
# Report the check.
echo "PASS  every action is pinned to a commit"
# The only trigger must be the manual button.
if grep -nE '^\s*(push|pull_request|schedule|release|pull_request_target):' .github/workflows/build.yml; then
  # An automatic trigger was printed above.
  echo "FAIL  an automatic trigger was found"; exit 1
fi
# Report the check.
echo "PASS  the only trigger is workflow_dispatch (the manual button)"
# The rights must be read-only.
grep -q '^  contents: read$' .github/workflows/build.yml || { echo "FAIL  contents: read is missing"; exit 1; }
# Report the check.
echo "PASS  read-only rights"
# Check the file is valid YAML when Python's yaml module is there (skipped otherwise).
if python3 -c 'import yaml' 2> /dev/null; then
  # Parse it.
  python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/build.yml"))' || { echo "FAIL  the file is not valid YAML"; exit 1; }
  # Report the check.
  echo "PASS  valid YAML"
else
  # Say that it was skipped.
  echo "SKIP  YAML check (python3 yaml module not installed)"
fi
# The program must still build and the tests pass, as before (the program is unchanged).
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Tell the person what to look at.
echo "NEXT  commit, push and merge this change; the workflow shows on the Actions tab only after it is on main"
# List the changed files; nothing is committed yet.
git status --short
