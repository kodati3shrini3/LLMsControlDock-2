// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bufio reads the streamed reply piece by piece.
	"bufio"
	// bytes wraps the request body.
	"bytes"
	// context lets a test be cancelled or given a deadline.
	"context"
	// encoding/json reads and writes Ollama's messages.
	"encoding/json"
	// errors builds plain error values.
	"errors"
	// fmt builds formatted text.
	"fmt"
	// io limits how much of a reply is read.
	"io"
	// net/http sends the requests.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// sort puts numbers in order for the median.
	"sort"
	// strings trims text.
	"strings"
	// time measures how long things take.
	"time"
) // end of imports

// perfPromptVersion names the fixed prompt; saved runs carry it, so only runs with the same prompt are compared.
const perfPromptVersion = "v1"

// perfPrompt is the fixed prompt of every test (about 200 tokens, so the prompt reading speed is a real figure). It is the program's own text; no text of the person is ever sent or stored.
const perfPrompt = "Read the following passage and then answer the question after it. " +
	"A lighthouse stands on a narrow headland where the sea is rough for most of the year. " +
	"Its keeper climbs the spiral staircase every evening, checks the lamp, polishes the lens and writes the weather in a thick logbook. " +
	"Ships that pass at night rely on the rhythm of the light to know which stretch of coast they are near, because every lighthouse flashes in its own pattern. " +
	"On clear days the keeper repairs the stone steps, paints the iron railings and counts the gulls that nest in the cliffs. " +
	"When fog rolls in, the keeper sounds a horn every thirty seconds, and the long, low note carries far across the water. " +
	"Supplies arrive once a month by boat, and the keeper trades news and tea with the crew before they sail away again. " +
	"In winter the storms are so strong that waves climb the rocks and spray reaches the windows near the top of the tower. " +
	"Question: In two sentences, what does the keeper do to keep ships safe?"

// perfTimedRuns is how many timed runs follow the warm-up run; the saved figure is their median.
const perfTimedRuns = 3

// perfAnswerTokens caps the length of every answer, so every run does the same amount of work.
const perfAnswerTokens = 64

// perfRequestTimeout is how long one request of the test may take; a very large model can need minutes to load.
const perfRequestTimeout = 10 * time.Minute

// maxPerfReply caps how many bytes of one test reply are read (64 MiB, far more than the real reply).
const maxPerfReply = 64 * 1024 * 1024

// maxHistoryRuns is how many runs the history keeps; older ones are dropped.
const maxHistoryRuns = 200

// perfFigures is what one request of the test reported, in Ollama's own units (durations in nanoseconds).
type perfFigures struct {
	// TotalNs is the whole request.
	TotalNs int64
	// LoadNs is the time to bring the model into memory.
	LoadNs int64
	// PromptCount is how many tokens the prompt had.
	PromptCount int64
	// PromptNs is the time spent reading the prompt.
	PromptNs int64
	// EvalCount is how many tokens the model wrote.
	EvalCount int64
	// EvalNs is the time spent writing them.
	EvalNs int64
	// FirstWord is the time until the first piece of output arrived, measured by this program on a streamed reply.
	FirstWord time.Duration
	// GotFirstWord is true when a first piece of output was seen.
	GotFirstWord bool
	// VectorLength is the length of the first embedding vector (embedding models only).
	VectorLength int
} // end of perfFigures

