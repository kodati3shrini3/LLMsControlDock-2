// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http gives the method and status names.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// regexp finds the buttons and their targets.
	"regexp"
	// strings searches the page and the script.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestCopyScriptIsServedAndHarmless checks that the script is sent as JavaScript, only on GET, and that it cannot send anything anywhere or run anything: it may only copy text that is already on the page.
func TestCopyScriptIsServedAndHarmless(t *testing.T) {
	// A rig.
	rig, _, _ := delRig(t)
	// Fetch the script.
	status, header, body := get(t, rig.h, http.MethodGet, "/copy.js")
	// Found and typed as JavaScript, with both ways of copying.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "navigator.clipboard") || !strings.Contains(body, "execCommand") {
		// Report it.
		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the check
	// Only GET is allowed.
	if res := post(t, rig.h, "/copy.js", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
		// Report it.
		t.Errorf("POST /copy.js = %d, want 405", res.StatusCode)
	} // end of the method check
	// Nothing that sends data away, runs text as code, writes markup or opens an address.
	for _, bad := range []string{"fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "eval(", "new Function", "innerHTML", "outerHTML", "document.write", "http://", "https://", "location", "import("} {
		// Present.
		if strings.Contains(body, bad) {
			// Report it.
			t.Errorf("the copy script must not contain %q", bad)
		} // end of the check
	} // end of the loop
	// Every code line carries a comment on the line above it or ends a block: no bare statement.
	lines := strings.Split(body, "\n")
	// Check from the second line.
	for i := 1; i < len(lines); i++ {
		// The trimmed line.
		l := strings.TrimSpace(lines[i])
		// Blank lines, comments, and lines that close or continue a block (they start with a closing brace) need nothing.
		if l == "" || strings.HasPrefix(l, "//") || strings.HasPrefix(l, "}") {
			// Fine.
			continue
		} // end of the skip check
		// The line above must be a comment.
		if prev := strings.TrimSpace(lines[i-1]); !strings.HasPrefix(prev, "//") && !strings.HasSuffix(strings.TrimSpace(lines[i]), "// ok") {
			// Allow the continuation of a statement that has a comment two lines up (a line inside a call).
			if i < 2 || !strings.HasPrefix(strings.TrimSpace(lines[i-2]), "//") {
				// Report it.
				t.Errorf("copy.js line %d has no comment above it: %q", i+1, l)
			} // end of the second check
		} // end of the comment check
	} // end of the line loop
} // end of TestCopyScriptIsServedAndHarmless

// TestRestorePageHasCopyButtons checks the restore page: a hidden Copy button for each of the five commands, each pointing at the element that holds that command, the script included once, and the security policy allowing scripts from this address only.
func TestRestorePageHasCopyButtons(t *testing.T) {
	// A rig with a deleted model that the library still has.
	rig, f, _ := delRig(t)
	// The library has the model.
	f.reg.setReg(manifestPath("alpha", "1b"), 200, "m-alpha")
	// Delete it.
	post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// The restore page.
	res := post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Its text.
	body := bodyOf(res)
	// Five buttons, each starting hidden.
	buttons := regexp.MustCompile(`<button type="button" class="copybtn" data-target="([a-z0-9-]+)" hidden aria-label="Copy command: [^"]+">`).FindAllStringSubmatch(body, -1)
	// Count.
	if len(buttons) != 5 {
		// Stop the test.
		t.Fatalf("%d copy buttons, want 5", len(buttons))
	} // end of the count check
	// Each target must be one element that holds the command it is meant for.
	want := map[string]string{
		// The direct command.
		"cmd-local": "ollama pull alpha:1b",
		// Docker.
		"cmd-docker": "docker exec &lt;container-name&gt; ollama pull alpha:1b",
		// Docker, finding the name.
		"cmd-docker-find": "docker ps",
		// Kubernetes.
		"cmd-k8s": "kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:1b",
		// Kubernetes, finding the pod.
		"cmd-k8s-find": "kubectl get pods -n &lt;namespace&gt;",
	} // end of the table
	// Go through the buttons.
	for _, b := range buttons {
		// The text the button must copy.
		text, ok := want[b[1]]
		// An unknown target.
		if !ok {
			// Report it.
			t.Errorf("unknown target %q", b[1])
			// Next.
			continue
		} // end of the target check
		// Exactly one element with that id, holding exactly that command.
		if strings.Count(body, `id="`+b[1]+`"`) != 1 || !strings.Contains(body, `<code id="`+b[1]+`">`+text+`</code>`) {
			// Report it.
			t.Errorf("target %s does not hold %q", b[1], text)
		} // end of the element check
		// Mark it as seen.
		delete(want, b[1])
	} // end of the loop
	// Every command had a button.
	if len(want) != 0 {
		// Report it.
		t.Errorf("commands without a button: %v", want)
	} // end of the coverage check
	// The script once, the status line for screen readers, and a policy that allows this address's scripts only.
	if strings.Count(body, `<script src="/copy.js" defer></script>`) != 1 || strings.Count(body, "<script") != 1 || !strings.Contains(body, `id="copystatus"`) {
		// Report it.
		t.Errorf("script or status line missing")
	} // end of the script check
	// The policy.
	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") || strings.Contains(csp, "unsafe-eval") {
		// Report it.
		t.Errorf("policy %q", csp)
	} // end of the policy check
	// A restore page with no command (the library lacks the model) has no button, no script and the strict policy.
	f.reg.setReg(manifestPath("alpha", "1b"), 404, "")
	// Ask again.
	res = post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// The text.
	body = bodyOf(res)
	// Nothing to copy.
	if strings.Contains(body, "copybtn") || strings.Contains(body, "<script") || strings.Contains(res.Header.Get("Content-Security-Policy"), "script-src") {
		// Report it.
		t.Errorf("a page without commands must carry no copy button, no script and the strict policy")
	} // end of the check
} // end of TestRestorePageHasCopyButtons
