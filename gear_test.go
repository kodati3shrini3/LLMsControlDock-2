// Package main tells Go that this test file belongs to the same program as gear.go.
package main

import ( // import lists the packages this test file uses.
	// encoding/json reads the create request the fake receives.
	"encoding/json"
	// fmt builds text.
	"fmt"
	// io reads request bodies in the fake Ollama.
	"io"
	// net/http provides requests and status codes.
	"net/http"
	// net/url builds form data.
	"net/url"
	// regexp finds the token in the page.
	"regexp"
	// strings searches the page text.
	"strings"
	// sync protects the fake's records and runs the double-click test.
	"sync"
	// testing is Go's built-in test framework.
	"testing"
	// time makes the fake's create slow.
	"time"
) // end of imports

// gearFake is a fake Ollama with two installed models and a saved-parameters text that /api/create changes like the real one did in the experiment (it replaces num_ctx and keeps every other line).
type gearFake struct {
	// mu protects every field below.
	mu sync.Mutex
	// params is the saved parameters text of every installed model (one shared text keeps the tests short).
	params string
	// modelInfo is the model_info JSON of every installed model.
	modelInfo string
	// loaded lists the names /api/ps reports.
	loaded []string
	// createStatus is the status /api/create answers (0 means 200).
	createStatus int
	// createMsg is the error text sent with a refusal.
	createMsg string
	// ignoreCreate makes /api/create answer 200 without changing anything.
	ignoreCreate bool
	// dropOthers makes /api/create answer 200 but also remove every other saved parameter.
	dropOthers bool
	// creates records every /api/create body.
	creates []string
	// calls records every other POST as "path body".
	calls []string
	// createDelay makes /api/create slow, with the fake's lock released meanwhile, so other requests can slip in (like real life).
	createDelay time.Duration
} // end of gearFake

// newGearFake builds a fake whose model supports 131072 tokens and has one saved stop word.
func newGearFake() *gearFake {
	// The values.
	return &gearFake{
		// A stop word, formatted the way Ollama prints it (name, spaces, value).
		params: "stop                           \"<end_of_turn>\"",
		// The model's own facts: architecture and its limit, plus a long list that must not matter.
		modelInfo: `{"general.architecture":"gemma3","gemma3.context_length":131072,"tokenizer.ggml.tokens":["a","b","c"]}`,
	} // end of the values
} // end of newGearFake

// start runs the fake as a server and returns it.
func (f *gearFake) start(t *testing.T) string {
	// Mark this as a helper.
	t.Helper()
	// Start the server.
	srv := fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
		// One request at a time.
		f.mu.Lock()
		// Release when this request is done.
		defer f.mu.Unlock()
		// Read the body, if any.
		b, _ := io.ReadAll(r.Body)
		// Pick the reply by path.
		switch r.URL.Path {
		// The version check.
		case "/api/version":
			// A valid version.
			w.Write([]byte(`{"version":"0.34.4"}`))
		// The installed list: two models.
		case "/api/tags":
			// Two models.
			w.Write([]byte(`{"models":[{"name":"alpha:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"embed:1b","size":2000000000,"details":{"family":"bert"},"capabilities":["embedding"]}]}`))
		// The loaded list.
		case "/api/ps":
			// Build the list from the fake's state.
			parts := []string{}
			// Every loaded name.
			for _, n := range f.loaded {
				// One entry.
				parts = append(parts, `{"name":"`+n+`","size":5,"expires_at":"2999-01-01T00:00:00Z"}`)
			} // end of the loop
			// Send the list.
			w.Write([]byte(`{"models":[` + strings.Join(parts, ",") + `]}`))
		// The details of one model.
		case "/api/show":
			// Read the name.
			var req struct {
				// Model is the asked name.
				Model string `json:"model"`
			} // end of the request shape
			// Decode it.
			_ = json.Unmarshal(b, &req)
			// Only the two installed models are known.
			if req.Model != "alpha:1b" && req.Model != "embed:1b" {
				// Not found, like the real one.
				w.WriteHeader(http.StatusNotFound)
				// The error text.
				w.Write([]byte(`{"error":"model not found"}`))
				// Stop here.
				return
			} // end of the unknown check
			// The reply, with the parameters as one string.
			out, _ := json.Marshal(map[string]any{"parameters": f.params, "model_info": json.RawMessage(f.modelInfo)})
			// Send it.
			w.Write(out)
		// The create request.
		case "/api/create":
			// Record it.
			f.creates = append(f.creates, string(b))
			// A slow create: let other requests in while it works.
			if f.createDelay > 0 {
				// Release the lock.
				f.mu.Unlock()
				// Work for a while.
				time.Sleep(f.createDelay)
				// Take the lock back, because the deferred unlock expects it.
				f.mu.Lock()
			} // end of the delay
			// A refusal.
			if f.createStatus != 0 {
				// The status.
				w.WriteHeader(f.createStatus)
				// The error text.
				w.Write([]byte(`{"error":` + fmt.Sprintf("%q", f.createMsg) + `}`))
				// Stop here.
				return
			} // end of the refusal
			// Accepted but without effect.
			if f.ignoreCreate {
				// Say success.
				w.Write([]byte(`{"status":"success"}`))
				// Stop here.
				return
			} // end of the ignore case
			// Read the wanted size.
			var req struct {
				// Parameters holds the wanted values.
				Parameters map[string]float64 `json:"parameters"`
			} // end of the request shape
			// Decode it.
			_ = json.Unmarshal(b, &req)
			// Keep the other lines (unless the test wants them dropped) and put the new size on top, like the real one did.
			var lines []string
			// The new size first.
			lines = append(lines, fmt.Sprintf("num_ctx                        %d", int64(req.Parameters["num_ctx"])))
			// Keep every other line.
			if !f.dropOthers {
				// Go through the old lines.
				for _, l := range strings.Split(f.params, "\n") {
					// Skip the old size line and blank lines.
					if strings.TrimSpace(l) != "" && !strings.HasPrefix(strings.TrimSpace(l), "num_ctx") {
						// Keep it.
						lines = append(lines, l)
					} // end of the skip check
				} // end of the line loop
			} // end of the keep case
			// Store the new text.
			f.params = strings.Join(lines, "\n")
			// Say success.
			w.Write([]byte(`{"status":"success"}`))
		// Anything else is a load or unload request or unknown.
		default:
			// Record it.
			f.calls = append(f.calls, r.URL.Path+" "+string(b))
			// Accept.
			w.Write([]byte(`{}`))
		} // end of the switch
	}) // end of the server
	// Hand the address back.
	return srv.URL
} // end of start