// perfRun is one saved test: numbers and names only, never any text of a prompt or an answer. A zero in a speed or time field means "not available".
type perfRun struct {
	// Time is when the test finished, in UTC.
	Time time.Time `json:"time"`
	// Model is the tested model.
	Model string `json:"model"`
	// Kind is generate for chat models and embedding for embedding models.
	Kind string `json:"kind"`
	// OllamaVersion is the version Ollama reported.
	OllamaVersion string `json:"ollama_version"`
	// Host is the address part of the Ollama address (no password).
	Host string `json:"host"`
	// PromptVersion names the fixed prompt.
	PromptVersion string `json:"prompt_version"`
	// Runs is how many timed runs the medians come from.
	Runs int `json:"runs"`
	// AnswerSpeed is the median answer speed in tokens per second.
	AnswerSpeed float64 `json:"answer_speed,omitempty"`
	// PromptSpeed is the median prompt reading speed in tokens per second.
	PromptSpeed float64 `json:"prompt_speed,omitempty"`
	// ColdLoadSec is the load time of the warm-up run, which loaded the model.
	ColdLoadSec float64 `json:"cold_load_sec,omitempty"`
	// ColdFirstWordSec is the measured time to the first word of the warm-up run.
	ColdFirstWordSec float64 `json:"cold_first_word_sec,omitempty"`
	// WarmFirstWordSec is the median measured time to the first word of the timed runs.
	WarmFirstWordSec float64 `json:"warm_first_word_sec,omitempty"`
	// WarmTotalSec is the median total time of the timed runs (for an embedding model, the embedding time).
	WarmTotalSec float64 `json:"warm_total_sec,omitempty"`
	// TokensIn is the number of prompt tokens.
	TokensIn int64 `json:"tokens_in,omitempty"`
	// TokensOut is the number of tokens written.
	TokensOut int64 `json:"tokens_out,omitempty"`
	// VectorLength is the length of an embedding vector.
	VectorLength int `json:"vector_length,omitempty"`
	// ModelBytes is the memory Ollama reports for the loaded model.
	ModelBytes int64 `json:"model_bytes,omitempty"`
	// GPUBytes is how much of it sits in graphics memory.
	GPUBytes int64 `json:"gpu_bytes,omitempty"`
	// ContextLength is the context the model was loaded with.
	ContextLength int64 `json:"context_length,omitempty"`
	// OtherLoaded lists the models that were loaded when the test started.
	OtherLoaded []string `json:"other_loaded,omitempty"`
	// Busy is true when the machine looked busy before the test.
	Busy bool `json:"busy"`
	// BusyReason says why.
	BusyReason string `json:"busy_reason,omitempty"`
	// Before and After are the machine snapshots around the test.
	Before machineSnapshot `json:"before"`
	// After is the snapshot after the timed runs, with the model still loaded.
	After machineSnapshot `json:"after"`
	// LeftLoaded is true when the model could not be unloaded again.
	LeftLoaded bool `json:"left_loaded,omitempty"`
} // end of perfRun

// secs turns nanoseconds into seconds.
func secs(ns int64) float64 {
	// One second is a billion nanoseconds.
	return float64(ns) / 1e9
} // end of secs

// perSecond turns a count and a duration in nanoseconds into a speed per second; zero means it cannot be worked out.
func perSecond(count, ns int64) float64 {
	// A speed needs both numbers.
	if count <= 0 || ns <= 0 {
		// Not available.
		return 0
	} // end of the check
	// Count divided by seconds.
	return float64(count) / secs(ns)
} // end of perSecond

// median returns the middle value of the numbers above zero; zero when there are none. With an even count it is the mean of the two in the middle.
func median(vals []float64) float64 {
	// Keep only usable numbers.
	var v []float64
	// Go through the input.
	for _, x := range vals {
		// A zero means "not available".
		if x > 0 {
			// Keep it.
			v = append(v, x)
		} // end of the check
	} // end of the loop
	// Nothing usable.
	if len(v) == 0 {
		// Not available.
		return 0
	} // end of the empty check
	// Put them in order.
	sort.Float64s(v)
	// The middle.
	mid := len(v) / 2
	// An odd count has one middle value.
	if len(v)%2 == 1 {
		// Return it.
		return v[mid]
	} // end of the odd case
	// An even count: the mean of the two middle values.
	return (v[mid-1] + v[mid]) / 2
} // end of median

