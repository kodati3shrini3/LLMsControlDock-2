// Package main tells Go that this test file belongs to the same program as perf.go.
package main

import ( // import lists the packages this test file uses.
	// context is needed by the GPU query replacement.
	"context"
	// encoding/json reads the requests the fake receives and the saved file.
	"encoding/json"
	// errors builds the "no tool" error of the GPU query replacement.
	"errors"
	// fmt builds text.
	"fmt"
	// net/http provides requests and status codes.
	"net/http"
	// net/url builds form data.
	"net/url"
	// os reads and writes the files of the tests.
	"os"
	// path/filepath joins file names.
	"path/filepath"
	// runtime tells the operating system, because file permissions differ on Windows.
	"runtime"
	// strings searches the page text.
	"strings"
	// sync protects the fake's records.
	"sync"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// secretText is the answer text of the fake; it must never reach a page of the monitor's own making or the saved file.
const secretText = "SECRET-ANSWER-TEXT"

// perfFake is a fake Ollama for the performance tests: it loads a model on the first request, streams an answer, and reports figures that differ per request so the median can be told from the mean.
type perfFake struct {
	// mu protects every field below.
	mu sync.Mutex
	// loaded is the set of models in memory.
	loaded map[string]bool
	// testCalls counts the generate and embed requests that are not unload requests.
	testCalls int
	// unloads records every unload request.
	unloads []string
	// failAt is the index (from 1) of the test request that fails; zero means none fail.
	failAt int
	// thinking makes the stream carry a thinking field instead of a response field.
	thinking bool
	// stuck makes unload requests do nothing.
	stuck bool
	// evalScale multiplies the answer durations, so a second run can be slower.
	evalScale float64
	// hold makes the first test request wait until release is closed, so a test can look at a running test.
	hold bool
	// entered is signalled when the first test request has arrived.
	entered chan struct{}
	// release lets the first test request go on when it is closed.
	release chan struct{}
} // end of perfFake

// newPerfFake builds a fake with nothing loaded.
func newPerfFake() *perfFake {
	// A fake with a neutral scale.
	return &perfFake{loaded: map[string]bool{}, evalScale: 1}
} // end of newPerfFake

// start runs the fake as a server and returns its address.
func (f *perfFake) start(t *testing.T) string {
	// Mark this as a helper.
	t.Helper()
	// Start the server.
	srv := fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
		// One request at a time.
		f.mu.Lock()
		// Release when this request is done.
		defer f.mu.Unlock()
		// Read the body into a generic shape.
		var req struct {
			// Model is the asked model.
			Model string `json:"model"`
			// KeepAlive is a number (0 unloads) or a text such as 2m.
			KeepAlive any `json:"keep_alive"`
		} // end of the request shape
		// Decode it (GET requests have no body).
		_ = json.NewDecoder(r.Body).Decode(&req)
		// Is this an unload request?
		unload := req.KeepAlive == float64(0)
		// Pick the reply by path.
		switch r.URL.Path {
		// The version check.
		case "/api/version":
			// A valid version.
			w.Write([]byte(`{"version":"0.34.4"}`))
		// The installed models.
		case "/api/tags":
			// Four models: a chat model, a thinking model, an embedding model and one with no known ability.
			w.Write([]byte(`{"models":[{"name":"chat:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"think:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion","thinking"]},{"name":"embed:1b","size":2000000000,"details":{"family":"bert"},"capabilities":["embedding"]},{"name":"odd:1b","size":1000,"details":{"family":"x"},"capabilities":[]}]}`))
		// The loaded models.
		case "/api/ps":
			// Build the list from the fake's state.
			parts := []string{}
			// Every loaded name.
			for n := range f.loaded {
				// One entry: 4 GB, all of it in graphics memory.
				parts = append(parts, `{"name":"`+n+`","size":4000000000,"size_vram":4000000000,"context_length":8192,"expires_at":"2999-01-01T00:00:00Z"}`)
			} // end of the loop
			// Send the list.
			w.Write([]byte(`{"models":[` + strings.Join(parts, ",") + `]}`))
		// A chat request.
		case "/api/generate":
			// An unload request.
			if unload {
				// Record it.
				f.unloads = append(f.unloads, req.Model)
				// Unload unless stuck.
				if !f.stuck {
					// Remove it.
					delete(f.loaded, req.Model)
				} // end of the stuck check
				// A short reply.
				if req.Model == "embed:1b" {
					// An embedding model cannot generate.
					w.WriteHeader(http.StatusBadRequest)
					// Ollama's message.
					w.Write([]byte(`{"error":"does not support generate"}`))
					// Stop here.
					return
				} // end of the embedding check
				// Fine.
				w.Write([]byte(`{"done":true}`))
				// Stop here.
				return
			} // end of the unload case
			// An embedding model cannot generate.
			if req.Model == "embed:1b" {
				// Refuse like Ollama.
				w.WriteHeader(http.StatusBadRequest)
				// Ollama's message.
				w.Write([]byte(`{"error":"does not support generate"}`))
				// Stop here.
				return
			} // end of the embedding check
			// Count the request.
			f.testCalls++
			// This index, from 1.
			n := f.testCalls
			// A test that wants to look at a running test holds the first request here.
			if f.hold && n == 1 {
				// Say the request has arrived.
				f.entered <- struct{}{}
				// Let other requests in while waiting.
				f.mu.Unlock()
				// Wait for the signal.
				<-f.release
				// Take the lock back before going on.
				f.mu.Lock()
			} // end of the hold check
			// A failing request.
			if f.failAt == n {
				// Refuse like Ollama.
				w.WriteHeader(http.StatusInternalServerError)
				// Ollama's message.
				w.Write([]byte(`{"error":"boom"}`))
				// Stop here.
				return
			} // end of the failure check
			// The first request loads the model.
			load := int64(1_000_000)
			// Cold.
			if !f.loaded[req.Model] {
				// Two seconds.
				load = 2_000_000_000
			} // end of the cold check
			// Now it is in memory.
			f.loaded[req.Model] = true
			// Answer durations per request: the warm-up is slow, the timed ones give 40, 20 and 40 tokens/s (median 40, mean 33.3, median with warm-up 30).
			eval := map[int]int64{1: 8_000_000_000, 2: 1_600_000_000, 3: 3_200_000_000, 4: 1_600_000_000}[(n-1)%4+1]
			// Scale it.
			eval = int64(float64(eval) * f.evalScale)
			// Prompt reading durations: the warm-up is slow, the timed ones read 1000 tokens/s.
			prompt := int64(200_000_000)
			// The warm-up.
			if (n-1)%4 == 0 {
				// Slower.
				prompt = 400_000_000
			} // end of the warm-up check
			// The first piece carries text.
			first := map[string]any{"response": secretText, "done": false}
			// A thinking model sends its reasoning in another field.
			if f.thinking {
				// Use it.
				first = map[string]any{"thinking": secretText, "done": false}
			} // end of the thinking check
			// The last piece carries the figures.
			last := map[string]any{"response": "", "done": true, "done_reason": "stop", "total_duration": load + prompt + eval, "load_duration": load, "prompt_eval_count": 200, "prompt_eval_duration": prompt, "eval_count": 64, "eval_duration": eval}
			// The flusher sends each line at once.
			fl, _ := w.(http.Flusher)
			// Both pieces.
			for _, p := range []map[string]any{first, last} {
				// Encode one line.
				b, _ := json.Marshal(p)
				// Send it.
				w.Write(append(b, '\n'))
				// Flush it.
				if fl != nil {
					// Now.
					fl.Flush()
				} // end of the flush check
			} // end of the pieces loop
		// An embedding request.
		case "/api/embed":
			// An unload request.
			if unload {
				// Record it.
				f.unloads = append(f.unloads, req.Model)
				// Unload unless stuck.
				if !f.stuck {
					// Remove it.
					delete(f.loaded, req.Model)
				} // end of the stuck check
				// Fine.
				w.Write([]byte(`{"embeddings":[]}`))
				// Stop here.
				return
			} // end of the unload case
			// Count the request.
			f.testCalls++
			// Cold or warm.
			load, total := int64(1_000_000), int64(50_000_000)
			// Cold.
			if !f.loaded[req.Model] {
				// Slow.
				load, total = 1_500_000_000, 1_600_000_000
			} // end of the cold check
			// Now it is in memory.
			f.loaded[req.Model] = true
			// The reply.
			w.Write([]byte(fmt.Sprintf(`{"model":"%s","embeddings":[[0.1,0.2,0.3]],"total_duration":%d,"load_duration":%d,"prompt_eval_count":200}`, req.Model, total, load)))
		// Anything else.
		default:
			// Not found.
			w.WriteHeader(http.StatusNotFound)
		} // end of the switch
	}) // end of the server
	// Hand back the address.
	return srv.URL
} // end of start

