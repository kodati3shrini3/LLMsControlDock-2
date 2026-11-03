// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the packages this file uses.
	// context is passed to the fetch.
	"context"
	// encoding/json reads the request body of the fake Ollama.
	"encoding/json"
	// fmt builds model names.
	"fmt"
	// net/http gives the fake server its types.
	"net/http"
	// net/http/httptest runs the fake Ollama.
	"net/http/httptest"
	// strings checks the capability text.
	"strings"
	// sync/atomic counts requests from the server goroutine.
	"sync/atomic"
	// testing is Go's test framework.
	"testing"
	// time gives the timeout and the fake clock.
	"time"
) // end of imports

// oldOllama is a fake Ollama like version 0.21.2 seems to be: the list has no capabilities and no context length, but /api/show has them. showStatus is the status /api/show answers with; shows counts the questions; names has the models.
type oldOllama struct {
	// srv is the fake server.
	srv *httptest.Server
	// shows counts the /api/show questions.
	shows atomic.Int32
	// showStatus is what /api/show answers (200 by default).
	showStatus atomic.Int32
} // end of oldOllama

// newOldOllama starts the fake with the given list body; the show answer depends on the model name.
func newOldOllama(t *testing.T, tags string) *oldOllama {
	// Mark this as a helper.
	t.Helper()
	// The fake.
	o := &oldOllama{}
	// Healthy by default.
	o.showStatus.Store(http.StatusOK)
	// The server.
	o.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// The list.
		if r.URL.Path == "/api/tags" {
			// Send it.
			w.Write([]byte(tags))
			// Done.
			return
		} // end of the list case
		// The details of one model.
		if r.URL.Path == "/api/show" && r.Method == http.MethodPost {
			// Count the question.
			o.shows.Add(1)
			// Which model.
			var in struct{ Model string }
			// Read it.
			json.NewDecoder(r.Body).Decode(&in)
			// A failing server.
			if st := int(o.showStatus.Load()); st != http.StatusOK {
				// Fail.
				http.Error(w, "boom", st)
				// Done.
				return
			} // end of the failure case
			// An embedding model has the embedding capability and a context length under its own architecture.
			if strings.HasPrefix(in.Model, "embed") {
				// The reply.
				w.Write([]byte(`{"capabilities":["embedding"],"model_info":{"general.architecture":"bert","bert.context_length":512}}`))
				// Done.
				return
			} // end of the embedding case
			// A model that tells nothing (older than 0.6.4).
			if strings.HasPrefix(in.Model, "mute") {
				// The reply.
				w.Write([]byte(`{"model_info":{}}`))
				// Done.
				return
			} // end of the mute case
			// A chat model.
			w.Write([]byte(`{"capabilities":["completion","tools"],"model_info":{"general.architecture":"llama","llama.context_length":131072}}`))
			// Done.
			return
		} // end of the show case
		// Anything else is a mistake.
		http.NotFound(w, r)
	}))
	// Stop it at the end.
	t.Cleanup(o.srv.Close)
	// Hand it back.
	return o
} // end of newOldOllama

// TestFallbackFillsCapabilitiesAndContext checks the Windows case: the list lacks both, /api/show has them.
func TestFallbackFillsCapabilitiesAndContext(t *testing.T) {
	// Start clean.
	resetFacts()
	// A list of a chat model and an embedding model, with no capabilities and no context length.
	o := newOldOllama(t, `{"models":[{"name":"chat:1","digest":"d1","details":{}},{"name":"embed:1","digest":"d2","details":{}}]}`)
	// Fetch.
	got, err := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// No error.
	if err != nil || len(got) != 2 {
		// Stop.
		t.Fatalf("err=%v len=%d", err, len(got))
	} // end of the check
	// The chat model.
	if c := categorize(got[0].Capabilities); c == categoryUnclassified || got[0].Details.ContextLength != 131072 {
		// Report it.
		t.Errorf("chat: caps=%v ctx=%d", got[0].Capabilities, got[0].Details.ContextLength)
	} // end of the chat check
	// The embedding model.
	if got[1].Details.ContextLength != 512 || len(got[1].Capabilities) != 1 || got[1].Capabilities[0] != "embedding" {
		// Report it.
		t.Errorf("embed: caps=%v ctx=%d", got[1].Capabilities, got[1].Details.ContextLength)
	} // end of the embedding check
	// A second fetch uses the memory: no new questions.
	before := o.shows.Load()
	// Fetch again.
	got2, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// Same answers, no questions.
	if o.shows.Load() != before || got2[0].Details.ContextLength != 131072 {
		// Report it.
		t.Errorf("second fetch asked %d more questions", o.shows.Load()-before)
	} // end of the memory check
} // end of TestFallbackFillsCapabilitiesAndContext