// genPiece is one line of a streamed /api/generate reply.
type genPiece struct {
	// Response is the next piece of the answer text (never stored).
	Response string `json:"response"`
	// Thinking is the next piece of a thinking model's reasoning text (never stored).
	Thinking string `json:"thinking"`
	// Done is true on the last piece, which carries the figures.
	Done bool `json:"done"`
	// Error is Ollama's own message when the request failed.
	Error string `json:"error"`
	// TotalDuration is the whole request in nanoseconds.
	TotalDuration int64 `json:"total_duration"`
	// LoadDuration is the load time in nanoseconds.
	LoadDuration int64 `json:"load_duration"`
	// PromptEvalCount is the number of prompt tokens.
	PromptEvalCount int64 `json:"prompt_eval_count"`
	// PromptEvalDuration is the prompt reading time in nanoseconds.
	PromptEvalDuration int64 `json:"prompt_eval_duration"`
	// EvalCount is the number of tokens written.
	EvalCount int64 `json:"eval_count"`
	// EvalDuration is the writing time in nanoseconds.
	EvalDuration int64 `json:"eval_duration"`
} // end of genPiece

// shortMessage keeps the start of a refusal text, so a long reply never fills the page.
func shortMessage(b []byte) string {
	// Ollama's own error shape.
	var e struct {
		// Error is the message.
		Error string `json:"error"`
	} // end of the shape
	// Try to read it; on failure the raw text is used.
	_ = json.Unmarshal(b, &e)
	// The message or the raw text.
	msg := strings.TrimSpace(e.Error)
	// No JSON message: use the raw text.
	if msg == "" {
		// Raw text.
		msg = strings.TrimSpace(string(b))
	} // end of the fallback
	// Keep at most 200 bytes.
	if len(msg) > 200 {
		// Cut it.
		msg = msg[:200]
	} // end of the cut
	// Hand it back.
	return msg
} // end of shortMessage

// runGenerate sends the fixed prompt once, reads the streamed reply and returns the figures; the first word is timed by this program.
func runGenerate(ctx context.Context, base *url.URL, model string) (perfFigures, error) {
	// Build the request body: the model, the fixed prompt, a stream, a keep-alive so the model stays for the next run, and options that keep every run alike.
	body, err := json.Marshal(map[string]any{"model": model, "prompt": perfPrompt, "stream": true, "keep_alive": "2m", "options": map[string]any{"num_predict": perfAnswerTokens, "temperature": 0, "seed": 1}})
	// A marshal failure cannot happen with these values; report it plainly if it ever does.
	if err != nil {
		// Plain message.
		return perfFigures{}, errors.New("the request could not be built")
	} // end of the marshal check
	// Give the request a deadline.
	ctx, cancel := context.WithTimeout(ctx, perfRequestTimeout)
	// Release the timer at the end.
	defer cancel()
	// Build the request.
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base.JoinPath("api/generate").String(), bytes.NewReader(body))
	// The address could not be used.
	if err != nil {
		// Plain message.
		return perfFigures{}, errors.New("the address could not be used to build a request")
	} // end of the request check
	// The body is JSON.
	req.Header.Set("Content-Type", "application/json")
	// Remember when the request starts.
	start := time.Now()
	// Send it; the client has no timeout of its own, the deadline above rules.
	resp, err := (&http.Client{}).Do(req)
	// Ollama could not be reached.
	if err != nil {
		// Say why in plain words.
		return perfFigures{}, errors.New(explainError(err))
	} // end of the send check
	// Close the reply at the end.
	defer resp.Body.Close()
	// Any status but 200 is a refusal; read its short message.
	if resp.StatusCode != http.StatusOK {
		// Read the start of the body.
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		// Say what Ollama said.
		return perfFigures{}, fmt.Errorf("Ollama refused the test request (status %d): %s", resp.StatusCode, shortMessage(b))
	} // end of the status check
	// Read the reply line by line, with a cap on the total size.
	rd := bufio.NewReaderSize(io.LimitReader(resp.Body, maxPerfReply), 64*1024)
	// The figures to build.
	var f perfFigures
	// Whether the last piece arrived.
	finished := false
	// Read until the end.
	for {
		// One line.
		line, rerr := rd.ReadBytes('\n')
		// A non-empty line is one piece.
		if len(bytes.TrimSpace(line)) > 0 {
			// Decode it.
			var p genPiece
			// A broken piece means this is not Ollama's stream.
			if err := json.Unmarshal(line, &p); err != nil {
				// Plain message.
				return perfFigures{}, errors.New("the reply was not the expected JSON, so it does not look like Ollama")
			} // end of the decode check
			// Ollama reported an error inside the stream.
			if p.Error != "" {
				// Say what it said, shortened.
				return perfFigures{}, fmt.Errorf("Ollama stopped the test: %s", shortMessage(line))
			} // end of the error check
			// The first piece of output, whether answer or reasoning, ends the wait for the first word.
			if !f.GotFirstWord && (p.Response != "" || p.Thinking != "") {
				// Remember how long it took.
				f.FirstWord, f.GotFirstWord = time.Since(start), true
			} // end of the first word check
			// The last piece carries the figures.
			if p.Done {
				// Copy them.
				f.TotalNs, f.LoadNs, f.PromptCount, f.PromptNs, f.EvalCount, f.EvalNs = p.TotalDuration, p.LoadDuration, p.PromptEvalCount, p.PromptEvalDuration, p.EvalCount, p.EvalDuration
				// Done.
				finished = true
			} // end of the done check
		} // end of the piece check
		// The end of the reply or a read problem.
		if rerr != nil {
			// Leave the loop.
			break
		} // end of the end check
	} // end of the read loop
	// A stream that ends without its last piece is incomplete.
	if !finished {
		// Plain message.
		return perfFigures{}, errors.New("the reply ended before Ollama reported its figures")
	} // end of the finished check
	// Hand the figures back.
	return f, nil
} // end of runGenerate