// calls says how many test requests (not unload requests) the fake has received.
func (f *perfFake) calls() int {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The number.
	return f.testCalls
} // end of calls

// isLoaded says whether a model is in memory.
func (f *perfFake) isLoaded(name string) bool {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The answer.
	return f.loaded[name]
} // end of isLoaded

// unloadCount says how many unload requests arrived.
func (f *perfFake) unloadCount() int {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The number.
	return len(f.unloads)
} // end of unloadCount

// quietMachine points the machine readers at a calm fake machine for one test and restores them afterwards.
func quietMachine(t *testing.T) {
	// Mark this as a helper.
	t.Helper()
	// A folder that plays the role of /proc.
	dir := t.TempDir()
	// The files.
	for name, text := range map[string]string{
		// Four-core machine, quiet.
		"cpuinfo": "processor\t: 0\nmodel name\t: Test Processor 9000\n",
		// Load of 0.5 on 4 cores.
		"loadavg": "0.50 0.40 0.30 1/200 123\n",
		// 16 GB total, 8 GB free, swap 2 GB with 1 GB free (in kilobytes).
		"meminfo": "MemTotal:       16000000 kB\nMemAvailable:    8000000 kB\nSwapTotal:       2000000 kB\nSwapFree:        1000000 kB\n",
	} { // end of the files
		// Write each.
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o600); err != nil {
			// Stop the test.
			t.Fatalf("fixture: %v", err)
		} // end of the write check
	} // end of the loop
	// Remember the real readers.
	oldProc, oldGPU := procDir, gpuQuery
	// Use the fixtures.
	procDir = dir
	// A card that is idle and shares its memory.
	gpuQuery = func(ctx context.Context) (string, error) { return "Test GPU, [N/A], [N/A], 0 %", nil }
	// Put the real readers back at the end.
	t.Cleanup(func() { procDir, gpuQuery = oldProc, oldGPU })
} // end of quietMachine