// createCount says how many create requests the fake has received.
func (f *gearFake) createCount() int {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The number.
	return len(f.creates)
} // end of createCount

// setLoaded changes what /api/ps reports.
func (f *gearFake) setLoaded(names ...string) {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// Store the list.
	f.loaded = names
} // end of setLoaded

// gearRig builds a handler on top of the fake and finds the page token.
func gearRig(t *testing.T, f *gearFake) themeRig {
	// Mark this as a helper.
	t.Helper()
	// Start the fake.
	h := handlerFor(t, f.start(t))
	// Fetch the main page.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the first hidden token field.
	m := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)
	// The page must carry a token.
	if m == nil {
		// Stop the test.
		t.Fatalf("no token found in the page")
	} // end of the token check
	// Hand back the pair.
	return themeRig{h: h, token: m[1]}
} // end of gearRig

// gearPost sends a form to one of the three settings routes as the page's own form would.
func gearPost(t *testing.T, rig themeRig, path, model, size string) (int, string, http.Header) {
	// Mark this as a helper.
	t.Helper()
	// Send it.
	res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {model}, "num_ctx": {size}}, fromThisPage)
	// Hand back status, body and headers.
	return res.StatusCode, bodyOf(res), res.Header
} // end of gearPost

// TestParseParams checks the parameters text is split into names and values, the way Ollama prints it.
func TestParseParams(t *testing.T) {
	// The real format: the name, many spaces, the value; blank lines appear too.
	got := parseParams("num_ctx                        8192\n\nstop                           \"<end_of_turn>\"\nstop   \"<eos>\"\n")
	// The expected pairs.
	want := []paramLine{{"num_ctx", "8192"}, {"stop", "\"<end_of_turn>\""}, {"stop", "\"<eos>\""}}
	// Compare the length and each pair.
	if len(got) != len(want) {
		// Report the difference.
		t.Fatalf("got %v", got)
	} // end of the length check
	// Go through the pairs.
	for i := range want {
		// A difference.
		if got[i] != want[i] {
			// Report it.
			t.Errorf("pair %d = %v, want %v", i, got[i], want[i])
		} // end of the compare
	} // end of the loop
	// An empty text gives nothing.
	if n := len(parseParams("")); n != 0 {
		// Report the problem.
		t.Errorf("empty text gave %d pairs", n)
	} // end of the empty check
} // end of TestParseParams

