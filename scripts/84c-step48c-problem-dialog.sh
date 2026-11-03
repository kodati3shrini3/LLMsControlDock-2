#!/usr/bin/env bash
# Script 84c (System check alert dialog): when the System check finds a problem (Ollama not found, Ollama older than the fully tested version, NVIDIA driver or card below the published minimum, no supported graphics card), the page opens an OK dialog that says what is wrong and lists the steps to fix it with the official pages. When nothing is wrong, no dialog appears. The report stays on the screen. Added: problems.go, problems_test.go, web/attention.js; changed: syscheck.go, web.go, web/systemcheck.html, web/app.css. The version stays 0.30.0.
# Run it from the project folder, on the feature branch (never on main): cd ~/OllamaControlCenter && bash scripts/84c-step48c-problem-dialog.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two files BEFORE the change (about.go as left by script 84).
declare -A BEFORE AFTER
BEFORE["syscheck.go"]="4d37370d8c684e4390f4d1d088ebad01882a502aeca575ac4fd5b2dd620b86b2"
BEFORE["web.go"]="2d99b19bbfb0397ee6e3d8c416b5383043c32c009055f4f10b90b15671bd210a"
BEFORE["web/systemcheck.html"]="bcaffd25b65a6513a08c656eed5b7becb8e11c6f7b878db73e03a1d108b29891"
BEFORE["web/app.css"]="743d855ccfaa53314b37e0f00225bbe675129f0f55ad7e9da4086b66dbc2dc7a"
AFTER["syscheck.go"]="e04d9e3e686955ccc6d7322750e069e68f4eb1a372c8c3832692cab35b20e35b"
AFTER["web.go"]="b8129b2aafa4dcee0fbbcf1263b1f2d555e72f8d9a6a957e75b08ec09cfe3284"
AFTER["web/systemcheck.html"]="04f8ef03680388d5b31fe3b4bbe6d07c65a1e6dbedb31564c27cb59549d37adc"
AFTER["web/app.css"]="816ac498602498929e6e6b57c760db3e2fcf2b3251b57711332c19743261e923"
AFTER["problems.go"]="1280a4325355ab2cc374c2e593baf7fed82f0d3b80e46617aaeda56178b070ea"
AFTER["problems_test.go"]="8e7c27480061256cd04ac18a6591e562c3cfa90698be704208619cd97a849ca7"
AFTER["web/attention.js"]="b1623d00a289d2c2442654f47df37a347ab9ec9e5ae0425354db0c605b7703c7"

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
# The project must be OllamaControlCenter: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the OllamaControlCenter folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; this script belongs on feature/environment-requirements"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 84 must have been applied: its new file exists.
[ -e environment.go ] || fail "environment.go is missing: run script 84 first"
# Report it.
pass "script 84 was applied (environment.go exists)"

# Refuse to run twice: the new wording is already there when the change was applied before.
[ -e about.go ] && grep -q 'my daughter Meghna' about.go || fail "script 84b was not applied (the new dedication is missing): run script 84b first"
pass "script 84b was applied"

if [ -e problems.go ]; then fail "problems.go exists: this script was already applied"; fi
pass "the problem dialog is not there yet (script not applied before)"

for F in "${!BEFORE[@]}"; do
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
done
pass "the four files to change are the expected versions before the change"

PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_84C_END'
diff --git a/problems.go b/problems.go
new file mode 100644
index 0000000..e1b4381
--- /dev/null
+++ b/problems.go
@@ -0,0 +1,181 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the packages this file uses.
+	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
+	_ "embed"
+	// fmt builds the texts that contain a number or an address.
+	"fmt"
+	// net/http provides requests and status codes.
+	"net/http"
+	// strings recognises which kind of finding a sentence is.
+	"strings"
+) // end of imports
+
+// attentionJS opens the problem dialog of the System check page, stored inside the executable at build time.
+//
+//go:embed web/attention.js
+var attentionJS []byte
+
+// attentionHandler sends the script file.
+func attentionHandler(w http.ResponseWriter, r *http.Request) {
+	// Tell the browser this is JavaScript.
+	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
+	// Send it.
+	w.Write(attentionJS)
+} // end of attentionHandler
+
+// fixStep is one step of a fix: a sentence and, when the step is a command, the command to type.
+type fixStep struct {
+	// Text is what to do.
+	Text string
+	// Cmd is the command to type for this step, or empty.
+	Cmd string
+} // end of fixStep
+
+// fixLink is an official page that backs a fix, shown with its full address so the person can see where it leads.
+type fixLink struct {
+	// Text says what the page is.
+	Text string
+	// URL is the address of the page.
+	URL string
+} // end of fixLink
+
+// problem is one thing the System check found that the person should fix, with the steps.
+type problem struct {
+	// Title is the short name of the problem.
+	Title string
+	// Why says in one sentence what is wrong and what it costs.
+	Why string
+	// Steps are the steps to fix it, in order; empty when there is no software fix.
+	Steps []fixStep
+	// NoFix is the honest sentence shown when no step can fix it.
+	NoFix string
+	// Links are the official pages the steps come from.
+	Links []fixLink
+} // end of problem
+
+// The official pages the fix steps rely on; each address was read from the vendor's own page.
+var (
+	// ollamaDownloadLink is Ollama's download page.
+	ollamaDownloadLink = fixLink{"Ollama download page", "https://ollama.com/download"}
+	// ollamaFAQLink is Ollama's FAQ, which says how to update Ollama.
+	ollamaFAQLink = fixLink{"Ollama FAQ: how to update Ollama", "https://github.com/ollama/ollama/blob/main/docs/faq.md"}
+	// ollamaGPULink is Ollama's GPU page with the published minimums.
+	ollamaGPULink = fixLink{"Ollama GPU page: the published minimums", "https://docs.ollama.com/gpu"}
+	// nvidiaCudaLink is NVIDIA's list of CUDA graphics cards.
+	nvidiaCudaLink = fixLink{"NVIDIA list of CUDA graphics cards", "https://developer.nvidia.com/cuda-gpus"}
+	// nvidiaDriverLink is NVIDIA's own driver download page.
+	nvidiaDriverLink = fixLink{"NVIDIA driver downloads", "https://www.nvidia.com/Download/index.aspx"}
+	// ollamaDockerLink is the official Ollama image page.
+	ollamaDockerLink = fixLink{"Ollama on Docker Hub", "https://hub.docker.com/r/ollama/ollama"}
+) // end of the official pages
+
+// The phrases by which the verdict sentences of judgeNvidia and judgeReport are recognised; a test keeps them in step with those sentences.
+const (
+	// phraseOldDriver is inside the sentence for a driver below the minimum.
+	phraseOldDriver = "is older than the published minimum"
+	// phraseOldCard is inside the sentence for a card below compute capability 5.0.
+	phraseOldCard = "is below the published minimum of 5.0"
+	// phraseNoCard is the start of the sentence for no confirmed card.
+	phraseNoCard = "No graphics card could be confirmed"
+) // end of the phrases
+
+// collectProblems lists what needs fixing, in the order of the page; it returns nothing when everything is fine, so no dialog is shown. Lines of level "info" are never problems.
+func collectProblems(online bool, address, goos string, env envView, findings []finding) []problem {
+	// The list.
+	var out []problem
+	// Ollama does not answer.
+	if !online {
+		// The problem and its steps.
+		out = append(out, problem{
+			Title: "Ollama was not found",
+			Why:   fmt.Sprintf("Nothing answered at %s. This tool works with Ollama only, so it can show nothing useful until Ollama runs.", address),
+			Steps: []fixStep{
+				{Text: "Install Ollama on the computer that should run your models, if it is not installed yet (see the download page below)."},
+				{Text: "Start Ollama and wait until it is running. If you use Docker, check that the Ollama container is running and that its port is published."},
+				{Text: "If Ollama runs at another address or port, open Settings in this tool and enter that address."},
+				{Text: "Open the System check again (reload this page). The problem is gone when Ollama answers."},
+			},
+			Links: []fixLink{ollamaDownloadLink},
+		})
+	} // end of the offline case
+	// The Ollama version is older than the fully tested one, or was tested only in part.
+	if env.OllamaVerdict.Level == "warn" {
+		// The steps depend on how Ollama is installed; the official FAQ names these ways.
+		steps := []fixStep{}
+		// The way for this operating system.
+		switch goos {
+		// Linux: run the install script again (Ollama FAQ).
+		case "linux":
+			// The command from the FAQ.
+			steps = append(steps, fixStep{Text: "If Ollama was installed with the install script, run the script again to update it:", Cmd: "curl -fsSL https://ollama.com/install.sh | sh"})
+		// Windows and macOS: Ollama updates itself; restart to finish (Ollama FAQ).
+		default:
+			// The FAQ steps.
+			steps = append(steps, fixStep{Text: "Ollama downloads updates by itself. Click the Ollama icon in the taskbar or menu bar and choose \"Restart to update\". You can also download the latest version by hand from the download page below."})
+		} // end of the system switch
+		// Docker is a common way to run Ollama on a server.
+		steps = append(steps, fixStep{Text: "If Ollama runs in Docker, pull the newer image, then stop and start the container again so it uses it:", Cmd: "docker pull ollama/ollama"})
+		// Then check.
+		steps = append(steps, fixStep{Text: "Open the System check again (reload this page). Under \"Ollama, found here\" the version should now be the minimum shown above or newer."})
+		// The problem.
+		out = append(out, problem{
+			Title: "The Ollama version is older than the one this tool was fully tested on",
+			Why:   env.OllamaVerdict.Text,
+			Steps: steps,
+			Links: []fixLink{ollamaFAQLink, ollamaDownloadLink, ollamaDockerLink},
+		})
+	} // end of the version case
+	// The graphics findings.
+	for _, f := range findings {
+		// Only warnings are problems.
+		if f.Level != "warn" {
+			// Skip ok and info lines.
+			continue
+		} // end of the level check
+		// Which kind?
+		switch {
+		// The driver is too old: a software fix exists.
+		case strings.Contains(f.Text, phraseOldDriver):
+			// The problem.
+			out = append(out, problem{
+				Title: "The NVIDIA driver is older than Ollama's published minimum",
+				Why:   f.Text,
+				Steps: []fixStep{
+					{Text: "Look up the driver you have now:", Cmd: "nvidia-smi"},
+					{Text: "Download and install a newer driver for your card from NVIDIA's own driver page (below). Ollama's page says 550 or newer, and 570 or newer for cards with compute capability 5.0 to 6.2."},
+					{Text: "Restart the computer, then restart Ollama."},
+					{Text: "Open the System check again (reload this page). The problem is gone when the driver is at least the minimum."},
+				},
+				Links: []fixLink{nvidiaDriverLink, ollamaGPULink},
+			})
+		// The card itself is too old: no software fix.
+		case strings.Contains(f.Text, phraseOldCard):
+			// The problem.
+			out = append(out, problem{
+				Title: "The graphics card is too old for Ollama",
+				Why:   f.Text,
+				NoFix: "No software update fixes this: Ollama supports NVIDIA cards with compute capability 5.0 or higher. Models will run on the processor, which is much slower, unless you use a newer card or another computer.",
+				Links: []fixLink{nvidiaCudaLink, ollamaGPULink},
+			})
+		// No card confirmed at all.
+		case strings.HasPrefix(f.Text, phraseNoCard):
+			// The problem.
+			out = append(out, problem{
+				Title: "No supported graphics card was confirmed",
+				Why:   f.Text,
+				Steps: []fixStep{
+					{Text: "If this computer has an NVIDIA card, check that its driver is installed and working:", Cmd: "nvidia-smi"},
+					{Text: "If that command fails or lists no card, install the driver from NVIDIA's driver page (below), restart the computer, and restart Ollama."},
+					{Text: "Compare your card with NVIDIA's list: Ollama needs compute capability 5.0 or higher."},
+					{Text: "Open the System check again (reload this page)."},
+				},
+				NoFix: "If the computer has no supported card, there is nothing to install: Ollama then uses the processor, and the speeds you measure are not the speeds of a graphics card.",
+				Links: []fixLink{nvidiaDriverLink, nvidiaCudaLink, ollamaGPULink},
+			})
+		} // end of the kind switch
+	} // end of the findings loop
+	// Hand the list back; empty means no dialog.
+	return out
+} // end of collectProblems
diff --git a/problems_test.go b/problems_test.go
new file mode 100644
index 0000000..7395f93
--- /dev/null
+++ b/problems_test.go
@@ -0,0 +1,167 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the packages this file uses.
+	// net/http gives the status codes.
+	"net/http"
+	// strings checks the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time gives the check timeout.
+	"time"
+) // end of imports
+
+// okEnv is an environment view with no complaint.
+var okEnv = envView{OllamaVerdict: finding{"ok", "fine"}, GoVerdict: finding{"ok", "fine"}, SystemVerdict: finding{"ok", "fine"}}
+
+// TestCollectProblems checks which situations are problems and which are not.
+func TestCollectProblems(t *testing.T) {
+	// A card with a good driver.
+	good := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.9", Driver: "580.1"}}})
+	// Cases: what goes in, how many problems, and a word the first title must contain.
+	cases := []struct {
+		name     string
+		online   bool
+		env      envView
+		findings []finding
+		want     int
+		title    string
+	}{
+		{"everything fine", true, okEnv, good, 0, ""},
+		{"Ollama offline", false, okEnv, good, 1, "not found"},
+		{"old Ollama", true, envView{OllamaVerdict: finding{"warn", "old"}}, good, 1, "Ollama version"},
+		{"info lines are no problem", true, envView{OllamaVerdict: finding{"info", "newer"}}, []finding{{"info", "x"}}, 0, ""},
+		{"old driver", true, okEnv, judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.6", Driver: "500.1"}}})[:1], 1, "driver"},
+		{"old card", true, okEnv, judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "3.5", Driver: "580.1"}}})[:1], 1, "too old"},
+		{"no card", true, okEnv, judgeReport(hostReport{}), 1, "No supported graphics card"},
+		{"offline and old driver", false, okEnv, judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.6", Driver: "500.1"}}})[:1], 2, "not found"},
+	}
+	// Run each case.
+	for _, c := range cases {
+		// One sub-test per case.
+		t.Run(c.name, func(t *testing.T) {
+			// Ask.
+			got := collectProblems(c.online, "http://127.0.0.1:11434", "linux", c.env, c.findings)
+			// The count.
+			if len(got) != c.want {
+				// Report it.
+				t.Fatalf("got %d problems, want %d: %+v", len(got), c.want, got)
+			} // end of the count check
+			// The title.
+			if c.want > 0 && !strings.Contains(got[0].Title, c.title) {
+				// Report it.
+				t.Errorf("first title %q lacks %q", got[0].Title, c.title)
+			} // end of the title check
+			// Every problem is complete: a reason, and steps or an honest "no fix", and official links.
+			for _, p := range got {
+				// A reason.
+				if p.Why == "" || (len(p.Steps) == 0 && p.NoFix == "") || len(p.Links) == 0 {
+					// Report it.
+					t.Errorf("incomplete problem: %+v", p)
+				} // end of the completeness check
+				// Every link is an https address.
+				for _, l := range p.Links {
+					// Check the start.
+					if !strings.HasPrefix(l.URL, "https://") || l.Text == "" {
+						// Report it.
+						t.Errorf("bad link %+v", l)
+					} // end of the link check
+				} // end of the link loop
+			} // end of the problem loop
+		})
+	} // end of the case loop
+} // end of TestCollectProblems
+
+// TestUpdateStepsFitTheSystem checks that the update steps match the operating system, as the Ollama FAQ describes them.
+func TestUpdateStepsFitTheSystem(t *testing.T) {
+	// A warning about the version.
+	env := envView{OllamaVerdict: finding{"warn", "old"}}
+	// For each system, a word the first step must contain.
+	for goos, word := range map[string]string{"linux": "install.sh", "windows": "Restart to update", "darwin": "Restart to update"} {
+		// Ask.
+		got := collectProblems(true, "x", goos, env, nil)
+		// One problem.
+		if len(got) != 1 {
+			// Report it.
+			t.Fatalf("%s: got %d problems", goos, len(got))
+		} // end of the count check
+		// The first step.
+		if s := got[0].Steps[0]; !strings.Contains(s.Text+s.Cmd, word) {
+			// Report it.
+			t.Errorf("%s: first step %+v lacks %q", goos, s, word)
+		} // end of the step check
+	} // end of the system loop
+} // end of TestUpdateStepsFitTheSystem
+
+// TestPhrasesMatchTheVerdicts keeps the recognised phrases in step with the sentences judgeReport really writes.
+func TestPhrasesMatchTheVerdicts(t *testing.T) {
+	// The three warnings.
+	old := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.6", Driver: "500.1"}}})[0].Text
+	// Too old a card.
+	card := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "3.5", Driver: "580.1"}}})[0].Text
+	// No card.
+	none := judgeReport(hostReport{})[0].Text
+	// Check each.
+	if !strings.Contains(old, phraseOldDriver) || !strings.Contains(card, phraseOldCard) || !strings.HasPrefix(none, phraseNoCard) {
+		// Report it.
+		t.Errorf("a phrase no longer matches:\n%q\n%q\n%q", old, card, none)
+	} // end of the check
+} // end of TestPhrasesMatchTheVerdicts
+
+// TestDialogOnThePage checks the real page: with a problem it has the dialog, the script and the matching policy; without one it has none of them.
+func TestDialogOnThePage(t *testing.T) {
+	// Fixed Go version so the Go line is calm.
+	old := goVersionNow
+	// Put it back.
+	t.Cleanup(func() { goVersionNow = old })
+	// The tested version.
+	goVersionNow = func() string { return "go" + testedGo }
+	// A rig with no graphics card, so the page has a problem.
+	r := newSysRig(t, false, false)
+	// A good Ollama.
+	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"`+minimumOllama+`"}`))
+	// The handler.
+	h := newWebHandlerWith(mustResolve(t, srv.URL), time.Second, r.mon)
+	// The page.
+	code, hdr, body := get(t, h, http.MethodGet, "/systemcheck")
+	// It opens.
+	if code != http.StatusOK {
+		// Stop.
+		t.Fatalf("status = %d", code)
+	} // end of the status check
+	// The dialog, its script and the policy that allows only that script.
+	for _, want := range []string{`<dialog id="attention"`, `role="alertdialog"`, `method="dialog"`, `<script src="/attention.js" defer></script>`, "No supported graphics card was confirmed", "https://docs.ollama.com/gpu"} {
+		// Check each.
+		if !strings.Contains(body, want) {
+			// Report it.
+			t.Errorf("page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The policy.
+	if csp := hdr.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe") {
+		// Report it.
+		t.Errorf("policy = %q", csp)
+	} // end of the policy check
+	// The script itself is served.
+	if c, _, js := get(t, h, http.MethodGet, "/attention.js"); c != http.StatusOK || !strings.Contains(js, "showModal") {
+		// Report it.
+		t.Errorf("attention.js: %d", c)
+	} // end of the script check
+	// The report content stays on the page next to the dialog.
+	if !strings.Contains(body, "What this tool needs") {
+		// Report it.
+		t.Error("the report content is gone")
+	} // end of the report check
+	// Now a computer with a good NVIDIA card: no problem, so no dialog and the strict policy.
+	fakeProbes(t, map[string]string{"nvidia-smi": "NVIDIA GB10, [N/A], 580.95.05, 12.1\n"})
+	// A fresh handler, so the hardware report is made again.
+	h2 := newWebHandlerWith(mustResolve(t, srv.URL), time.Second, r.mon)
+	// The page.
+	_, hdr2, body2 := get(t, h2, http.MethodGet, "/systemcheck")
+	// No dialog, no script.
+	if strings.Contains(body2, "<dialog") || strings.Contains(body2, "<script") || strings.Contains(hdr2.Get("Content-Security-Policy"), "script-src") {
+		// Report it.
+		t.Errorf("a good computer must get no dialog:\n%s", body2)
+	} // end of the check
+} // end of TestDialogOnThePage
diff --git a/syscheck.go b/syscheck.go
index 64ad514..a9f0f86 100644
--- a/syscheck.go
+++ b/syscheck.go
@@ -136,6 +136,8 @@ type sysPage struct {
 	Reason string
 	// Findings are the verdict lines.
 	Findings []finding
+	// Problems are the things to fix; when there are any, the page opens a dialog with the steps, and otherwise it shows none.
+	Problems []problem
 	// Source names the page the verdicts come from.
 	Source string
 	// Env is the "What this tool needs" section: the Ollama and Go versions it was tested with, and the systems it was tested on.
@@ -352,6 +354,11 @@ func systemCheckHandlers(addr ollamaAddress, mon *monitor, token string, desktop
 			// Stop here.
 			return
 		} // end of the template check
+		// A page with a problem dialog may run the monitor's own script, and nothing else.
+		if len(data.Problems) > 0 {
+			// Replace the strict policy by the one that allows the script file.
+			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
+		} // end of the script policy
 		// Tell the browser this is an HTML page.
 		w.Header().Set("Content-Type", "text/html; charset=utf-8")
 		// Send the page.
@@ -392,7 +399,10 @@ func systemCheckHandlers(addr ollamaAddress, mon *monitor, token string, desktop
 		// Ask Ollama once.
 		res := checkOllama(r.Context(), addr.URL, mon.timeoutOr(defaultCheckTimeout))
 		// Fill in the page.
-		send(w, r, sysPage{Kind: "report", Rows: reportRows(rep), Online: res.Online, Address: addr.URL.Redacted(), Version: res.Version, Reason: res.Reason, Findings: judgeReport(rep), Source: ollamaGPUSource, Env: buildEnvView(res.Online, res.Version, reportOS, reportArch)})
+		// The verdict lines and the requirements.
+		findings, env := judgeReport(rep), buildEnvView(res.Online, res.Version, reportOS, reportArch)
+		// Fill in the page; the problems decide whether the dialog is shown.
+		send(w, r, sysPage{Kind: "report", Rows: reportRows(rep), Online: res.Online, Address: addr.URL.Redacted(), Version: res.Version, Reason: res.Reason, Findings: findings, Source: ollamaGPUSource, Env: env, Problems: collectProblems(res.Online, addr.URL.Redacted(), reportOS, env, findings)})
 	} // end of show
 	// cont: remember the answer and open the monitor.
 	cont = func(w http.ResponseWriter, r *http.Request) {
diff --git a/web.go b/web.go
index 70fb98c..e64ffa1 100644
--- a/web.go
+++ b/web.go
@@ -292,6 +292,8 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	mux.HandleFunc("GET /copy.js", copyHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
 	mux.HandleFunc("GET /loading.js", loadingHandler)
+	// Route: a GET request for "/attention.js" sends the small script that opens the problem dialog (only the System check page uses it, and only when it found a problem).
+	mux.HandleFunc("GET /attention.js", attentionHandler)
 	// Route: a GET request for exactly "/" shows the page; other paths get 404 and other methods get 405 from the router.
 	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
 		// The very first start: show the System check once, before the monitor.
diff --git a/web/app.css b/web/app.css
index 6f59ce3..d2ec02a 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2472,3 +2472,51 @@ html[data-size="medium"] svg[width="22"] {
   /* A gap between picture and ring. */
   outline-offset: 2px;
 } /* end of rule */
+
+/* The problem dialog of the System check: a modal window with a solid outline, so it stands out without colour. */
+.attention {
+  /* The page colours. */
+  background: var(--bg);
+  /* Text colour. */
+  color: var(--text);
+  /* A thick solid outline. */
+  border: 3px solid var(--text);
+  /* Rounded like the panels. */
+  border-radius: 0.5rem;
+  /* Room inside. */
+  padding: 1rem 1.25rem;
+  /* Never wider than the screen. */
+  max-width: min(42rem, 92vw);
+  /* Never taller than the screen; long text scrolls inside. */
+  max-height: 88vh;
+  /* Scroll inside when long. */
+  overflow-y: auto;
+} /* end of rule */
+
+/* The dimmed page behind the dialog. */
+.attention::backdrop {
+  /* A dark veil. */
+  background: rgba(0, 0, 0, 0.6);
+} /* end of rule */
+
+/* One problem inside the dialog. */
+.attprob {
+  /* A line above each problem. */
+  border-top: 1px solid var(--border);
+  /* Space above. */
+  margin-top: 0.75rem;
+  /* Space inside. */
+  padding-top: 0.5rem;
+} /* end of rule */
+
+/* Long web addresses may break instead of widening the dialog. */
+.attention a, .attention code {
+  /* Break anywhere when needed. */
+  overflow-wrap: anywhere;
+} /* end of rule */
+
+/* The title is focused when the dialog opens, so the top is read first; it needs no ring because it is not a control. */
+.attention h2:focus {
+  /* No ring on the title. */
+  outline: none;
+} /* end of rule */
diff --git a/web/attention.js b/web/attention.js
new file mode 100644
index 0000000..4574b0d
--- /dev/null
+++ b/web/attention.js
@@ -0,0 +1,12 @@
+// Problem dialog: when the System check found something to fix, the page contains a dialog; this script opens it as a modal window. It sends nothing anywhere. Closing needs no script: the OK button is a form of method "dialog".
+(function () {
+  // Find the dialog; the page has it only when there is a problem.
+  var d = document.getElementById('attention');
+  // Nothing to do without the dialog, or in a browser that cannot open one.
+  if (!d || typeof d.showModal !== 'function' || d.open) {
+    // Stop here.
+    return;
+  }
+  // Open it as a modal window: the page behind is blocked until OK, the focus stays inside, and Escape closes it.
+  d.showModal();
+})();
diff --git a/web/systemcheck.html b/web/systemcheck.html
index 9a0e0b9..f97cb24 100644
--- a/web/systemcheck.html
+++ b/web/systemcheck.html
@@ -72,6 +72,26 @@
 {{/* Uninstall: only goes to the confirmation page; nothing is removed yet. */}}
 <span class="tipbox"><a class="btn-solid btn-danger" href="/uninstall" aria-describedby="tipuninstall">Uninstall this tool</a><span class="tip" role="tooltip" id="tipuninstall">Removes the desktop icon and this program&rsquo;s saved settings, results and history, after you confirm. Your Ollama and its models are not touched. You then delete the program file yourself.</span></span>
 </div>
+{{/* The problem dialog: present only when something needs fixing. The script opens it as a modal window; OK closes it with no script, because the button is a form of method dialog. The report above stays on the page. */}}
+{{if .Problems}}
+<dialog id="attention" class="attention" role="alertdialog" aria-labelledby="attentiontitle" aria-describedby="attentionintro">
+<form method="dialog">
+<h2 id="attentiontitle" tabindex="-1" autofocus><span aria-hidden="true">&#9888;</span> Please fix {{if eq (len .Problems) 1}}this problem{{else}}these problems{{end}}</h2>
+<p id="attentionintro">The System check found something that stops this tool from working fully. The steps below come from the vendors&rsquo; own pages. This report stays on the screen after you press OK.</p>
+{{range .Problems}}
+<section class="attprob">
+<h3>{{.Title}}</h3>
+<p>{{.Why}}</p>
+{{if .Steps}}<ol>{{range .Steps}}<li>{{.Text}}{{if .Cmd}}<br><code>{{.Cmd}}</code>{{end}}</li>{{end}}</ol>{{end}}
+{{if .NoFix}}<p><strong>{{.NoFix}}</strong></p>{{end}}
+{{if .Links}}<p class="muted">Official pages:</p><ul>{{range .Links}}<li>{{.Text}}: <a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.URL}}</a></li>{{end}}</ul>{{end}}
+</section>
+{{end}}
+<div class="choices"><button type="submit" class="btn-solid">OK</button></div>
+</form>
+</dialog>
+<script src="/attention.js" defer></script>
+{{end}}
 {{/* Version 2: the uninstall question. */}}
 {{else if eq .Kind "uninstall"}}
 <h1>Uninstall OllamaControlCenter</h1>
OCC_PATCH_84C_END

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
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
done
pass "the four changed files and the three new files have the expected sha256"

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
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter . || fail "go build failed"
# Report it.
pass "build for this computer: bin/OllamaControlCenter"

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
echo "NEXT  start the monitor and open http://127.0.0.1:8765/systemcheck (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
