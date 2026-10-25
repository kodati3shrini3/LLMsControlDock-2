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
	// sort puts the keys of a request in order.
	"sort"
	// strconv quotes text the way Ollama prints it.
	"strconv"
	// strings searches the page text.
	"strings"
	// sync protects the fake's records and runs the double-click test.
	"sync"
	// testing is Go's built-in test framework.
	"testing"
	// time makes the fake's create slow.
	"time"
) // end of imports

// gearFake is a fake Ollama with two installed models and saved parameters that /api/create changes like the real one did in the experiment: only the names sent change, and a new stop list replaces the old one.
type gearFake struct {
	// mu protects every field below.
	mu sync.Mutex
	// params is the saved parameters of every installed model (one shared set keeps the tests short), in print order.
	params []paramLine
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

// newGearFake builds a fake whose model supports 131072 tokens and has the settings a real gemma model has saved.
func newGearFake() *gearFake {
	// The values.
	return &gearFake{
		// Saved settings, formatted the way Ollama prints them.
		params: []paramLine{{"temperature", "1"}, {"top_k", "64"}, {"top_p", "0.95"}, {"stop", `"<end_of_turn>"`}},
		// The model's own facts: architecture and its limit, plus a long list that must not matter.
		modelInfo: `{"general.architecture":"gemma3","gemma3.context_length":131072,"tokenizer.ggml.tokens":["a","b","c"]}`,
	} // end of the values
} // end of newGearFake

// paramsText renders the saved parameters the way /api/show prints them.
func (f *gearFake) paramsText() string {
	// One line each: the name, spaces, the value.
	var lines []string
	// Go through the parameters.
	for _, p := range f.params {
		// Pad the name like Ollama does.
		lines = append(lines, fmt.Sprintf("%-31s%s", p.Name, p.Value))
	} // end of the loop
	// Join.
	return strings.Join(lines, "\n")
} // end of paramsText

// saved returns the printed values of one parameter.
func (f *gearFake) saved(name string) []string {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// Collect the values.
	var out []string
	// Go through the parameters.
	for _, p := range f.params {
		// A match.
		if p.Name == name {
			// Keep it.
			out = append(out, p.Value)
		} // end of the match check
	} // end of the loop
	// Hand back the list.
	return out
} // end of saved

// apply changes the saved parameters like the real Ollama: each name sent replaces every old line of that name and the rest stay.
func (f *gearFake) apply(body []byte) {
	// The body shape.
	var req struct {
		// Parameters holds the wanted values, left raw so numbers keep their text.
		Parameters map[string]json.RawMessage `json:"parameters"`
	} // end of the request shape
	// Decode it.
	_ = json.Unmarshal(body, &req)
	// Work in a stable order.
	keys := make([]string, 0, len(req.Parameters))
	// Collect the names.
	for k := range req.Parameters {
		// Add it.
		keys = append(keys, k)
	} // end of the collect
	// Sort.
	sort.Strings(keys)
	// Start from the old lines, or from nothing when the fake drops them.
	var out []paramLine
	// Keep the lines of names that were not sent.
	if !f.dropOthers {
		// Go through the old lines.
		for _, p := range f.params {
			// Not sent: keep.
			if _, sent := req.Parameters[p.Name]; !sent {
				// Keep it.
				out = append(out, p)
			} // end of the check
		} // end of the loop
	} // end of the keep case
	// Add the new values.
	for _, k := range keys {
		// A list becomes one quoted line per entry.
		var list []string
		// Try a list first.
		if err := json.Unmarshal(req.Parameters[k], &list); err == nil {
			// Each entry.
			for _, w := range list {
				// Quoted with Go's rules, like Ollama prints it.
				out = append(out, paramLine{k, strconv.Quote(w)})
			} // end of the entries
			// Next name.
			continue
		} // end of the list case
		// A number keeps its text.
		out = append(out, paramLine{k, string(req.Parameters[k])})
	} // end of the loop
	// Store the new set.
	f.params = out
} // end of apply

// start runs the fake as a server and returns its address.
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
			out, _ := json.Marshal(map[string]any{"parameters": f.paramsText(), "model_info": json.RawMessage(f.modelInfo)})
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
			if !f.ignoreCreate {
				// Change the saved parameters.
				f.apply(b)
			} // end of the effect
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

// gearPost sends a form to one of the three settings routes as the page's own form would; pairs are field name, value, field name, value, and so on (a name may repeat).
func gearPost(t *testing.T, rig themeRig, path, model string, pairs ...string) (int, string, http.Header) {
	// Mark this as a helper.
	t.Helper()
	// The form with the token and the model.
	form := url.Values{"token": {rig.token}, "model": {model}}
	// Add the pairs.
	for i := 0; i+1 < len(pairs); i += 2 {
		// Add one field.
		form.Add(pairs[i], pairs[i+1])
	} // end of the loop
	// Send it.
	res := post(t, rig.h, path, form, fromThisPage)
	// Hand back status, body and headers.
	return res.StatusCode, bodyOf(res), res.Header
} // end of gearPost

// TestSettingSpecsAreSound checks the table of ten settings: unique names, the expected order, and sensible limits.
func TestSettingSpecsAreSound(t *testing.T) {
	// The expected names in order.
	want := []string{"num_ctx", "temperature", "top_k", "top_p", "min_p", "repeat_penalty", "repeat_last_n", "seed", "num_predict", "stop"}
	// The count.
	if len(settingSpecs) != len(want) {
		// Report the problem.
		t.Fatalf("%d settings, want %d", len(settingSpecs), len(want))
	} // end of the count check
	// Go through them.
	for i, s := range settingSpecs {
		// The name and order.
		if s.Key != want[i] {
			// Report the problem.
			t.Errorf("setting %d is %q, want %q", i, s.Key, want[i])
		} // end of the name check
		// Every setting has a default text and a heading.
		if s.Default == "" || s.Heading == "" {
			// Report the problem.
			t.Errorf("%s lacks a default or a heading", s.Key)
		} // end of the text check
		// A fixed range must be a real range.
		if s.Kind != kindList && !s.FromModel && !(s.Min < s.Max) {
			// Report the problem.
			t.Errorf("%s has the range %v to %v", s.Key, s.Min, s.Max)
		} // end of the range check
		// A model-dependent setting needs the model maximum.
		if _, _, ok := s.limits(0); ok == s.FromModel {
			// Report the problem.
			t.Errorf("%s: limits without a model maximum ok=%v", s.Key, ok)
		} // end of the limit check
		// The heading has a help text.
		if _, ok := helpFor(s.Heading); !ok {
			// Report the problem.
			t.Errorf("%s has no help text", s.Heading)
		} // end of the help check
	} // end of the loop
} // end of TestSettingSpecsAreSound

// TestParseNumber checks the rules for typed numbers, setting by setting.
func TestParseNumber(t *testing.T) {
	// A helper to find a spec.
	spec := func(key string) settingSpec {
		// Look it up.
		s, ok := specByKey(key)
		// A test bug if missing.
		if !ok {
			// Stop.
			t.Fatalf("no spec %s", key)
		} // end of the check
		// Hand back.
		return s
	} // end of spec
	// The cases: setting, typed text, whether accepted, and the number.
	cases := []struct {
		// key is the setting.
		key string
		// in is what was typed.
		in string
		// ok says whether it is accepted.
		ok bool
		// n is the expected number.
		n float64
	}{
		// The context size: limits 512 and the model maximum 131072.
		{"num_ctx", "512", true, 512}, {"num_ctx", "131072", true, 131072}, {"num_ctx", " 8192 ", true, 8192}, {"num_ctx", "511", false, 0}, {"num_ctx", "131073", false, 0}, {"num_ctx", "8192.5", false, 0}, {"num_ctx", "-8192", false, 0}, {"num_ctx", "1e5", false, 0}, {"num_ctx", "+8192", false, 0}, {"num_ctx", "８１９２", false, 0}, {"num_ctx", "0x2000", false, 0},
		// Temperature 0 to 2.
		{"temperature", "0", true, 0}, {"temperature", "0.2", true, 0.2}, {"temperature", "2", true, 2}, {"temperature", "2.01", false, 0}, {"temperature", "-0.1", false, 0}, {"temperature", ".5", false, 0}, {"temperature", "1.", false, 0}, {"temperature", "1.2.3", false, 0}, {"temperature", "abc", false, 0}, {"temperature", "0,5", false, 0}, {"temperature", "NaN", false, 0}, {"temperature", "Inf", false, 0},
		// Top-k 1 to 1000, whole numbers.
		{"top_k", "1", true, 1}, {"top_k", "1000", true, 1000}, {"top_k", "0", false, 0}, {"top_k", "1001", false, 0}, {"top_k", "40.5", false, 0},
		// Top-p 0.01 to 1.
		{"top_p", "0.01", true, 0.01}, {"top_p", "1", true, 1}, {"top_p", "0", false, 0}, {"top_p", "1.5", false, 0},
		// Min-p 0 to 1.
		{"min_p", "0", true, 0}, {"min_p", "0.05", true, 0.05}, {"min_p", "1.01", false, 0},
		// Repeat penalty 0.5 to 2.
		{"repeat_penalty", "0.5", true, 0.5}, {"repeat_penalty", "1.1", true, 1.1}, {"repeat_penalty", "2", true, 2}, {"repeat_penalty", "0.4", false, 0}, {"repeat_penalty", "2.1", false, 0},
		// Repeat window -1 to the model maximum.
		{"repeat_last_n", "-1", true, -1}, {"repeat_last_n", "0", true, 0}, {"repeat_last_n", "64", true, 64}, {"repeat_last_n", "-2", false, 0}, {"repeat_last_n", "131073", false, 0}, {"repeat_last_n", "--1", false, 0}, {"repeat_last_n", "1-", false, 0},
		// Seed 0 to 2147483647.
		{"seed", "0", true, 0}, {"seed", "42", true, 42}, {"seed", "2147483647", true, 2147483647}, {"seed", "2147483648", false, 0}, {"seed", "-1", false, 0},
		// Answer length: -1, or 1 and up; never 0.
		{"num_predict", "-1", true, -1}, {"num_predict", "512", true, 512}, {"num_predict", "0", false, 0}, {"num_predict", "-2", false, 0}, {"num_predict", "131073", false, 0},
		// Too long to read.
		{"temperature", "0.00000000000000000000001", false, 0}, {"top_k", strings.Repeat("9", 400), false, 0},
	} // end of the case table
	// Go through the cases.
	for _, c := range cases {
		// Check it against a model that supports 131072.
		n, problem := spec(c.key).parseNumber(c.in, 131072)
		// Compare.
		if (problem == "") != c.ok || n != c.n {
			// Cut a long input for the report.
			in := c.in
			// Cut it.
			if len(in) > 30 {
				// Keep the start.
				in = in[:30]
			} // end of the cut
			// Report.
			t.Errorf("%s %q: got (%v, %q), want ok=%v n=%v", c.key, in, n, problem, c.ok, c.n)
		} // end of the compare
	} // end of the case loop
	// Without a known model maximum the three model-dependent settings refuse everything.
	for _, key := range []string{"num_ctx", "repeat_last_n", "num_predict"} {
		// Try a normal value.
		if _, problem := spec(key).parseNumber("64", 0); problem == "" {
			// Report the problem.
			t.Errorf("%s accepted a value without a known model maximum", key)
		} // end of the check
	} // end of the loop
} // end of TestParseNumber

// TestParseStopWords checks the rules for the stop word box.
func TestParseStopWords(t *testing.T) {
	// Good input: lines, Windows line breaks, blank lines skipped, inner spaces and quotes kept.
	got, problem := parseStopWords("AAA\r\n\r\na b\nsay \"hi\"\nback\\slash\n")
	// It must be accepted and exact.
	if problem != "" || fmt.Sprintf("%q", got) != `["AAA" "a b" "say \"hi\"" "back\\slash"]` {
		// Report the problem.
		t.Errorf("good input: %q %q", got, problem)
	} // end of the good check
	// Bad input.
	for name, in := range map[string]string{
		// A control character.
		"tab": "a\tb",
		// A bell.
		"bell": "a\x07b",
		// Invalid UTF-8.
		"utf8": "a\xffb",
		// Too many.
		"nine": "1\n2\n3\n4\n5\n6\n7\n8\n9",
		// A repeat.
		"repeat": "AAA\nAAA",
		// Too long a word.
		"long": strings.Repeat("x", 101),
		// Far too much text.
		"huge": strings.Repeat("x\n", 2000),
	} { // end of the bad map
		// Check it.
		if _, problem := parseStopWords(in); problem == "" {
			// Report the problem.
			t.Errorf("%s was accepted", name)
		} // end of the check
	} // end of the loop
	// Exactly the limits are fine.
	if _, problem := parseStopWords(strings.Repeat("x", 100) + "\n2\n3\n4\n5\n6\n7\n8"); problem != "" {
		// Report the problem.
		t.Errorf("the limits were refused: %q", problem)
	} // end of the limit check
} // end of TestParseStopWords

// TestReadSavedAndCompare checks how saved text is read, in every format seen on the real Ollama, and how values are compared.
func TestReadSavedAndCompare(t *testing.T) {
	// The specs.
	temp, _ := specByKey("temperature")
	// The stop words.
	stop, _ := specByKey("stop")
	// A normal number.
	if v, present, ok := readSaved(temp, []string{"0.2"}); !present || !ok || v.Num != 0.2 {
		// Report the problem.
		t.Errorf("0.2 -> %v %v %v", v, present, ok)
	} // end of the number check
	// Ollama printed a big number like this.
	if v, _, ok := readSaved(temp, []string{"1e+08"}); !ok || v.Num != 1e8 {
		// Report the problem.
		t.Errorf("1e+08 -> %v %v", v, ok)
	} // end of the exponent check
	// Text instead of a number: present but unreadable.
	if _, present, ok := readSaved(temp, []string{`"abc"`}); !present || ok {
		// Report the problem.
		t.Errorf("text value: present=%v readable=%v", present, ok)
	} // end of the text check
	// Nothing saved.
	if _, present, _ := readSaved(temp, nil); present {
		// Report the problem.
		t.Errorf("nothing saved was reported as saved")
	} // end of the nothing check
	// The last line of a number wins.
	if v, _, _ := readSaved(temp, []string{"1", "2"}); v.Num != 2 {
		// Report the problem.
		t.Errorf("last line did not win: %v", v)
	} // end of the last-wins check
	// Quoted stop words are unquoted, including escapes.
	v, _, _ := readSaved(stop, []string{`"a b"`, `"say \"hi\""`, `"back\\slash"`})
	// Check.
	if fmt.Sprintf("%q", v.List) != `["a b" "say \"hi\"" "back\\slash"]` {
		// Report the problem.
		t.Errorf("stop words -> %q", v.List)
	} // end of the stop check
	// Lists compare without regard to order.
	if !(settingValue{List: []string{"a", "b"}}).equal(settingValue{List: []string{"b", "a"}}, stop) {
		// Report the problem.
		t.Errorf("order mattered")
	} // end of the order check
	// Different lists differ.
	if (settingValue{List: []string{"a"}}).equal(settingValue{List: []string{"a", "b"}}, stop) {
		// Report the problem.
		t.Errorf("different lists were equal")
	} // end of the difference check
} // end of TestReadSavedAndCompare

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

// TestGearShowsSettings checks the settings page: all ten settings with defaults and saved values, the fields with their limits, the help bubbles, no script, and nothing changed.
func TestGearShowsSettings(t *testing.T) {
	// A fake with the settings a real gemma model has saved.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// Open the settings of the first model.
	status, body, header := gearPost(t, rig, "/gear", "alpha:1b")
	// It must load.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d", status)
	} // end of the status check
	// Everything the page must say.
	for _, want := range []string{
		// The heading names the model.
		"Settings for <code>alpha:1b</code>",
		// The form goes to the review step.
		`action="/gear/review"`,
		// The saved values appear in the Saved column.
		`">1</td>`, `">64</td>`, `">0.95</td>`, `">&#34;&lt;end_of_turn&gt;&#34;</td>`,
		// Settings with nothing saved say so.
		`">not set</td>`,
		// Ollama's defaults.
		"automatic (docs: 2048)", `">0.8</td>`, `">40</td>`, `">0.9</td>`, "0 (off)", "1 (off)", `">64</td>`, "-1 (no limit)", `">none</td>`,
		// The allowed values.
		"512 to 131072", "0 to 2", "1 to 1000", "0.01 to 1", "0.5 to 2", "-1 to 131072", "0 to 2147483647", "-1, or 1 to 131072", "up to 8 words",
		// The context size has suggestions.
		`<option value="8192">`,
		// The rule about removing.
		"never emptied",
		// The help bubbles, each with the three standard parts.
		"Example:", "Helps you decide:",
	} { // end of the list
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The column is called "Set in the model" and the label "In plain words" is gone.
	if !strings.Contains(body, ">Set in the model</span>") || strings.Contains(body, "Saved in the model") || strings.Contains(body, "In plain words") {
		// Report the problem.
		t.Errorf("wording of the column or the bubbles is wrong")
	} // end of the wording check
	// Every setting has a field and a help bubble.
	for _, s := range settingSpecs {
		// The field.
		if !strings.Contains(body, `name="s_`+s.Key+`"`) || !strings.Contains(body, `aria-describedby="tip-gear-`+s.Key+`"`) {
			// Report the gap.
			t.Errorf("no field or bubble for %s", s.Key)
		} // end of the check
	} // end of the loop
	// Saved settings must not be emptiable in the browser, and unsaved ones may be left empty.
	if !regexp.MustCompile(`name="s_temperature"[^>]*value="1" required`).MatchString(body) || regexp.MustCompile(`name="s_min_p"[^>]*required`).MatchString(body) {
		// Report the problem.
		t.Errorf("the required flags are wrong")
	} // end of the required check
	// The number fields carry the limits for the browser.
	if !regexp.MustCompile(`name="s_temperature" type="number" inputmode="decimal" min="0" max="2" step="any"`).MatchString(body) || !regexp.MustCompile(`name="s_top_k" type="number" inputmode="decimal" min="1" max="1000" step="1"`).MatchString(body) {
		// Report the problem.
		t.Errorf("the browser limits are wrong")
	} // end of the limit check
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

// TestGearListsUnknownSavedSettings checks a saved setting this page does not edit is listed and kept.
func TestGearListsUnknownSavedSettings(t *testing.T) {
	// A fake with an extra saved setting.
	f := newGearFake()
	// Add it.
	f.params = append(f.params, paramLine{"mirostat", "2"})
	// Build the rig.
	rig := gearRig(t, f)
	// Open the settings.
	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
	// It is listed, once.
	if !strings.Contains(body, "kept as they are: <code>mirostat 2</code>") {
		// Report the problem.
		t.Errorf("the extra setting is not listed")
	} // end of the check
	// Saving another setting keeps it.
	gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
	// Still there.
	if got := f.saved("mirostat"); len(got) != 1 || got[0] != "2" {
		// Report the problem.
		t.Errorf("mirostat is now %v", got)
	} // end of the check
} // end of TestGearListsUnknownSavedSettings

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
		// Send a valid value.
		status, body, _ := gearPost(t, rig, path, "alpha:1b", "s_temperature", "0.2")
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
		_, body, _ := gearPost(t, rig, path, "ghost:1b", "s_temperature", "0.2")
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

// TestGearRejectsBadValues checks every bad value of every setting is refused on the review step and on the save step, shown back escaped with a reason, and never reaches Ollama.
func TestGearRejectsBadValues(t *testing.T) {
	// A fake where seed and num_ctx are saved too, so "emptying" would mean losing something.
	f := newGearFake()
	// Add saved values.
	f.params = append(f.params, paramLine{"num_ctx", "4096"}, paramLine{"seed", "42"}, paramLine{"num_predict", "512"})
	// Build the rig.
	rig := gearRig(t, f)
	// The bad values for each setting.
	bad := map[string][]string{
		// Context size.
		"num_ctx": {"", "   ", "abc", "-5", "0", "511", "131073", "8192.5", "1e5", "+8192", "８１９２", "99999999999999999999", "<script>alert(1)</script>"},
		// Temperature (saved).
		"temperature": {"", "3", "-1", "x", "1,5", "NaN", "<b>"},
		// Top-k (saved).
		"top_k": {"", "0", "1.5", "5000"},
		// Top-p (saved).
		"top_p": {"", "0", "2"},
		// Min-p (not saved): an empty field is fine, so only wrong values.
		"min_p": {"2", "-0.5", "x"},
		// Repeat penalty (not saved).
		"repeat_penalty": {"0.1", "9"},
		// Repeat window (not saved).
		"repeat_last_n": {"-5", "9999999"},
		// Seed (saved).
		"seed": {"", "-1", "99999999999"},
		// Answer length (saved).
		"num_predict": {"", "0", "-2", "x"},
		// Stop words (saved).
		"stop": {"", "   \n  ", "a\tb", "1\n2\n3\n4\n5\n6\n7\n8\n9", "AAA\nAAA"},
	} // end of the bad values
	// Go through the settings.
	for key, values := range bad {
		// Go through the values.
		for _, v := range values {
			// Both steps.
			for _, path := range []string{"/gear/review", "/gear/save"} {
				// Send it.
				status, body, _ := gearPost(t, rig, path, "alpha:1b", "s_"+key, v)
				// The settings page comes back with the reason, and no confirm button.
				if status != http.StatusOK || !strings.Contains(body, "Not saved.") || !strings.Contains(body, `role="alert"><strong>⚠</strong>`) || strings.Contains(body, "Yes, save them into the model") {
					// Report the problem.
					t.Errorf("%s %s %q: status %d", path, key, v, status)
				} // end of the check
				// An empty value of a saved setting gets its own, clear reason.
				if strings.TrimSpace(v) == "" && !strings.Contains(body, "cannot be empty") {
					// Report the problem.
					t.Errorf("%s %s %q: no 'cannot be empty' reason", path, key, v)
				} // end of the empty check
				// Markup must come back escaped.
				if strings.Contains(body, "<script>alert") || strings.Contains(body, "<b>") {
					// Report the problem.
					t.Errorf("%s %s: unescaped markup in the page", path, key)
				} // end of the escape check
			} // end of the path loop
		} // end of the value loop
	} // end of the setting loop
	// One bad value blocks the good ones next to it.
	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2", "s_top_k", "0")
	// Nothing is saved.
	if !strings.Contains(body, "Not saved.") {
		// Report the problem.
		t.Errorf("a good value was saved next to a bad one")
	} // end of the mixed check
	// Nothing reached Ollama.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("a bad value was sent to Ollama")
	} // end of the change check
	// The saved values are untouched.
	if got := f.saved("num_ctx"); len(got) != 1 || got[0] != "4096" {
		// Report the problem.
		t.Errorf("the saved size changed to %v", got)
	} // end of the saved check
} // end of TestGearRejectsBadValues

// TestGearEmptyUnsavedIsFine checks an unsaved setting left empty is not an error and not a change.
func TestGearEmptyUnsavedIsFine(t *testing.T) {
	// A fake.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// Empty fields for settings that are not saved.
	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "s_min_p", "", "s_seed", "  ", "s_stop_nothing", "x")
	// It is "nothing to change", not an error.
	if status != http.StatusOK || !strings.Contains(body, "Nothing to change") || strings.Contains(body, "Not saved.") {
		// Report the problem.
		t.Errorf("status %d, body %q", status, body)
	} // end of the check
} // end of TestGearEmptyUnsavedIsFine