// perfRig builds a web handler for a fake, with the history in a folder of the test; it returns the rig and the history file path.
func perfRig(t *testing.T, f *perfFake) (themeRig, string) {
	// Mark this as a helper.
	t.Helper()
	// A calm machine.
	quietMachine(t)
	// The history goes into a folder of this test, never into the real configuration folder.
	dir := t.TempDir()
	// Remember the real lookup.
	old := userConfigDir
	// Use the test folder.
	userConfigDir = func() (string, error) { return dir, nil }
	// Put it back at the end.
	t.Cleanup(func() { userConfigDir = old })
	// Start the fake and build the handler.
	h := handlerFor(t, f.start(t))
	// Fetch the main page.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the page token.
	i := strings.Index(body, `name="token" value="`)
	// The page must carry one.
	if i < 0 {
		// Stop the test.
		t.Fatalf("no token found in the page")
	} // end of the token check
	// The token is 32 characters after the marker.
	tok := body[i+len(`name="token" value="`) : i+len(`name="token" value="`)+32]
	// Hand back the rig and the file path.
	return themeRig{h: h, token: tok}, filepath.Join(dir, "OllamaControlCenter", "performance.json")
} // end of perfRig

// perfPost sends a form to a performance route as the page's own form would.
func perfPost(t *testing.T, rig themeRig, path, model string) (int, string, http.Header) {
	// Mark this as a helper.
	t.Helper()
	// Send it.
	res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {model}}, fromThisPage)
	// Hand back status, body and headers.
	return res.StatusCode, bodyOf(res), res.Header
} // end of perfPost

// savedRuns reads the history file of a test.
func savedRuns(t *testing.T, path string) []perfRun {
	// Mark this as a helper.
	t.Helper()
	// Read the file.
	data, err := os.ReadFile(path)
	// A missing file means nothing was saved.
	if os.IsNotExist(err) {
		// No runs.
		return nil
	} // end of the missing check
	// Any other problem is a test failure.
	if err != nil {
		// Stop the test.
		t.Fatalf("read history: %v", err)
	} // end of the read check
	// Decode it.
	var h historyFile
	// It must be valid.
	if err := json.Unmarshal(data, &h); err != nil {
		// Stop the test.
		t.Fatalf("history is not valid JSON: %v", err)
	} // end of the decode check
	// The runs.
	return h.Runs
} // end of savedRuns

// TestPerfStartPageChangesNothing checks the start page shows the caution and the run button and sends no test request.
func TestPerfStartPageChangesNothing(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, _ := perfRig(t, f)
	// Open the page for a chat model.
	status, body, header := perfPost(t, rig, "/performance", "chat:1b")
	// It must work.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d", status)
	} // end of the status check
	// The page says what it must.
	for _, want := range []string{"Performance of <code>chat:1b</code>", "Caution: do not run this while the model is in use", "Run the performance test", `action="/performance/run"`, "data-loading", "write text", "Only numbers are saved, never any text"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// Only the monitor's own script is allowed.
	if !strings.Contains(header.Get("Content-Security-Policy"), "script-src 'self'") || strings.Contains(body, "<script>") {
		// Report the problem.
		t.Errorf("script policy is wrong")
	} // end of the policy check
	// Nothing was sent to the model.
	if f.calls() != 0 || f.unloadCount() != 0 || f.isLoaded("chat:1b") {
		// Report the problem.
		t.Errorf("the start page changed something: %d calls", f.calls())
	} // end of the effect check
	// An embedding model gets its own words.
	_, body, _ = perfPost(t, rig, "/performance", "embed:1b")
	// The wording.
	if !strings.Contains(body, "work through a text") {
		// Report the gap.
		t.Errorf("the embedding start page has the chat wording")
	} // end of the embedding check
} // end of TestPerfStartPageChangesNothing

