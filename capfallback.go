// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the packages this file uses.
	// context lets the work stop when the request is cancelled.
	"context"
	// net/http provides the status codes.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// sync makes the memory safe for several requests at once.
	"sync"
	// time provides the clock and durations.
	"time"
) // end of imports

// Why this file exists: the Ollama API documentation lists neither "capabilities" nor "context_length" for /api/tags, only for /api/show (capabilities since version 0.6.4; the context length is in model_info). Some Ollama versions (for example 0.21.2 on Windows) leave them out of /api/tags, so the model categories, the Max context length column and the speed test messages were empty. This file asks /api/show for exactly the models whose list entry lacks them, once per model.

// maxShowPerFetch is the most /api/show questions one list fetch may ask, so a page never waits long; the rest are asked on the next fetch.
const maxShowPerFetch = 20

// factsRetry is how long a failed /api/show question is left alone before it is asked again.
const factsRetry = time.Minute

// modelFacts is what /api/show told about one model, remembered so the question is asked only once.
type modelFacts struct {
	// Caps are the capabilities (empty when Ollama gave none).
	Caps []string
	// Ctx is the largest context in tokens, or 0 when it could not be read.
	Ctx int64
	// Failed is true when the question did not get a good answer; it is asked again after factsRetry.
	Failed bool
	// At is when the question was asked.
	At time.Time
} // end of modelFacts

// factsMemory holds the remembered answers; the key is the Ollama address plus the model's digest (its name when it has none), so a changed model is asked again.
var factsMemory = struct {
	// Lock protects the map.
	sync.Mutex
	// byKey holds the answers.
	byKey map[string]modelFacts
}{byKey: map[string]modelFacts{}}

// factsNow is the clock; a test replaces it.
var factsNow = time.Now

// factsKey builds the memory key of one model.
func factsKey(base *url.URL, m installedModel) string {
	// The digest identifies the content; the name is the fallback.
	id := m.Digest
	// No digest reported.
	if id == "" {
		// Use the name.
		id = m.Name
	} // end of the digest check
	// Address, a separator that cannot be in either, and the identity.
	return base.Redacted() + "\n" + id
} // end of factsKey

// resetFacts forgets everything; used by tests.
func resetFacts() {
	// One at a time.
	factsMemory.Lock()
	// Release at the end.
	defer factsMemory.Unlock()
	// A fresh map.
	factsMemory.byKey = map[string]modelFacts{}
} // end of resetFacts

// fillFromShow completes the list in place: for each model whose capabilities or context length are missing it uses what /api/show says. It never fails the list: a model that cannot be asked stays as /api/tags gave it.
func fillFromShow(ctx context.Context, base *url.URL, timeout time.Duration, models []installedModel) {
	// How many questions this fetch has asked.
	asked := 0
	// Go through the models.
	for i := range models {
		// What is missing.
		m := &models[i]
		// Nothing missing: nothing to ask.
		if len(m.Capabilities) > 0 && m.Details.ContextLength > 0 {
			// Next model.
			continue
		} // end of the nothing-missing check
		// The request may have been cancelled.
		if ctx.Err() != nil {
			// Stop asking.
			return
		} // end of the cancel check
		// The memory key.
		key := factsKey(base, *m)
		// Look it up.
		factsMemory.Lock()
		f, known := factsMemory.byKey[key]
		factsMemory.Unlock()
		// A failed answer is left alone for a while.
		if known && f.Failed && factsNow().Sub(f.At) >= factsRetry {
			// Ask again.
			known = false
		} // end of the retry check
		// Not remembered: ask Ollama, within the limit.
		if !known {
			// Too many questions for one fetch: the rest wait for the next one.
			if asked >= maxShowPerFetch {
				// Next model.
				continue
			} // end of the limit check
			// One more question.
			asked++
			// Ask.
			reply, status, err := fetchShow(ctx, base, m.Name, timeout)
			// Build the answer.
			f = modelFacts{At: factsNow()}
			// A good answer.
			if err == nil && status == http.StatusOK {
				// What Ollama said.
				f.Caps = reply.Capabilities
				// The context length, from the model's own facts.
				if n, ok := modelMaxContext(reply.ModelInfo); ok {
					// Keep it.
					f.Ctx = n
				} // end of the context check
			} else {
				// Ask again later.
				f.Failed = true
			} // end of the answer check
			// Remember it, unless the request was cancelled (then the answer may be a cancel error, which says nothing about the model).
			if ctx.Err() == nil {
				// One at a time.
				factsMemory.Lock()
				factsMemory.byKey[key] = f
				factsMemory.Unlock()
			} // end of the remember check
		} // end of the ask
		// Fill only what /api/tags left out; what it gave stays.
		if len(m.Capabilities) == 0 && len(f.Caps) > 0 {
			// Copy, so the memory is never changed by a caller.
			m.Capabilities = append([]string(nil), f.Caps...)
		} // end of the capabilities fill
		// The context length.
		if m.Details.ContextLength == 0 && f.Ctx > 0 {
			// Fill it.
			m.Details.ContextLength = f.Ctx
		} // end of the context fill
	} // end of the model loop
} // end of fillFromShow