// TestSavedContext checks the saved size is read from every format Ollama was seen to print.
func TestSavedContext(t *testing.T) {
	// The cases: text, then the expected text, number and presence.
	cases := []struct {
		// name for the report.
		name string
		// in is the parameters text.
		in string
		// text is the expected value text.
		text string
		// n is the expected number.
		n int64
		// present is the expected presence.
		present bool
	}{
		// Nothing saved.
		{"none", "stop \"x\"", "", 0, false},
		// A plain number.
		{"plain", "num_ctx   8192", "8192", 8192, true},
		// Ollama printed a big number like this in the experiment.
		{"exponent", "num_ctx   1e+08", "1e+08", 100000000, true},
		// Text instead of a number.
		{"garbage", "num_ctx   lots", "lots", 0, true},
		// A decimal is not a size.
		{"decimal", "num_ctx   8192.5", "8192.5", 0, true},
		// Zero is not a size.
		{"zero", "num_ctx   0", "0", 0, true},
		// The last line wins.
		{"twice", "num_ctx 4096\nnum_ctx 8192", "8192", 8192, true},
	} // end of the case table
	// Go through the cases.
	for _, c := range cases {
		// Read it.
		text, n, present := savedContext(parseParams(c.in))
		// Compare.
		if text != c.text || n != c.n || present != c.present {
			// Report the difference.
			t.Errorf("%s: got (%q, %d, %v), want (%q, %d, %v)", c.name, text, n, present, c.text, c.n, c.present)
		} // end of the compare
	} // end of the case loop
} // end of TestSavedContext

// TestModelMaxContext checks the model maximum is read from the architecture key, or from a single other key, and never guessed.
func TestModelMaxContext(t *testing.T) {
	// A helper that builds the map from JSON.
	build := func(s string) map[string]json.RawMessage {
		// Decode.
		var m map[string]json.RawMessage
		// A test bug if it fails.
		if err := json.Unmarshal([]byte(s), &m); err != nil {
			// Stop.
			t.Fatalf("bad test json: %v", err)
		} // end of the check
		// Hand back.
		return m
	} // end of build
	// The cases.
	cases := []struct {
		// name for the report.
		name string
		// in is the model_info JSON.
		in string
		// n is the expected number.
		n int64
		// ok is the expected success.
		ok bool
	}{
		// The normal case.
		{"architecture key", `{"general.architecture":"gemma3","gemma3.context_length":131072}`, 131072, true},
		// No architecture, one key.
		{"single key", `{"bert.context_length":512}`, 512, true},
		// Two different keys and no architecture: do not guess.
		{"two keys", `{"a.context_length":1000,"b.context_length":2000}`, 0, false},
		// Nothing.
		{"empty", `{}`, 0, false},
		// Not a number.
		{"text", `{"general.architecture":"x","x.context_length":"big"}`, 0, false},
		// A decimal.
		{"decimal", `{"general.architecture":"x","x.context_length":1.5}`, 0, false},
		// Zero.
		{"zero", `{"general.architecture":"x","x.context_length":0}`, 0, false},
	} // end of the case table
	// Go through the cases.
	for _, c := range cases {
		// Read it.
		n, ok := modelMaxContext(build(c.in))
		// Compare.
		if n != c.n || ok != c.ok {
			// Report the difference.
			t.Errorf("%s: got (%d, %v), want (%d, %v)", c.name, n, ok, c.n, c.ok)
		} // end of the compare
	} // end of the case loop
	// A missing map is the same as an empty one.
	if _, ok := modelMaxContext(nil); ok {
		// Report the problem.
		t.Errorf("a missing model_info gave a maximum")
	} // end of the nil check
} // end of TestModelMaxContext

// TestValidateContext checks every rule for the typed size, including the ones that keep a saved value from being emptied.
func TestValidateContext(t *testing.T) {
	// The cases: typed text and whether it is accepted.
	cases := []struct {
		// in is what was typed.
		in string
		// n is the expected number when accepted.
		n int64
		// ok says whether it is accepted.
		ok bool
	}{
		// The smallest and the largest allowed values, and normal ones.
		{"512", 512, true}, {"8192", 8192, true}, {"131072", 131072, true}, {"  8192  ", 8192, true}, {"0008192", 8192, true},
		// Empty and blank: never allowed.
		{"", 0, false}, {"   ", 0, false},
		// Outside the range.
		{"511", 0, false}, {"131073", 0, false}, {"0", 0, false},
		// Not a plain whole number.
		{"-8192", 0, false}, {"+8192", 0, false}, {"8192.0", 0, false}, {"8,192", 0, false}, {"1e4", 0, false}, {"0x2000", 0, false}, {"abc", 0, false}, {"８１９２", 0, false}, {"٨١٩٢", 0, false}, {"8 192", 0, false},
		// Far too long.
		{"99999999999999999999", 0, false}, {strings.Repeat("9", 400), 0, false},
		// Markup.
		{"<script>alert(1)</script>", 0, false},
	} // end of the case table
	// Go through the cases.
	for _, c := range cases {
		// Check it against a model that supports 131072.
		n, problem := validateContext(c.in, minContext, 131072)
		// Compare.
		if (problem == "") != c.ok || n != c.n {
			// Report the difference (the input is cut so a long one does not flood the report).
			in := c.in
			// Cut it.
			if len(in) > 30 {
				// Keep the start.
				in = in[:30]
			} // end of the cut
			// Report.
			t.Errorf("%q: got (%d, %q), want ok=%v n=%d", in, n, problem, c.ok, c.n)
		} // end of the compare
	} // end of the case loop
} // end of TestValidateContext