// TestGearReviewThenSave checks the two-step flow with several settings: the review changes nothing and lists only the changes, the save sends exactly one precise create request with only the changed names, and then verifies.
func TestGearReviewThenSave(t *testing.T) {
	// A fake with the gemma-like settings.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// The typed form: a changed context size, temperature, top-k, new stop words, an unchanged top-p, and an empty unsaved field.
	typed := []string{"s_num_ctx", "8192", "s_temperature", "0.2", "s_top_k", "40", "s_top_p", "0.95", "s_min_p", "", "s_stop", "AAA\r\nBBB"}
	// Step 2: review.
	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", typed...)
	// The confirmation page with the values to be saved.
	for _, want := range []string{"This changes the model itself", "<th scope=\"row\">Context size</th><td>not set</td><td><strong>8192</strong></td>", "<th scope=\"row\">Temperature</th><td>1</td><td><strong>0.2</strong></td>", "<th scope=\"row\">Top-k</th><td>64</td><td><strong>40</strong></td>", `<strong>&#34;AAA&#34;, &#34;BBB&#34;</strong>`, `action="/gear/save"`, `name="s_stop" value="AAA"`, `name="s_stop" value="BBB"`, `name="s_num_ctx" value="8192"`, "Yes, save them into the model", "Cancel, do not change"} {
		// Look for it.
		if status != http.StatusOK || !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("review page lacks %q (status %d)", want, status)
		} // end of the check
	} // end of the loop
	// The unchanged top-p is not listed.
	if strings.Contains(body, "Top-p</th>") && strings.Contains(body, `name="s_top_p"`) {
		// Report the problem.
		t.Errorf("an unchanged setting is listed")
	} // end of the unchanged check
	// The review changed nothing.
	if f.createCount() != 0 {
		// Report the problem.
		t.Fatalf("the review step sent a create request")
	} // end of the review check
	// Step 3: save, with the values the review page passes on (only the changes).
	status, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "s_num_ctx", "8192", "s_stop", "AAA", "s_stop", "BBB", "s_temperature", "0.2", "s_top_k", "40")
	// The result page.
	if status != http.StatusOK || !strings.Contains(body, "<strong>Saved.</strong>") || !strings.Contains(body, "8192") {
		// Report the problem.
		t.Errorf("save page: status %d, body %q", status, body)
	} // end of the result check
	// Exactly one create request, with only the changed names (keys are sorted by Go's JSON writer).
	if len(f.creates) != 1 || f.creates[0] != `{"from":"alpha:1b","model":"alpha:1b","parameters":{"num_ctx":8192,"stop":["AAA","BBB"],"temperature":0.2,"top_k":40},"stream":false}` {
		// Report the problem.
		t.Errorf("create requests: %v", f.creates)
	} // end of the create check
	// The untouched setting is still there, and the old stop word is gone (a new list replaces the old one).
	if got := f.saved("top_p"); len(got) != 1 || got[0] != "0.95" {
		// Report the problem.
		t.Errorf("top_p is now %v", got)
	} // end of the other-parameter check
	// The stop words are the new ones.
	if got := f.saved("stop"); fmt.Sprint(got) != `["AAA" "BBB"]` {
		// Report the problem.
		t.Errorf("stop words are now %v", got)
	} // end of the stop check
} // end of TestGearReviewThenSave

