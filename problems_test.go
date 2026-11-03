// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the packages this file uses.
	// net/http gives the status codes.
	"net/http"
	// strings checks the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time gives the check timeout.
	"time"
) // end of imports

// okEnv is an environment view with no complaint.
var okEnv = envView{OllamaVerdict: finding{"ok", "fine"}, GoVerdict: finding{"ok", "fine"}, SystemVerdict: finding{"ok", "fine"}}

// TestCollectProblems checks which situations are problems and which are not.
func TestCollectProblems(t *testing.T) {
	// A card with a good driver.
	good := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.9", Driver: "580.1"}}})
	// Cases: what goes in, how many problems, and a word the first title must contain.
	cases := []struct {
		name     string
		online   bool
		env      envView
		findings []finding
		want     int
		title    string
	}{
		{"everything fine", true, okEnv, good, 0, ""},
		{"Ollama offline", false, okEnv, good, 1, "not found"},
		{"old Ollama", true, envView{OllamaVerdict: finding{"warn", "old"}}, good, 1, "Ollama version"},
		{"info lines are no problem", true, envView{OllamaVerdict: finding{"info", "newer"}}, []finding{{"info", "x"}}, 0, ""},
		{"old driver", true, okEnv, judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.6", Driver: "500.1"}}})[:1], 1, "driver"},
		{"old card", true, okEnv, judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "3.5", Driver: "580.1"}}})[:1], 1, "too old"},
		{"no card", true, okEnv, judgeReport(hostReport{}), 1, "No supported graphics card"},
		{"offline and old driver", false, okEnv, judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.6", Driver: "500.1"}}})[:1], 2, "not found"},
	}
	// Run each case.
	for _, c := range cases {
		// One sub-test per case.
		t.Run(c.name, func(t *testing.T) {
			// Ask.
			got := collectProblems(c.online, "http://127.0.0.1:11434", "linux", c.env, c.findings)
			// The count.
			if len(got) != c.want {
				// Report it.
				t.Fatalf("got %d problems, want %d: %+v", len(got), c.want, got)
			} // end of the count check
			// The title.
			if c.want > 0 && !strings.Contains(got[0].Title, c.title) {
				// Report it.
				t.Errorf("first title %q lacks %q", got[0].Title, c.title)
			} // end of the title check
			// Every problem is complete: a reason, and steps or an honest "no fix", and official links.
			for _, p := range got {
				// A reason.
				if p.Why == "" || (len(p.Steps) == 0 && p.NoFix == "") || len(p.Links) == 0 {
					// Report it.
					t.Errorf("incomplete problem: %+v", p)
				} // end of the completeness check
				// Every link is an https address.
				for _, l := range p.Links {
					// Check the start.
					if !strings.HasPrefix(l.URL, "https://") || l.Text == "" {
						// Report it.
						t.Errorf("bad link %+v", l)
					} // end of the link check
				} // end of the link loop
			} // end of the problem loop
		})
	} // end of the case loop
} // end of TestCollectProblems

// TestUpdateStepsFitTheSystem checks that the update steps match the operating system, as the Ollama FAQ describes them.
func TestUpdateStepsFitTheSystem(t *testing.T) {
	// A warning about the version.
	env := envView{OllamaVerdict: finding{"warn", "old"}}
	// For each system, a word the first step must contain.
	for goos, word := range map[string]string{"linux": "install.sh", "windows": "Restart to update", "darwin": "Restart to update"} {
		// Ask.
		got := collectProblems(true, "x", goos, env, nil)
		// One problem.
		if len(got) != 1 {
			// Report it.
			t.Fatalf("%s: got %d problems", goos, len(got))
		} // end of the count check
		// The first step.
		if s := got[0].Steps[0]; !strings.Contains(s.Text+s.Cmd, word) {
			// Report it.
			t.Errorf("%s: first step %+v lacks %q", goos, s, word)
		} // end of the step check
	} // end of the system loop
} // end of TestUpdateStepsFitTheSystem

// TestPhrasesMatchTheVerdicts keeps the recognised phrases in step with the sentences judgeReport really writes.
func TestPhrasesMatchTheVerdicts(t *testing.T) {
	// The three warnings.
	old := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "8.6", Driver: "500.1"}}})[0].Text
	// Too old a card.
	card := judgeReport(hostReport{GPUs: []gpuInfo{{Vendor: "nvidia", Name: "A", Compute: "3.5", Driver: "580.1"}}})[0].Text
	// No card.
	none := judgeReport(hostReport{})[0].Text
	// Check each.
	if !strings.Contains(old, phraseOldDriver) || !strings.Contains(card, phraseOldCard) || !strings.HasPrefix(none, phraseNoCard) {
		// Report it.
		t.Errorf("a phrase no longer matches:\n%q\n%q\n%q", old, card, none)
	} // end of the check
} // end of TestPhrasesMatchTheVerdicts

// TestDialogOnThePage checks the real page: with a problem it has the dialog, the script and the matching policy; without one it has none of them.
func TestDialogOnThePage(t *testing.T) {
	// Fixed Go version so the Go line is calm.
	old := goVersionNow
	// Put it back.
	t.Cleanup(func() { goVersionNow = old })
	// The tested version.
	goVersionNow = func() string { return "go" + testedGo }
	// A rig with no graphics card, so the page has a problem.
	r := newSysRig(t, false, false)
	// A good Ollama.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"`+minimumOllama+`"}`))
	// The handler.
	h := newWebHandlerWith(mustResolve(t, srv.URL), time.Second, r.mon)
	// The page.
	code, hdr, body := get(t, h, http.MethodGet, "/systemcheck")
	// It opens.
	if code != http.StatusOK {
		// Stop.
		t.Fatalf("status = %d", code)
	} // end of the status check
	// The dialog, its script and the policy that allows only that script.
	for _, want := range []string{`<dialog id="attention"`, `role="alertdialog"`, `method="dialog"`, `<script src="/attention.js" defer></script>`, "No supported graphics card was confirmed", "https://docs.ollama.com/gpu"} {
		// Check each.
		if !strings.Contains(body, want) {
			// Report it.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The policy.
	if csp := hdr.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe") {
		// Report it.
		t.Errorf("policy = %q", csp)
	} // end of the policy check
	// The script itself is served.
	if c, _, js := get(t, h, http.MethodGet, "/attention.js"); c != http.StatusOK || !strings.Contains(js, "showModal") {
		// Report it.
		t.Errorf("attention.js: %d", c)
	} // end of the script check
	// The report content stays on the page next to the dialog.
	if !strings.Contains(body, "What this tool needs") {
		// Report it.
		t.Error("the report content is gone")
	} // end of the report check
	// Now a computer with a good NVIDIA card: no problem, so no dialog and the strict policy.
	fakeProbes(t, map[string]string{"nvidia-smi": "NVIDIA GB10, [N/A], 580.95.05, 12.1\n"})
	// A fresh handler, so the hardware report is made again.
	h2 := newWebHandlerWith(mustResolve(t, srv.URL), time.Second, r.mon)
	// The page.
	_, hdr2, body2 := get(t, h2, http.MethodGet, "/systemcheck")
	// No dialog, no script.
	if strings.Contains(body2, "<dialog") || strings.Contains(body2, "<script") || strings.Contains(hdr2.Get("Content-Security-Policy"), "script-src") {
		// Report it.
		t.Errorf("a good computer must get no dialog:\n%s", body2)
	} // end of the check
} // end of TestDialogOnThePage