// embedReply is the part of an /api/embed reply that the test uses.
type embedReply struct {
	// Embeddings is one vector per input text.
	Embeddings [][]float64 `json:"embeddings"`
	// TotalDuration is the whole request in nanoseconds.
	TotalDuration int64 `json:"total_duration"`
	// LoadDuration is the load time in nanoseconds.
	LoadDuration int64 `json:"load_duration"`
	// PromptEvalCount is the number of tokens of the text.
	PromptEvalCount int64 `json:"prompt_eval_count"`
} // end of embedReply

// runEmbed embeds the fixed text once and returns the figures.
func runEmbed(ctx context.Context, base *url.URL, model string) (perfFigures, error) {
	// A place for the reply.
	var r embedReply
	// Send the request; the keep-alive keeps the model loaded for the next run.
	status, msg, err := postForReply(ctx, base, "api/embed", perfRequestTimeout, map[string]any{"model": model, "input": perfPrompt, "keep_alive": "2m"}, &r)
	// Ollama could not be reached or answered with something unexpected.
	if err != nil {
		// Pass the plain message on.
		return perfFigures{}, err
	} // end of the send check
	// Any status but 200 is a refusal.
	if status != http.StatusOK {
		// Say what Ollama said.
		return perfFigures{}, fmt.Errorf("Ollama refused the test request (status %d): %s", status, msg)
	} // end of the status check
	// The figures.
	f := perfFigures{TotalNs: r.TotalDuration, LoadNs: r.LoadDuration, PromptCount: r.PromptEvalCount}
	// The vector length.
	if len(r.Embeddings) > 0 {
		// The first vector.
		f.VectorLength = len(r.Embeddings[0])
	} // end of the vector check
	// Hand the figures back.
	return f, nil
} // end of runEmbed