// TestGearSpecialValuesRoundTrip checks the special values and awkward stop words survive a save and the check afterwards.
func TestGearSpecialValuesRoundTrip(t *testing.T) {
	// A fake.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// Special numbers and stop words with a space, a quote and a backslash.
	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_num_predict", "-1", "s_repeat_last_n", "-1", "s_seed", "0", "s_temperature", "0", "s_top_p", "1", "s_stop", "a b\nsay \"hi\"\nback\\slash")
	// It must succeed.
	if !strings.Contains(body, "<strong>Saved.</strong>") {
		// Report the problem.
		t.Fatalf("save failed: %q", body)
	} // end of the result check
	// The request has whole numbers as whole numbers.
	if len(f.creates) != 1 || !strings.Contains(f.creates[0], `"num_predict":-1`) || !strings.Contains(f.creates[0], `"repeat_last_n":-1`) || !strings.Contains(f.creates[0], `"seed":0`) || !strings.Contains(f.creates[0], `"stop":["a b","say \"hi\"","back\\slash"]`) {
		// Report the problem.
		t.Errorf("create requests: %v", f.creates)
	} // end of the request check
	// The fake printed the stop words quoted; the saved list has three.
	if got := f.saved("stop"); len(got) != 3 {
		// Report the problem.
		t.Errorf("stop lines: %v", got)
	} // end of the stop check
} // end of TestGearSpecialValuesRoundTrip