// TestContextPresets checks the suggestions stay inside the range, in order, and always include the maximum.
func TestContextPresets(t *testing.T) {
	// A model that supports 131072: the powers of two up to it.
	got := contextPresets(512, 131072)
	// The expected list.
	want := []int64{2048, 4096, 8192, 16384, 32768, 65536, 131072}
	// Compare.
	if fmt.Sprint(got) != fmt.Sprint(want) {
		// Report the difference.
		t.Errorf("got %v, want %v", got, want)
	} // end of the compare
	// A model whose maximum is not a power of two: the maximum is added at the end.
	got = contextPresets(512, 40960)
	// The expected list.
	want = []int64{2048, 4096, 8192, 16384, 32768, 40960}
	// Compare.
	if fmt.Sprint(got) != fmt.Sprint(want) {
		// Report the difference.
		t.Errorf("got %v, want %v", got, want)
	} // end of the compare
	// A small embedding model: only its maximum.
	got = contextPresets(512, 512)
	// Compare.
	if fmt.Sprint(got) != "[512]" {
		// Report the difference.
		t.Errorf("got %v", got)
	} // end of the compare
} // end of TestContextPresets

// TestGearShowsSettings checks the settings page: the facts, the form with its limits and suggestions, the help bubbles, no script, and nothing changed.
func TestGearShowsSettings(t *testing.T) {
	// A fake with no saved size.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// Open the settings of the first model.
	status, body, header := gearPost(t, rig, "/gear", "alpha:1b", "")
	// It must load.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d", status)
	} // end of the status check
	// Everything the page must say.
	for _, want := range []string{
		// The heading names the model.
		"Settings for <code>alpha:1b</code>",
		// Nothing is saved yet.
		"not saved in the model",
		// The model's own limit.
		"131072 tokens",
		// The smallest allowed value.
		"512 tokens",
		// The other saved setting is shown, and escaped.
		"stop &#34;&lt;end_of_turn&gt;&#34;",
		// The form goes to the review step.
		`action="/gear/review"`,
		// The field has the limits and cannot be left empty.
		`min="512" max="131072" step="1" required`,
		// The suggestions.
		`<option value="8192">`,
		// The rule about removing.
		"cannot be removed, only changed",
		// The five help bubbles, each with the three standard parts.
		`aria-describedby="tip-gear-ctx"`, `aria-describedby="tip-gear-max"`, `aria-describedby="tip-gear-min"`, `aria-describedby="tip-gear-saved"`, `aria-describedby="tip-gear-other"`,
		"In plain words:", "Example:", "Helps you decide:",
	} { // end of the list
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// No script and the strict policy.
	if strings.Contains(body, "<script") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
		// Report the problem.
		t.Errorf("the settings page allows or contains a script")
	} // end of the script check
	// Opening the page changes nothing.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("opening the page sent a create request")
	} // end of the change check
} // end of TestGearShowsSettings

// TestGearPrefillsSavedValue checks the field starts with the saved size, so it is never blank.
func TestGearPrefillsSavedValue(t *testing.T) {
	// A fake with 4096 saved.
	f := newGearFake()
	// The saved text.
	f.params = "num_ctx                        4096\n" + f.params
	// Build the rig.
	rig := gearRig(t, f)
	// Open the settings.
	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
	// The field value and the facts.
	if !strings.Contains(body, `required value="4096"`) || !strings.Contains(body, "<td>4096</td>") {
		// Report the gap.
		t.Errorf("the saved value is not shown or pre-filled")
	} // end of the check
} // end of TestGearPrefillsSavedValue