// performTest runs the whole test on one model that is not loaded: one warm-up run (which loads it), then timed runs, then it reads what Ollama reports and unloads the model again. The result holds numbers only.
func performTest(ctx context.Context, base *url.URL, model string, embedding bool, version string) (run perfRun, err error) {
	// Is Ollama on this same computer? Only then do the machine figures describe it.
	local := isLocalAddress(base)
	// The result starts with the facts known before the test.
	run = perfRun{Time: time.Now().UTC(), Model: model, Kind: "generate", OllamaVersion: version, Host: base.Host, PromptVersion: perfPromptVersion, Runs: perfTimedRuns}
	// An embedding model is tested differently.
	if embedding {
		// Mark it.
		run.Kind = "embedding"
	} // end of the kind check
	// The machine before the test.
	run.Before = snapshotMachine(ctx, local)
	// Whether it looked busy.
	run.BusyReason = busyReason(run.Before)
	// The flag.
	run.Busy = run.BusyReason != ""
	// The models that are loaded now (the test only starts when the tested model is not among them).
	if list, lerr := fetchLoaded(ctx, base, defaultCheckTimeout); lerr == nil {
		// Their names.
		for _, m := range list {
			// Keep each.
			run.OtherLoaded = append(run.OtherLoaded, m.Name)
		} // end of the loop
	} // end of the loaded read
	// From the first request on the model may be in memory, so it must be unloaded however the test ends.
	started := false
	// The cleanup: unload and check; it uses a context that survives a closed browser page.
	defer func() {
		// Nothing was sent, nothing to unload.
		if !started {
			// Leave.
			return
		} // end of the started check
		// A context that is not cancelled when the person closes the page.
		c := context.WithoutCancel(ctx)
		// Ask Ollama to unload it (the same call the Unload button uses).
		_, uerr := unloadModel(c, base, model, unloadTimeout)
		// Whether it is gone.
		gone := false
		// Check only when the request was accepted.
		if uerr == nil {
			// Wait until the loaded list no longer holds it.
			gone, _ = waitUntilGone(c, base, model, defaultCheckTimeout)
		} // end of the unload check
		// Tell the person when it is still loaded.
		run.LeftLoaded = !gone
	}() // end of the cleanup
	// one runs one request of the right kind.
	one := func() (perfFigures, error) {
		// From now on the model may be loaded.
		started = true
		// An embedding model.
		if embedding {
			// Embed the fixed text.
			return runEmbed(ctx, base, model)
		} // end of the embedding case
		// A chat model.
		return runGenerate(ctx, base, model)
	} // end of one
	// The warm-up run: it loads the model, so its load time and first word are the cold figures.
	cold, err := one()
	// The test failed.
	if err != nil {
		// Report it.
		return run, err
	} // end of the warm-up check
	// The timed runs, with the model already loaded.
	var timed []perfFigures
	// Run them one after the other.
	for i := 0; i < perfTimedRuns; i++ {
		// One run.
		f, err := one()
		// The test failed.
		if err != nil {
			// Report it.
			return run, err
		} // end of the check
		// Keep the figures.
		timed = append(timed, f)
	} // end of the timed loop
	// Collect each figure over the timed runs.
	var answer, prompt, firstWord, total []float64
	// Go through the runs.
	for _, f := range timed {
		// Answer speed.
		answer = append(answer, perSecond(f.EvalCount, f.EvalNs))
		// Prompt reading speed.
		prompt = append(prompt, perSecond(f.PromptCount, f.PromptNs))
		// First word, when one was seen.
		if f.GotFirstWord {
			// Keep it in seconds.
			firstWord = append(firstWord, f.FirstWord.Seconds())
		} // end of the first word check
		// Total time.
		total = append(total, secs(f.TotalNs))
	} // end of the loop
	// The medians.
	run.AnswerSpeed, run.PromptSpeed, run.WarmFirstWordSec, run.WarmTotalSec = median(answer), median(prompt), median(firstWord), median(total)
	// The cold figures.
	run.ColdLoadSec = secs(cold.LoadNs)
	// The cold first word.
	if cold.GotFirstWord {
		// In seconds.
		run.ColdFirstWordSec = cold.FirstWord.Seconds()
	} // end of the cold first word check
	// The sizes of the test, from the last timed run.
	last := timed[len(timed)-1]
	// Tokens in and out, and the vector length.
	run.TokensIn, run.TokensOut, run.VectorLength = last.PromptCount, last.EvalCount, last.VectorLength
	// What Ollama reports about the loaded model.
	if list, lerr := fetchLoaded(ctx, base, defaultCheckTimeout); lerr == nil {
		// Find the tested model.
		if m, ok := findLoaded(list, model); ok {
			// Its memory, graphics memory and context.
			run.ModelBytes, run.GPUBytes, run.ContextLength = m.Size, m.SizeVRAM, m.ContextLength
		} // end of the find check
	} // end of the loaded read
	// The machine after the timed runs, with the model still in memory.
	run.After = snapshotMachine(ctx, local)
	// Done; the deferred cleanup unloads the model.
	return run, nil
} // end of performTest