// TestGearSameValueChangesNothing checks that saving values that are already saved sends nothing (this is also what a second click on Yes does).
func TestGearSameValueChangesNothing(t *testing.T) {
	// A fake.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// Both steps, with the saved values, also written differently (1.0 is 1).
	for _, path := range []string{"/gear/review", "/gear/save"} {
		// Send the same values.
		_, body, _ := gearPost(t, rig, path, "alpha:1b", "s_temperature", "1.0", "s_top_k", "64", "s_stop", "<end_of_turn>")
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
		// Save a value.
		_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
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
	// Save a value.
	status, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
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
	if _, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "s_temperature", "0.2"); !strings.Contains(body, "Yes, save them into the model") {
		// Stop the test.
		t.Fatalf("no review page")
	} // end of the review check
	// Someone loads the model now.
	f.setLoaded("alpha:1b")
	// The save step.
	_, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
	// It must refuse.
	if !strings.Contains(body, "Unload it first") || f.createCount() != 0 {
		// Report the problem.
		t.Errorf("a model loaded in the meantime was changed")
	} // end of the check
} // end of TestGearModelLoadedBetweenReviewAndSave

// TestGearUnknownMaximum checks that without a known model maximum the three settings that depend on it cannot be changed, while the others still can.
func TestGearUnknownMaximum(t *testing.T) {
	// A fake whose model reports no limit.
	f := newGearFake()
	// No model facts.
	f.modelInfo = `{}`
	// Build the rig.
	rig := gearRig(t, f)
	// The settings page has three fields fewer and says why.
	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
	// Check it.
	if strings.Count(body, "cannot be changed: Ollama does not report") != 3 || strings.Contains(body, `name="s_num_ctx"`) || !strings.Contains(body, `name="s_temperature"`) {
		// Report the problem.
		t.Errorf("settings page: %d notes", strings.Count(body, "cannot be changed"))
	} // end of the check
	// A forged value for one of them is refused on both steps.
	for _, path := range []string{"/gear/review", "/gear/save"} {
		// Send a size.
		_, body, _ := gearPost(t, rig, path, "alpha:1b", "s_num_ctx", "8192")
		// It must refuse.
		if !strings.Contains(body, "Not saved.") || !strings.Contains(body, "No safe limit is known") {
			// Report the problem.
			t.Errorf("%s: %q", path, body)
		} // end of the check
	} // end of the loop
	// Nothing was sent.
	if f.createCount() != 0 {
		// Report the problem.
		t.Errorf("a setting without a known limit was changed")
	} // end of the change check
	// The other settings can still be saved.
	if _, body, _ := gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2"); !strings.Contains(body, "<strong>Saved.</strong>") {
		// Report the problem.
		t.Errorf("a normal setting could not be saved: %q", body)
	} // end of the normal save
} // end of TestGearUnknownMaximum

