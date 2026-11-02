#!/usr/bin/env bash
# Script 77: the Settings page now notices when the launcher on the desktop is out of date (for example its picture still points at the old folder after an upgrade, or the program was moved) and shows a warning with an "Update the icon" button; nothing on the desktop is changed without the button. The version becomes 0.27.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/refresh-launcher" ] || { echo "FAIL  not on feature/refresh-launcher"; exit 1; }
# Refuse to run twice.
if grep -q staleness desktopicon.go; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index 0f90d6c..3609e19 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.26.0"
+const appVersion = "0.27.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/desktopicon.go b/desktopicon.go
index fe9630b..4fdd8be 100644
--- a/desktopicon.go
+++ b/desktopicon.go
@@ -285,21 +285,14 @@ func (d desktopIcon) decline() error {
 	return d.remember("declined")
 } // end of decline
 
-// create writes the icon picture next to the settings and the launcher on the desktop, then remembers the answer.
-func (d desktopIcon) create() error {
-	// A desktop must exist.
-	dir, ok := d.env.desktopDir()
-	// Refuse without one.
-	if !ok || d.dir == "" {
-		// Not supported.
-		return errDesktopUnsupported
-	} // end of the support check
+// launcherPaths returns the program path and the picture path a launcher should hold now, both checked to be plain; it returns an error when the program's place is unknown or holds unusual characters.
+func (d desktopIcon) launcherPaths() (string, string, error) {
 	// The program's own file.
 	exe, err := d.env.exePath()
 	// Report a failure.
 	if err != nil {
 		// Report it.
-		return err
+		return "", "", err
 	} // end of the program check
 	// The path as the system sees it.
 	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
@@ -309,15 +302,86 @@ func (d desktopIcon) create() error {
 	// Only plain characters are allowed.
 	if !safePathPattern.MatchString(exe) {
 		// Refuse.
-		return errUnusualPath
+		return "", "", errUnusualPath
 	} // end of the path check
 	// Where the picture goes.
 	icon := filepath.Join(d.iconDir(), iconFileName)
 	// The picture's path must be plain too.
 	if !safePathPattern.MatchString(icon) {
 		// Refuse.
-		return errUnusualPath
+		return "", "", errUnusualPath
 	} // end of the icon path check
+	// Both are fine.
+	return exe, icon, nil
+} // end of launcherPaths
+
+// staleness says whether the launcher on the desktop differs from what the program would write now (for example after an upgrade moved the picture, or after the program was moved); it returns the picture path the launcher holds and the one it should hold. A missing or unreadable launcher is not stale, because there is nothing to refresh.
+func (d desktopIcon) staleness() (bool, string, string) {
+	// No launcher, nothing to refresh.
+	p := d.desktopPath()
+	// No desktop.
+	if p == "" {
+		// Not stale.
+		return false, "", ""
+	} // end of the path check
+	// Open the launcher.
+	f, err := os.Open(p)
+	// Missing: not stale.
+	if err != nil {
+		// Not stale.
+		return false, "", ""
+	} // end of the open check
+	// Close it at the end.
+	defer f.Close()
+	// Read at most 8 KiB; a real launcher is far smaller.
+	have, err := io.ReadAll(io.LimitReader(f, 8192))
+	// Unreadable: not stale.
+	if err != nil {
+		// Not stale.
+		return false, "", ""
+	} // end of the read check
+	// What the program would write now.
+	exe, icon, err := d.launcherPaths()
+	// Without plain paths nothing can be compared.
+	if err != nil {
+		// Not stale.
+		return false, "", ""
+	} // end of the paths check
+	// The same text: current.
+	if string(have) == desktopFileText(exe, icon) {
+		// Not stale.
+		return false, icon, icon
+	} // end of the compare
+	// The picture path the launcher holds now.
+	old := ""
+	// Look at each line.
+	for _, line := range strings.Split(string(have), "\n") {
+		// The picture line.
+		if strings.HasPrefix(line, "Icon=") {
+			// Keep the path.
+			old = strings.TrimPrefix(line, "Icon=")
+		} // end of the picture line
+	} // end of the line loop
+	// Stale.
+	return true, old, icon
+} // end of staleness
+
+// create writes the icon picture next to the data and the launcher on the desktop, then remembers the answer.
+func (d desktopIcon) create() error {
+	// A desktop must exist.
+	dir, ok := d.env.desktopDir()
+	// Refuse without one.
+	if !ok || d.dir == "" {
+		// Not supported.
+		return errDesktopUnsupported
+	} // end of the support check
+	// The paths the launcher should hold.
+	exe, icon, err := d.launcherPaths()
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the paths check
 	// Write the picture.
 	if err := writeFile(d.iconDir(), iconFileName, appIcon); err != nil {
 		// Report it.
diff --git a/desktopicon_test.go b/desktopicon_test.go
index 19eaa4b..4d18579 100644
--- a/desktopicon_test.go
+++ b/desktopicon_test.go
@@ -513,3 +513,116 @@ func TestDesktopDeclineAndNoDesktop(t *testing.T) {
 		t.Errorf("icon route: %d %q", code, hdr.Get("Content-Type"))
 	} // end of the icon check
 } // end of TestDesktopDeclineAndNoDesktop
+
+// TestDesktopStaleness checks when the launcher counts as out of date.
+func TestDesktopStaleness(t *testing.T) {
+	// The pretend desktop and the two folders.
+	f := newFakeDesktop(t)
+	// The settings folder.
+	set := filepath.Join(f.home, ".config", "OllamaControlCenter")
+	// The data folder, where the picture lives now.
+	data := filepath.Join(f.home, ".local", "share", "OllamaControlCenter")
+	// The manager.
+	d := desktopIcon{env: f.env, dir: set, dataDir: data}
+	// No launcher: nothing to refresh.
+	if stale, _, _ := d.staleness(); stale {
+		// Report it.
+		t.Error("a missing launcher was called stale")
+	} // end of the missing check
+	// Create it: now it is current.
+	if err := d.create(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the create check
+	// Current.
+	if stale, _, _ := d.staleness(); stale {
+		// Report it.
+		t.Error("a fresh launcher was called stale")
+	} // end of the current check
+	// Path of the launcher.
+	path := filepath.Join(f.desk, desktopFileName)
+	// An old launcher: the picture is in the old place (as version 0.25.0 wrote it).
+	oldIcon := filepath.Join(set, iconFileName)
+	// Write it.
+	if err := os.WriteFile(path, []byte(desktopFileText(f.exe, oldIcon)), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// Stale, with both paths named.
+	stale, got, want := d.staleness()
+	// Compare.
+	if !stale || got != oldIcon || want != filepath.Join(data, iconFileName) {
+		// Report it.
+		t.Errorf("old icon: stale %v, old %q, new %q", stale, got, want)
+	} // end of the old-icon check
+	// A launcher for another copy of the program.
+	if err := os.WriteFile(path, []byte(desktopFileText(filepath.Join(f.home, "elsewhere", "occ"), filepath.Join(data, iconFileName))), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// Stale, with the same picture path.
+	stale, got, want = d.staleness()
+	// Compare.
+	if !stale || got != want {
+		// Report it.
+		t.Errorf("old program: stale %v, old %q, new %q", stale, got, want)
+	} // end of the old-program check
+	// Updating makes it current again.
+	if err := d.create(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the update check
+	// Current.
+	if stale, _, _ := d.staleness(); stale {
+		// Report it.
+		t.Error("still stale after the update")
+	} // end of the after check
+} // end of TestDesktopStaleness
+
+// TestDesktopStaleWarningOnPage checks the warning and the "Update the icon" button on the Settings page, and that the button fixes it.
+func TestDesktopStaleWarningOnPage(t *testing.T) {
+	// The rig.
+	r := newDesktopRig(t)
+	// A current launcher first.
+	d := desktopIcon{env: r.f.env, dir: r.mon.store.dir, dataDir: dataRoot()}
+	// Create it.
+	if err := d.create(); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the create check
+	// The page: no warning.
+	_, _, body := get(t, r.h, http.MethodGet, "/settings")
+	// No warning, the usual button.
+	if strings.Contains(body, "out of date") || strings.Contains(body, "Update the icon") || !strings.Contains(body, "Create the icon again") {
+		// Report it.
+		t.Error("a current launcher shows a warning")
+	} // end of the current check
+	// Make the launcher old.
+	old := filepath.Join(r.mon.store.dir, iconFileName)
+	// Write it.
+	if err := os.WriteFile(filepath.Join(r.f.desk, desktopFileName), []byte(desktopFileText(r.f.exe, old)), 0o755); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// The page: the warning and the button.
+	_, _, body = get(t, r.h, http.MethodGet, "/settings")
+	// Both must show, with the old path named.
+	if !strings.Contains(body, "out of date") || !strings.Contains(body, "Update the icon") || !strings.Contains(body, old) {
+		// Report it.
+		t.Errorf("no warning for an old launcher")
+	} // end of the stale check
+	// Press the button (the action is "create").
+	form := url.Values{"token": {r.token}, "action": {"create"}}
+	// Send it.
+	if resp := post(t, r.h, "/desktopicon", form, fromThisPage); resp.StatusCode != http.StatusSeeOther {
+		// Report it.
+		t.Errorf("update status = %d", resp.StatusCode)
+	} // end of the post check
+	// The page again: no warning.
+	_, _, body = get(t, r.h, http.MethodGet, "/settings")
+	// Gone.
+	if strings.Contains(body, "out of date") {
+		// Report it.
+		t.Error("the warning stayed after the update")
+	} // end of the fixed check
+} // end of TestDesktopStaleWarningOnPage
diff --git a/settingspage.go b/settingspage.go
index 674cec9..0d4d2d9 100644
--- a/settingspage.go
+++ b/settingspage.go
@@ -83,6 +83,12 @@ type settingsPage struct {
 	IconPath string
 	// IconNote is the plain sentence about what just happened (empty when nothing did).
 	IconNote string
+	// IconStale is true when the launcher on the desktop differs from what the program would write now.
+	IconStale bool
+	// IconOld is the picture path the launcher holds now.
+	IconOld string
+	// IconNew is the picture path the launcher should hold.
+	IconNew string
 } // end of settingsPage
 
 // iconNotes are the sentences shown after a desktop icon button; the address carries only the key, so no free text is ever echoed.
@@ -267,10 +273,12 @@ func settingsHandlers(addr ollamaAddress, mon *monitor, token string) (http.Hand
 		desk := desktopIcon{env: mon.denv, dir: mon.store.dir, dataDir: dataRoot()}
 		// The icon section's facts.
 		iconAvail, iconExists, iconPath := desk.available(), desk.exists(), desk.desktopPath()
+		// Whether the launcher is out of date, and the two picture paths.
+		iconStale, iconOld, iconNew := desk.staleness()
 		// The note after a button; unknown keys show nothing.
 		iconNote := iconNotes[r.URL.Query().Get("icon")]
 		// Everything the template needs.
-		data := settingsPage{IconAvailable: iconAvail, IconExists: iconExists, IconPath: iconPath, IconNote: iconNote, Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder, DataFolder: dataFolder, StateFolder: stateFolder}
+		data := settingsPage{IconAvailable: iconAvail, IconExists: iconExists, IconPath: iconPath, IconNote: iconNote, IconStale: iconStale && iconAvail, IconOld: iconOld, IconNew: iconNew, Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder, DataFolder: dataFolder, StateFolder: stateFolder}
 		// Build the page in memory first, so a template error gives a clean 500.
 		var buf bytes.Buffer
 		// Fill the template.
diff --git a/web/settings.html b/web/settings.html
index 3b83b5f..36ff6c5 100644
--- a/web/settings.html
+++ b/web/settings.html
@@ -75,11 +75,13 @@
 {{/* The state and the buttons. */}}
 {{if .IconAvailable}}
 <p class="muted">{{if .IconExists}}The icon is on your desktop: <code>{{.IconPath}}</code>.{{else}}There is no icon on your desktop now.{{end}} One click on it starts the monitor (if it is not running) and opens the page in your browser. If you move the program, create the icon again.</p>
+{{/* The launcher is out of date: say what differs and offer the update. */}}
+{{if .IconStale}}<p class="warn" role="status"><strong>⚠</strong> The icon on your desktop is out of date: {{if ne .IconOld .IconNew}}it still points at an old place (<code>{{.IconOld}}</code>) for its picture, so the picture may be missing. Press <strong>Update the icon</strong> to rewrite it with the current place (<code>{{.IconNew}}</code>).{{else}}it starts the program from another place than the one running now. Press <strong>Update the icon</strong> to rewrite it for this program.{{end}} Nothing else on your desktop is touched.</p>{{end}}
 <form method="post" action="/desktopicon">
 {{/* The page token proves the form comes from this monitor. */}}
 <input type="hidden" name="token" value="{{.Token}}">
 {{/* The buttons. */}}
-<p><button type="submit" name="action" value="create" class="btn-plain">{{if .IconExists}}Create the icon again{{else}}Create desktop icon{{end}}</button>{{if .IconExists}} <button type="submit" name="action" value="remove" class="btn-plain">Remove desktop icon</button>{{end}}</p>
+<p><button type="submit" name="action" value="create" class="btn-plain">{{if .IconStale}}Update the icon{{else if .IconExists}}Create the icon again{{else}}Create desktop icon{{end}}</button>{{if .IconExists}} <button type="submit" name="action" value="remove" class="btn-plain">Remove desktop icon</button>{{end}}</p>
 {{/* End of the form. */}}
 </form>
 {{end}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
0210d278e1273ce89e1d98fd784dafede3c6ab4758c93d7292d83ca7c633e730  about.go
114fbe7fc31fec727c6df8df5676cd73af95970a1cc5f2c48d7dc76a9350e680  desktopicon.go
cc1b480fdbe4778634324df37189a0088d69b63962527c5b313b5b8591856daf  desktopicon_test.go
7b24992428c10d26f3c3581c0e387d09df677fd8669e6b51b7afdae8f8b24060  settingspage.go
cff1496516e8b056e82dfd00f17504c0d693a5d6d42701e43fbc8af55c57b1ee  web/settings.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build for this computer the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Check that the program also compiles for Windows and macOS (nothing is kept).
for target in windows/amd64 darwin/arm64 darwin/amd64; do
  # Build for one target and throw the file away.
  GOOS="${target%/*}" GOARCH="${target#*/}" CGO_ENABLED=0 go build -trimpath -o /dev/null . || { echo "FAIL  build for $target"; exit 1; }
  # Report it.
  echo "PASS  compiles for $target"
done
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# Tell the person what to look at.
echo "NEXT  start ./bin/OllamaControlCenter, open http://127.0.0.1:8765/settings: if the launcher on the desktop is out of date you see a warning with Update the icon; press it, then run: grep ^Icon= ~/Desktop/OllamaControlCenter.desktop (it must show ~/.local/share/OllamaControlCenter/icon.png)"
# List the changed files; nothing is committed yet.
git status --short