// TestPerfRunGenerate checks a full run: warm-up plus three timed runs, the median (not the mean), no text anywhere, the model unloaded, and the numbers saved.
func TestPerfRunGenerate(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Run the test.
	status, body, header := perfPost(t, rig, "/performance/run", "chat:1b")
	// It must work.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d: %s", status, body)
	} // end of the status check
	// Four requests: the warm-up and three timed runs.
	if f.calls() != 4 {
		// Report the problem.
		t.Errorf("%d test requests, want 4", f.calls())
	} // end of the count check
	// The median of 40, 20 and 40 is 40; the mean would be 33.3 and a median with the warm-up 30.
	for _, want := range []string{"40.0 tokens/s", "1000.0 tokens/s", "2.00 s", "100% graphics card, 0% processor and main memory", "4.0 GB", "8192", "Test Processor 9000", "Test GPU, 0% busy, memory not reported", "none", "No earlier test of this model"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("result lacks %q", want)
		} // end of the check
	} // end of the loop
	// Wrong ways to combine the runs must not appear.
	for _, bad := range []string{"33.3 tokens/s", "30.0 tokens/s", "8.0 tokens/s"} {
		// Look for it.
		if strings.Contains(body, bad) {
			// Report the problem.
			t.Errorf("result shows %q", bad)
		} // end of the check
	} // end of the loop
	// The tooltips of the indicators are there.
	for _, h := range []string{"Answer speed", "Prompt reading speed", "Load time", "Total time", "Time to first word", "Tokens counted", "Processor split", "Memory used", "CPU cores", "CPU load", "Memory free", "Swap in use", "Other models loaded", "GPU"} {
		// The heading is a focusable help element.
		if !strings.Contains(body, `tabindex="0"`) || !strings.Contains(body, ">"+h+"</span>") {
			// Report the gap.
			t.Errorf("no help heading for %q", h)
		} // end of the check
	} // end of the loop
	// No script on the result page and a strict policy.
	if strings.Contains(body, "<script") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
		// Report the problem.
		t.Errorf("the result page allows or contains a script")
	} // end of the script check
	// The model was unloaded again.
	if f.isLoaded("chat:1b") || f.unloadCount() == 0 {
		// Report the problem.
		t.Errorf("the model is still loaded")
	} // end of the unload check
	// One run was saved, with numbers only.
	runs := savedRuns(t, hist)
	// Exactly one.
	if len(runs) != 1 {
		// Stop the test.
		t.Fatalf("%d saved runs, want 1", len(runs))
	} // end of the count check
	// The saved figures.
	r := runs[0]
	// Check a few.
	if r.AnswerSpeed != 40 || r.PromptSpeed != 1000 || r.ColdLoadSec != 2 || r.Kind != "generate" || r.Model != "chat:1b" || r.TokensIn != 200 || r.TokensOut != 64 || r.OllamaVersion != "0.34.4" || r.Runs != 3 || r.PromptVersion != perfPromptVersion {
		// Report the problem.
		t.Errorf("saved run is wrong: %+v", r)
	} // end of the figures check
	// No text of any answer or prompt anywhere: not on the page, not in the file.
	data, _ := os.ReadFile(hist)
	// Check both.
	for name, text := range map[string]string{"page": body, "file": string(data)} {
		// The answer text and a piece of the fixed prompt.
		if strings.Contains(text, secretText) || strings.Contains(text, "lighthouse") {
			// Report the leak.
			t.Errorf("text of the test reached the %s", name)
		} // end of the check
	} // end of the loop
	// The file is private to the person (not on Windows, which has no such permissions).
	if runtime.GOOS != "windows" {
		// Look at the file.
		info, err := os.Stat(hist)
		// It must exist with mode 0600.
		if err != nil || info.Mode().Perm() != 0o600 {
			// Report the problem.
			t.Errorf("history file permissions: %v %v", info, err)
		} // end of the mode check
	} // end of the platform check
	// No temporary file is left behind.
	left, _ := filepath.Glob(filepath.Join(filepath.Dir(hist), "*.tmp"))
	// There must be none.
	if len(left) != 0 {
		// Report the problem.
		t.Errorf("temporary files left: %v", left)
	} // end of the temp check
} // end of TestPerfRunGenerate

// TestPerfThinkingModelFirstWord checks the first word is found when the stream carries reasoning text only.
func TestPerfThinkingModelFirstWord(t *testing.T) {
	// A thinking fake.
	f := newPerfFake()
	// Its stream uses the thinking field.
	f.thinking = true
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Run the test.
	_, body, _ := perfPost(t, rig, "/performance/run", "think:1b")
	// The saved run has first-word figures.
	runs := savedRuns(t, hist)
	// One run, with both first-word figures above zero.
	if len(runs) != 1 || runs[0].WarmFirstWordSec <= 0 || runs[0].ColdFirstWordSec <= 0 {
		// Report the problem.
		t.Errorf("first word not measured: %+v", runs)
	} // end of the check
	// The page does not claim it is missing.
	if strings.Contains(body, "Time to first word</span>") && strings.Contains(body, "not available</td>") && !strings.Contains(body, "cold:") {
		// Report the problem.
		t.Errorf("the first word is shown as missing")
	} // end of the page check
	// The reasoning text never reaches the page.
	if strings.Contains(body, secretText) {
		// Report the leak.
		t.Errorf("reasoning text reached the page")
	} // end of the leak check
} // end of TestPerfThinkingModelFirstWord

// TestPerfRunEmbedding checks the embedding variant: its own indicators, no chat figures, unloaded afterwards.
func TestPerfRunEmbedding(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Run the test.
	status, body, _ := perfPost(t, rig, "/performance/run", "embed:1b")
	// It must work.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d: %s", status, body)
	} // end of the status check
	// Four requests: warm-up and three timed.
	if f.calls() != 4 {
		// Report the problem.
		t.Errorf("%d test requests, want 4", f.calls())
	} // end of the count check
	// The embedding figures.
	for _, want := range []string{"Embedding time", "0.050 s", "1.50 s", "Vector length", "3 numbers", "200 in", "An embedding model writes no text"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("result lacks %q", want)
		} // end of the check
	} // end of the loop
	// No chat figures.
	if strings.Contains(body, "tokens/s</td>") || strings.Contains(body, ">Answer speed</span>") {
		// Report the problem.
		t.Errorf("chat figures on an embedding result")
	} // end of the chat check
	// Unloaded through the embed fallback.
	if f.isLoaded("embed:1b") {
		// Report the problem.
		t.Errorf("the embedding model is still loaded")
	} // end of the unload check
	// The saved run is an embedding run.
	if runs := savedRuns(t, hist); len(runs) != 1 || runs[0].Kind != "embedding" || runs[0].VectorLength != 3 {
		// Report the problem.
		t.Errorf("saved run: %+v", runs)
	} // end of the saved check
} // end of TestPerfRunEmbedding