// TestGearSavedAboveMaximum checks a saved size above the model's limit is pointed out and can be fixed by saving a valid one.
func TestGearSavedAboveMaximum(t *testing.T) {
	// A fake with a size far above the limit saved (the experiment showed Ollama accepts such a value).
	f := newGearFake()
	// The saved text, in the form Ollama printed.
	f.params = append(f.params, paramLine{"num_ctx", "1e+08"})
	// Build the rig.
	rig := gearRig(t, f)
	// The settings page.
	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
	// It warns.
	if !strings.Contains(body, "above what this model supports") {
		// Report the problem.
		t.Errorf("no warning in %q", body)
	} // end of the warning check
	// Saving a valid size works.
	_, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "s_num_ctx", "8192")
	// The result.
	if !strings.Contains(body, "<strong>Saved.</strong>") {
		// Report the problem.
		t.Errorf("fixing the value failed: %q", body)
	} // end of the result check
} // end of TestGearSavedAboveMaximum

// TestGearUnreadableSavedValue checks a saved value that is not a number (Ollama accepts text) is shown as it is, and can be replaced by a valid number.
func TestGearUnreadableSavedValue(t *testing.T) {
	// A fake with text saved as the temperature.
	f := newGearFake()
	// Replace the temperature.
	f.params[0] = paramLine{"temperature", `"abc"`}
	// Build the rig.
	rig := gearRig(t, f)
	// The settings page shows it and does not pre-fill the field.
	_, body, _ := gearPost(t, rig, "/gear", "alpha:1b")
	// Check.
	if !strings.Contains(body, "(not a usable value)") || strings.Contains(body, `name="s_temperature" type="number" inputmode="decimal" min="0" max="2" step="any" aria-label="Temperature for alpha:1b" value="abc"`) {
		// Report the problem.
		t.Errorf("unreadable value shown wrongly")
	} // end of the check
	// A valid number replaces it.
	_, body, _ = gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.7")
	// It works.
	if !strings.Contains(body, "<strong>Saved.</strong>") {
		// Report the problem.
		t.Errorf("replacing failed: %q", body)
	} // end of the check
} // end of TestGearUnreadableSavedValue