// TestFallbackLeavesCompleteListsAlone checks that a list that already has both costs no /api/show question and is not changed.
func TestFallbackLeavesCompleteListsAlone(t *testing.T) {
	// Start clean.
	resetFacts()
	// A complete entry.
	o := newOldOllama(t, `{"models":[{"name":"chat:1","digest":"d1","capabilities":["completion"],"details":{"context_length":4096}}]}`)
	// Fetch.
	got, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// Nothing asked, nothing changed.
	if o.shows.Load() != 0 || got[0].Details.ContextLength != 4096 || len(got[0].Capabilities) != 1 {
		// Report it.
		t.Errorf("asked %d, got %+v", o.shows.Load(), got[0])
	} // end of the check
} // end of TestFallbackLeavesCompleteListsAlone

// TestFallbackKeepsWhatTheListGave checks that only the missing part is filled: a list with capabilities but no context length keeps its capabilities.
func TestFallbackKeepsWhatTheListGave(t *testing.T) {
	// Start clean.
	resetFacts()
	// Capabilities present, context length missing.
	o := newOldOllama(t, `{"models":[{"name":"chat:1","digest":"d1","capabilities":["vision"],"details":{}}]}`)
	// Fetch.
	got, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// The list's own capabilities stay; the context length is filled.
	if len(got[0].Capabilities) != 1 || got[0].Capabilities[0] != "vision" || got[0].Details.ContextLength != 131072 {
		// Report it.
		t.Errorf("got %+v", got[0])
	} // end of the check
} // end of TestFallbackKeepsWhatTheListGave

// TestFallbackFailureIsSilentAndRetried checks that a failing /api/show never fails the list, is not asked again at once, and is asked again after the wait.
func TestFallbackFailureIsSilentAndRetried(t *testing.T) {
	// Start clean.
	resetFacts()
	// A fake clock.
	now := time.Now()
	// Replace the clock; put it back at the end.
	old := factsNow
	// Restore.
	t.Cleanup(func() { factsNow = old })
	// The clock reads this variable.
	factsNow = func() time.Time { return now }
	// A server whose /api/show fails.
	o := newOldOllama(t, `{"models":[{"name":"chat:1","digest":"d1","details":{}}]}`)
	// Fail.
	o.showStatus.Store(http.StatusInternalServerError)
	// Fetch.
	got, err := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// The list still works, unchanged.
	if err != nil || len(got) != 1 || len(got[0].Capabilities) != 0 || got[0].Details.ContextLength != 0 {
		// Stop.
		t.Fatalf("err=%v got=%+v", err, got)
	} // end of the check
	// One question so far.
	if o.shows.Load() != 1 {
		// Report it.
		t.Fatalf("asked %d", o.shows.Load())
	} // end of the count check
	// Fetch again at once: not asked again.
	fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// Still one.
	if o.shows.Load() != 1 {
		// Report it.
		t.Errorf("asked again too soon: %d", o.shows.Load())
	} // end of the quiet check
	// The server heals and the wait passes.
	o.showStatus.Store(http.StatusOK)
	// Time passes.
	now = now.Add(factsRetry + time.Second)
	// Fetch.
	got, _ = fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// Now it is filled.
	if o.shows.Load() != 2 || got[0].Details.ContextLength != 131072 {
		// Report it.
		t.Errorf("asked %d, got %+v", o.shows.Load(), got[0])
	} // end of the retry check
} // end of TestFallbackFailureIsSilentAndRetried

