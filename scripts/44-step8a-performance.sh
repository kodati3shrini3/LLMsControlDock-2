#!/usr/bin/env bash
# Script 44: adds the performance test (chart icon, test page, saved results, comparison, machine condition).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-performance-test" ] || { echo "FAIL  not on feature/model-performance-test"; exit 1; }
# Script 42 must be applied first (it creates modelfile.go).
[ -f modelfile.go ] || { echo "FAIL  script 42 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -f perf.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/gear_test.go b/gear_test.go
index 72a1551..b0dcd31 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -1233,8 +1233,8 @@ func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
 		// Report the problem.
 		t.Errorf("a loaded model has a gear")
 	} // end of the loaded check
-	// The loaded row has the empty slot.
-	if strings.Count(body, `class="gearslot"`) != 1 {
+	// The loaded row has two empty slots: one where the performance icon would be, one where the gear would be.
+	if strings.Count(body, `class="gearslot"`) != 2 {
 		// Report the problem.
 		t.Errorf("the loaded row has no empty gear slot")
 	} // end of the slot check
diff --git a/machine.go b/machine.go
new file mode 100644
index 0000000..244d5b9
--- /dev/null
+++ b/machine.go
@@ -0,0 +1,212 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context lets the graphics-card query be cancelled.
+	"context"
+	// net/url holds the parsed address type.
+	"net/url"
+	// os reads the files that describe the machine.
+	"os"
+	// os/exec runs the graphics-card tool, only when it is already installed.
+	"os/exec"
+	// path/filepath joins the folder and file names.
+	"path/filepath"
+	// runtime tells how many processor cores there are.
+	"runtime"
+	// strconv turns text into numbers.
+	"strconv"
+	// strings splits and trims text.
+	"strings"
+	// time limits the graphics-card query.
+	"time"
+) // end of imports
+
+// machineSnapshot is what the monitor can read about the machine at one moment; every part says whether it was reported.
+type machineSnapshot struct {
+	// Local is true when Ollama runs on the same computer as the monitor, so the figures below describe the right machine.
+	Local bool `json:"local"`
+	// Note explains why nothing was read (Ollama on another computer).
+	Note string `json:"note,omitempty"`
+	// Cores is the number of logical processor cores.
+	Cores int `json:"cores,omitempty"`
+	// CPUName is the processor name, or empty when the system does not report one.
+	CPUName string `json:"cpu_name,omitempty"`
+	// Load1 is the load average of the last minute, or -1 when not reported.
+	Load1 float64 `json:"load1"`
+	// MemTotalGB is the total memory in gigabytes, or 0 when not reported.
+	MemTotalGB float64 `json:"mem_total_gb,omitempty"`
+	// MemFreeGB is the memory available for new work in gigabytes, or 0 when not reported.
+	MemFreeGB float64 `json:"mem_free_gb,omitempty"`
+	// SwapTotalGB is the swap space in gigabytes.
+	SwapTotalGB float64 `json:"swap_total_gb,omitempty"`
+	// SwapUsedGB is the swap space in use in gigabytes, or -1 when not reported.
+	SwapUsedGB float64 `json:"swap_used_gb"`
+	// GPUName is the graphics card name, or empty when no tool reported one.
+	GPUName string `json:"gpu_name,omitempty"`
+	// GPUMemory is the graphics memory use as the tool printed it (shared-memory machines print "[N/A]"), or empty.
+	GPUMemory string `json:"gpu_memory,omitempty"`
+	// GPUUtil is the graphics card's busy percentage at that moment, or -1 when not reported.
+	GPUUtil int `json:"gpu_util"`
+} // end of machineSnapshot
+
+// procDir is where Linux describes the machine; a test points it at a folder of its own.
+var procDir = "/proc"
+
+// gpuQuery asks the graphics-card tool for one CSV line; a test replaces it. The tool is never required.
+var gpuQuery = func(ctx context.Context) (string, error) {
+	// Look for the tool; a machine without it simply reports nothing.
+	exe, err := exec.LookPath("nvidia-smi")
+	// Not installed.
+	if err != nil {
+		// Hand the error back; the caller treats it as "not reported".
+		return "", err
+	} // end of the lookup check
+	// Never wait more than ten seconds for it.
+	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
+	// Release the timer at the end.
+	defer cancel()
+	// Run it with fixed arguments only; nothing typed by a person ever reaches this command.
+	out, err := exec.CommandContext(ctx, exe, "--query-gpu=name,memory.used,memory.total,utilization.gpu", "--format=csv,noheader").Output()
+	// Hand back the text and any error.
+	return strings.TrimSpace(string(out)), err
+} // end of gpuQuery
+
+// isLocalAddress reports whether the address points at this same computer.
+func isLocalAddress(u *url.URL) bool {
+	// The host name without the port.
+	h := u.Hostname()
+	// The usual names for "this computer".
+	return h == "127.0.0.1" || h == "localhost" || h == "::1"
+} // end of isLocalAddress
+
+// readKB reads the memory table of /proc/meminfo into a map of kilobytes.
+func readKB() map[string]float64 {
+	// The result.
+	out := map[string]float64{}
+	// Read the file; a missing file gives an empty table.
+	data, err := os.ReadFile(filepath.Join(procDir, "meminfo"))
+	// Not readable.
+	if err != nil {
+		// Nothing to report.
+		return out
+	} // end of the read check
+	// Go through the lines.
+	for _, line := range strings.Split(string(data), "\n") {
+		// A line looks like "MemTotal:  127000 kB".
+		f := strings.Fields(line)
+		// Skip lines of another shape.
+		if len(f) < 2 {
+			// Next line.
+			continue
+		} // end of the shape check
+		// Read the number.
+		if v, err := strconv.ParseFloat(f[1], 64); err == nil {
+			// Store it under the name without the colon.
+			out[strings.TrimSuffix(f[0], ":")] = v
+		} // end of the number check
+	} // end of the loop
+	// Hand back the table.
+	return out
+} // end of readKB
+
+// snapshotMachine reads what the machine says about itself; for Ollama on another computer it reports only that.
+func snapshotMachine(ctx context.Context, local bool) machineSnapshot {
+	// Start with "not reported" values.
+	s := machineSnapshot{Local: local, Load1: -1, SwapUsedGB: -1, GPUUtil: -1}
+	// Ollama is elsewhere: these figures would describe the wrong computer.
+	if !local {
+		// Say so.
+		s.Note = "Ollama is on another computer, so this computer's figures would not describe it."
+		// Stop here.
+		return s
+	} // end of the remote case
+	// The processor count is always known.
+	s.Cores = runtime.NumCPU()
+	// The processor name, when Linux lists one.
+	if data, err := os.ReadFile(filepath.Join(procDir, "cpuinfo")); err == nil {
+		// Look for the first "model name" line.
+		for _, line := range strings.Split(string(data), "\n") {
+			// Found.
+			if strings.HasPrefix(strings.ToLower(line), "model name") {
+				// Keep the text after the colon.
+				if i := strings.Index(line, ":"); i >= 0 {
+					// Trim spaces.
+					s.CPUName = strings.TrimSpace(line[i+1:])
+				} // end of the colon check
+				// Only the first one.
+				break
+			} // end of the name check
+		} // end of the loop
+	} // end of the cpuinfo read
+	// The load average: the first number is the last minute.
+	if data, err := os.ReadFile(filepath.Join(procDir, "loadavg")); err == nil {
+		// Split into numbers.
+		if f := strings.Fields(string(data)); len(f) > 0 {
+			// Read the first.
+			if v, err := strconv.ParseFloat(f[0], 64); err == nil {
+				// Keep it.
+				s.Load1 = v
+			} // end of the number check
+		} // end of the field check
+	} // end of the loadavg read
+	// Memory in kilobytes (1024 bytes each); gigabytes are decimal, like every size the monitor shows (1 GB = 1,000,000,000 bytes).
+	kb := readKB()
+	// Total and available memory.
+	s.MemTotalGB, s.MemFreeGB = kb["MemTotal"]*1024/1e9, kb["MemAvailable"]*1024/1e9
+	// Swap, only when the machine reports a swap total at all.
+	if t, ok := kb["SwapTotal"]; ok {
+		// Total swap.
+		s.SwapTotalGB = t * 1024 / 1e9
+		// Swap in use is total minus free.
+		s.SwapUsedGB = (t - kb["SwapFree"]) * 1024 / 1e9
+	} // end of the swap check
+	// The graphics card, when its own tool is already on the machine.
+	if line, err := gpuQuery(ctx); err == nil && line != "" {
+		// The line is "name, memory used, memory total, utilization".
+		parts := strings.Split(strings.SplitN(line, "\n", 2)[0], ",")
+		// Trim each part.
+		for i := range parts {
+			// Remove spaces around it.
+			parts[i] = strings.TrimSpace(parts[i])
+		} // end of the trim loop
+		// The name.
+		s.GPUName = parts[0]
+		// The memory: used and total, as printed.
+		if len(parts) >= 3 {
+			// Shared-memory machines print [N/A] for both.
+			s.GPUMemory = parts[1] + " of " + parts[2]
+		} // end of the memory check
+		// The busy percentage, like "96 %".
+		if len(parts) >= 4 {
+			// Remove the percent sign and spaces.
+			if v, err := strconv.Atoi(strings.TrimSpace(strings.TrimSuffix(parts[3], "%"))); err == nil {
+				// Keep it.
+				s.GPUUtil = v
+			} // end of the number check
+		} // end of the util check
+	} // end of the GPU query
+	// Hand back everything that was read.
+	return s
+} // end of snapshotMachine
+
+// busyReason says why the machine looked busy before the test, or returns an empty text when it did not.
+func busyReason(s machineSnapshot) string {
+	// Figures from another computer say nothing about this one.
+	if !s.Local {
+		// Not judged.
+		return ""
+	} // end of the remote case
+	// The graphics card was working.
+	if s.GPUUtil > 10 {
+		// Say so with the figure.
+		return "the graphics card was " + strconv.Itoa(s.GPUUtil) + "% busy before the test"
+	} // end of the GPU check
+	// The processor had a lot to do: the one-minute load above half the cores.
+	if s.Cores > 0 && s.Load1 > float64(s.Cores)/2 {
+		// Say so with the figures.
+		return "the processor load (" + strconv.FormatFloat(s.Load1, 'f', 1, 64) + ") was above half of its " + strconv.Itoa(s.Cores) + " cores before the test"
+	} // end of the load check
+	// Nothing unusual.
+	return ""
+} // end of busyReason
diff --git a/perf.go b/perf.go
new file mode 100644
index 0000000..942ff96
--- /dev/null
+++ b/perf.go
@@ -0,0 +1,485 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bufio reads the streamed reply piece by piece.
+	"bufio"
+	// bytes wraps the request body.
+	"bytes"
+	// context lets a test be cancelled or given a deadline.
+	"context"
+	// encoding/json reads and writes Ollama's messages.
+	"encoding/json"
+	// errors builds plain error values.
+	"errors"
+	// fmt builds formatted text.
+	"fmt"
+	// io limits how much of a reply is read.
+	"io"
+	// net/http sends the requests.
+	"net/http"
+	// net/url holds the parsed address type.
+	"net/url"
+	// sort puts numbers in order for the median.
+	"sort"
+	// strings trims text.
+	"strings"
+	// time measures how long things take.
+	"time"
+) // end of imports
+
+// perfPromptVersion names the fixed prompt; saved runs carry it, so only runs with the same prompt are compared.
+const perfPromptVersion = "v1"
+
+// perfPrompt is the fixed prompt of every test (about 200 tokens, so the prompt reading speed is a real figure). It is the program's own text; no text of the person is ever sent or stored.
+const perfPrompt = "Read the following passage and then answer the question after it. " +
+	"A lighthouse stands on a narrow headland where the sea is rough for most of the year. " +
+	"Its keeper climbs the spiral staircase every evening, checks the lamp, polishes the lens and writes the weather in a thick logbook. " +
+	"Ships that pass at night rely on the rhythm of the light to know which stretch of coast they are near, because every lighthouse flashes in its own pattern. " +
+	"On clear days the keeper repairs the stone steps, paints the iron railings and counts the gulls that nest in the cliffs. " +
+	"When fog rolls in, the keeper sounds a horn every thirty seconds, and the long, low note carries far across the water. " +
+	"Supplies arrive once a month by boat, and the keeper trades news and tea with the crew before they sail away again. " +
+	"In winter the storms are so strong that waves climb the rocks and spray reaches the windows near the top of the tower. " +
+	"Question: In two sentences, what does the keeper do to keep ships safe?"
+
+// perfTimedRuns is how many timed runs follow the warm-up run; the saved figure is their median.
+const perfTimedRuns = 3
+
+// perfAnswerTokens caps the length of every answer, so every run does the same amount of work.
+const perfAnswerTokens = 64
+
+// perfRequestTimeout is how long one request of the test may take; a very large model can need minutes to load.
+const perfRequestTimeout = 10 * time.Minute
+
+// maxPerfReply caps how many bytes of one test reply are read (64 MiB, far more than the real reply).
+const maxPerfReply = 64 * 1024 * 1024
+
+// maxHistoryRuns is how many runs the history keeps; older ones are dropped.
+const maxHistoryRuns = 200
+
+// perfFigures is what one request of the test reported, in Ollama's own units (durations in nanoseconds).
+type perfFigures struct {
+	// TotalNs is the whole request.
+	TotalNs int64
+	// LoadNs is the time to bring the model into memory.
+	LoadNs int64
+	// PromptCount is how many tokens the prompt had.
+	PromptCount int64
+	// PromptNs is the time spent reading the prompt.
+	PromptNs int64
+	// EvalCount is how many tokens the model wrote.
+	EvalCount int64
+	// EvalNs is the time spent writing them.
+	EvalNs int64
+	// FirstWord is the time until the first piece of output arrived, measured by this program on a streamed reply.
+	FirstWord time.Duration
+	// GotFirstWord is true when a first piece of output was seen.
+	GotFirstWord bool
+	// VectorLength is the length of the first embedding vector (embedding models only).
+	VectorLength int
+} // end of perfFigures
+
+// perfRun is one saved test: numbers and names only, never any text of a prompt or an answer. A zero in a speed or time field means "not available".
+type perfRun struct {
+	// Time is when the test finished, in UTC.
+	Time time.Time `json:"time"`
+	// Model is the tested model.
+	Model string `json:"model"`
+	// Kind is generate for chat models and embedding for embedding models.
+	Kind string `json:"kind"`
+	// OllamaVersion is the version Ollama reported.
+	OllamaVersion string `json:"ollama_version"`
+	// Host is the address part of the Ollama address (no password).
+	Host string `json:"host"`
+	// PromptVersion names the fixed prompt.
+	PromptVersion string `json:"prompt_version"`
+	// Runs is how many timed runs the medians come from.
+	Runs int `json:"runs"`
+	// AnswerSpeed is the median answer speed in tokens per second.
+	AnswerSpeed float64 `json:"answer_speed,omitempty"`
+	// PromptSpeed is the median prompt reading speed in tokens per second.
+	PromptSpeed float64 `json:"prompt_speed,omitempty"`
+	// ColdLoadSec is the load time of the warm-up run, which loaded the model.
+	ColdLoadSec float64 `json:"cold_load_sec,omitempty"`
+	// ColdFirstWordSec is the measured time to the first word of the warm-up run.
+	ColdFirstWordSec float64 `json:"cold_first_word_sec,omitempty"`
+	// WarmFirstWordSec is the median measured time to the first word of the timed runs.
+	WarmFirstWordSec float64 `json:"warm_first_word_sec,omitempty"`
+	// WarmTotalSec is the median total time of the timed runs (for an embedding model, the embedding time).
+	WarmTotalSec float64 `json:"warm_total_sec,omitempty"`
+	// TokensIn is the number of prompt tokens.
+	TokensIn int64 `json:"tokens_in,omitempty"`
+	// TokensOut is the number of tokens written.
+	TokensOut int64 `json:"tokens_out,omitempty"`
+	// VectorLength is the length of an embedding vector.
+	VectorLength int `json:"vector_length,omitempty"`
+	// ModelBytes is the memory Ollama reports for the loaded model.
+	ModelBytes int64 `json:"model_bytes,omitempty"`
+	// GPUBytes is how much of it sits in graphics memory.
+	GPUBytes int64 `json:"gpu_bytes,omitempty"`
+	// ContextLength is the context the model was loaded with.
+	ContextLength int64 `json:"context_length,omitempty"`
+	// OtherLoaded lists the models that were loaded when the test started.
+	OtherLoaded []string `json:"other_loaded,omitempty"`
+	// Busy is true when the machine looked busy before the test.
+	Busy bool `json:"busy"`
+	// BusyReason says why.
+	BusyReason string `json:"busy_reason,omitempty"`
+	// Before and After are the machine snapshots around the test.
+	Before machineSnapshot `json:"before"`
+	// After is the snapshot after the timed runs, with the model still loaded.
+	After machineSnapshot `json:"after"`
+	// LeftLoaded is true when the model could not be unloaded again.
+	LeftLoaded bool `json:"left_loaded,omitempty"`
+} // end of perfRun
+
+// secs turns nanoseconds into seconds.
+func secs(ns int64) float64 {
+	// One second is a billion nanoseconds.
+	return float64(ns) / 1e9
+} // end of secs
+
+// perSecond turns a count and a duration in nanoseconds into a speed per second; zero means it cannot be worked out.
+func perSecond(count, ns int64) float64 {
+	// A speed needs both numbers.
+	if count <= 0 || ns <= 0 {
+		// Not available.
+		return 0
+	} // end of the check
+	// Count divided by seconds.
+	return float64(count) / secs(ns)
+} // end of perSecond
+
+// median returns the middle value of the numbers above zero; zero when there are none. With an even count it is the mean of the two in the middle.
+func median(vals []float64) float64 {
+	// Keep only usable numbers.
+	var v []float64
+	// Go through the input.
+	for _, x := range vals {
+		// A zero means "not available".
+		if x > 0 {
+			// Keep it.
+			v = append(v, x)
+		} // end of the check
+	} // end of the loop
+	// Nothing usable.
+	if len(v) == 0 {
+		// Not available.
+		return 0
+	} // end of the empty check
+	// Put them in order.
+	sort.Float64s(v)
+	// The middle.
+	mid := len(v) / 2
+	// An odd count has one middle value.
+	if len(v)%2 == 1 {
+		// Return it.
+		return v[mid]
+	} // end of the odd case
+	// An even count: the mean of the two middle values.
+	return (v[mid-1] + v[mid]) / 2
+} // end of median
+
+// genPiece is one line of a streamed /api/generate reply.
+type genPiece struct {
+	// Response is the next piece of the answer text (never stored).
+	Response string `json:"response"`
+	// Thinking is the next piece of a thinking model's reasoning text (never stored).
+	Thinking string `json:"thinking"`
+	// Done is true on the last piece, which carries the figures.
+	Done bool `json:"done"`
+	// Error is Ollama's own message when the request failed.
+	Error string `json:"error"`
+	// TotalDuration is the whole request in nanoseconds.
+	TotalDuration int64 `json:"total_duration"`
+	// LoadDuration is the load time in nanoseconds.
+	LoadDuration int64 `json:"load_duration"`
+	// PromptEvalCount is the number of prompt tokens.
+	PromptEvalCount int64 `json:"prompt_eval_count"`
+	// PromptEvalDuration is the prompt reading time in nanoseconds.
+	PromptEvalDuration int64 `json:"prompt_eval_duration"`
+	// EvalCount is the number of tokens written.
+	EvalCount int64 `json:"eval_count"`
+	// EvalDuration is the writing time in nanoseconds.
+	EvalDuration int64 `json:"eval_duration"`
+} // end of genPiece
+
+// shortMessage keeps the start of a refusal text, so a long reply never fills the page.
+func shortMessage(b []byte) string {
+	// Ollama's own error shape.
+	var e struct {
+		// Error is the message.
+		Error string `json:"error"`
+	} // end of the shape
+	// Try to read it; on failure the raw text is used.
+	_ = json.Unmarshal(b, &e)
+	// The message or the raw text.
+	msg := strings.TrimSpace(e.Error)
+	// No JSON message: use the raw text.
+	if msg == "" {
+		// Raw text.
+		msg = strings.TrimSpace(string(b))
+	} // end of the fallback
+	// Keep at most 200 bytes.
+	if len(msg) > 200 {
+		// Cut it.
+		msg = msg[:200]
+	} // end of the cut
+	// Hand it back.
+	return msg
+} // end of shortMessage
+
+// runGenerate sends the fixed prompt once, reads the streamed reply and returns the figures; the first word is timed by this program.
+func runGenerate(ctx context.Context, base *url.URL, model string) (perfFigures, error) {
+	// Build the request body: the model, the fixed prompt, a stream, a keep-alive so the model stays for the next run, and options that keep every run alike.
+	body, err := json.Marshal(map[string]any{"model": model, "prompt": perfPrompt, "stream": true, "keep_alive": "2m", "options": map[string]any{"num_predict": perfAnswerTokens, "temperature": 0, "seed": 1}})
+	// A marshal failure cannot happen with these values; report it plainly if it ever does.
+	if err != nil {
+		// Plain message.
+		return perfFigures{}, errors.New("the request could not be built")
+	} // end of the marshal check
+	// Give the request a deadline.
+	ctx, cancel := context.WithTimeout(ctx, perfRequestTimeout)
+	// Release the timer at the end.
+	defer cancel()
+	// Build the request.
+	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base.JoinPath("api/generate").String(), bytes.NewReader(body))
+	// The address could not be used.
+	if err != nil {
+		// Plain message.
+		return perfFigures{}, errors.New("the address could not be used to build a request")
+	} // end of the request check
+	// The body is JSON.
+	req.Header.Set("Content-Type", "application/json")
+	// Remember when the request starts.
+	start := time.Now()
+	// Send it; the client has no timeout of its own, the deadline above rules.
+	resp, err := (&http.Client{}).Do(req)
+	// Ollama could not be reached.
+	if err != nil {
+		// Say why in plain words.
+		return perfFigures{}, errors.New(explainError(err))
+	} // end of the send check
+	// Close the reply at the end.
+	defer resp.Body.Close()
+	// Any status but 200 is a refusal; read its short message.
+	if resp.StatusCode != http.StatusOK {
+		// Read the start of the body.
+		b, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
+		// Say what Ollama said.
+		return perfFigures{}, fmt.Errorf("Ollama refused the test request (status %d): %s", resp.StatusCode, shortMessage(b))
+	} // end of the status check
+	// Read the reply line by line, with a cap on the total size.
+	rd := bufio.NewReaderSize(io.LimitReader(resp.Body, maxPerfReply), 64*1024)
+	// The figures to build.
+	var f perfFigures
+	// Whether the last piece arrived.
+	finished := false
+	// Read until the end.
+	for {
+		// One line.
+		line, rerr := rd.ReadBytes('\n')
+		// A non-empty line is one piece.
+		if len(bytes.TrimSpace(line)) > 0 {
+			// Decode it.
+			var p genPiece
+			// A broken piece means this is not Ollama's stream.
+			if err := json.Unmarshal(line, &p); err != nil {
+				// Plain message.
+				return perfFigures{}, errors.New("the reply was not the expected JSON, so it does not look like Ollama")
+			} // end of the decode check
+			// Ollama reported an error inside the stream.
+			if p.Error != "" {
+				// Say what it said, shortened.
+				return perfFigures{}, fmt.Errorf("Ollama stopped the test: %s", shortMessage(line))
+			} // end of the error check
+			// The first piece of output, whether answer or reasoning, ends the wait for the first word.
+			if !f.GotFirstWord && (p.Response != "" || p.Thinking != "") {
+				// Remember how long it took.
+				f.FirstWord, f.GotFirstWord = time.Since(start), true
+			} // end of the first word check
+			// The last piece carries the figures.
+			if p.Done {
+				// Copy them.
+				f.TotalNs, f.LoadNs, f.PromptCount, f.PromptNs, f.EvalCount, f.EvalNs = p.TotalDuration, p.LoadDuration, p.PromptEvalCount, p.PromptEvalDuration, p.EvalCount, p.EvalDuration
+				// Done.
+				finished = true
+			} // end of the done check
+		} // end of the piece check
+		// The end of the reply or a read problem.
+		if rerr != nil {
+			// Leave the loop.
+			break
+		} // end of the end check
+	} // end of the read loop
+	// A stream that ends without its last piece is incomplete.
+	if !finished {
+		// Plain message.
+		return perfFigures{}, errors.New("the reply ended before Ollama reported its figures")
+	} // end of the finished check
+	// Hand the figures back.
+	return f, nil
+} // end of runGenerate
+
+// embedReply is the part of an /api/embed reply that the test uses.
+type embedReply struct {
+	// Embeddings is one vector per input text.
+	Embeddings [][]float64 `json:"embeddings"`
+	// TotalDuration is the whole request in nanoseconds.
+	TotalDuration int64 `json:"total_duration"`
+	// LoadDuration is the load time in nanoseconds.
+	LoadDuration int64 `json:"load_duration"`
+	// PromptEvalCount is the number of tokens of the text.
+	PromptEvalCount int64 `json:"prompt_eval_count"`
+} // end of embedReply
+
+// runEmbed embeds the fixed text once and returns the figures.
+func runEmbed(ctx context.Context, base *url.URL, model string) (perfFigures, error) {
+	// A place for the reply.
+	var r embedReply
+	// Send the request; the keep-alive keeps the model loaded for the next run.
+	status, msg, err := postForReply(ctx, base, "api/embed", perfRequestTimeout, map[string]any{"model": model, "input": perfPrompt, "keep_alive": "2m"}, &r)
+	// Ollama could not be reached or answered with something unexpected.
+	if err != nil {
+		// Pass the plain message on.
+		return perfFigures{}, err
+	} // end of the send check
+	// Any status but 200 is a refusal.
+	if status != http.StatusOK {
+		// Say what Ollama said.
+		return perfFigures{}, fmt.Errorf("Ollama refused the test request (status %d): %s", status, msg)
+	} // end of the status check
+	// The figures.
+	f := perfFigures{TotalNs: r.TotalDuration, LoadNs: r.LoadDuration, PromptCount: r.PromptEvalCount}
+	// The vector length.
+	if len(r.Embeddings) > 0 {
+		// The first vector.
+		f.VectorLength = len(r.Embeddings[0])
+	} // end of the vector check
+	// Hand the figures back.
+	return f, nil
+} // end of runEmbed
+
+// performTest runs the whole test on one model that is not loaded: one warm-up run (which loads it), then timed runs, then it reads what Ollama reports and unloads the model again. The result holds numbers only.
+func performTest(ctx context.Context, base *url.URL, model string, embedding bool, version string) (run perfRun, err error) {
+	// Is Ollama on this same computer? Only then do the machine figures describe it.
+	local := isLocalAddress(base)
+	// The result starts with the facts known before the test.
+	run = perfRun{Time: time.Now().UTC(), Model: model, Kind: "generate", OllamaVersion: version, Host: base.Host, PromptVersion: perfPromptVersion, Runs: perfTimedRuns}
+	// An embedding model is tested differently.
+	if embedding {
+		// Mark it.
+		run.Kind = "embedding"
+	} // end of the kind check
+	// The machine before the test.
+	run.Before = snapshotMachine(ctx, local)
+	// Whether it looked busy.
+	run.BusyReason = busyReason(run.Before)
+	// The flag.
+	run.Busy = run.BusyReason != ""
+	// The models that are loaded now (the test only starts when the tested model is not among them).
+	if list, lerr := fetchLoaded(ctx, base, defaultCheckTimeout); lerr == nil {
+		// Their names.
+		for _, m := range list {
+			// Keep each.
+			run.OtherLoaded = append(run.OtherLoaded, m.Name)
+		} // end of the loop
+	} // end of the loaded read
+	// From the first request on the model may be in memory, so it must be unloaded however the test ends.
+	started := false
+	// The cleanup: unload and check; it uses a context that survives a closed browser page.
+	defer func() {
+		// Nothing was sent, nothing to unload.
+		if !started {
+			// Leave.
+			return
+		} // end of the started check
+		// A context that is not cancelled when the person closes the page.
+		c := context.WithoutCancel(ctx)
+		// Ask Ollama to unload it (the same call the Unload button uses).
+		_, uerr := unloadModel(c, base, model, unloadTimeout)
+		// Whether it is gone.
+		gone := false
+		// Check only when the request was accepted.
+		if uerr == nil {
+			// Wait until the loaded list no longer holds it.
+			gone, _ = waitUntilGone(c, base, model, defaultCheckTimeout)
+		} // end of the unload check
+		// Tell the person when it is still loaded.
+		run.LeftLoaded = !gone
+	}() // end of the cleanup
+	// one runs one request of the right kind.
+	one := func() (perfFigures, error) {
+		// From now on the model may be loaded.
+		started = true
+		// An embedding model.
+		if embedding {
+			// Embed the fixed text.
+			return runEmbed(ctx, base, model)
+		} // end of the embedding case
+		// A chat model.
+		return runGenerate(ctx, base, model)
+	} // end of one
+	// The warm-up run: it loads the model, so its load time and first word are the cold figures.
+	cold, err := one()
+	// The test failed.
+	if err != nil {
+		// Report it.
+		return run, err
+	} // end of the warm-up check
+	// The timed runs, with the model already loaded.
+	var timed []perfFigures
+	// Run them one after the other.
+	for i := 0; i < perfTimedRuns; i++ {
+		// One run.
+		f, err := one()
+		// The test failed.
+		if err != nil {
+			// Report it.
+			return run, err
+		} // end of the check
+		// Keep the figures.
+		timed = append(timed, f)
+	} // end of the timed loop
+	// Collect each figure over the timed runs.
+	var answer, prompt, firstWord, total []float64
+	// Go through the runs.
+	for _, f := range timed {
+		// Answer speed.
+		answer = append(answer, perSecond(f.EvalCount, f.EvalNs))
+		// Prompt reading speed.
+		prompt = append(prompt, perSecond(f.PromptCount, f.PromptNs))
+		// First word, when one was seen.
+		if f.GotFirstWord {
+			// Keep it in seconds.
+			firstWord = append(firstWord, f.FirstWord.Seconds())
+		} // end of the first word check
+		// Total time.
+		total = append(total, secs(f.TotalNs))
+	} // end of the loop
+	// The medians.
+	run.AnswerSpeed, run.PromptSpeed, run.WarmFirstWordSec, run.WarmTotalSec = median(answer), median(prompt), median(firstWord), median(total)
+	// The cold figures.
+	run.ColdLoadSec = secs(cold.LoadNs)
+	// The cold first word.
+	if cold.GotFirstWord {
+		// In seconds.
+		run.ColdFirstWordSec = cold.FirstWord.Seconds()
+	} // end of the cold first word check
+	// The sizes of the test, from the last timed run.
+	last := timed[len(timed)-1]
+	// Tokens in and out, and the vector length.
+	run.TokensIn, run.TokensOut, run.VectorLength = last.PromptCount, last.EvalCount, last.VectorLength
+	// What Ollama reports about the loaded model.
+	if list, lerr := fetchLoaded(ctx, base, defaultCheckTimeout); lerr == nil {
+		// Find the tested model.
+		if m, ok := findLoaded(list, model); ok {
+			// Its memory, graphics memory and context.
+			run.ModelBytes, run.GPUBytes, run.ContextLength = m.Size, m.SizeVRAM, m.ContextLength
+		} // end of the find check
+	} // end of the loaded read
+	// The machine after the timed runs, with the model still in memory.
+	run.After = snapshotMachine(ctx, local)
+	// Done; the deferred cleanup unloads the model.
+	return run, nil
+} // end of performTest
diff --git a/perf_test.go b/perf_test.go
new file mode 100644
index 0000000..72c2a80
--- /dev/null
+++ b/perf_test.go
@@ -0,0 +1,1089 @@
+// Package main tells Go that this test file belongs to the same program as perf.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// context is needed by the GPU query replacement.
+	"context"
+	// encoding/json reads the requests the fake receives and the saved file.
+	"encoding/json"
+	// errors builds the "no tool" error of the GPU query replacement.
+	"errors"
+	// fmt builds text.
+	"fmt"
+	// net/http provides requests and status codes.
+	"net/http"
+	// net/url builds form data.
+	"net/url"
+	// os reads and writes the files of the tests.
+	"os"
+	// path/filepath joins file names.
+	"path/filepath"
+	// runtime tells the operating system, because file permissions differ on Windows.
+	"runtime"
+	// strings searches the page text.
+	"strings"
+	// sync protects the fake's records.
+	"sync"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// secretText is the answer text of the fake; it must never reach a page of the monitor's own making or the saved file.
+const secretText = "SECRET-ANSWER-TEXT"
+
+// perfFake is a fake Ollama for the performance tests: it loads a model on the first request, streams an answer, and reports figures that differ per request so the median can be told from the mean.
+type perfFake struct {
+	// mu protects every field below.
+	mu sync.Mutex
+	// loaded is the set of models in memory.
+	loaded map[string]bool
+	// testCalls counts the generate and embed requests that are not unload requests.
+	testCalls int
+	// unloads records every unload request.
+	unloads []string
+	// failAt is the index (from 1) of the test request that fails; zero means none fail.
+	failAt int
+	// thinking makes the stream carry a thinking field instead of a response field.
+	thinking bool
+	// stuck makes unload requests do nothing.
+	stuck bool
+	// evalScale multiplies the answer durations, so a second run can be slower.
+	evalScale float64
+	// hold makes the first test request wait until release is closed, so a test can look at a running test.
+	hold bool
+	// entered is signalled when the first test request has arrived.
+	entered chan struct{}
+	// release lets the first test request go on when it is closed.
+	release chan struct{}
+} // end of perfFake
+
+// newPerfFake builds a fake with nothing loaded.
+func newPerfFake() *perfFake {
+	// A fake with a neutral scale.
+	return &perfFake{loaded: map[string]bool{}, evalScale: 1}
+} // end of newPerfFake
+
+// start runs the fake as a server and returns its address.
+func (f *perfFake) start(t *testing.T) string {
+	// Mark this as a helper.
+	t.Helper()
+	// Start the server.
+	srv := fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
+		// One request at a time.
+		f.mu.Lock()
+		// Release when this request is done.
+		defer f.mu.Unlock()
+		// Read the body into a generic shape.
+		var req struct {
+			// Model is the asked model.
+			Model string `json:"model"`
+			// KeepAlive is a number (0 unloads) or a text such as 2m.
+			KeepAlive any `json:"keep_alive"`
+		} // end of the request shape
+		// Decode it (GET requests have no body).
+		_ = json.NewDecoder(r.Body).Decode(&req)
+		// Is this an unload request?
+		unload := req.KeepAlive == float64(0)
+		// Pick the reply by path.
+		switch r.URL.Path {
+		// The version check.
+		case "/api/version":
+			// A valid version.
+			w.Write([]byte(`{"version":"0.34.4"}`))
+		// The installed models.
+		case "/api/tags":
+			// Four models: a chat model, a thinking model, an embedding model and one with no known ability.
+			w.Write([]byte(`{"models":[{"name":"chat:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"think:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion","thinking"]},{"name":"embed:1b","size":2000000000,"details":{"family":"bert"},"capabilities":["embedding"]},{"name":"odd:1b","size":1000,"details":{"family":"x"},"capabilities":[]}]}`))
+		// The loaded models.
+		case "/api/ps":
+			// Build the list from the fake's state.
+			parts := []string{}
+			// Every loaded name.
+			for n := range f.loaded {
+				// One entry: 4 GB, all of it in graphics memory.
+				parts = append(parts, `{"name":"`+n+`","size":4000000000,"size_vram":4000000000,"context_length":8192,"expires_at":"2999-01-01T00:00:00Z"}`)
+			} // end of the loop
+			// Send the list.
+			w.Write([]byte(`{"models":[` + strings.Join(parts, ",") + `]}`))
+		// A chat request.
+		case "/api/generate":
+			// An unload request.
+			if unload {
+				// Record it.
+				f.unloads = append(f.unloads, req.Model)
+				// Unload unless stuck.
+				if !f.stuck {
+					// Remove it.
+					delete(f.loaded, req.Model)
+				} // end of the stuck check
+				// A short reply.
+				if req.Model == "embed:1b" {
+					// An embedding model cannot generate.
+					w.WriteHeader(http.StatusBadRequest)
+					// Ollama's message.
+					w.Write([]byte(`{"error":"does not support generate"}`))
+					// Stop here.
+					return
+				} // end of the embedding check
+				// Fine.
+				w.Write([]byte(`{"done":true}`))
+				// Stop here.
+				return
+			} // end of the unload case
+			// An embedding model cannot generate.
+			if req.Model == "embed:1b" {
+				// Refuse like Ollama.
+				w.WriteHeader(http.StatusBadRequest)
+				// Ollama's message.
+				w.Write([]byte(`{"error":"does not support generate"}`))
+				// Stop here.
+				return
+			} // end of the embedding check
+			// Count the request.
+			f.testCalls++
+			// This index, from 1.
+			n := f.testCalls
+			// A test that wants to look at a running test holds the first request here.
+			if f.hold && n == 1 {
+				// Say the request has arrived.
+				f.entered <- struct{}{}
+				// Let other requests in while waiting.
+				f.mu.Unlock()
+				// Wait for the signal.
+				<-f.release
+				// Take the lock back before going on.
+				f.mu.Lock()
+			} // end of the hold check
+			// A failing request.
+			if f.failAt == n {
+				// Refuse like Ollama.
+				w.WriteHeader(http.StatusInternalServerError)
+				// Ollama's message.
+				w.Write([]byte(`{"error":"boom"}`))
+				// Stop here.
+				return
+			} // end of the failure check
+			// The first request loads the model.
+			load := int64(1_000_000)
+			// Cold.
+			if !f.loaded[req.Model] {
+				// Two seconds.
+				load = 2_000_000_000
+			} // end of the cold check
+			// Now it is in memory.
+			f.loaded[req.Model] = true
+			// Answer durations per request: the warm-up is slow, the timed ones give 40, 20 and 40 tokens/s (median 40, mean 33.3, median with warm-up 30).
+			eval := map[int]int64{1: 8_000_000_000, 2: 1_600_000_000, 3: 3_200_000_000, 4: 1_600_000_000}[(n-1)%4+1]
+			// Scale it.
+			eval = int64(float64(eval) * f.evalScale)
+			// Prompt reading durations: the warm-up is slow, the timed ones read 1000 tokens/s.
+			prompt := int64(200_000_000)
+			// The warm-up.
+			if (n-1)%4 == 0 {
+				// Slower.
+				prompt = 400_000_000
+			} // end of the warm-up check
+			// The first piece carries text.
+			first := map[string]any{"response": secretText, "done": false}
+			// A thinking model sends its reasoning in another field.
+			if f.thinking {
+				// Use it.
+				first = map[string]any{"thinking": secretText, "done": false}
+			} // end of the thinking check
+			// The last piece carries the figures.
+			last := map[string]any{"response": "", "done": true, "done_reason": "stop", "total_duration": load + prompt + eval, "load_duration": load, "prompt_eval_count": 200, "prompt_eval_duration": prompt, "eval_count": 64, "eval_duration": eval}
+			// The flusher sends each line at once.
+			fl, _ := w.(http.Flusher)
+			// Both pieces.
+			for _, p := range []map[string]any{first, last} {
+				// Encode one line.
+				b, _ := json.Marshal(p)
+				// Send it.
+				w.Write(append(b, '\n'))
+				// Flush it.
+				if fl != nil {
+					// Now.
+					fl.Flush()
+				} // end of the flush check
+			} // end of the pieces loop
+		// An embedding request.
+		case "/api/embed":
+			// An unload request.
+			if unload {
+				// Record it.
+				f.unloads = append(f.unloads, req.Model)
+				// Unload unless stuck.
+				if !f.stuck {
+					// Remove it.
+					delete(f.loaded, req.Model)
+				} // end of the stuck check
+				// Fine.
+				w.Write([]byte(`{"embeddings":[]}`))
+				// Stop here.
+				return
+			} // end of the unload case
+			// Count the request.
+			f.testCalls++
+			// Cold or warm.
+			load, total := int64(1_000_000), int64(50_000_000)
+			// Cold.
+			if !f.loaded[req.Model] {
+				// Slow.
+				load, total = 1_500_000_000, 1_600_000_000
+			} // end of the cold check
+			// Now it is in memory.
+			f.loaded[req.Model] = true
+			// The reply.
+			w.Write([]byte(fmt.Sprintf(`{"model":"%s","embeddings":[[0.1,0.2,0.3]],"total_duration":%d,"load_duration":%d,"prompt_eval_count":200}`, req.Model, total, load)))
+		// Anything else.
+		default:
+			// Not found.
+			w.WriteHeader(http.StatusNotFound)
+		} // end of the switch
+	}) // end of the server
+	// Hand back the address.
+	return srv.URL
+} // end of start
+
+// calls says how many test requests (not unload requests) the fake has received.
+func (f *perfFake) calls() int {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// The number.
+	return f.testCalls
+} // end of calls
+
+// isLoaded says whether a model is in memory.
+func (f *perfFake) isLoaded(name string) bool {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// The answer.
+	return f.loaded[name]
+} // end of isLoaded
+
+// unloadCount says how many unload requests arrived.
+func (f *perfFake) unloadCount() int {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// The number.
+	return len(f.unloads)
+} // end of unloadCount
+
+// quietMachine points the machine readers at a calm fake machine for one test and restores them afterwards.
+func quietMachine(t *testing.T) {
+	// Mark this as a helper.
+	t.Helper()
+	// A folder that plays the role of /proc.
+	dir := t.TempDir()
+	// The files.
+	for name, text := range map[string]string{
+		// Four-core machine, quiet.
+		"cpuinfo": "processor\t: 0\nmodel name\t: Test Processor 9000\n",
+		// Load of 0.5 on 4 cores.
+		"loadavg": "0.50 0.40 0.30 1/200 123\n",
+		// 16 GB total, 8 GB free, swap 2 GB with 1 GB free (in kilobytes).
+		"meminfo": "MemTotal:       16000000 kB\nMemAvailable:    8000000 kB\nSwapTotal:       2000000 kB\nSwapFree:        1000000 kB\n",
+	} { // end of the files
+		// Write each.
+		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o600); err != nil {
+			// Stop the test.
+			t.Fatalf("fixture: %v", err)
+		} // end of the write check
+	} // end of the loop
+	// Remember the real readers.
+	oldProc, oldGPU := procDir, gpuQuery
+	// Use the fixtures.
+	procDir = dir
+	// A card that is idle and shares its memory.
+	gpuQuery = func(ctx context.Context) (string, error) { return "Test GPU, [N/A], [N/A], 0 %", nil }
+	// Put the real readers back at the end.
+	t.Cleanup(func() { procDir, gpuQuery = oldProc, oldGPU })
+} // end of quietMachine
+
+// perfRig builds a web handler for a fake, with the history in a folder of the test; it returns the rig and the history file path.
+func perfRig(t *testing.T, f *perfFake) (themeRig, string) {
+	// Mark this as a helper.
+	t.Helper()
+	// A calm machine.
+	quietMachine(t)
+	// The history goes into a folder of this test, never into the real configuration folder.
+	dir := t.TempDir()
+	// Remember the real lookup.
+	old := userConfigDir
+	// Use the test folder.
+	userConfigDir = func() (string, error) { return dir, nil }
+	// Put it back at the end.
+	t.Cleanup(func() { userConfigDir = old })
+	// Start the fake and build the handler.
+	h := handlerFor(t, f.start(t))
+	// Fetch the main page.
+	_, _, body := get(t, h, http.MethodGet, "/")
+	// Find the page token.
+	i := strings.Index(body, `name="token" value="`)
+	// The page must carry one.
+	if i < 0 {
+		// Stop the test.
+		t.Fatalf("no token found in the page")
+	} // end of the token check
+	// The token is 32 characters after the marker.
+	tok := body[i+len(`name="token" value="`) : i+len(`name="token" value="`)+32]
+	// Hand back the rig and the file path.
+	return themeRig{h: h, token: tok}, filepath.Join(dir, "OllamaControlCenter", "performance.json")
+} // end of perfRig
+
+// perfPost sends a form to a performance route as the page's own form would.
+func perfPost(t *testing.T, rig themeRig, path, model string) (int, string, http.Header) {
+	// Mark this as a helper.
+	t.Helper()
+	// Send it.
+	res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {model}}, fromThisPage)
+	// Hand back status, body and headers.
+	return res.StatusCode, bodyOf(res), res.Header
+} // end of perfPost
+
+// savedRuns reads the history file of a test.
+func savedRuns(t *testing.T, path string) []perfRun {
+	// Mark this as a helper.
+	t.Helper()
+	// Read the file.
+	data, err := os.ReadFile(path)
+	// A missing file means nothing was saved.
+	if os.IsNotExist(err) {
+		// No runs.
+		return nil
+	} // end of the missing check
+	// Any other problem is a test failure.
+	if err != nil {
+		// Stop the test.
+		t.Fatalf("read history: %v", err)
+	} // end of the read check
+	// Decode it.
+	var h historyFile
+	// It must be valid.
+	if err := json.Unmarshal(data, &h); err != nil {
+		// Stop the test.
+		t.Fatalf("history is not valid JSON: %v", err)
+	} // end of the decode check
+	// The runs.
+	return h.Runs
+} // end of savedRuns
+
+// TestPerfStartPageChangesNothing checks the start page shows the caution and the run button and sends no test request.
+func TestPerfStartPageChangesNothing(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// Open the page for a chat model.
+	status, body, header := perfPost(t, rig, "/performance", "chat:1b")
+	// It must work.
+	if status != http.StatusOK {
+		// Stop the test.
+		t.Fatalf("status %d", status)
+	} // end of the status check
+	// The page says what it must.
+	for _, want := range []string{"Performance of <code>chat:1b</code>", "Caution: do not run this while the model is in use", "Run the performance test", `action="/performance/run"`, "data-loading", "write text", "Only numbers are saved, never any text"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// Only the monitor's own script is allowed.
+	if !strings.Contains(header.Get("Content-Security-Policy"), "script-src 'self'") || strings.Contains(body, "<script>") {
+		// Report the problem.
+		t.Errorf("script policy is wrong")
+	} // end of the policy check
+	// Nothing was sent to the model.
+	if f.calls() != 0 || f.unloadCount() != 0 || f.isLoaded("chat:1b") {
+		// Report the problem.
+		t.Errorf("the start page changed something: %d calls", f.calls())
+	} // end of the effect check
+	// An embedding model gets its own words.
+	_, body, _ = perfPost(t, rig, "/performance", "embed:1b")
+	// The wording.
+	if !strings.Contains(body, "work through a text") {
+		// Report the gap.
+		t.Errorf("the embedding start page has the chat wording")
+	} // end of the embedding check
+} // end of TestPerfStartPageChangesNothing
+
+// TestPerfRunGenerate checks a full run: warm-up plus three timed runs, the median (not the mean), no text anywhere, the model unloaded, and the numbers saved.
+func TestPerfRunGenerate(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Run the test.
+	status, body, header := perfPost(t, rig, "/performance/run", "chat:1b")
+	// It must work.
+	if status != http.StatusOK {
+		// Stop the test.
+		t.Fatalf("status %d: %s", status, body)
+	} // end of the status check
+	// Four requests: the warm-up and three timed runs.
+	if f.calls() != 4 {
+		// Report the problem.
+		t.Errorf("%d test requests, want 4", f.calls())
+	} // end of the count check
+	// The median of 40, 20 and 40 is 40; the mean would be 33.3 and a median with the warm-up 30.
+	for _, want := range []string{"40.0 tokens/s", "1000.0 tokens/s", "2.00 s", "100% graphics card, 0% processor and main memory", "4.0 GB", "8192", "Test Processor 9000", "Test GPU, 0% busy, memory not reported", "none", "No earlier test of this model"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("result lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// Wrong ways to combine the runs must not appear.
+	for _, bad := range []string{"33.3 tokens/s", "30.0 tokens/s", "8.0 tokens/s"} {
+		// Look for it.
+		if strings.Contains(body, bad) {
+			// Report the problem.
+			t.Errorf("result shows %q", bad)
+		} // end of the check
+	} // end of the loop
+	// The tooltips of the indicators are there.
+	for _, h := range []string{"Answer speed", "Prompt reading speed", "Load time", "Total time", "Time to first word", "Tokens counted", "Processor split", "Memory used", "CPU cores", "CPU load", "Memory free", "Swap in use", "Other models loaded", "GPU"} {
+		// The heading is a focusable help element.
+		if !strings.Contains(body, `tabindex="0"`) || !strings.Contains(body, ">"+h+"</span>") {
+			// Report the gap.
+			t.Errorf("no help heading for %q", h)
+		} // end of the check
+	} // end of the loop
+	// No script on the result page and a strict policy.
+	if strings.Contains(body, "<script") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
+		// Report the problem.
+		t.Errorf("the result page allows or contains a script")
+	} // end of the script check
+	// The model was unloaded again.
+	if f.isLoaded("chat:1b") || f.unloadCount() == 0 {
+		// Report the problem.
+		t.Errorf("the model is still loaded")
+	} // end of the unload check
+	// One run was saved, with numbers only.
+	runs := savedRuns(t, hist)
+	// Exactly one.
+	if len(runs) != 1 {
+		// Stop the test.
+		t.Fatalf("%d saved runs, want 1", len(runs))
+	} // end of the count check
+	// The saved figures.
+	r := runs[0]
+	// Check a few.
+	if r.AnswerSpeed != 40 || r.PromptSpeed != 1000 || r.ColdLoadSec != 2 || r.Kind != "generate" || r.Model != "chat:1b" || r.TokensIn != 200 || r.TokensOut != 64 || r.OllamaVersion != "0.34.4" || r.Runs != 3 || r.PromptVersion != perfPromptVersion {
+		// Report the problem.
+		t.Errorf("saved run is wrong: %+v", r)
+	} // end of the figures check
+	// No text of any answer or prompt anywhere: not on the page, not in the file.
+	data, _ := os.ReadFile(hist)
+	// Check both.
+	for name, text := range map[string]string{"page": body, "file": string(data)} {
+		// The answer text and a piece of the fixed prompt.
+		if strings.Contains(text, secretText) || strings.Contains(text, "lighthouse") {
+			// Report the leak.
+			t.Errorf("text of the test reached the %s", name)
+		} // end of the check
+	} // end of the loop
+	// The file is private to the person (not on Windows, which has no such permissions).
+	if runtime.GOOS != "windows" {
+		// Look at the file.
+		info, err := os.Stat(hist)
+		// It must exist with mode 0600.
+		if err != nil || info.Mode().Perm() != 0o600 {
+			// Report the problem.
+			t.Errorf("history file permissions: %v %v", info, err)
+		} // end of the mode check
+	} // end of the platform check
+	// No temporary file is left behind.
+	left, _ := filepath.Glob(filepath.Join(filepath.Dir(hist), "*.tmp"))
+	// There must be none.
+	if len(left) != 0 {
+		// Report the problem.
+		t.Errorf("temporary files left: %v", left)
+	} // end of the temp check
+} // end of TestPerfRunGenerate
+
+// TestPerfThinkingModelFirstWord checks the first word is found when the stream carries reasoning text only.
+func TestPerfThinkingModelFirstWord(t *testing.T) {
+	// A thinking fake.
+	f := newPerfFake()
+	// Its stream uses the thinking field.
+	f.thinking = true
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Run the test.
+	_, body, _ := perfPost(t, rig, "/performance/run", "think:1b")
+	// The saved run has first-word figures.
+	runs := savedRuns(t, hist)
+	// One run, with both first-word figures above zero.
+	if len(runs) != 1 || runs[0].WarmFirstWordSec <= 0 || runs[0].ColdFirstWordSec <= 0 {
+		// Report the problem.
+		t.Errorf("first word not measured: %+v", runs)
+	} // end of the check
+	// The page does not claim it is missing.
+	if strings.Contains(body, "Time to first word</span>") && strings.Contains(body, "not available</td>") && !strings.Contains(body, "cold:") {
+		// Report the problem.
+		t.Errorf("the first word is shown as missing")
+	} // end of the page check
+	// The reasoning text never reaches the page.
+	if strings.Contains(body, secretText) {
+		// Report the leak.
+		t.Errorf("reasoning text reached the page")
+	} // end of the leak check
+} // end of TestPerfThinkingModelFirstWord
+
+// TestPerfRunEmbedding checks the embedding variant: its own indicators, no chat figures, unloaded afterwards.
+func TestPerfRunEmbedding(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Run the test.
+	status, body, _ := perfPost(t, rig, "/performance/run", "embed:1b")
+	// It must work.
+	if status != http.StatusOK {
+		// Stop the test.
+		t.Fatalf("status %d: %s", status, body)
+	} // end of the status check
+	// Four requests: warm-up and three timed.
+	if f.calls() != 4 {
+		// Report the problem.
+		t.Errorf("%d test requests, want 4", f.calls())
+	} // end of the count check
+	// The embedding figures.
+	for _, want := range []string{"Embedding time", "0.050 s", "1.50 s", "Vector length", "3 numbers", "200 in", "An embedding model writes no text"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("result lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// No chat figures.
+	if strings.Contains(body, "tokens/s</td>") || strings.Contains(body, ">Answer speed</span>") {
+		// Report the problem.
+		t.Errorf("chat figures on an embedding result")
+	} // end of the chat check
+	// Unloaded through the embed fallback.
+	if f.isLoaded("embed:1b") {
+		// Report the problem.
+		t.Errorf("the embedding model is still loaded")
+	} // end of the unload check
+	// The saved run is an embedding run.
+	if runs := savedRuns(t, hist); len(runs) != 1 || runs[0].Kind != "embedding" || runs[0].VectorLength != 3 {
+		// Report the problem.
+		t.Errorf("saved run: %+v", runs)
+	} // end of the saved check
+} // end of TestPerfRunEmbedding
+
+// TestPerfRefusals checks a loaded model, an unknown model and a model of unknown ability are refused, and nothing is sent to the model.
+func TestPerfRefusals(t *testing.T) {
+	// A fake with the chat model already in memory.
+	f := newPerfFake()
+	// Loaded, maybe in use.
+	f.loaded["chat:1b"] = true
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// The cases.
+	for _, tc := range []struct{ model, want string }{
+		// A loaded model.
+		{"chat:1b", "loaded now and may be in use"},
+		// An unknown model.
+		{"nope:1b", "not installed"},
+		// A model with no known ability.
+		{"odd:1b", "does not report that this model can write text"},
+	} { // end of the cases
+		// Both the start page and the run refuse.
+		for _, path := range []string{"/performance", "/performance/run"} {
+			// Send it.
+			status, body, _ := perfPost(t, rig, path, tc.model)
+			// It is a normal page that explains.
+			if status != http.StatusOK || !strings.Contains(body, tc.want) {
+				// Report the problem.
+				t.Errorf("%s %s: status %d, body lacks %q", path, tc.model, status, tc.want)
+			} // end of the check
+		} // end of the path loop
+	} // end of the case loop
+	// No test request was sent, and nothing was unloaded or saved.
+	if f.calls() != 0 || f.unloadCount() != 0 || !f.isLoaded("chat:1b") || len(savedRuns(t, hist)) != 0 {
+		// Report the problem.
+		t.Errorf("a refused test changed something")
+	} // end of the effect check
+} // end of TestPerfRefusals
+
+// TestPerfFormRefusals checks the same refusals as the other forms on all four routes, and that a refused request reaches nothing.
+func TestPerfFormRefusals(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// The cases.
+	for _, tc := range []struct {
+		// name describes the case.
+		name string
+		// form is the posted form.
+		form url.Values
+		// headers are the request headers.
+		headers map[string]string
+		// want is the expected status.
+		want int
+	}{ // the cases follow
+		// Another site posts the form.
+		{"cross-site", url.Values{"token": {rig.token}, "model": {"chat:1b"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
+		// No browser headers.
+		{"no origin headers", url.Values{"token": {rig.token}, "model": {"chat:1b"}}, map[string]string{}, http.StatusForbidden},
+		// No token.
+		{"missing token", url.Values{"model": {"chat:1b"}}, fromThisPage, http.StatusForbidden},
+		// A wrong token.
+		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "model": {"chat:1b"}}, fromThisPage, http.StatusForbidden},
+		// No model.
+		{"no model", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
+		// Too much data.
+		{"too large", url.Values{"token": {rig.token}, "model": {"chat:1b"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
+	} { // end of the table
+		// Every route must refuse in the same way.
+		for _, path := range []string{"/performance", "/performance/run", "/performance/clear", "/performance/clear/confirm"} {
+			// A named subtest.
+			t.Run(tc.name+" "+path, func(t *testing.T) {
+				// Send it.
+				res := post(t, rig.h, path, tc.form, tc.headers)
+				// Compare the status.
+				if res.StatusCode != tc.want {
+					// Report the difference.
+					t.Errorf("status %d, want %d", res.StatusCode, tc.want)
+				} // end of the status check
+			}) // end of the subtest
+		} // end of the path loop
+	} // end of the table loop
+	// GET is refused on every route.
+	for _, path := range []string{"/performance", "/performance/run", "/performance/clear", "/performance/clear/confirm"} {
+		// Check the method.
+		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
+			// Report the problem.
+			t.Errorf("GET %s = %d, want 405", path, status)
+		} // end of the check
+	} // end of the loop
+	// Nothing reached the model.
+	if f.calls() != 0 || f.unloadCount() != 0 {
+		// Report the problem.
+		t.Errorf("a refused request reached the model")
+	} // end of the effect check
+} // end of TestPerfFormRefusals
+
+// TestPerfFailureUnloadsAndSavesNothing checks a failing request ends the test, tells why, unloads the model and saves nothing.
+func TestPerfFailureUnloadsAndSavesNothing(t *testing.T) {
+	// A fake whose second test request fails.
+	f := newPerfFake()
+	// The failure.
+	f.failAt = 2
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Run the test.
+	status, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
+	// A bad-gateway page with the reason.
+	if status != http.StatusBadGateway || !strings.Contains(body, "Could not do this") || !strings.Contains(body, "boom") {
+		// Report the problem.
+		t.Errorf("status %d, body: %s", status, body)
+	} // end of the check
+	// The model was unloaded again, and nothing was saved.
+	if f.isLoaded("chat:1b") || len(savedRuns(t, hist)) != 0 {
+		// Report the problem.
+		t.Errorf("a failed test left the model loaded or saved a run")
+	} // end of the effect check
+} // end of TestPerfFailureUnloadsAndSavesNothing
+
+// TestPerfLeftLoadedWarning checks the page says so when the model could not be unloaded again.
+func TestPerfLeftLoadedWarning(t *testing.T) {
+	// A fake that ignores unload requests.
+	f := newPerfFake()
+	// Stuck.
+	f.stuck = true
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Run the test.
+	_, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
+	// The warning.
+	if !strings.Contains(body, "could not be unloaded again") {
+		// Report the problem.
+		t.Errorf("no warning that the model is still loaded")
+	} // end of the check
+	// The saved run says so.
+	if runs := savedRuns(t, hist); len(runs) != 1 || !runs[0].LeftLoaded {
+		// Report the problem.
+		t.Errorf("saved run: %+v", runs)
+	} // end of the saved check
+} // end of TestPerfLeftLoadedWarning
+
+// TestPerfComparisonAndHistory checks the comparison with the previous run, the history table, and clearing in two steps.
+func TestPerfComparisonAndHistory(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// The first run.
+	perfPost(t, rig, "/performance/run", "chat:1b")
+	// The second run is twice as slow: the answers take twice as long.
+	f.mu.Lock()
+	// The scale.
+	f.evalScale = 2
+	// Release.
+	f.mu.Unlock()
+	// The second run.
+	_, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
+	// The comparison.
+	for _, want := range []string{"This run", "Previous run", "20.0 tokens/s", "40.0 tokens/s", "-50.0% (slower)", "Saved tests of this model", "Clear all saved results (2)"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("result lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// Two runs are saved.
+	if n := len(savedRuns(t, hist)); n != 2 {
+		// Stop the test.
+		t.Fatalf("%d saved runs, want 2", n)
+	} // end of the count check
+	// The first step of clearing only asks.
+	_, ask, _ := perfPost(t, rig, "/performance/clear", "chat:1b")
+	// The question names the number.
+	if !strings.Contains(ask, "removes all 2 saved test results") || len(savedRuns(t, hist)) != 2 {
+		// Report the problem.
+		t.Errorf("the clear question removed something or is wrong")
+	} // end of the ask check
+	// The second step clears.
+	_, done, _ := perfPost(t, rig, "/performance/clear/confirm", "chat:1b")
+	// The confirmation.
+	if !strings.Contains(done, "All saved test results were removed") || len(savedRuns(t, hist)) != 0 {
+		// Report the problem.
+		t.Errorf("clearing failed")
+	} // end of the clear check
+} // end of TestPerfComparisonAndHistory
+
+// TestPerfBusyMachineWarning checks a busy graphics card is flagged on the start page and in the saved run.
+func TestPerfBusyMachineWarning(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// The graphics card is busy.
+	gpuQuery = func(ctx context.Context) (string, error) { return "Test GPU, [N/A], [N/A], 96 %", nil }
+	// The start page warns.
+	_, start, _ := perfPost(t, rig, "/performance", "chat:1b")
+	// The warning.
+	if !strings.Contains(start, "The machine looks busy right now") || !strings.Contains(start, "96% busy") {
+		// Report the gap.
+		t.Errorf("no busy warning on the start page")
+	} // end of the start check
+	// The test still runs and marks the result.
+	_, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
+	// The result warns too.
+	if !strings.Contains(body, "The machine looked busy before the test") {
+		// Report the gap.
+		t.Errorf("no busy warning on the result")
+	} // end of the result check
+	// The saved run is marked.
+	if runs := savedRuns(t, hist); len(runs) != 1 || !runs[0].Busy || runs[0].BusyReason == "" {
+		// Report the problem.
+		t.Errorf("saved run: %+v", runs)
+	} // end of the saved check
+} // end of TestPerfBusyMachineWarning
+
+// TestPerfOneTestAtATime checks a second test is refused while one is running, and does not reach the model.
+func TestPerfOneTestAtATime(t *testing.T) {
+	// A fake that holds the first test request.
+	f := newPerfFake()
+	// Hold it.
+	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// The first run in the background.
+	done := make(chan string)
+	// Start it.
+	go func() {
+		// Run.
+		_, body, _ := perfPost(t, rig, "/performance/run", "chat:1b")
+		// Report.
+		done <- body
+	}() // end of the goroutine
+	// Wait until the first run is inside the model request.
+	<-f.entered
+	// A second run now.
+	_, second, _ := perfPost(t, rig, "/performance/run", "think:1b")
+	// It is refused.
+	if !strings.Contains(second, "Another performance test is running") {
+		// Report the problem.
+		t.Errorf("the second test was not refused: %s", second)
+	} // end of the refusal check
+	// Let the first one finish.
+	close(f.release)
+	// Wait for it.
+	first := <-done
+	// The first one completed normally.
+	if !strings.Contains(first, "Measured by the test") || len(savedRuns(t, hist)) != 1 {
+		// Report the problem.
+		t.Errorf("the first test did not complete")
+	} // end of the first check
+} // end of TestPerfOneTestAtATime
+
+// TestMedian checks the median helper: odd and even counts, unsorted input, and numbers that are not available.
+func TestMedian(t *testing.T) {
+	// The cases.
+	for _, tc := range []struct {
+		// in is the input.
+		in []float64
+		// want is the median.
+		want float64
+	}{ // the cases follow
+		// Odd count, unsorted.
+		{[]float64{40, 20, 40}, 40},
+		// Even count: the mean of the middle two.
+		{[]float64{1, 2, 3, 10}, 2.5},
+		// Zeros are ignored.
+		{[]float64{0, 5, 0}, 5},
+		// Nothing usable.
+		{[]float64{0, 0}, 0},
+		// Nothing at all.
+		{nil, 0},
+	} { // end of the cases
+		// Check it.
+		if got := median(tc.in); got != tc.want {
+			// Report the difference.
+			t.Errorf("median(%v) = %v, want %v", tc.in, got, tc.want)
+		} // end of the check
+	} // end of the loop
+} // end of TestMedian
+
+// TestChangeText checks the percentage and the words, for speeds (higher is faster) and times (lower is faster).
+func TestChangeText(t *testing.T) {
+	// The cases.
+	for _, tc := range []struct {
+		// cur and prev are the two figures.
+		cur, prev float64
+		// higher says higher is faster.
+		higher bool
+		// want is the text.
+		want string
+	}{ // the cases follow
+		// A speed that fell by half.
+		{20, 40, true, "-50.0% (slower)"},
+		// A speed that rose by a quarter.
+		{50, 40, true, "+25.0% (faster)"},
+		// A time that fell by half.
+		{1, 2, false, "-50.0% (faster)"},
+		// A time that doubled.
+		{2, 1, false, "+100.0% (slower)"},
+		// Almost the same.
+		{40.1, 40, true, "no change (within 0.5%)"},
+		// Missing figure.
+		{0, 40, true, "not comparable"},
+	} { // end of the cases
+		// Check it.
+		if got := changeText(tc.cur, tc.prev, tc.higher); got != tc.want {
+			// Report the difference.
+			t.Errorf("changeText(%v,%v,%v) = %q, want %q", tc.cur, tc.prev, tc.higher, got, tc.want)
+		} // end of the check
+	} // end of the loop
+} // end of TestChangeText
+
+// TestMachineSnapshot checks what is read from the machine, in decimal gigabytes, and what happens for a remote Ollama.
+func TestMachineSnapshot(t *testing.T) {
+	// A calm fake machine.
+	quietMachine(t)
+	// Read it as a local machine.
+	s := snapshotMachine(context.Background(), true)
+	// The figures.
+	if !s.Local || s.CPUName != "Test Processor 9000" || s.Load1 != 0.5 || s.MemTotalGB != 16.384 || s.MemFreeGB != 8.192 || s.SwapTotalGB != 2.048 || s.SwapUsedGB != 1.024 || s.GPUName != "Test GPU" || s.GPUUtil != 0 || s.Cores < 1 {
+		// Report the problem.
+		t.Errorf("snapshot: %+v", s)
+	} // end of the figures check
+	// A quiet machine is not busy.
+	if r := busyReason(s); r != "" {
+		// Report the problem.
+		t.Errorf("a quiet machine looks busy: %s", r)
+	} // end of the quiet check
+	// A busy graphics card.
+	s.GPUUtil = 96
+	// It is named.
+	if r := busyReason(s); !strings.Contains(r, "96%") {
+		// Report the problem.
+		t.Errorf("busy graphics card not noticed: %q", r)
+	} // end of the GPU check
+	// A busy processor: load above half of the cores.
+	s.GPUUtil, s.Cores, s.Load1 = 0, 4, 2.5
+	// It is named.
+	if r := busyReason(s); !strings.Contains(r, "2.5") {
+		// Report the problem.
+		t.Errorf("busy processor not noticed: %q", r)
+	} // end of the load check
+	// Exactly half is not yet busy.
+	s.Load1 = 2
+	// Not busy.
+	if r := busyReason(s); r != "" {
+		// Report the problem.
+		t.Errorf("load at half of the cores is called busy: %q", r)
+	} // end of the boundary check
+	// A remote Ollama: nothing is read, and nothing is judged.
+	remote := snapshotMachine(context.Background(), false)
+	// Only the note.
+	if remote.Local || remote.Note == "" || remote.Cores != 0 || remote.MemTotalGB != 0 || busyReason(remote) != "" {
+		// Report the problem.
+		t.Errorf("remote snapshot: %+v", remote)
+	} // end of the remote check
+	// A missing graphics tool is not an error.
+	gpuQuery = func(ctx context.Context) (string, error) { return "", errors.New("not installed") }
+	// Read again.
+	if s := snapshotMachine(context.Background(), true); s.GPUName != "" || s.GPUUtil != -1 {
+		// Report the problem.
+		t.Errorf("a missing tool left traces: %+v", s)
+	} // end of the missing-tool check
+} // end of TestMachineSnapshot
+
+// TestIsLocalAddress checks which addresses count as this same computer.
+func TestIsLocalAddress(t *testing.T) {
+	// The cases.
+	for raw, want := range map[string]bool{"http://127.0.0.1:11434": true, "http://localhost:11434": true, "http://[::1]:11434": true, "http://192.168.1.20:11434": false, "http://spark.example.org:11434": false} {
+		// Parse it.
+		u, err := parseOllamaURL(raw)
+		// It must parse.
+		if err != nil {
+			// Stop the test.
+			t.Fatalf("%s: %v", raw, err)
+		} // end of the parse check
+		// Compare.
+		if got := isLocalAddress(u); got != want {
+			// Report the difference.
+			t.Errorf("isLocalAddress(%s) = %v, want %v", raw, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestIsLocalAddress
+
+// TestResultForRemoteOllama checks the machine table says why it has no figures when Ollama is on another computer, but still lists the loaded models.
+func TestResultForRemoteOllama(t *testing.T) {
+	// A run that was made against a remote Ollama.
+	run := perfRun{Kind: "generate", Model: "m", PromptVersion: "v1", Runs: 3, OtherLoaded: []string{"x:1b"}}
+	// The snapshots say remote.
+	run.Before = snapshotMachine(context.Background(), false)
+	// The same after.
+	run.After = run.Before
+	// Build the tables.
+	groups := buildGroups(run, nil, map[string]tipView{})
+	// The last group is the machine.
+	d := groups[len(groups)-1]
+	// The note and the one row.
+	if !strings.Contains(d.Note, "Ollama is on another computer") || len(d.Rows) != 1 || d.Rows[0].Cells[0] != "x:1b" {
+		// Report the problem.
+		t.Errorf("remote machine group: %+v", d)
+	} // end of the check
+} // end of TestResultForRemoteOllama
+
+// TestPerfStoreLimitAndDamage checks the history keeps the newest 200 runs, and leaves a damaged or foreign file alone.
+func TestPerfStoreLimitAndDamage(t *testing.T) {
+	// A folder of this test.
+	dir := t.TempDir()
+	// The file.
+	path := filepath.Join(dir, "sub", "performance.json")
+	// Open (the folder does not exist yet).
+	s := openPerfStore(path, "")
+	// Add more runs than the limit.
+	for i := 1; i <= maxHistoryRuns+5; i++ {
+		// One run, numbered by its answer speed.
+		if err := s.add(perfRun{Model: "m", Kind: "generate", AnswerSpeed: float64(i)}); err != nil {
+			// Stop the test.
+			t.Fatalf("add: %v", err)
+		} // end of the add check
+	} // end of the loop
+	// Reopen from the file.
+	again := openPerfStore(path, "")
+	// The count and the oldest and newest kept.
+	runs := again.forModel("m", "generate")
+	// Newest first: 205 down to 6.
+	if len(runs) != maxHistoryRuns || runs[0].AnswerSpeed != float64(maxHistoryRuns+5) || runs[len(runs)-1].AnswerSpeed != 6 {
+		// Report the problem.
+		t.Errorf("kept %d runs from %v to %v", len(runs), runs[0].AnswerSpeed, runs[len(runs)-1].AnswerSpeed)
+	} // end of the limit check
+	// A damaged file and a file of another version.
+	for name, content := range map[string]string{"damaged": "{not json", "future": `{"version":99,"runs":[]}`} {
+		// Write it.
+		bad := filepath.Join(dir, name+".json")
+		// The file.
+		if err := os.WriteFile(bad, []byte(content), 0o600); err != nil {
+			// Stop the test.
+			t.Fatalf("write: %v", err)
+		} // end of the write check
+		// Open it.
+		b := openPerfStore(bad, "")
+		// Adding a run must keep working in memory and must not touch the file.
+		if err := b.add(perfRun{Model: "m", Kind: "generate"}); err != nil {
+			// Report the problem.
+			t.Errorf("%s: add failed: %v", name, err)
+		} // end of the add check
+		// The file is unchanged.
+		if got, _ := os.ReadFile(bad); string(got) != content {
+			// Report the problem.
+			t.Errorf("%s: the file was changed", name)
+		} // end of the file check
+		// The page can say why.
+		if _, note := b.where(); note == "" || len(b.forModel("m", "generate")) != 1 {
+			// Report the problem.
+			t.Errorf("%s: no note or the run is not kept in memory", name)
+		} // end of the note check
+	} // end of the loop
+} // end of TestPerfStoreLimitAndDamage
+
+// TestMainPagePerformanceIcon checks every model that is not loaded has the chart icon before its name with a tip, and a loaded model has an empty slot instead.
+func TestMainPagePerformanceIcon(t *testing.T) {
+	// A fake with the chat model loaded.
+	f := newPerfFake()
+	// Loaded.
+	f.loaded["chat:1b"] = true
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// Fetch the page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// A not-loaded model has the icon, its label, its tip and its form, and the icon is before the name.
+	row := body[strings.Index(body, `<tr data-model="embed:1b"`):]
+	// The cell of the row heading.
+	cell := row[:strings.Index(row, "</th>")]
+	// Everything must be in the cell, and the name must come last.
+	for _, want := range []string{`action="/performance"`, `aria-label="Performance of embed:1b"`, `id="tipperf-embed:1b"`, "Performance: see how fast this model runs on this machine", "📈"} {
+		// Look for it.
+		if !strings.Contains(cell, want) {
+			// Report the gap.
+			t.Errorf("the row heading lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The name comes after the icon.
+	if !strings.HasSuffix(strings.TrimSpace(cell), "embed:1b") || strings.Index(cell, "📈") > strings.LastIndex(cell, "embed:1b") {
+		// Report the problem.
+		t.Errorf("the icon is not before the name")
+	} // end of the order check
+	// The loaded model has no icon, and only the three others have one.
+	if strings.Contains(body, `aria-label="Performance of chat:1b"`) || strings.Count(body, `action="/performance"`) != 3 {
+		// Report the problem.
+		t.Errorf("a loaded model has the performance icon, or the count is wrong: %d", strings.Count(body, `action="/performance"`))
+	} // end of the loaded check
+} // end of TestMainPagePerformanceIcon
+
+// TestMain keeps every test away from the person's real configuration folder.
+func TestMain(m *testing.M) {
+	// A folder for the whole test run.
+	dir, err := os.MkdirTemp("", "occ-test-config-")
+	// Without it the tests cannot be made safe.
+	if err != nil {
+		// Stop.
+		panic(err)
+	} // end of the folder check
+	// Use it as the configuration folder.
+	userConfigDir = func() (string, error) { return dir, nil }
+	// Run the tests.
+	code := m.Run()
+	// Remove the folder.
+	os.RemoveAll(dir)
+	// Leave with the tests' result.
+	os.Exit(code)
+} // end of TestMain
diff --git a/perfpage.go b/perfpage.go
new file mode 100644
index 0000000..c5195f6
--- /dev/null
+++ b/perfpage.go
@@ -0,0 +1,663 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds the page in memory before it is sent.
+	"bytes"
+	// embed stores the page template inside the executable.
+	_ "embed"
+	// fmt builds formatted text.
+	"fmt"
+	// html/template builds the page and escapes every inserted text.
+	"html/template"
+	// log writes the real reason for an error for the person running the program.
+	"log"
+	// math measures the size of a change.
+	"math"
+	// net/http provides the request and response types.
+	"net/http"
+	// strings joins and searches text.
+	"strings"
+	// sync keeps two tests from running at the same time.
+	"sync"
+) // end of imports
+
+// performanceTemplateText holds the performance pages, stored inside the executable at build time.
+//
+//go:embed web/performance.html
+var performanceTemplateText string
+
+// perfRow is one line of a table on the performance page.
+type perfRow struct {
+	// Tip is the help bubble of the indicator; its ID is empty when the row has only a plain label.
+	Tip tipView
+	// Label is the plain label used when there is no bubble.
+	Label string
+	// Cells are the values, one per column.
+	Cells []string
+} // end of perfRow
+
+// perfGroup is one table with a heading.
+type perfGroup struct {
+	// Title is the heading of the table.
+	Title string
+	// Tip is the help bubble of the heading, when it has one.
+	Tip tipView
+	// Note is a sentence under the heading.
+	Note string
+	// Cols are the column headings after the first.
+	Cols []string
+	// Rows are the lines.
+	Rows []perfRow
+} // end of perfGroup
+
+// perfPage is everything the performance pages can show.
+type perfPage struct {
+	// Theme is the saved colour theme, or empty to follow the system.
+	Theme string
+	// Token is the page token every form carries.
+	Token string
+	// Kind chooses the version of the page.
+	Kind string
+	// Model is the model name.
+	Model string
+	// Detail is a plain reason on the error page.
+	Detail string
+	// Embedding is true for an embedding model.
+	Embedding bool
+	// Groups are the result tables.
+	Groups []perfGroup
+	// BusyReason is set when the machine looked busy.
+	BusyReason string
+	// LeftLoaded is true when the model could not be unloaded again.
+	LeftLoaded bool
+	// SaveNote says where the history is kept, or why it is not saved to a file.
+	SaveNote string
+	// HistoryCols are the column headings of the history table.
+	HistoryCols []string
+	// HistoryRows are the lines of the history table, newest first.
+	HistoryRows [][]string
+	// HistoryCount is how many runs are saved in all, for every model.
+	HistoryCount int
+	// Seconds is the rough time the test may take, in words.
+	Duration string
+} // end of perfPage
+
+// fmtSecs shows a time in seconds with sensible decimals; zero means not available.
+func fmtSecs(v float64) string {
+	// Not available.
+	if v <= 0 {
+		// Say so.
+		return "not available"
+	} // end of the check
+	// Under a second: milliseconds' precision.
+	if v < 1 {
+		// Three decimals.
+		return fmt.Sprintf("%.3f s", v)
+	} // end of the small case
+	// Under a hundred seconds: two decimals.
+	if v < 100 {
+		// Two decimals.
+		return fmt.Sprintf("%.2f s", v)
+	} // end of the middle case
+	// Longer: whole seconds.
+	return fmt.Sprintf("%.0f s", v)
+} // end of fmtSecs
+
+// fmtSpeed shows a speed in tokens per second; zero means not available.
+func fmtSpeed(v float64) string {
+	// Not available.
+	if v <= 0 {
+		// Say so.
+		return "not available"
+	} // end of the check
+	// One decimal.
+	return fmt.Sprintf("%.1f tokens/s", v)
+} // end of fmtSpeed
+
+// changeText compares this run with the previous one: the percentage and the words faster or slower.
+func changeText(cur, prev float64, higherIsFaster bool) string {
+	// Both figures are needed.
+	if cur <= 0 || prev <= 0 {
+		// Say so.
+		return "not comparable"
+	} // end of the check
+	// The change in percent.
+	pct := (cur - prev) / prev * 100
+	// A tiny change is called no change.
+	if math.Abs(pct) < 0.5 {
+		// Say so.
+		return "no change (within 0.5%)"
+	} // end of the tiny case
+	// Faster means a higher speed or a lower time.
+	faster := (pct > 0) == higherIsFaster
+	// The word.
+	word := "slower"
+	// Switch it for a faster run.
+	if faster {
+		// Faster.
+		word = "faster"
+	} // end of the word choice
+	// The text.
+	return fmt.Sprintf("%+.1f%% (%s)", pct, word)
+} // end of changeText
+
+// gbText shows decimal gigabytes with one decimal; zero means not reported.
+func gbText(v float64) string {
+	// Not reported.
+	if v <= 0 {
+		// Say so.
+		return "not reported"
+	} // end of the check
+	// One decimal.
+	return fmt.Sprintf("%.1f GB", v)
+} // end of gbText
+
+// machineRows builds the "machine condition" table rows from the two snapshots.
+func machineRows(before, after machineSnapshot, other []string, tips map[string]tipView) []perfRow {
+	// The rows.
+	var rows []perfRow
+	// cpu load text.
+	load := func(s machineSnapshot) string {
+		// Not reported.
+		if s.Load1 < 0 {
+			// Say so.
+			return "not reported"
+		} // end of the check
+		// One decimal.
+		return fmt.Sprintf("%.1f (last minute)", s.Load1)
+	} // end of load
+	// memory text.
+	mem := func(s machineSnapshot) string {
+		// Not reported.
+		if s.MemTotalGB <= 0 {
+			// Say so.
+			return "not reported"
+		} // end of the check
+		// Free of total.
+		return gbText(s.MemFreeGB) + " free of " + gbText(s.MemTotalGB)
+	} // end of mem
+	// swap text.
+	swap := func(s machineSnapshot) string {
+		// Not reported.
+		if s.SwapUsedGB < 0 {
+			// Say so.
+			return "not reported"
+		} // end of the check
+		// Used of total.
+		return fmt.Sprintf("%.1f GB of %.1f GB", s.SwapUsedGB, s.SwapTotalGB)
+	} // end of swap
+	// gpu text.
+	gpu := func(s machineSnapshot) string {
+		// No tool reported a card.
+		if s.GPUName == "" {
+			// Say so.
+			return "not reported"
+		} // end of the check
+		// The name.
+		t := s.GPUName
+		// The busy percentage.
+		if s.GPUUtil >= 0 {
+			// Add it.
+			t += fmt.Sprintf(", %d%% busy", s.GPUUtil)
+		} // end of the util check
+		// The memory, unless it is not reported.
+		if s.GPUMemory != "" && !strings.Contains(s.GPUMemory, "N/A") {
+			// Add it.
+			t += ", memory " + s.GPUMemory
+		} else {
+			// Say so.
+			t += ", memory not reported"
+		} // end of the memory check
+		// The text.
+		return t
+	} // end of gpu
+	// The processor.
+	cores := func(s machineSnapshot) string {
+		// The count, and the name when known.
+		t := fmt.Sprintf("%d", s.Cores)
+		// The name.
+		if s.CPUName != "" {
+			// Add it.
+			t += " (" + s.CPUName + ")"
+		} // end of the name check
+		// The text.
+		return t
+	} // end of cores
+	// The other loaded models.
+	others := "none"
+	// Some were loaded.
+	if len(other) > 0 {
+		// List them.
+		others = strings.Join(other, ", ")
+	} // end of the check
+	// The six rows, in the order of the plan.
+	rows = append(rows,
+		// Cores.
+		perfRow{Tip: tips["CPU cores"], Cells: []string{cores(before), cores(after)}},
+		// Load.
+		perfRow{Tip: tips["CPU load"], Cells: []string{load(before), load(after)}},
+		// Free memory.
+		perfRow{Tip: tips["Memory free"], Cells: []string{mem(before), mem(after)}},
+		// Swap.
+		perfRow{Tip: tips["Swap in use"], Cells: []string{swap(before), swap(after)}},
+		// Other models.
+		perfRow{Tip: tips["Other models loaded"], Cells: []string{others, "-"}},
+		// The graphics card.
+		perfRow{Tip: tips["GPU"], Cells: []string{gpu(before), gpu(after)}},
+	) // end of the rows
+	// Hand them back.
+	return rows
+} // end of machineRows
+
+// buildGroups builds the four result tables of a run; prev is the previous run of the same model and prompt, or nil.
+func buildGroups(run perfRun, prev *perfRun, tips map[string]tipView) []perfGroup {
+	// The groups.
+	var groups []perfGroup
+	// Group A: measured by the test.
+	a := perfGroup{Title: "Measured by the test", Cols: []string{"Result", "Detail"}}
+	// An embedding model.
+	if run.Kind == "embedding" {
+		// A note: no text is written.
+		a.Note = "An embedding model writes no text, so answer speed and prompt reading speed do not apply to it."
+		// The rows.
+		a.Rows = append(a.Rows,
+			// Embedding time.
+			perfRow{Tip: tips["Embedding time"], Cells: []string{fmtSecs(run.WarmTotalSec), fmt.Sprintf("median of %d timed runs, model already loaded", run.Runs)}},
+			// Load time.
+			perfRow{Tip: tips["Load time"], Cells: []string{fmtSecs(run.ColdLoadSec), "cold: the warm-up run loaded the model from disk"}},
+			// Tokens.
+			perfRow{Tip: tips["Tokens counted"], Cells: []string{fmt.Sprintf("%d in", run.TokensIn), "the same fixed text every time (version " + run.PromptVersion + ")"}},
+			// Vector.
+			perfRow{Tip: tips["Vector length"], Cells: []string{fmt.Sprintf("%d numbers", run.VectorLength), "one vector per text"}},
+		) // end of the rows
+	} else {
+		// A chat model: the first word shows warm and cold.
+		first := fmtSecs(run.WarmFirstWordSec)
+		// The cold detail.
+		firstDetail := "warm (model loaded)"
+		// Add the cold figure when there is one.
+		if run.ColdFirstWordSec > 0 {
+			// Cold includes loading.
+			firstDetail += "; cold: " + fmtSecs(run.ColdFirstWordSec)
+		} // end of the cold check
+		// The rows.
+		a.Rows = append(a.Rows,
+			// Answer speed.
+			perfRow{Tip: tips["Answer speed"], Cells: []string{fmtSpeed(run.AnswerSpeed), fmt.Sprintf("median of %d timed runs", run.Runs)}},
+			// Prompt reading speed.
+			perfRow{Tip: tips["Prompt reading speed"], Cells: []string{fmtSpeed(run.PromptSpeed), fmt.Sprintf("median of %d timed runs", run.Runs)}},
+			// Load time.
+			perfRow{Tip: tips["Load time"], Cells: []string{fmtSecs(run.ColdLoadSec), "cold: the warm-up run loaded the model from disk"}},
+			// Total time.
+			perfRow{Tip: tips["Total time"], Cells: []string{fmtSecs(run.WarmTotalSec), fmt.Sprintf("median of %d timed runs, model already loaded", run.Runs)}},
+			// First word.
+			perfRow{Tip: tips["Time to first word"], Cells: []string{first, firstDetail}},
+			// Tokens.
+			perfRow{Tip: tips["Tokens counted"], Cells: []string{fmt.Sprintf("%d in, %d out", run.TokensIn, run.TokensOut), "the same fixed prompt every time (version " + run.PromptVersion + ")"}},
+		) // end of the rows
+	} // end of the kind check
+	// Add group A.
+	groups = append(groups, a)
+	// Group B: reported by Ollama.
+	b := perfGroup{Title: "Reported by Ollama about the loaded model", Cols: []string{"Result", "Detail"}}
+	// The processor split needs the memory figures.
+	split, splitDetail := "not reported", ""
+	// Work it out.
+	if run.ModelBytes > 0 {
+		// The graphics share.
+		gpuPct := float64(run.GPUBytes) / float64(run.ModelBytes) * 100
+		// The text.
+		split = fmt.Sprintf("%.0f%% graphics card, %.0f%% processor and main memory", gpuPct, 100-gpuPct)
+		// The detail.
+		splitDetail = "from the memory Ollama reports"
+	} // end of the split check
+	// The memory text.
+	memText := "not reported"
+	// Known.
+	if run.ModelBytes > 0 {
+		// Use the same size format as the tables.
+		memText = formatSize(run.ModelBytes)
+	} // end of the memory check
+	// The context text.
+	ctxText := "not reported"
+	// Known.
+	if run.ContextLength > 0 {
+		// The number.
+		ctxText = fmt.Sprintf("%d", run.ContextLength)
+	} // end of the context check
+	// The rows.
+	b.Rows = append(b.Rows,
+		// Split.
+		perfRow{Tip: tips["Processor split"], Cells: []string{split, splitDetail}},
+		// Memory.
+		perfRow{Tip: tips["Memory used"], Cells: []string{memText, "as Ollama reports it"}},
+		// Context.
+		perfRow{Tip: tips["Loaded context length"], Cells: []string{ctxText, "the context the model was loaded with"}},
+	) // end of the rows
+	// Add group B.
+	groups = append(groups, b)
+	// Group C: compared with the previous run.
+	c := perfGroup{Title: "Change since the previous run", Tip: tips["Change since the previous run"]}
+	// No earlier run.
+	if prev == nil {
+		// Say so.
+		c.Note = "No earlier test of this model with the same prompt is saved, so there is nothing to compare yet."
+	} else {
+		// The columns.
+		c.Cols = []string{"This run", "Previous run", "Change"}
+		// The previous run's date.
+		c.Note = "The previous run was made on " + formatTime(prev.Time) + "."
+		// An embedding model compares its time only.
+		if run.Kind == "embedding" {
+			// One row.
+			c.Rows = append(c.Rows, perfRow{Label: "Embedding time", Cells: []string{fmtSecs(run.WarmTotalSec), fmtSecs(prev.WarmTotalSec), changeText(run.WarmTotalSec, prev.WarmTotalSec, false)}})
+		} else {
+			// Three rows.
+			c.Rows = append(c.Rows,
+				// Answer speed: higher is faster.
+				perfRow{Label: "Answer speed", Cells: []string{fmtSpeed(run.AnswerSpeed), fmtSpeed(prev.AnswerSpeed), changeText(run.AnswerSpeed, prev.AnswerSpeed, true)}},
+				// Prompt speed: higher is faster.
+				perfRow{Label: "Prompt reading speed", Cells: []string{fmtSpeed(run.PromptSpeed), fmtSpeed(prev.PromptSpeed), changeText(run.PromptSpeed, prev.PromptSpeed, true)}},
+				// Total time: lower is faster.
+				perfRow{Label: "Total time", Cells: []string{fmtSecs(run.WarmTotalSec), fmtSecs(prev.WarmTotalSec), changeText(run.WarmTotalSec, prev.WarmTotalSec, false)}},
+			) // end of the rows
+		} // end of the kind check
+	} // end of the previous check
+	// Add group C.
+	groups = append(groups, c)
+	// Group D: the machine.
+	d := perfGroup{Title: "Machine condition during the test", Cols: []string{"Before the test", "With the model loaded"}}
+	// Ollama on another computer: only the note.
+	if !run.Before.Local {
+		// The note.
+		d.Note = run.Before.Note
+		// The other models are still known from Ollama itself.
+		others := "none"
+		// Some were loaded.
+		if len(run.OtherLoaded) > 0 {
+			// List them.
+			others = strings.Join(run.OtherLoaded, ", ")
+		} // end of the check
+		// One row.
+		d.Rows = append(d.Rows, perfRow{Tip: tips["Other models loaded"], Cells: []string{others, "-"}})
+	} else {
+		// The rows.
+		d.Rows = machineRows(run.Before, run.After, run.OtherLoaded, tips)
+	} // end of the local check
+	// Add group D.
+	groups = append(groups, d)
+	// Hand them back.
+	return groups
+} // end of buildGroups
+
+// historyTable builds the history table of one model: headings and lines, newest first, at most 20 lines.
+func historyTable(runs []perfRun, kind string) ([]string, [][]string) {
+	// The headings.
+	cols := []string{"Date", "Answer speed", "Prompt reading speed", "Load time (cold)", "Total time", "Machine busy?"}
+	// An embedding model has other columns.
+	if kind == "embedding" {
+		// Its headings.
+		cols = []string{"Date", "Embedding time", "Load time (cold)", "Tokens in", "Vector length", "Machine busy?"}
+	} // end of the kind check
+	// The lines.
+	var rows [][]string
+	// Go through the runs, newest first, at most twenty.
+	for i, r := range runs {
+		// Stop after twenty.
+		if i >= 20 {
+			// Enough.
+			break
+		} // end of the limit check
+		// The busy cell: a symbol and words, so colour is never the only signal.
+		busy := "no"
+		// Busy.
+		if r.Busy {
+			// Say so.
+			busy = "⚠ yes"
+		} // end of the busy check
+		// The line.
+		if kind == "embedding" {
+			// An embedding line.
+			rows = append(rows, []string{formatTime(r.Time), fmtSecs(r.WarmTotalSec), fmtSecs(r.ColdLoadSec), fmt.Sprintf("%d", r.TokensIn), fmt.Sprintf("%d", r.VectorLength), busy})
+		} else {
+			// A chat line.
+			rows = append(rows, []string{formatTime(r.Time), fmtSpeed(r.AnswerSpeed), fmtSpeed(r.PromptSpeed), fmtSecs(r.ColdLoadSec), fmtSecs(r.WarmTotalSec), busy})
+		} // end of the line choice
+	} // end of the loop
+	// Hand them back.
+	return cols, rows
+} // end of historyTable
+
+// perfHandlers builds the four handlers: the start page (changes nothing), the run, and the two steps of clearing the history.
+func perfHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
+	// Read the template once, together with the shared help-bubble templates; Must stops the program at start-up if it is broken, which a test would catch first.
+	page := template.Must(template.New("performance").Parse(performanceTemplateText + tipsTemplateText))
+	// The help bubbles never change, so build them once, each with an element name that is unique on the page.
+	tips := map[string]tipView{}
+	// One for each indicator, and the loaded context column that is shared with the Loaded table.
+	for i, h := range append(append([]string{}, perfHeadings...), "Loaded context length") {
+		// Build it.
+		tips[h] = makeTip(fmt.Sprintf("tip-perf-%d", i), h)
+	} // end of the loop
+	// Only one test may run at a time: two would disturb each other's figures.
+	var runLock sync.Mutex
+	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
+	show := func(w http.ResponseWriter, r *http.Request, status int, data perfPage) {
+		// Add what every version needs.
+		data.Theme, data.Token = themeFromRequest(r), token
+		// Build the page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason for the person running the program.
+			log.Printf("performance page error: %v", err)
+			// Send a plain 500 without details.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// The start page may run the monitor's own waiting-message script, and nothing else.
+		if data.Kind == "start" {
+			// Replace the strict policy by the one that allows the script file.
+			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
+		} // end of the script policy
+		// Tell the browser this is an HTML page.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the status line.
+		w.WriteHeader(status)
+		// Send the finished page.
+		w.Write(buf.Bytes())
+	} // end of show
+	// check runs the checks the start and the run share: the form, the model installed, not loaded, and able to be tested; ok is false after a page was shown.
+	check := func(w http.ResponseWriter, r *http.Request) (string, bool, bool) {
+		// The form checks: same page, valid token, sensible model name.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return "", false, false
+		} // end of the form checks
+		// Read the installed models now, not what the page showed earlier.
+		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, perfPage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return "", false, false
+		} // end of the installed read check
+		// The model must exist.
+		m, found := findInstalled(installed, name)
+		// Not installed.
+		if !found {
+			// Say so.
+			show(w, r, http.StatusOK, perfPage{Kind: "notinstalled", Model: name})
+			// Stop here.
+			return "", false, false
+		} // end of the installed check
+		// Read the loaded models.
+		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, perfPage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return "", false, false
+		} // end of the loaded read check
+		// A loaded model may be in use: the test is refused.
+		if _, ok := findLoaded(loaded, name); ok {
+			// Say so.
+			show(w, r, http.StatusOK, perfPage{Kind: "loaded", Model: name})
+			// Stop here.
+			return "", false, false
+		} // end of the loaded check
+		// Which kind of test fits the model.
+		switch categorize(m.Capabilities) {
+		// Embedding models are tested by embedding.
+		case categoryEmbedding:
+			// An embedding test.
+			return name, true, true
+		// Models that write text.
+		case categoryText, categoryMultimodal:
+			// A generate test.
+			return name, false, true
+		} // end of the switch
+		// Anything else cannot be tested.
+		show(w, r, http.StatusOK, perfPage{Kind: "unsupported", Model: name})
+		// Stop here.
+		return "", false, false
+	} // end of check
+	// historyFor fills the history part of a page for one model.
+	historyFor := func(p *perfPage, name string, embedding bool) {
+		// The kind.
+		kind := "generate"
+		// An embedding model.
+		if embedding {
+			// Its kind.
+			kind = "embedding"
+		} // end of the kind check
+		// The table.
+		p.HistoryCols, p.HistoryRows = historyTable(store.forModel(name, kind), kind)
+		// The count of all saved runs.
+		p.HistoryCount = store.count()
+		// Where the history lives.
+		path, note := store.where()
+		// A file, or the reason there is none.
+		if path != "" {
+			// Say where.
+			p.SaveNote = "Results are saved in " + path + " (numbers only; the last " + fmt.Sprint(maxHistoryRuns) + " runs are kept)."
+		} else {
+			// The reason.
+			p.SaveNote = note
+		} // end of the path check
+	} // end of historyFor
+	// start is the first step: it explains the test and the risks, and shows earlier results; it changes nothing.
+	start := func(w http.ResponseWriter, r *http.Request) {
+		// The checks.
+		name, embedding, ok := check(w, r)
+		// A page was already shown.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// The page.
+		p := perfPage{Kind: "start", Model: name, Embedding: embedding, Duration: "usually under a minute; a very large model can take several minutes to load"}
+		// What the machine looks like now: a busy machine gets a warning.
+		p.BusyReason = busyReason(snapshotMachine(r.Context(), isLocalAddress(addr.URL)))
+		// The history.
+		historyFor(&p, name, embedding)
+		// Show it.
+		show(w, r, http.StatusOK, p)
+	} // end of start
+	// run is the second step: it runs the test, saves the numbers and shows them.
+	run := func(w http.ResponseWriter, r *http.Request) {
+		// The checks.
+		name, embedding, ok := check(w, r)
+		// A page was already shown.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// Only one test at a time.
+		if !runLock.TryLock() {
+			// Say so.
+			show(w, r, http.StatusOK, perfPage{Kind: "running", Model: name})
+			// Stop here.
+			return
+		} // end of the lock check
+		// Release it when done.
+		defer runLock.Unlock()
+		// The Ollama version, for the record.
+		version := checkOllama(r.Context(), addr.URL, defaultCheckTimeout).Version
+		// Run the test.
+		res, err := performTest(r.Context(), addr.URL, name, embedding, version)
+		// The test failed.
+		if err != nil {
+			// Show the plain reason; the model was unloaded again by the test itself.
+			show(w, r, http.StatusBadGateway, perfPage{Kind: "error", Model: name, Detail: err.Error(), LeftLoaded: res.LeftLoaded})
+			// Stop here.
+			return
+		} // end of the failure check
+		// The previous run of the same model, kind and prompt, found before this one is added.
+		var prev *perfRun
+		// Newest first.
+		for _, old := range store.forModel(name, res.Kind) {
+			// Only runs with the same prompt are comparable.
+			if old.PromptVersion == res.PromptVersion {
+				// Keep a copy.
+				o := old
+				// This is it.
+				prev = &o
+				// Stop looking.
+				break
+			} // end of the prompt check
+		} // end of the loop
+		// Save the numbers.
+		saveErr := store.add(res)
+		// The page.
+		p := perfPage{Kind: "result", Model: name, Embedding: embedding, Groups: buildGroups(res, prev, tips), BusyReason: res.BusyReason, LeftLoaded: res.LeftLoaded}
+		// The history.
+		historyFor(&p, name, embedding)
+		// A save problem is told plainly.
+		if saveErr != nil {
+			// Say so.
+			p.SaveNote = "The result could not be saved to the file (" + saveErr.Error() + "), so it is kept only until the monitor stops."
+		} // end of the save check
+		// Show it.
+		show(w, r, http.StatusOK, p)
+	} // end of run
+	// clearAsk is the first step of clearing: it asks "are you sure?" and changes nothing.
+	clearAsk := func(w http.ResponseWriter, r *http.Request) {
+		// The form checks.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the form checks
+		// Show the question.
+		show(w, r, http.StatusOK, perfPage{Kind: "clearask", Model: name, HistoryCount: store.count()})
+	} // end of clearAsk
+	// clearDo is the second step: it removes every saved run.
+	clearDo := func(w http.ResponseWriter, r *http.Request) {
+		// The form checks.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the form checks
+		// Remove everything.
+		if err := store.clear(); err != nil {
+			// Say why.
+			show(w, r, http.StatusInternalServerError, perfPage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return
+		} // end of the clear check
+		// Say it is done.
+		show(w, r, http.StatusOK, perfPage{Kind: "cleared", Model: name})
+	} // end of clearDo
+	// Hand the four handlers back.
+	return start, run, clearAsk, clearDo
+} // end of perfHandlers
diff --git a/perfstore.go b/perfstore.go
new file mode 100644
index 0000000..d0fc05e
--- /dev/null
+++ b/perfstore.go
@@ -0,0 +1,247 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// encoding/json reads and writes the history file.
+	"encoding/json"
+	// errors builds plain error values.
+	"errors"
+	// fmt builds formatted text.
+	"fmt"
+	// os reads and writes the file.
+	"os"
+	// path/filepath joins folder and file names.
+	"path/filepath"
+	// sync keeps two requests from changing the history at the same moment.
+	"sync"
+) // end of imports
+
+// historyFileVersion is the format number written into the file, so a future version can tell old files apart.
+const historyFileVersion = 1
+
+// maxHistoryFile is the largest history file the monitor will read (8 MiB, far more than 200 runs need).
+const maxHistoryFile = 8 * 1024 * 1024
+
+// userConfigDir finds the person's configuration folder; a test replaces it so it never touches the real one.
+var userConfigDir = os.UserConfigDir
+
+// historyFile is the shape of the file on disk.
+type historyFile struct {
+	// Version is historyFileVersion.
+	Version int `json:"version"`
+	// Runs holds the saved runs, oldest first.
+	Runs []perfRun `json:"runs"`
+} // end of historyFile
+
+// perfStore keeps the saved test runs: in memory always, and in a file when the file can be used.
+type perfStore struct {
+	// mu protects everything below.
+	mu sync.Mutex
+	// path is the file; empty means memory only.
+	path string
+	// runs holds the runs, oldest first.
+	runs []perfRun
+	// note says why the file is not used (empty when all is well).
+	note string
+} // end of perfStore
+
+// defaultHistoryPath returns the history file in the person's configuration folder, or an empty text and a reason.
+func defaultHistoryPath() (string, string) {
+	// Ask for the configuration folder.
+	dir, err := userConfigDir()
+	// None found.
+	if err != nil || dir == "" {
+		// Memory only.
+		return "", "No configuration folder was found, so results are kept only until the monitor stops."
+	} // end of the lookup check
+	// The file lives in a folder of its own.
+	return filepath.Join(dir, "OllamaControlCenter", "performance.json"), ""
+} // end of defaultHistoryPath
+
+// openPerfStore opens the history at the given path (an empty path means memory only); a file that cannot be read is left untouched and the store stays in memory.
+func openPerfStore(path, note string) *perfStore {
+	// The store starts empty.
+	s := &perfStore{path: path, note: note}
+	// Memory only: nothing to read.
+	if path == "" {
+		// Done.
+		return s
+	} // end of the memory case
+	// Look at the file.
+	info, err := os.Stat(path)
+	// No file yet is normal.
+	if errors.Is(err, os.ErrNotExist) {
+		// Start empty.
+		return s
+	} // end of the missing-file case
+	// Some other problem with the file.
+	if err != nil {
+		// Keep the file untouched.
+		s.path, s.note = "", "The history file could not be opened ("+err.Error()+"), so results are kept only until the monitor stops."
+		// Done.
+		return s
+	} // end of the stat check
+	// A file that is far too large is not ours.
+	if info.Size() > maxHistoryFile {
+		// Keep the file untouched.
+		s.path, s.note = "", "The history file is unusually large, so it was left alone and results are kept only until the monitor stops."
+		// Done.
+		return s
+	} // end of the size check
+	// Read it.
+	data, err := os.ReadFile(path)
+	// A read problem.
+	if err != nil {
+		// Keep the file untouched.
+		s.path, s.note = "", "The history file could not be read ("+err.Error()+"), so results are kept only until the monitor stops."
+		// Done.
+		return s
+	} // end of the read check
+	// Decode it.
+	var h historyFile
+	// A damaged or foreign file.
+	if err := json.Unmarshal(data, &h); err != nil || h.Version != historyFileVersion {
+		// Keep the file untouched, so nothing is lost.
+		s.path, s.note = "", "The history file is damaged or from another version, so it was left alone and results are kept only until the monitor stops."
+		// Done.
+		return s
+	} // end of the decode check
+	// Use the saved runs.
+	s.runs = h.Runs
+	// Done.
+	return s
+} // end of openPerfStore
+
+// writeLocked writes the file (the caller holds the lock): a temporary file in the same folder, then a rename, so a crash never leaves half a file.
+func (s *perfStore) writeLocked() error {
+	// Memory only: nothing to write.
+	if s.path == "" {
+		// Not an error.
+		return nil
+	} // end of the memory case
+	// The folder, private to the person.
+	dir := filepath.Dir(s.path)
+	// Create it when missing.
+	if err := os.MkdirAll(dir, 0o700); err != nil {
+		// Say why.
+		return fmt.Errorf("the history folder could not be created: %w", err)
+	} // end of the folder check
+	// Encode the runs (an empty list is written as an empty list, not null).
+	runs := s.runs
+	// Avoid null.
+	if runs == nil {
+		// Empty list.
+		runs = []perfRun{}
+	} // end of the nil check
+	// The file text.
+	data, err := json.MarshalIndent(historyFile{Version: historyFileVersion, Runs: runs}, "", "  ")
+	// Cannot happen with these types.
+	if err != nil {
+		// Say why.
+		return fmt.Errorf("the history could not be encoded: %w", err)
+	} // end of the encode check
+	// A temporary file next to the real one.
+	tmp, err := os.CreateTemp(dir, "performance-*.tmp")
+	// Could not create it.
+	if err != nil {
+		// Say why.
+		return fmt.Errorf("the history file could not be written: %w", err)
+	} // end of the create check
+	// Remove the temporary file if anything below fails (after a successful rename it no longer exists).
+	defer os.Remove(tmp.Name())
+	// Only the person may read it.
+	if err := tmp.Chmod(0o600); err != nil {
+		// Close and report.
+		tmp.Close()
+		// Say why.
+		return fmt.Errorf("the history file could not be protected: %w", err)
+	} // end of the chmod check
+	// Write the text.
+	if _, err := tmp.Write(data); err != nil {
+		// Close and report.
+		tmp.Close()
+		// Say why.
+		return fmt.Errorf("the history file could not be written: %w", err)
+	} // end of the write check
+	// Close it so everything reaches the disk.
+	if err := tmp.Close(); err != nil {
+		// Say why.
+		return fmt.Errorf("the history file could not be written: %w", err)
+	} // end of the close check
+	// Replace the real file in one step.
+	if err := os.Rename(tmp.Name(), s.path); err != nil {
+		// Say why.
+		return fmt.Errorf("the history file could not be replaced: %w", err)
+	} // end of the rename check
+	// Saved.
+	return nil
+} // end of writeLocked
+
+// add appends one run, drops the oldest beyond the limit, and saves; the run is kept in memory even when the file cannot be written.
+func (s *perfStore) add(r perfRun) error {
+	// One change at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Append.
+	s.runs = append(s.runs, r)
+	// Drop the oldest ones beyond the limit.
+	if len(s.runs) > maxHistoryRuns {
+		// Keep the newest.
+		s.runs = append([]perfRun(nil), s.runs[len(s.runs)-maxHistoryRuns:]...)
+	} // end of the limit check
+	// Save.
+	return s.writeLocked()
+} // end of add
+
+// forModel returns the runs of one model and kind, newest first.
+func (s *perfStore) forModel(model, kind string) []perfRun {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// The result.
+	var out []perfRun
+	// Walk from the newest to the oldest.
+	for i := len(s.runs) - 1; i >= 0; i-- {
+		// A match.
+		if s.runs[i].Model == model && s.runs[i].Kind == kind {
+			// Keep it.
+			out = append(out, s.runs[i])
+		} // end of the match check
+	} // end of the loop
+	// Hand them back.
+	return out
+} // end of forModel
+
+// count says how many runs are saved in all.
+func (s *perfStore) count() int {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// The number.
+	return len(s.runs)
+} // end of count
+
+// where describes where the history lives, for the page.
+func (s *perfStore) where() (path, note string) {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Both values.
+	return s.path, s.note
+} // end of where
+
+// clear removes every saved run and saves the empty history.
+func (s *perfStore) clear() error {
+	// One change at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Forget everything.
+	s.runs = nil
+	// Save.
+	return s.writeLocked()
+} // end of clear
diff --git a/tooltips.go b/tooltips.go
index fcbbf60..16406bb 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -22,6 +22,9 @@ var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Lo
 // gearHeadings are the headings on the settings page and the Load page that have a help bubble, in the order they appear; a test checks each has a text.
 var gearHeadings = []string{"Set in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}
 
+// perfHeadings are the indicator names on the performance page that have a help bubble; a test checks each has a text.
+var perfHeadings = []string{"Answer speed", "Prompt reading speed", "Load time", "Total time", "Time to first word", "Tokens counted", "Embedding time", "Vector length", "Processor split", "Memory used", "Change since the previous run", "CPU cores", "CPU load", "Memory free", "Swap in use", "Other models loaded", "GPU"}
+
 // helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
 // The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
 var helpTexts = map[string]tooltip{
@@ -319,6 +322,159 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Fast answers against memory kept free for other work.",
 	}, // end of Keep-alive time
+	// The performance page: speed of the answer.
+	"Answer speed": {
+		// What it tells you.
+		Plain: "How fast the model writes, in tokens per second. A token is a piece of a word.",
+		// A real case from the test machine.
+		Example: "medgemma:latest writes about 80 tokens a second, qwen3.6:27b about 36.",
+		// What it helps with.
+		Decide: "Whether the model feels quick enough for the work you give it.",
+	}, // end of Answer speed
+	// The performance page: speed of reading the prompt.
+	"Prompt reading speed": {
+		// What it tells you.
+		Plain: "How fast the model reads your question or document before it starts to answer, in tokens per second.",
+		// A real case from the test machine.
+		Example: "With a short prompt, medgemma:latest read about 640 tokens a second and qwen3.6:27b about 168.",
+		// What it helps with.
+		Decide: "Whether long documents will make you wait.",
+	}, // end of Prompt reading speed
+	// The performance page: load time.
+	"Load time": {
+		// What it tells you.
+		Plain: "The time to bring the model from disk into memory. It is near zero when the model is already loaded.",
+		// A real case from the test machine.
+		Example: "qwen3.6:27b needed 7.0 s to load, medgemma:latest 3.7 s.",
+		// What it helps with.
+		Decide: "Whether to keep the model loaded longer between uses.",
+	}, // end of Load time
+	// The performance page: total time.
+	"Total time": {
+		// What it tells you.
+		Plain: "The whole request from start to finish, with the model already loaded.",
+		// A real case from the test machine.
+		Example: "A 64-token answer took 1.9 s with qwen3.6:27b and 0.78 s with medgemma:latest.",
+		// What it helps with.
+		Decide: "How long a typical short request takes.",
+	}, // end of Total time
+	// The performance page: time to first word.
+	"Time to first word": {
+		// What it tells you.
+		Plain: "How long you wait before the first text appears. Warm means the model was loaded; cold includes loading it.",
+		// A real case from the test machine.
+		Example: "medgemma:latest started writing after 0.03 s when warm.",
+		// What it helps with.
+		Decide: "Whether the model feels responsive in a chat.",
+	}, // end of Time to first word
+	// The performance page: tokens counted.
+	"Tokens counted": {
+		// What it tells you.
+		Plain: "How many tokens the test prompt had and how many the model wrote. The test is the same every time.",
+		// A real case.
+		Example: "About 200 tokens in and at most 64 out.",
+		// What it helps with.
+		Decide: "Whether two runs can be compared fairly: the same prompt version means yes.",
+	}, // end of Tokens counted
+	// The performance page: embedding time.
+	"Embedding time": {
+		// What it tells you.
+		Plain: "How long the model needs to turn the fixed text into numbers, with the model already loaded.",
+		// A real case from the test machine.
+		Example: "rjmalagon/gte-qwen2-instruct needed 0.043 s for a short text.",
+		// What it helps with.
+		Decide: "Whether it is fast enough to prepare many documents for search.",
+	}, // end of Embedding time
+	// The performance page: vector length.
+	"Vector length": {
+		// What it tells you.
+		Plain: "How many numbers the model produces for one text. It belongs to the model, not to the machine.",
+		// A real case from the test machine.
+		Example: "rjmalagon/gte-qwen2-instruct gives 1536 numbers.",
+		// What it helps with.
+		Decide: "Whether it fits the search system that will store the numbers.",
+	}, // end of Vector length
+	// The performance page: processor split.
+	"Processor split": {
+		// What it tells you.
+		Plain: "How much of the model sits in the graphics card's memory, and how much is left to the processor and main memory.",
+		// A real case from the test machine.
+		Example: "qwen3.6:27b ran 100% on the graphics card.",
+		// What it helps with.
+		Decide: "A processor share explains slow answers; a smaller model may fit on the graphics card.",
+	}, // end of Processor split
+	// The performance page: memory used.
+	"Memory used": {
+		// What it tells you.
+		Plain: "The memory Ollama reports for the loaded model.",
+		// A real case from the test machine.
+		Example: "qwen3.6:27b: 18.8 GB (gigabytes).",
+		// What it helps with.
+		Decide: "Whether another model still fits next to it.",
+	}, // end of Memory used
+	// The performance page: change since the previous run.
+	"Change since the previous run": {
+		// What it tells you.
+		Plain: "How much a figure moved compared with the last test of the same model, as a percentage.",
+		// A real case.
+		Example: "38 tokens/s before and 31 tokens/s now is -18%, which is slower.",
+		// What it helps with.
+		Decide: "Whether a setting, an update or a busy machine made the model faster or slower.",
+	}, // end of Change since the previous run
+	// The performance page: processor cores.
+	"CPU cores": {
+		// What it tells you.
+		Plain: "How many processor cores the computer has.",
+		// A real case from the test machine.
+		Example: "20 on this computer.",
+		// What it helps with.
+		Decide: "How much room the processor has when part of a model spills onto it.",
+	}, // end of CPU cores
+	// The performance page: processor load.
+	"CPU load": {
+		// What it tells you.
+		Plain: "How busy the processor was during the last minute. Compare it with the number of cores.",
+		// A real case from the test machine.
+		Example: "A load of 1.8 on 20 cores is quiet.",
+		// What it helps with.
+		Decide: "Whether other work disturbed the test.",
+	}, // end of CPU load
+	// The performance page: free memory.
+	"Memory free": {
+		// What it tells you.
+		Plain: "The memory the system could still hand out, before the test and with the model loaded.",
+		// A real case from the test machine.
+		Example: "About 114 GB (gigabytes) before and 105 GB (gigabytes) with medgemma:latest loaded.",
+		// What it helps with.
+		Decide: "Whether the machine was short of memory.",
+	}, // end of Memory free
+	// The performance page: swap.
+	"Swap in use": {
+		// What it tells you.
+		Plain: "Memory that spilled over to the disk, which is far slower than real memory.",
+		// A real case from the test machine.
+		Example: "0 GB (gigabytes) in use on this computer.",
+		// What it helps with.
+		Decide: "Why a run was very slow.",
+	}, // end of Swap in use
+	// The performance page: other models in memory.
+	"Other models loaded": {
+		// What it tells you.
+		Plain: "Models that were already in memory when the test started. They share the machine with the tested model.",
+		// A real case from the test machine.
+		Example: "None during the first experiments.",
+		// What it helps with.
+		Decide: "Whether the figures are fair.",
+	}, // end of Other models loaded
+	// The performance page: graphics card.
+	"GPU": {
+		// What it tells you.
+		Plain: "The graphics card the monitor could see, and how busy it was then. Shared memory shows as not reported.",
+		// A real case from the test machine.
+		Example: "The NVIDIA graphics card in this computer was 0% busy before the test.",
+		// What it helps with.
+		Decide: "Whether the graphics card was shared with other work.",
+	}, // end of GPU
 } // end of helpTexts
 
 // helpFor returns the tooltip for a heading, and false when there is none.
diff --git a/tooltips_test.go b/tooltips_test.go
index 416858e..395bf08 100644
--- a/tooltips_test.go
+++ b/tooltips_test.go
@@ -30,6 +30,8 @@ func allHeadings() []string {
 	} // end of the column loop
 	// Then the headings of the settings page and the Load page.
 	out = append(out, gearHeadings...)
+	// The performance page headings.
+	out = append(out, perfHeadings...)
 	// Then the four categories, by their display names.
 	for c := categoryEmbedding; c <= categoryUnclassified; c++ {
 		// Add the category's heading text.
diff --git a/web.go b/web.go
index 456a2d2..74322cd 100644
--- a/web.go
+++ b/web.go
@@ -106,6 +106,18 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /gear/save", gearSave)
 	// Route: a POST request for "/modelfile" shows a model's Modelfile, read-only.
 	mux.HandleFunc("POST /modelfile", modelfileHandler(addr, token))
+	// Make the four performance handlers: the start page, the test run, and the two steps of clearing the saved results (the checks are in perfpage.go); the history lives in the person's configuration folder.
+	histPath, histNote := defaultHistoryPath()
+	// Open the saved results.
+	perfStart, perfRun, perfClearAsk, perfClearDo := perfHandlers(addr, token, openPerfStore(histPath, histNote))
+	// Route: a POST request for "/performance" shows the performance page and changes nothing.
+	mux.HandleFunc("POST /performance", perfStart)
+	// Route: a POST request for "/performance/run" runs the test.
+	mux.HandleFunc("POST /performance/run", perfRun)
+	// Route: a POST request for "/performance/clear" asks whether to remove the saved results.
+	mux.HandleFunc("POST /performance/clear", perfClearAsk)
+	// Route: a POST request for "/performance/clear/confirm" removes them.
+	mux.HandleFunc("POST /performance/clear/confirm", perfClearDo)
 	// Route: a GET request for "/countdown.js" sends the small script that makes the timers tick (only the message pages use it).
 	mux.HandleFunc("GET /countdown.js", countdownHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
diff --git a/web/app.css b/web/app.css
index d524790..94bcc2f 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1034,3 +1034,39 @@ code {
   /* Exactly the size of the surrounding text, in headings too. */
   font-size: 1em;
 } /* end of rule */
+
+/* Performance pages: every table uses the same column widths so stacked tables line up. */
+.perftable {
+  /* Fixed layout so widths come from the header cells only. */
+  table-layout: fixed;
+  /* Use the full width of the panel. */
+  width: 100%;
+} /* end of rule */
+
+/* First column (indicator names). */
+.perftable th:nth-child(1) {
+  /* About a quarter of the width. */
+  width: 24%;
+} /* end of rule */
+
+/* Second column (result). */
+.perftable th:nth-child(2) {
+  /* About a third of the width. */
+  width: 32%;
+} /* end of rule */
+
+/* Space above the second-level headings on the performance pages. */
+.panel h2 + table, .panel table + h2 {
+  /* A little air. */
+  margin-top: 0.75rem;
+} /* end of rule */
+
+/* A button that is drawn like a plain link button keeps the page font. */
+button.btn-plain {
+  /* Same font as the page. */
+  font: inherit;
+  /* A hand cursor. */
+  cursor: pointer;
+  /* Transparent background like the link version. */
+  background: transparent;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 5250a93..44c0823 100644
--- a/web/index.html
+++ b/web/index.html
@@ -79,7 +79,7 @@
 {{/* Case 4: the table itself. */}}
 {{else}}
 {{/* A hint above the table so people know the dotted headings have help. */}}
-<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The table scrolls sideways.</p>
+<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The chart icon 📈 before a model name opens its performance page (a model that is loaded may be in use, so it has none). The table scrolls sideways.</p>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
@@ -134,7 +134,28 @@
 {{/* A model row; the name and loaded flag let the script compare this page with a fresh copy. */}}
 <tr data-model="{{.Name}}" data-loaded="{{if .Loaded}}1{{else}}0{{end}}">{{/* start of a table row. */}}
 {{/* The model name is the row heading and stays visible while scrolling. */}}
-<th scope="row" class="stickycol">{{.Name}}</th>
+<th scope="row" class="stickycol">
+{{/* The performance icon comes before the name; a loaded model may be in use, so it gets an empty slot of the same width instead, and the names stay in line. */}}
+{{if .Loaded}}<span class="gearslot" aria-hidden="true"></span>{{else}}
+{{/* A small form that sends the model name and the page token to the performance page, which changes nothing. */}}
+<form class="gearform" method="post" action="/performance">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{$.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Name}}">
+{{/* The area that opens the tip: pointing at the icon or reaching it with Tab shows what it is for. */}}
+<span class="tipbox">
+{{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
+<button type="submit" class="gear" aria-label="Performance of {{.Name}}" aria-describedby="tipperf-{{.Name}}"><span aria-hidden="true">📈</span></button>
+{{/* The tip. */}}
+<span class="tip tip-icon" role="tooltip" id="tipperf-{{.Name}}">Performance: see how fast this model runs on this machine</span>
+{{/* End of the tip area. */}}
+</span>
+{{/* End of the form. */}}
+</form>
+{{/* End of the performance icon. */}}
+{{end}}
+{{.Name}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
 <td>
 {{/* Two small icons stacked in a fixed-width column, centred above each other: the Modelfile page icon on top (for every model) and the gear just below it (only for a model that is not loaded; a loaded model gets an empty slot, so the state words stay in line). */}}
diff --git a/web/performance.html b/web/performance.html
new file mode 100644
index 0000000..87f4fa6
--- /dev/null
+++ b/web/performance.html
@@ -0,0 +1,185 @@
+{{/* Performance page template: one page with several versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
+{{/* A table of results: the first column holds the indicator (with its help bubble when it has one), the others hold the values. */}}
+{{define "perfgroup"}}
+{{/* The heading of the table, with a bubble when it has one. */}}
+<h2>{{if .Tip.ID}}{{template "tipbox" .Tip}}{{else}}{{.Title}}{{end}}</h2>
+{{/* A sentence under the heading. */}}
+{{if .Note}}<p class="muted">{{.Note}}</p>{{end}}
+{{/* The table, only when it has rows. */}}
+{{if .Rows}}
+<table class="settingtable perftable">
+{{/* The column headings. */}}
+<thead><tr><th scope="col">Indicator</th>{{range .Cols}}<th scope="col">{{.}}</th>{{end}}</tr></thead>
+{{/* The body. */}}
+<tbody>
+{{/* One row for each indicator. */}}
+{{range $r := .Rows}}
+{{/* The row: the first cell names the indicator. */}}
+<tr><th scope="row">{{if $r.Tip.ID}}{{template "tipbox" $r.Tip}}{{else}}{{$r.Label}}{{end}}</th>{{range $i, $c := $r.Cells}}<td data-label="{{index $.Cols $i}}">{{$c}}</td>{{end}}</tr>
+{{/* End of the rows. */}}
+{{end}}
+{{/* End of the body. */}}
+</tbody>
+</table>
+{{/* End of the rows check. */}}
+{{end}}
+{{/* End of the group. */}}
+{{end}}
+{{/* The history table of one model. */}}
+{{define "perfhistory"}}
+{{/* Only when there are saved runs. */}}
+{{if .HistoryRows}}
+<h2>Saved tests of this model</h2>
+<table class="settingtable perftable">
+{{/* The headings. */}}
+<thead><tr>{{range .HistoryCols}}<th scope="col">{{.}}</th>{{end}}</tr></thead>
+{{/* The body. */}}
+<tbody>
+{{/* One row for each saved run, newest first. */}}
+{{range $row := .HistoryRows}}
+<tr>{{range $i, $c := $row}}<td data-label="{{index $.HistoryCols $i}}">{{$c}}</td>{{end}}</tr>
+{{/* End of the rows. */}}
+{{end}}
+{{/* End of the body. */}}
+</tbody>
+</table>
+{{/* No saved run. */}}
+{{else}}
+<p class="muted">No test of this model is saved yet.</p>
+{{/* End of the check. */}}
+{{end}}
+{{/* Where the numbers are kept, and the button that clears them. */}}
+{{if .SaveNote}}<p class="muted">{{.SaveNote}}</p>{{end}}
+{{if .HistoryCount}}
+{{/* A small form that sends the model name and the page token to the clear question. */}}
+<form method="post" action="/performance/clear">
+<input type="hidden" name="token" value="{{.Token}}">
+<input type="hidden" name="model" value="{{.Model}}">
+<button type="submit" class="btn-plain">Clear all saved results ({{.HistoryCount}})…</button>
+</form>
+{{end}}
+{{end}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Performance - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+{{/* The waiting-message script, only on the start page. */}}
+{{if eq .Kind "start"}}<script src="/loading.js" defer></script>{{end}}
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* A panel that holds the message. */}}
+<section class="panel">
+{{/* The heading names the model, so there is no doubt which one is meant. */}}
+<h1>Performance of <code>{{.Model}}</code></h1>
+{{/* Version 1: the start page. */}}
+{{if eq .Kind "start"}}
+{{/* The caution, with a symbol and a bold lead, so colour is never the only signal. */}}
+<p class="warn" role="note"><strong>⚠ Caution: do not run this while the model is in use.</strong> The test makes the model {{if .Embedding}}work through a text{{else}}write text{{end}}. If a person or a program is using it, the test can slow their work down or wait in line behind it, and your numbers will come out too low. It can also use extra memory, and on a full machine Ollama may unload another model to make room. Run it when Ollama is idle.</p>
+{{/* A second warning when the machine looks busy right now. */}}
+{{if .BusyReason}}
+<p class="warn" role="alert"><strong>⚠ The machine looks busy right now:</strong> {{.BusyReason}}. The figures of a test would be unreliable.</p>
+{{end}}
+{{/* What the test does. */}}
+<p>What the test does, in order:</p>
+<ol>
+<li>One warm-up request loads the model from disk. Its load time is reported as the cold figure.</li>
+<li>Three timed requests follow with the model in memory; each result is the median of the three.</li>
+<li>The monitor reads what Ollama reports about the loaded model, and what the machine looks like.</li>
+<li>The model is unloaded again, so memory is left as it was found.</li>
+</ol>
+<p class="muted">The test uses the same fixed prompt every time ({{if .Embedding}}an embedding model gets the same text{{else}}about 200 tokens; each answer is capped at 64 tokens{{end}}). Time needed: {{.Duration}}. Only numbers are saved, never any text.</p>
+{{/* The two choices side by side. */}}
+<div class="choices" id="choices">
+{{/* The Run form sends the model name and the page token to the second step. */}}
+<form id="perfform" method="post" action="/performance/run" data-loading>
+<input type="hidden" name="token" value="{{.Token}}">
+<input type="hidden" name="model" value="{{.Model}}">
+<button type="submit" class="btn-load">Run the performance test</button>
+</form>
+{{/* The Cancel link simply goes back; nothing was changed. */}}
+<a class="btn-plain" href="/">Back to the monitor</a>
+</div>
+{{/* The waiting box: hidden at first; the script shows it when Run is pressed. */}}
+<div id="loading" role="status" aria-live="polite" hidden>
+<p><strong>Testing, please wait.</strong> Ollama is working on <code>{{.Model}}</code>. Time passed: <span class="elapsed">0 s</span></p>
+<div class="bar" aria-hidden="true"><span class="barfill"></span></div>
+<p class="muted">The bar only shows that work is going on. It is not a percentage. Please do not close this page and do not use the model meanwhile.</p>
+</div>
+{{/* The saved tests. */}}
+{{template "perfhistory" .}}
+{{/* Version 2: the result. */}}
+{{else if eq .Kind "result"}}
+{{/* The warnings. */}}
+{{if .BusyReason}}
+<p class="warn" role="alert"><strong>⚠ The machine looked busy before the test:</strong> {{.BusyReason}}. Treat these figures with care.</p>
+{{end}}
+{{if .LeftLoaded}}
+<p class="warn" role="alert"><strong>⚠ The model could not be unloaded again.</strong> It is still in memory; use the Unload button on the monitor page.</p>
+{{end}}
+{{/* The four tables. */}}
+{{range .Groups}}{{template "perfgroup" .}}{{end}}
+{{/* The saved tests, with the clear button. */}}
+{{template "perfhistory" .}}
+{{/* The links. */}}
+<div class="choices">
+<form method="post" action="/performance">
+<input type="hidden" name="token" value="{{.Token}}">
+<input type="hidden" name="model" value="{{.Model}}">
+<button type="submit" class="btn-plain">Performance page of this model</button>
+</form>
+<a class="btn-plain" href="/">Back to the monitor</a>
+</div>
+{{/* Version 3: the model is loaded, so no test. */}}
+{{else if eq .Kind "loaded"}}
+<p>This model is loaded now and may be in use, so the test is not run. Unload it first (or wait until nobody uses it), then run the test.</p>
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 4: not installed. */}}
+{{else if eq .Kind "notinstalled"}}
+<p>This model is not installed, so it cannot be tested.</p>
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 5: Ollama does not say what the model can do. */}}
+{{else if eq .Kind "unsupported"}}
+<p>Ollama does not report that this model can write text or make embeddings, so the test cannot judge its speed.</p>
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 6: another test is running. */}}
+{{else if eq .Kind "running"}}
+<p><strong>Another performance test is running.</strong> Two tests at once would disturb each other's figures. Wait until it has finished, then try again.</p>
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 7: ask before clearing. */}}
+{{else if eq .Kind "clearask"}}
+<p class="warn"><strong>⚠ This removes all {{.HistoryCount}} saved test results, for every model.</strong> It cannot be undone.</p>
+<div class="choices">
+<form method="post" action="/performance/clear/confirm">
+<input type="hidden" name="token" value="{{.Token}}">
+<input type="hidden" name="model" value="{{.Model}}">
+<button type="submit" class="btn-load">Yes, remove them all</button>
+</form>
+<a class="btn-plain" href="/">Cancel, keep them</a>
+</div>
+{{/* Version 8: cleared. */}}
+{{else if eq .Kind "cleared"}}
+<p><strong>Done.</strong> All saved test results were removed.</p>
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 9: something went wrong. */}}
+{{else}}
+<p><strong>Could not do this.</strong> {{.Detail}}</p>
+{{if .LeftLoaded}}<p class="warn" role="alert"><strong>⚠ The model could not be unloaded again.</strong> It may still be in memory; use the Unload button on the monitor page.</p>{{end}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* End of the versions. */}}
+{{end}}
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/webtable_test.go b/webtable_test.go
index 4bce601..efd6d72 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -114,10 +114,10 @@ func TestTablePageRealModels(t *testing.T) {
 	i1 := strings.Index(body, "<strong>Search and similarity (embedding)</strong>")
 	// The multimodal heading position.
 	i2 := strings.Index(body, "<strong>Chat with images or audio (multimodal)</strong>")
-	// The first embedding model, found as a row heading (the help bubbles also mention model names).
-	i3 := strings.Index(body, `class="stickycol">hf.co/NeoRoth`)
+	// The first embedding model, found as a table row (the help bubbles also mention model names).
+	i3 := strings.Index(body, `<tr data-model="hf.co/NeoRoth`)
 	// The second embedding model, found the same way.
-	i4 := strings.Index(body, `class="stickycol">rjmalagon/gte-qwen2`)
+	i4 := strings.Index(body, `<tr data-model="rjmalagon/gte-qwen2`)
 	// All four positions must be in this order.
 	if !(i1 < i3 && i3 < i4 && i4 < i2) {
 		// Report the order found.
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
1c30f83edddc6dc70abc89f01368cb1de5080cf68d3e693bfb07d9ef9d7d45fd  gear_test.go
fef50691293ac274b95a27d9e3bb5d61ab1a53da723c64868569f47e0932608a  machine.go
a68c66823aef87554d4cf257d75d5449de3fc4f1fa28cd413177301dcf702295  perf.go
40f1d91aa124d44b7e311a9f028c5db278ba8bd2ee23f16506e900716d194c69  perf_test.go
fc61771c218f5627a46afa5241b2b238c3966f2f249917aaf9433143d7c5b4d5  perfpage.go
795d0aabc6fec1f19bf3ee24ca8501efbe07eedbbc9b05b32292960bae88283b  perfstore.go
48680af11f0f3d379e17af9968a11731bf1c2fc9ad2a73431cdd14540b2d9f00  tooltips.go
cf10cb04dcb84b7b58d4d8ef9fc30f39d75bd671ca5f89a2add7bf4dbec4cf1a  tooltips_test.go
204c9bd4a5dee9e94569469fa3271ebe2ce19468626ffbf56df16ba95d10177d  web.go
2e60c8ec93f7b87505e728abeda05e9e43ac669863f86cbe532e9c7156239ead  web/app.css
9ac6eecde888eaab0e21af125808f1171c666b068aa11984d1585c4e9b59cb21  web/index.html
ef6a32ff7f7130a8155b652cee78dd5239ec3c1027350a9347d11bfa5710f80c  web/performance.html
f6434a76c8b2732b7176bd6b212be877ac703d2db546a6056f3cfacda230a395  webtable_test.go
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
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
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
# List the changed files; nothing is committed yet.
git status --short
