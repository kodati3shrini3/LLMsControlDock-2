#!/usr/bin/env bash
# Script 108 (Help page, topics open and close): every help topic is now a section that starts closed and opens when its title is clicked (no script needed); a list of topic links sits at the top of the page; and each open topic has the round back arrow to the monitor at its top and at its bottom, besides the arrow at the top of the page. Tests follow.
# Run it from a new branch made from main (after script 107 is merged): cd ~/LLMsControlDock && git switch -c feature/help-topics-open-close && bash scripts/108-step71-help-topics-open-close.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 107), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["help_test.go"]="8204ec551ff624d93216fc3a0e40345b7802e9797bdb5e66734585f28892684f"
BEFORE["web/help.html"]="d8ec2a70356d1a06d044bdda5974b2fb1cbc865489c667368fb93f45ccaa4de9"
BEFORE["web/app.css"]="a0aad37afed17c08c185f2d331621caa63078380e3ed76c7249a31898d73ff1d"
AFTER["help_test.go"]="ba1b4ade36d6d53abed2d70d907d749461654f4c8f4e45df0c8107eda2aee4cd"
AFTER["web/help.html"]="b528233151596ee80c0b35906ad7221549f147771d82129623362b64de7f1bd6"
AFTER["web/app.css"]="63884d33aaf880b8476219b7fae6ef43c9b0f1f052e6fd2e434764a3f1a4a83f"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/help-topics-open-close"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 107 must have been applied: the Help page exists.
[ -f help.go ] || fail "script 107 must be applied first"
# Report it.
pass "script 107 is applied"

# Refuse to run twice: the closed sections exist when this change was applied before.
if grep -q 'class="helptopic"' web/help.html && grep -q '<details' web/help.html; then fail "web/help.html already has the closed sections: this script was already applied"; fi
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
diff --git a/help_test.go b/help_test.go
index c2de9b4..422fecc 100644
--- a/help_test.go
+++ b/help_test.go
@@ -131,6 +131,38 @@ func TestHelpPage(t *testing.T) {
 			t.Errorf("lane %q has no name in the picture", l)
 		} // end of the look
 	} // end of the lane loop