// TestGearRefusesLoadedModel checks a loaded model gets no form on any of the three steps, and nothing is saved.
func TestGearRefusesLoadedModel(t *testing.T) {
	// A fake with the model loaded.
	f := newGearFake()
	// Mark it loaded.
	f.loaded = []string{"alpha:1b"}
	// Build the rig.
	rig := gearRig(t, f)
	// All three steps.
	for _, path := range []string{"/gear", "/gear/review", "/gear/save"} {
		// Send a valid size.
		status, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
		// The page explains and offers no form.
		if status != http.StatusOK || !strings.Contains(body, "Unload it first") || strings.Contains(body, `action="/gear/`) {
			// Report the problem.
			t.Errorf("%s: status %d, body %q", path, status, body)
		} // end of the check
	} // end of the loop
	// Nothing was saved.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("a loaded model was changed")
	} // end of the change check
} // end of TestGearRefusesLoadedModel

// TestGearNotInstalled checks an unknown model name is refused politely and nothing is sent to Ollama.
func TestGearNotInstalled(t *testing.T) {
	// A fake.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// All three steps with a made-up name.
	for _, path := range []string{"/gear", "/gear/review", "/gear/save"} {
		// Send it.
		_, body, _ := gearPost(t, rig, path, "ghost:1b", "8192")
		// The page says so.
		if !strings.Contains(body, "not installed") {
			// Report the problem.
			t.Errorf("%s: %q", path, body)
		} // end of the check
	} // end of the loop
	// Nothing was saved.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("an unknown model was changed")
	} // end of the change check
} // end of TestGearNotInstalled

// TestGearRejectsBadValues checks every bad value is refused on the review step and on the save step, shown back escaped, and never reaches Ollama.
func TestGearRejectsBadValues(t *testing.T) {
	// A fake with 4096 saved, so "emptying" would mean losing something.
	f := newGearFake()
	// The saved text.
	f.params = "num_ctx                        4096\n" + f.params
	// Build the rig.
	rig := gearRig(t, f)
	// The bad values.
	for _, bad := range []string{"", "   ", "abc", "-5", "0", "511", "131073", "8192.5", "1e5", "+8192", "８１９２", "99999999999999999999", "<script>alert(1)</script>"} {
		// Both steps.
		for _, path := range []string{"/gear/review", "/gear/save"} {
			// Send it.
			status, body, _ := gearPost(t, rig, path, "alpha:1b", bad)
			// The settings page comes back with the reason, and no confirm button.
			if status != http.StatusOK || !strings.Contains(body, "Not saved.") || strings.Contains(body, "Yes, save it into the model") {
				// Report the problem.
				t.Errorf("%s %q: status %d", path, bad, status)
			} // end of the check
			// An empty value gets its own, clear reason.
			if strings.TrimSpace(bad) == "" && !strings.Contains(body, "cannot be empty") {
				// Report the problem.
				t.Errorf("%s %q: no 'cannot be empty' reason", path, bad)
			} // end of the empty check
			// Markup must come back escaped.
			if strings.Contains(body, "<script>alert") {
				// Report the problem.
				t.Errorf("%s: unescaped markup in the page", path)
			} // end of the escape check
		} // end of the path loop
	} // end of the value loop
	// Nothing reached Ollama.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("a bad value was sent to Ollama")
	} // end of the change check
	// The saved value is untouched.
	if _, n, _ := savedContext(parseParams(f.params)); n != 4096 {
		// Report the problem.
		t.Errorf("the saved size changed to %d", n)
	} // end of the saved check
} // end of TestGearRejectsBadValues

// TestGearReviewThenSave checks the two-step flow: the review changes nothing, the save sends exactly one precise create request and then verifies.
func TestGearReviewThenSave(t *testing.T) {
	// A fake with no saved size.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// Step 2: review.
	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "8192")
	// The confirmation page with the values to be saved.
	for _, want := range []string{"This changes the model itself", "not saved in the model", "<strong>8192</strong>", `action="/gear/save"`, `name="num_ctx" value="8192"`, "Yes, save it into the model", "Cancel, do not change"} {
		// Look for it.
		if status != http.StatusOK || !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("review page lacks %q (status %d)", want, status)
		} // end of the check
	} // end of the loop
	// The review changed nothing.
	if f.createCount() != 0 {
		// Report the problem.
		t.Fatalf("the review step sent a create request")
	} // end of the review check
	// Step 3: save.
	status, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
	// The result page.
	if status != http.StatusOK || !strings.Contains(body, "<strong>Saved.</strong>") || !strings.Contains(body, "8192") {
		// Report the problem.
		t.Errorf("save page: status %d, body %q", status, body)
	} // end of the result check
	// Exactly one create request, with exactly the expected body (keys are sorted by Go's JSON writer).
	if len(f.creates) != 1 || f.creates[0] != `{"from":"alpha:1b","model":"alpha:1b","parameters":{"num_ctx":8192},"stream":false}` {
		// Report the problem.
		t.Errorf("create requests: %v", f.creates)
	} // end of the create check
	// The other saved parameter is still there.
	if !strings.Contains(f.params, "end_of_turn") {
		// Report the problem.
		t.Errorf("the stop word was lost: %q", f.params)
	} // end of the other-parameter check
} // end of TestGearReviewThenSave