// TestGearLargestForm checks a form with the longest possible stop words (eight words of 100 four-byte characters) is accepted, and a form beyond the limit is refused.
func TestGearLargestForm(t *testing.T) {
	// A fake.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// Eight words of 100 characters, each four bytes long.
	var words []string
	// Build them, each different.
	for i := 0; i < 8; i++ {
		// One word.
		words = append(words, strings.Repeat("𝔘", 99)+string(rune('a'+i)))
	} // end of the loop
	// The review step must accept it.
	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", "s_stop", strings.Join(words, "\n"))
	// Check.
	if status != http.StatusOK || !strings.Contains(body, "Yes, save them into the model") {
		// Report the problem.
		t.Errorf("the largest valid form failed: status %d", status)
	} // end of the check
	// A form of 20 KB is refused as a bad form.
	status, _, _ = gearPost(t, rig, "/gear/review", "alpha:1b", "s_stop", strings.Repeat("x", 20000))
	// Check.
	if status != http.StatusBadRequest {
		// Report the problem.
		t.Errorf("an oversized form gave status %d", status)
	} // end of the size check
} // end of TestGearLargestForm

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
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "s_temperature": {"0.2"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
			// Report the problem.
			t.Errorf("cross-site %s = %d", path, res.StatusCode)
		} // end of the origin check
		// A POST without any browser header is refused.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "s_temperature": {"0.2"}}, nil); res.StatusCode != http.StatusForbidden {
			// Report the problem.
			t.Errorf("headerless %s = %d", path, res.StatusCode)
		} // end of the headerless check
		// A POST with a wrong token is refused.
		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "model": {"alpha:1b"}, "s_temperature": {"0.2"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
			// Report the problem.
			t.Errorf("wrong token %s = %d", path, res.StatusCode)
		} // end of the token check
		// A POST without a model name is refused.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "s_temperature": {"0.2"}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
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

// TestGearDoubleClickSavesOnce checks that many simultaneous saves of the same values send only one create request.
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
			gearPost(t, rig, "/gear/save", "alpha:1b", "s_temperature", "0.2")
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