+	// Each topic is a closed section that opens when its title is clicked, and the contents list links to it.
+	for _, tp := range helpTopics {
+		// The closed section (no "open" word).
+		if !strings.Contains(body, `<details class="helptopic" id="`+tp.ID+`">`) || strings.Contains(body, `<details class="helptopic" id="`+tp.ID+`" open`) {
+			// Report.
+			t.Errorf("topic %s is not a closed section", tp.ID)
+		} // end of the section check
+		// The contents link.
+		if !strings.Contains(body, `<li><a href="#`+tp.ID+`">`+html.EscapeString(tp.Title)+`</a></li>`) {
+			// Report.
+			t.Errorf("the contents list lacks a link to %s", tp.ID)
+		} // end of the link check
+		// The title is the clickable row.
+		if !strings.Contains(body, `<summary class="helpsum"><h2 id="`+tp.ID+`-title">`) {
+			// Report.
+			t.Errorf("topic %s has no clickable title", tp.ID)
+		} // end of the title check
+		// An arrow at the top of the open topic (before the picture) and one at the bottom (after the list).
+		top, bottom := strings.Index(body, `id="tipback-`+tp.ID+`-top"`), strings.Index(body, `id="tipback-`+tp.ID+`-bottom"`)
+		// The picture and the list.
+		svg, list := strings.Index(body, `<svg class="swimlane"`), strings.Index(body, `<ol class="helpsteps">`)
+		// Check the order.
+		if top < 0 || bottom < 0 || !(top < svg && list < bottom) {
+			// Report.
+			t.Errorf("topic %s: arrows at %d and %d, picture at %d, list at %d", tp.ID, top, bottom, svg, list)
+		} // end of the arrow check
+	} // end of the topic loop
+	// The page's own arrow plus two for every topic.
+	if n := strings.Count(body, `aria-label="Back to the monitor"`); n != 1+2*len(helpTopics) {
+		// Report.
+		t.Errorf("%d back arrows, want %d", n, 1+2*len(helpTopics))
+	} // end of the arrow count
 	// The monitor links to the Help page.
 	if _, _, main := get(t, rig.h, http.MethodGet, "/"); !strings.Contains(main, `<a class="brandbtn" href="/help">Help</a>`) {
 		// Report.
diff --git a/web/app.css b/web/app.css
index 29b576b..a3b4d1e 100644
--- a/web/app.css
+++ b/web/app.css
@@ -3128,3 +3128,33 @@ html[data-size="medium"] svg[width="22"] {
   /* Room for the numbers. */
   padding-left: 1.5rem;
 } /* end of rule */
+
+/* The list of topic links at the top of the Help page. */
+.helptoc {
+  /* Room for the bullets. */
+  padding-left: 1.5rem;
+} /* end of rule */
+
+/* The clickable title row of a closed or open topic. */
+.helpsum {
+  /* Shows the pointing hand over the title. */
+  cursor: pointer;
+  /* Space around the title, so it is easy to hit. */
+  padding: 0.4rem 0;
+} /* end of rule */
+
+/* The title inside the clickable row stays on the same line as the open or close triangle. */
+.helpsum h2 {
+  /* Next to the triangle. */
+  display: inline;
+  /* Same size as other section headings. */
+  font-size: 1.1rem;
+} /* end of rule */
+
+/* The back arrow row at the top and bottom of an open topic: the arrow sits at the right end. */
+.helpback {
+  /* At the right. */
+  text-align: right;
+  /* Space above and below. */
+  margin: 0.6rem 0;
+} /* end of rule */
diff --git a/web/help.html b/web/help.html
index da7c7b0..45a3fea 100644
--- a/web/help.html
+++ b/web/help.html
@@ -22,13 +22,21 @@
 {{/* The name of the page. */}}
 <h1>Help</h1>
 {{/* What the page is. */}}
-<p class="muted">Each topic shows who does what, in lanes, from the top down. This is the first topic; more follow.</p>
-{{/* The topics. */}}
+<p class="muted">Each topic shows who does what, in lanes, from the top down. Click a topic's title to open it. This is the first topic; more follow.</p>
+{{/* The contents: a link to every topic's title. */}}
+<nav aria-label="Help topics">
+<ul class="helptoc">
+{{range .Topics}}<li><a href="#{{.ID}}">{{.Title}}</a></li>
+{{end}}</ul>
+</nav>
+{{/* The topics; each one starts closed and opens when its title is clicked (no script is needed). */}}
 {{range $t := .Topics}}
 {{/* One topic. */}}
-<section class="helptopic" id="{{.ID}}" aria-labelledby="{{.ID}}-title">
-{{/* Its heading. */}}
-<h2 id="{{.ID}}-title">{{.Title}}</h2>
+<details class="helptopic" id="{{.ID}}">
+{{/* Its heading, which is also the button that opens it. */}}
+<summary class="helpsum"><h2 id="{{.ID}}-title">{{.Title}}</h2></summary>
+{{/* A way back to the monitor at the top of the open topic. */}}
+<p class="helpback"><span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-{{$t.ID}}-top"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-{{$t.ID}}-top">Back to the monitor</span></span></p>
 {{/* The plain introduction. */}}
 <p>{{.Intro}}</p>
 {{/* The picture; its name and description are read by screen readers, and the numbered list below says the same in words. */}}
@@ -56,8 +64,10 @@
 <ol class="helpsteps">
 {{range .List}}<li><strong>{{.Lane}}:</strong> {{.Text}}</li>
 {{end}}</ol>
+{{/* A way back to the monitor at the bottom of the open topic, because the pictures are long. */}}
+<p class="helpback"><span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-{{$t.ID}}-bottom"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-{{$t.ID}}-bottom">Back to the monitor</span></span></p>
 {{/* End of the topic. */}}
-</section>
+</details>
 {{end}}
 {{/* A link back. */}}
 <p><a class="btn-plain" href="/">Back to the monitor</a></p>
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
echo "NEXT  start bin/LLMsControlDock and open the Help page, open the topic and use the back arrows (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