// TestGearSameValueChangesNothing checks that saving the value that is already saved sends nothing (this is also what a second click on Yes does).
func TestGearSameValueChangesNothing(t *testing.T) {
	// A fake with 8192 saved.
	f := newGearFake()
	// The saved text.
	f.params = "num_ctx                        8192\n" + f.params
	// Build the rig.
	rig := gearRig(t, f)
	// Both steps.
	for _, path := range []string{"/gear/review", "/gear/save"} {
		// Send the same value.
		_, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
		// The page says nothing changes.
		if !strings.Contains(body, "Nothing to change") {
			// Report the problem.
			t.Errorf("%s: %q", path, body)
		} // end of the check
	} // end of the loop
	// Nothing was sent.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("an unchanged value was sent")
	} // end of the change check
} // end of TestGearSameValueChangesNothing

// TestGearVerifiesTheResult checks that a create which Ollama accepts but does not apply, or applies while dropping other settings, is reported honestly.
func TestGearVerifiesTheResult(t *testing.T) {
	// Two ways Ollama can misbehave.
	for _, mode := range []string{"ignore", "drop"} {
		// A fake.
		f := newGearFake()
		// Pick the misbehaviour.
		f.ignoreCreate, f.dropOthers = mode == "ignore", mode == "drop"
		// Build the rig.
		rig := gearRig(t, f)
		// Save a size.
		_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
		// The page must not claim success.
		if strings.Contains(body, "<strong>Saved.</strong>") || !strings.Contains(body, "Please check") {
			// Report the problem.
			t.Errorf("%s: %q", mode, body)
		} // end of the check
	} // end of the loop
} // end of TestGearVerifiesTheResult

// TestGearCreateRefused checks Ollama's refusal is shown in plain words, escaped.
func TestGearCreateRefused(t *testing.T) {
	// A fake that refuses.
	f := newGearFake()
	// The refusal.
	f.createStatus, f.createMsg = http.StatusInternalServerError, "disk <full>"
	// Build the rig.
	rig := gearRig(t, f)
	// Save a size.
	status, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
	// The page says what happened.
	if status != http.StatusBadGateway || !strings.Contains(body, "status 500") || !strings.Contains(body, "disk &lt;full&gt;") || strings.Contains(body, "<strong>Saved.</strong>") {
		// Report the problem.
		t.Errorf("status %d, body %q", status, body)
	} // end of the check
} // end of TestGearCreateRefused

// TestGearModelLoadedBetweenReviewAndSave checks the save step looks again: a model that was loaded in the meantime is not changed.
func TestGearModelLoadedBetweenReviewAndSave(t *testing.T) {
	// A fake.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// The review step is fine.
	if _, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "8192"); !strings.Contains(body, "Yes, save it into the model") {
		// Stop the test.
		t.Fatalf("no review page")
	} // end of the review check
	// Someone loads the model now.
	f.setLoaded("alpha:1b")
	// The save step.
	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
	// It must refuse.
	if !strings.Contains(body, "Unload it first") || f.createCount() != 0 {
		// Report the problem.
		t.Errorf("a model loaded in the meantime was changed")
	} // end of the check
} // end of TestGearModelLoadedBetweenReviewAndSave

// TestGearUnknownMaximum checks that without a known model maximum nothing can be saved, on any step.
func TestGearUnknownMaximum(t *testing.T) {
	// A fake whose model reports no limit.
	f := newGearFake()
	// No model facts.
	f.modelInfo = `{}`
	// Build the rig.
	rig := gearRig(t, f)
	// The settings page has no form.
	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
	// Check it.
	if strings.Contains(body, `action="/gear/review"`) || !strings.Contains(body, "does not report this model's maximum") {
		// Report the problem.
		t.Errorf("settings page: %q", body)
	} // end of the check
	// The other two steps refuse.
	for _, path := range []string{"/gear/review", "/gear/save"} {
		// Send a size.
		_, body, _ := gearPost(t, rig, path, "alpha:1b", "8192")
		// It must refuse.
		if !strings.Contains(body, "Not saved.") {
			// Report the problem.
			t.Errorf("%s: %q", path, body)
		} // end of the check
	} // end of the loop
	// Nothing was sent.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("a model without a known limit was changed")
	} // end of the change check
} // end of TestGearUnknownMaximum