// TestPerfRefusals checks a loaded model, an unknown model and a model of unknown ability are refused, and nothing is sent to the model.
func TestPerfRefusals(t *testing.T) {
	// A fake with the chat model already in memory.
	f := newPerfFake()
	// Loaded, maybe in use.
	f.loaded["chat:1b"] = true
	// Build the rig.
	rig, hist := perfRig(t, f)
	// The cases.
	for _, tc := range []struct{ model, want string }{
		// A loaded model.
		{"chat:1b", "loaded now and may be in use"},
		// An unknown model.
		{"nope:1b", "not installed"},
		// A model with no known ability.
		{"odd:1b", "does not report that this model can write text"},
	} { // end of the cases
		// Both the start page and the run refuse.
		for _, path := range []string{"/performance", "/performance/run"} {
			// Send it.
			status, body, _ := perfPost(t, rig, path, tc.model)
			// It is a normal page that explains.
			if status != http.StatusOK || !strings.Contains(body, tc.want) {
				// Report the problem.
				t.Errorf("%s %s: status %d, body lacks %q", path, tc.model, status, tc.want)
			} // end of the check
		} // end of the path loop
	} // end of the case loop
	// No test request was sent, and nothing was unloaded or saved.
	if f.calls() != 0 || f.unloadCount() != 0 || !f.isLoaded("chat:1b") || len(savedRuns(t, hist)) != 0 {
		// Report the problem.
		t.Errorf("a refused test changed something")
	} // end of the effect check
} // end of TestPerfRefusals