// TestFallbackRemembersMuteModels checks that a model that tells nothing (an old Ollama) is asked only once, and stays unclassified.
func TestFallbackRemembersMuteModels(t *testing.T) {
	// Start clean.
	resetFacts()
	// A mute model.
	o := newOldOllama(t, `{"models":[{"name":"mute:1","digest":"d1","details":{}}]}`)
	// Fetch twice.
	for i := 0; i < 2; i++ {
		// Fetch.
		got, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
		// Still unclassified.
		if categorize(got[0].Capabilities) != categoryUnclassified {
			// Report it.
			t.Errorf("round %d: caps=%v", i, got[0].Capabilities)
		} // end of the check
	} // end of the loop
	// Asked once.
	if o.shows.Load() != 1 {
		// Report it.
		t.Errorf("asked %d times", o.shows.Load())
	} // end of the count check
} // end of TestFallbackRemembersMuteModels

// TestFallbackAsksAgainWhenTheModelChanges checks that a new digest is a new question.
func TestFallbackAsksAgainWhenTheModelChanges(t *testing.T) {
	// Start clean.
	resetFacts()
	// The list the server sends can be switched.
	var tags atomic.Value
	// First list.
	tags.Store(`{"models":[{"name":"chat:1","digest":"d1","details":{}}]}`)
	// A server that serves the current list and the usual show answer.
	o := newOldOllama(t, "")
	// Replace the list handling: a second server in front would be heavier, so ask through a wrapper.
	front := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// The list comes from the switch.
		if r.URL.Path == "/api/tags" {
			// Send it.
			w.Write([]byte(tags.Load().(string)))
			// Done.
			return
		} // end of the list case
		// Everything else goes to the fake.
		o.srv.Config.Handler.ServeHTTP(w, r)
	}))
	// Stop it at the end.
	t.Cleanup(front.Close)
	// Fetch.
	fetchInstalled(context.Background(), mustParse(t, front.URL), time.Second)
	// The same name, a new digest.
	tags.Store(`{"models":[{"name":"chat:1","digest":"d2","details":{}}]}`)
	// Fetch again.
	fetchInstalled(context.Background(), mustParse(t, front.URL), time.Second)
	// Two questions.
	if o.shows.Load() != 2 {
		// Report it.
		t.Errorf("asked %d times, want 2", o.shows.Load())
	} // end of the count check
} // end of TestFallbackAsksAgainWhenTheModelChanges

// TestFallbackLimitsQuestionsPerFetch checks that one fetch asks at most maxShowPerFetch questions and the next fetch asks the rest.
func TestFallbackLimitsQuestionsPerFetch(t *testing.T) {
	// Start clean.
	resetFacts()
	// Thirty models.
	var rows []string
	// Build them.
	for i := 0; i < 30; i++ {
		// One row.
		rows = append(rows, fmt.Sprintf(`{"name":"chat:%d","digest":"d%d","details":{}}`, i, i))
	} // end of the loop
	// The server.
	o := newOldOllama(t, `{"models":[`+strings.Join(rows, ",")+`]}`)
	// First fetch.
	fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// At most the limit.
	if n := o.shows.Load(); n != maxShowPerFetch {
		// Report it.
		t.Fatalf("first fetch asked %d, want %d", n, maxShowPerFetch)
	} // end of the limit check
	// Second fetch asks the rest only.
	got, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
	// Thirty in all.
	if n := o.shows.Load(); n != 30 {
		// Report it.
		t.Errorf("after two fetches asked %d, want 30", n)
	} // end of the total check
	// Everyone is filled now.
	for _, m := range got {
		// Check one.
		if m.Details.ContextLength != 131072 {
			// Report it.
			t.Errorf("%s not filled", m.Name)
		} // end of the check
	} // end of the loop
} // end of TestFallbackLimitsQuestionsPerFetch