// TestGearSavedAboveMaximum checks a saved size above the model's limit is pointed out and can be fixed by saving a valid one.
func TestGearSavedAboveMaximum(t *testing.T) {
	// A fake with a size far above the limit saved (the experiment showed Ollama accepts such a value).
	f := newGearFake()
	// The saved text, in the form Ollama printed.
	f.params = "num_ctx                        1e+08\n" + f.params
	// Build the rig.
	rig := gearRig(t, f)
	// The settings page.
	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b", "")
	// It warns, and the field is not pre-filled with a value that would be refused.
	if !strings.Contains(body, "above what this model supports") {
		// Report the problem.
		t.Errorf("no warning in %q", body)
	} // end of the warning check
	// Saving a valid size works.
	_, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
	// The result.
	if !strings.Contains(body, "<strong>Saved.</strong>") {
		// Report the problem.
		t.Errorf("fixing the value failed: %q", body)
	} // end of the result check
} // end of TestGearSavedAboveMaximum

// TestGearSecurity checks the three routes need a POST from this page with the right token, like every other changing route.
func TestGearSecurity(t *testing.T) {
	// A fake.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// Go through the routes.
	for _, path := range []string{"/gear", "/gear/review", "/gear/save"} {
		// A GET is not allowed.
		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
			// Report the problem.
			t.Errorf("GET %s = %d", path, status)
		} // end of the GET check
		// A POST from another site is refused.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
			// Report the problem.
			t.Errorf("cross-site %s = %d", path, res.StatusCode)
		} // end of the origin check
		// A POST without any browser header is refused.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, nil); res.StatusCode != http.StatusForbidden {
			// Report the problem.
			t.Errorf("headerless %s = %d", path, res.StatusCode)
		} // end of the headerless check
		// A POST with a wrong token is refused.
		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "model": {"alpha:1b"}, "num_ctx": {"8192"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
			// Report the problem.
			t.Errorf("wrong token %s = %d", path, res.StatusCode)
		} // end of the token check
		// A POST without a model name is refused.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "num_ctx": {"8192"}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
			// Report the problem.
			t.Errorf("no model %s = %d", path, res.StatusCode)
		} // end of the model check
	} // end of the route loop
	// Nothing was changed by any of it.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("a refused request changed the model")
	} // end of the change check
} // end of TestGearSecurity

// TestGearDoubleClickSavesOnce checks that many simultaneous saves of the same value send only one create request.
func TestGearDoubleClickSavesOnce(t *testing.T) {
	// A fake whose create is slow, so the clicks really overlap.
	f := newGearFake()
	// A slow create.
	f.createDelay = 40 * time.Millisecond
	// Build the rig.
	rig := gearRig(t, f)
	// Ten clicks at the same moment.
	var wg sync.WaitGroup
	// Start them.
	for i := 0; i < 10; i++ {
		// Count one.
		wg.Add(1)
		// Send it in its own goroutine.
		go func() {
			// Count it done at the end.
			defer wg.Done()
			// The same save.
			gearPost(t, rig, "/gear/save", "alpha:1b", "8192")
		}() // end of the goroutine
	} // end of the start loop
	// Wait for all of them.
	wg.Wait()
	// Exactly one create request.
	if n := f.createCount(); n != 1 {
		// Report the problem.
		t.Errorf("%d create requests, want 1", n)
	} // end of the count check
} // end of TestGearDoubleClickSavesOnce

// TestMainPageGearOnlyForNotLoaded checks the gear appears before the state words of a model that is not loaded, and an empty slot of the same width stands in for a loaded one.
func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
	// A fake with one model loaded.
	f := newGearFake()
	// Mark it loaded.
	f.loaded = []string{"alpha:1b"}
	// Build the rig.
	rig := gearRig(t, f)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// The not-loaded model has a gear form with an accessible name.
	for _, want := range []string{`action="/gear"`, `aria-label="Settings for embed:1b"`, `class="gear"`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The loaded model has none, and only one gear form exists.
	if strings.Contains(body, `aria-label="Settings for alpha:1b"`) || strings.Count(body, `action="/gear"`) != 1 {
		// Report the problem.
		t.Errorf("a loaded model has a gear")
	} // end of the loaded check
	// The loaded row has the empty slot.
	if strings.Count(body, `class="gearslot"`) != 1 {
		// Report the problem.
		t.Errorf("the loaded row has no empty gear slot")
	} // end of the slot check
	// The gear comes before the state words in its cell.
	if i, j := strings.Index(body, `class="gearform"`), strings.Index(body, `class="statelabel"`); !(i >= 0 && j >= 0 && i < strings.LastIndex(body, `class="statelabel"`)) {
		// Report the problem.
		t.Errorf("gear position: %d %d", i, j)
	} // end of the order check
	// The hint line explains the gear.
	if !strings.Contains(body, "appears only for models that are not loaded") {
		// Report the problem.
		t.Errorf("no hint about the gear")
	} // end of the hint check
} // end of TestMainPageGearOnlyForNotLoaded