// TestPerfFormRefusals checks the same refusals as the other forms on all four routes, and that a refused request reaches nothing.
func TestPerfFormRefusals(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, _ := perfRig(t, f)
	// The cases.
	for _, tc := range []struct {
		// name describes the case.
		name string
		// form is the posted form.
		form url.Values
		// headers are the request headers.
		headers map[string]string
		// want is the expected status.
		want int
	}{ // the cases follow
		// Another site posts the form.
		{"cross-site", url.Values{"token": {rig.token}, "model": {"chat:1b"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		// No browser headers.
		{"no origin headers", url.Values{"token": {rig.token}, "model": {"chat:1b"}}, map[string]string{}, http.StatusForbidden},
		// No token.
		{"missing token", url.Values{"model": {"chat:1b"}}, fromThisPage, http.StatusForbidden},
		// A wrong token.
		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "model": {"chat:1b"}}, fromThisPage, http.StatusForbidden},
		// No model.
		{"no model", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
		// Too much data.
		{"too large", url.Values{"token": {rig.token}, "model": {"chat:1b"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
	} { // end of the table
		// Every route must refuse in the same way.
		for _, path := range []string{"/performance", "/performance/run", "/performance/clear", "/performance/clear/confirm"} {
			// A named subtest.
			t.Run(tc.name+" "+path, func(t *testing.T) {
				// Send it.
				res := post(t, rig.h, path, tc.form, tc.headers)
				// Compare the status.
				if res.StatusCode != tc.want {
					// Report the difference.
					t.Errorf("status %d, want %d", res.StatusCode, tc.want)
				} // end of the status check
			}) // end of the subtest
		} // end of the path loop
	} // end of the table loop
	// GET is refused on every route.
	for _, path := range []string{"/performance", "/performance/run", "/performance/clear", "/performance/clear/confirm"} {
		// Check the method.
		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
			// Report the problem.
			t.Errorf("GET %s = %d, want 405", path, status)
		} // end of the check
	} // end of the loop
	// Nothing reached the model.
	if f.calls() != 0 || f.unloadCount() != 0 {
		// Report the problem.
		t.Errorf("a refused request reached the model")
	} // end of the effect check
} // end of TestPerfFormRefusals

// TestPerfFailureUnloadsAndSavesNothing checks a failing request ends the test, tells why, unloads the model and saves nothing.
func TestPerfFailureUnloadsAndSavesNothing(t *testing.T) {
	// A fake whose second test request fails.
	f := newPerfFake()
	// The failure.
	f.failAt = 2
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Run the test.
	status, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
	// A bad-gateway page with the reason.
	if status != http.StatusBadGateway || !strings.Contains(body, "Could not do this") || !strings.Contains(body, "boom") {
		// Report the problem.
		t.Errorf("status %d, body: %s", status, body)
	} // end of the check
	// The model was unloaded again, and nothing was saved.
	if f.isLoaded("chat:1b") || len(savedRuns(t, hist)) != 0 {
		// Report the problem.
		t.Errorf("a failed test left the model loaded or saved a run")
	} // end of the effect check
} // end of TestPerfFailureUnloadsAndSavesNothing

// TestPerfLeftLoadedWarning checks the page says so when the model could not be unloaded again.
func TestPerfLeftLoadedWarning(t *testing.T) {
	// A fake that ignores unload requests.
	f := newPerfFake()
	// Stuck.
	f.stuck = true
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Run the test.
	_, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
	// The warning.
	if !strings.Contains(body, "could not be unloaded again") {
		// Report the problem.
		t.Errorf("no warning that the model is still loaded")
	} // end of the check
	// The saved run says so.
	if runs := savedRuns(t, hist); len(runs) != 1 || !runs[0].LeftLoaded {
		// Report the problem.
		t.Errorf("saved run: %+v", runs)
	} // end of the saved check
} // end of TestPerfLeftLoadedWarning

// TestPerfComparisonAndHistory checks the comparison with the previous run, the history table, and clearing in two steps.
func TestPerfComparisonAndHistory(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, hist := perfRig(t, f)
	// The first run.
	perfPost(t, rig, "/performance/run", "chat:1b")
	// The second run is twice as slow: the answers take twice as long.
	f.mu.Lock()
	// The scale.
	f.evalScale = 2
	// Release.
	f.mu.Unlock()
	// The second run.
	_, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
	// The comparison.
	for _, want := range []string{"This run", "Previous run", "20.0 tokens/s", "40.0 tokens/s", "-50.0% (slower)", "Saved tests of this model", "Clear all saved results (2)"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("result lacks %q", want)
		} // end of the check
	} // end of the loop
	// Two runs are saved.
	if n := len(savedRuns(t, hist)); n != 2 {
		// Stop the test.
		t.Fatalf("%d saved runs, want 2", n)
	} // end of the count check
	// The first step of clearing only asks.
	_, ask, _ := perfPost(t, rig, "/performance/clear", "chat:1b")
	// The question names the number.
	if !strings.Contains(ask, "permanently remove all 2 saved test results") || len(savedRuns(t, hist)) != 2 {
		// Report the problem.
		t.Errorf("the clear question removed something or is wrong")
	} // end of the ask check
	// The second step clears.
	_, done, _ := perfPost(t, rig, "/performance/clear/confirm", "chat:1b")
	// The confirmation.
	if !strings.Contains(done, "All saved test results were removed") || len(savedRuns(t, hist)) != 0 {
		// Report the problem.
		t.Errorf("clearing failed")
	} // end of the clear check
} // end of TestPerfComparisonAndHistory

// TestPerfBusyMachineWarning checks a busy graphics card is flagged on the start page and in the saved run.
func TestPerfBusyMachineWarning(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, hist := perfRig(t, f)
	// The graphics card is busy.
	gpuQuery = func(ctx context.Context) (string, error) { return "Test GPU, [N/A], [N/A], 96 %", nil }
	// The start page warns.
	_, start, _ := perfPost(t, rig, "/performance", "chat:1b")
	// The warning.
	if !strings.Contains(start, "The machine looks busy right now") || !strings.Contains(start, "96% busy") {
		// Report the gap.
		t.Errorf("no busy warning on the start page")
	} // end of the start check
	// The test still runs and marks the result.
	_, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
	// The result warns too.
	if !strings.Contains(body, "The machine looked busy before the test") {
		// Report the gap.
		t.Errorf("no busy warning on the result")
	} // end of the result check
	// The saved run is marked.
	if runs := savedRuns(t, hist); len(runs) != 1 || !runs[0].Busy || runs[0].BusyReason == "" {
		// Report the problem.
		t.Errorf("saved run: %+v", runs)
	} // end of the saved check
} // end of TestPerfBusyMachineWarning

// TestPerfOneTestAtATime checks a second test is refused while one is running, and does not reach the model.
func TestPerfOneTestAtATime(t *testing.T) {
	// A fake that holds the first test request.
	f := newPerfFake()
	// Hold it.
	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
	// Build the rig.
	rig, hist := perfRig(t, f)
	// The first run in the background.
	done := make(chan string)
	// Start it.
	go func() {
		// Run.
		_, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
		// Report.
		done <- body
	}() // end of the goroutine
	// Wait until the first run is inside the model request.
	<-f.entered
	// A second run now.
	_, second, _ := perfPost(t, rig, "/performance/run", "think:1b")
	// It is refused.
	if !strings.Contains(second, "Another performance test is running") {
		// Report the problem.
		t.Errorf("the second test was not refused: %s", second)
	} // end of the refusal check
	// Let the first one finish.
	close(f.release)
	// Wait for it.
	first := <-done
	// The first one completed normally.
	if !strings.Contains(first, "Measured by the test") || len(savedRuns(t, hist)) != 1 {
		// Report the problem.
		t.Errorf("the first test did not complete")
	} // end of the first check
} // end of TestPerfOneTestAtATime

// TestMedian checks the median helper: odd and even counts, unsorted input, and numbers that are not available.
func TestMedian(t *testing.T) {
	// The cases.
	for _, tc := range []struct {
		// in is the input.
		in []float64
		// want is the median.
		want float64
	}{ // the cases follow
		// Odd count, unsorted.
		{[]float64{40, 20, 40}, 40},
		// Even count: the mean of the middle two.
		{[]float64{1, 2, 3, 10}, 2.5},
		// Zeros are ignored.
		{[]float64{0, 5, 0}, 5},
		// Nothing usable.
		{[]float64{0, 0}, 0},
		// Nothing at all.
		{nil, 0},
	} { // end of the cases
		// Check it.
		if got := median(tc.in); got != tc.want {
			// Report the difference.
			t.Errorf("median(%v) = %v, want %v", tc.in, got, tc.want)
		} // end of the check
	} // end of the loop
} // end of TestMedian

// TestChangeText checks the percentage and the words, for speeds (higher is faster) and times (lower is faster).
func TestChangeText(t *testing.T) {
	// The cases.
	for _, tc := range []struct {
		// cur and prev are the two figures.
		cur, prev float64
		// higher says higher is faster.
		higher bool
		// want is the text.
		want string
	}{ // the cases follow
		// A speed that fell by half.
		{20, 40, true, "-50.0% (slower)"},
		// A speed that rose by a quarter.
		{50, 40, true, "+25.0% (faster)"},
		// A time that fell by half.
		{1, 2, false, "-50.0% (faster)"},
		// A time that doubled.
		{2, 1, false, "+100.0% (slower)"},
		// Almost the same.
		{40.1, 40, true, "no change (within 0.5%)"},
		// Missing figure.
		{0, 40, true, "not comparable"},
	} { // end of the cases
		// Check it.
		if got := changeText(tc.cur, tc.prev, tc.higher); got != tc.want {
			// Report the difference.
			t.Errorf("changeText(%v,%v,%v) = %q, want %q", tc.cur, tc.prev, tc.higher, got, tc.want)
		} // end of the check
	} // end of the loop
} // end of TestChangeText

// TestMachineSnapshot checks what is read from the machine, in decimal gigabytes, and what happens for a remote Ollama.
func TestMachineSnapshot(t *testing.T) {
	// A calm fake machine.
	quietMachine(t)
	// Read it as a local machine.
	s := snapshotMachine(context.Background(), true)
	// The figures.
	if !s.Local || s.CPUName != "Test Processor 9000" || s.Load1 != 0.5 || s.MemTotalGB != 16.384 || s.MemFreeGB != 8.192 || s.SwapTotalGB != 2.048 || s.SwapUsedGB != 1.024 || s.GPUName != "Test GPU" || s.GPUUtil != 0 || s.Cores < 1 {
		// Report the problem.
		t.Errorf("snapshot: %+v", s)
	} // end of the figures check
	// A quiet machine is not busy.
	if r := busyReason(s); r != "" {
		// Report the problem.
		t.Errorf("a quiet machine looks busy: %s", r)
	} // end of the quiet check
	// A busy graphics card.
	s.GPUUtil = 96
	// It is named.
	if r := busyReason(s); !strings.Contains(r, "96%") {
		// Report the problem.
		t.Errorf("busy graphics card not noticed: %q", r)
	} // end of the GPU check
	// A busy processor: load above half of the cores.
	s.GPUUtil, s.Cores, s.Load1 = 0, 4, 2.5
	// It is named.
	if r := busyReason(s); !strings.Contains(r, "2.5") {
		// Report the problem.
		t.Errorf("busy processor not noticed: %q", r)
	} // end of the load check
	// Exactly half is not yet busy.
	s.Load1 = 2
	// Not busy.
	if r := busyReason(s); r != "" {
		// Report the problem.
		t.Errorf("load at half of the cores is called busy: %q", r)
	} // end of the boundary check
	// A remote Ollama: nothing is read, and nothing is judged.
	remote := snapshotMachine(context.Background(), false)
	// Only the note.
	if remote.Local || remote.Note == "" || remote.Cores != 0 || remote.MemTotalGB != 0 || busyReason(remote) != "" {
		// Report the problem.
		t.Errorf("remote snapshot: %+v", remote)
	} // end of the remote check
	// A missing graphics tool is not an error.
	gpuQuery = func(ctx context.Context) (string, error) { return "", errors.New("not installed") }
	// Read again.
	if s := snapshotMachine(context.Background(), true); s.GPUName != "" || s.GPUUtil != -1 {
		// Report the problem.
		t.Errorf("a missing tool left traces: %+v", s)
	} // end of the missing-tool check
} // end of TestMachineSnapshot

// TestIsLocalAddress checks which addresses count as this same computer.
func TestIsLocalAddress(t *testing.T) {
	// The cases.
	for raw, want := range map[string]bool{"http://127.0.0.1:11434": true, "http://localhost:11434": true, "http://[::1]:11434": true, "http://192.168.1.20:11434": false, "http://spark.example.org:11434": false} {
		// Parse it.
		u, err := parseOllamaURL(raw)
		// It must parse.
		if err != nil {
			// Stop the test.
			t.Fatalf("%s: %v", raw, err)
		} // end of the parse check
		// Compare.
		if got := isLocalAddress(u); got != want {
			// Report the difference.
			t.Errorf("isLocalAddress(%s) = %v, want %v", raw, got, want)
		} // end of the check
	} // end of the loop
} // end of TestIsLocalAddress

// TestResultForRemoteOllama checks the machine table says why it has no figures when Ollama is on another computer, but still lists the loaded models.
func TestResultForRemoteOllama(t *testing.T) {
	// A run that was made against a remote Ollama.
	run := perfRun{Kind: "generate", Model: "m", PromptVersion: "v1", Runs: 3, OtherLoaded: []string{"x:1b"}}
	// The snapshots say remote.
	run.Before = snapshotMachine(context.Background(), false)
	// The same after.
	run.After = run.Before
	// Build the tables.
	groups := buildGroups(run, nil, map[string]tipView{})
	// The last group is the machine.
	d := groups[len(groups)-1]
	// The note and the one row.
	if !strings.Contains(d.Note, "Ollama is on another computer") || len(d.Rows) != 1 || d.Rows[0].Cells[0] != "x:1b" {
		// Report the problem.
		t.Errorf("remote machine group: %+v", d)
	} // end of the check
} // end of TestResultForRemoteOllama

// TestPerfStoreLimitAndDamage checks the history keeps the newest 200 runs, and leaves a damaged or foreign file alone.
func TestPerfStoreLimitAndDamage(t *testing.T) {
	// A folder of this test.
	dir := t.TempDir()
	// The file.
	path := filepath.Join(dir, "sub", "performance.json")
	// Open (the folder does not exist yet).
	s := openPerfStore(path, "")
	// Add more runs than the limit.
	for i := 1; i <= maxHistoryRuns+5; i++ {
		// One run, numbered by its answer speed.
		if err := s.add(perfRun{Model: "m", Kind: "generate", AnswerSpeed: float64(i)}); err != nil {
			// Stop the test.
			t.Fatalf("add: %v", err)
		} // end of the add check
	} // end of the loop
	// Reopen from the file.
	again := openPerfStore(path, "")
	// The count and the oldest and newest kept.
	runs := again.forModel("m", "generate")
	// Newest first: 205 down to 6.
	if len(runs) != maxHistoryRuns || runs[0].AnswerSpeed != float64(maxHistoryRuns+5) || runs[len(runs)-1].AnswerSpeed != 6 {
		// Report the problem.
		t.Errorf("kept %d runs from %v to %v", len(runs), runs[0].AnswerSpeed, runs[len(runs)-1].AnswerSpeed)
	} // end of the limit check
	// A damaged file and a file of another version.
	for name, content := range map[string]string{"damaged": "{not json", "future": `{"version":99,"runs":[]}`} {
		// Write it.
		bad := filepath.Join(dir, name+".json")
		// The file.
		if err := os.WriteFile(bad, []byte(content), 0o600); err != nil {
			// Stop the test.
			t.Fatalf("write: %v", err)
		} // end of the write check
		// Open it.
		b := openPerfStore(bad, "")
		// Adding a run must keep working in memory and must not touch the file.
		if err := b.add(perfRun{Model: "m", Kind: "generate"}); err != nil {
			// Report the problem.
			t.Errorf("%s: add failed: %v", name, err)
		} // end of the add check
		// The file is unchanged.
		if got, _ := os.ReadFile(bad); string(got) != content {
			// Report the problem.
			t.Errorf("%s: the file was changed", name)
		} // end of the file check
		// The page can say why.
		if _, note := b.where(); note == "" || len(b.forModel("m", "generate")) != 1 {
			// Report the problem.
			t.Errorf("%s: no note or the run is not kept in memory", name)
		} // end of the note check
	} // end of the loop
} // end of TestPerfStoreLimitAndDamage

// TestMainPagePerformanceIcon checks every model that is not loaded has the chart icon before its name with a tip, and a loaded model has an empty slot instead.
func TestMainPagePerformanceIcon(t *testing.T) {
	// A fake with the chat model loaded.
	f := newPerfFake()
	// Loaded.
	f.loaded["chat:1b"] = true
	// Build the rig.
	rig, _ := perfRig(t, f)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// A not-loaded model has the icon, its label, its tip and its form, and the icon is before the name.
	row := body[strings.Index(body, `<tr data-model="embed:1b"`):]
	// The cell of the row heading.
	cell := row[:strings.Index(row, "</th>")]
	// Everything must be in the cell, and the name must come last.
	for _, want := range []string{`action="/performance"`, `aria-label="Performance of embed:1b"`, `id="tipperf-embed:1b"`, "Performance: see how fast this model runs on this machine", `<svg class="ico"`} {
		// Look for it.
		if !strings.Contains(cell, want) {
			// Report the gap.
			t.Errorf("the row heading lacks %q", want)
		} // end of the check
	} // end of the loop
	// The name comes after the icon.
	if !strings.HasSuffix(strings.TrimSpace(cell), "embed:1b") || strings.Index(cell, `<svg class="ico"`) > strings.LastIndex(cell, "embed:1b") {
		// Report the problem.
		t.Errorf("the icon is not before the name")
	} // end of the order check
	// The loaded model has no icon, and only the three others have one.
	if strings.Contains(body, `aria-label="Performance of chat:1b"`) || strings.Count(body, `action="/performance"`) != 3 {
		// Report the problem.
		t.Errorf("a loaded model has the performance icon, or the count is wrong: %d", strings.Count(body, `action="/performance"`))
	} // end of the loaded check
} // end of TestMainPagePerformanceIcon

// TestMain keeps every test away from the person's real configuration folder.
func TestMain(m *testing.M) {
	// A folder for the whole test run.
	dir, err := os.MkdirTemp("", "occ-test-config-")
	// Without it the tests cannot be made safe.
	if err != nil {
		// Stop.
		panic(err)
	} // end of the folder check
	// Use it as the configuration folder.
	userConfigDir = func() (string, error) { return dir, nil }
	// The program's own place is not used by the tests, so no test can write a folder next to the test program.
	executablePath = func() (string, error) { return "", errors.New("not used in tests") }
	// Run the tests.
	code := m.Run()
	// Remove the folder.
	os.RemoveAll(dir)
	// Leave with the tests' result.
	os.Exit(code)
} // end of TestMain

// TestDefaultHistoryPath checks where the saved results go: next to the project when the program runs from its bin folder, next to the program elsewhere, and in the configuration folder when the program's place is unknown.
func TestDefaultHistoryPath(t *testing.T) {
	// Put the real lookups back when the test ends.
	oldExe, oldCfg := executablePath, userConfigDir
	// Restore them.
	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
	// The configuration folder, for the fallback.
	userConfigDir = func() (string, error) { return "/cfg", nil }
	// The cases.
	for _, c := range []struct {
		// exe is where the program is.
		exe string
		// err is the failure of the lookup, when there is one.
		err error
		// want is the expected file.
		want string
	}{
		// From the bin folder of the project.
		{"/home/u/OllamaControlCenter/bin/OllamaControlCenter", nil, "/home/u/OllamaControlCenter/PerformanceCompare/performance.json"},
		// From any other folder: next to the program.
		{"/opt/occ/OllamaControlCenter", nil, "/opt/occ/PerformanceCompare/performance.json"},
		// Unknown place: the configuration folder.
		{"", errors.New("no path"), "/cfg/OllamaControlCenter/performance.json"},
	} {
		// Use this case.
		executablePath = func() (string, error) { return c.exe, c.err }
		// Ask.
		got, note := defaultHistoryPath()
		// Compare.
		if filepath.ToSlash(got) != c.want || note != "" {
			// Report it.
			t.Errorf("exe %q: path %q note %q, want %q", c.exe, got, note, c.want)
		} // end of the check
	} // end of the loop
	// No program place and no configuration folder: memory only, with a reason.
	executablePath = func() (string, error) { return "", errors.New("no path") }
	// No folder either.
	userConfigDir = func() (string, error) { return "", errors.New("none") }
	// Ask.
	if got, note := defaultHistoryPath(); got != "" || note == "" {
		// Report it.
		t.Errorf("memory-only case: %q / %q", got, note)
	} // end of the memory check
} // end of TestDefaultHistoryPath