// TestKeepAliveChoiceOnLoadPage checks the load page offers the fixed list with its help bubble, and the choice reaches Ollama exactly as chosen.
func TestKeepAliveChoiceOnLoadPage(t *testing.T) {
	// The cases: the form value, the fragment that must appear in the generate request (empty means no keep_alive at all).
	cases := []struct {
		// choice is the form value.
		choice string
		// want is the expected fragment.
		want string
	}{
		// Ollama's default: nothing is sent.
		{"", ""},
		// A time.
		{"1h", `"keep_alive":"1h"`},
		// Never unload: a negative number, not text.
		{"-1", `"keep_alive":-1`},
	} // end of the case table
	// Go through the cases.
	for _, c := range cases {
		// A fake with nothing loaded.
		f := &loadFake{}
		// Build the rig.
		rig := loadRig(t, f, 16e9)
		// The warning page has the drop-down and its bubble.
		res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
		// Read it.
		page := bodyOf(res)
		// The parts.
		for _, want := range []string{`name="keep" form="loadform"`, `<option value="">Ollama&#39;s default (5 minutes)</option>`, `<option value="-1">Until I unload it`, `aria-describedby="tip-keep"`, ">Keep-alive time<"} {
			// Look for it.
			if !strings.Contains(page, want) {
				// Report the gap.
				t.Errorf("load page lacks %q", want)
			} // end of the check
		} // end of the loop
		// Confirm with the choice.
		res = post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "keep": {c.choice}}, fromThisPage)
		// It must work.
		if res.StatusCode != http.StatusOK {
			// Report the problem.
			t.Errorf("choice %q: status %d", c.choice, res.StatusCode)
		} // end of the status check
		// One request, with or without the keep-alive.
		if len(f.calls) != 1 || (c.want == "") == strings.Contains(f.calls[0], "keep_alive") || !strings.Contains(f.calls[0], c.want) {
			// Report the problem.
			t.Errorf("choice %q: requests %v", c.choice, f.calls)
		} // end of the request check
	} // end of the case loop
} // end of TestKeepAliveChoiceOnLoadPage

// TestKeepAliveRejectsOtherValues checks anything outside the fixed list is refused before any model is touched.
func TestKeepAliveRejectsOtherValues(t *testing.T) {
	// A fake with nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Values that are not in the list.
	for _, bad := range []string{"abc", "0", "1", "5M", "99h", "-2", " 5m", "5m ", "forever", "1e3", "<b>"} {
		// Confirm with it.
		res := post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "keep": {bad}}, fromThisPage)
		// It must be refused.
		if res.StatusCode != http.StatusBadRequest {
			// Report the problem.
			t.Errorf("keep %q: status %d", bad, res.StatusCode)
		} // end of the status check
	} // end of the loop
	// Nothing was sent to Ollama.
	if f.callCount() != 0 {
		// Report the problem.
		t.Errorf("a refused choice reached Ollama")
	} // end of the request check
} // end of TestKeepAliveRejectsOtherValues

// TestKeepAliveReachesEmbeddingFallback checks the choice is also sent when the model has to be loaded through the embedding request.
func TestKeepAliveReachesEmbeddingFallback(t *testing.T) {
	// A fake whose generate refuses, like an embedding model.
	f := &loadFake{generateStatus: http.StatusBadRequest}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Confirm with a choice.
	post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"embed:1b"}, "keep": {"30m"}}, fromThisPage)
	// Two requests, and the second is the embedding one with the choice.
	if len(f.calls) != 2 || !strings.HasPrefix(f.calls[1], "/api/embed ") || !strings.Contains(f.calls[1], `"keep_alive":"30m"`) {
		// Report the problem.
		t.Errorf("requests: %v", f.calls)
	} // end of the check
} // end of TestKeepAliveReachesEmbeddingFallback
