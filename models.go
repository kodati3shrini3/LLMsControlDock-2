// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context lets a request be cancelled or given a deadline.
	"context"
	// encoding/json decodes the JSON (JavaScript Object Notation) reply.
	"encoding/json"
	// errors creates simple error values.
	"errors"
	// fmt builds formatted text.
	"fmt"
	// io limits how much of a reply we read.
	"io"
	// net/http is the built-in web client.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// time provides the timestamp type and durations.
	"time"
) // end of imports

// maxListReply caps how many bytes of a model list we read (4 MiB, far more than any real list).
const maxListReply = 4 * 1024 * 1024

// modelDetails holds the "details" block of one installed model; fields we do not list (such as parent_model) are ignored.
type modelDetails struct {
	// Family is the model family exactly as Ollama reports it (for example gemma3).
	Family string `json:"family"`
	// ParameterSize is the size label Ollama reports (for example 27.4B).
	ParameterSize string `json:"parameter_size"`
	// QuantizationLevel is the compression level Ollama reports (for example Q4_K_M).
	QuantizationLevel string `json:"quantization_level"`
	// ContextLength is the largest context the model supports, in tokens.
	ContextLength int64 `json:"context_length"`
	// EmbeddingLength is the width of the model's internal vectors.
	EmbeddingLength int64 `json:"embedding_length"`
} // end of modelDetails

// installedModel is one row of the Installed table, as returned by /api/tags.
type installedModel struct {
	// Name is the model name including its tag (for example medgemma:latest).
	Name string `json:"name"`
	// ModifiedAt is when the model was last changed, in UTC.
	ModifiedAt time.Time `json:"modified_at"`
	// Size is the size on disk in bytes; int64 because large models exceed what a 32-bit number holds.
	Size int64 `json:"size"`
	// Digest is the model's fingerprint.
	Digest string `json:"digest"`
	// Capabilities lists what the model can do, as Ollama reports it (for example completion, vision, embedding).
	Capabilities []string `json:"capabilities"`
	// Details holds the family, sizes and lengths.
	Details modelDetails `json:"details"`
} // end of installedModel

// tagsReply is the shape of the JSON that /api/tags returns.
type tagsReply struct {
	// Models is the list of installed models.
	Models []installedModel `json:"models"`
} // end of tagsReply

// getJSON fetches base+path once and decodes the JSON reply into out; every error text is fixed and never contains the address.
func getJSON(ctx context.Context, base *url.URL, path string, timeout time.Duration, out any) error {
	// Build the full address by adding the path safely.
	target := base.JoinPath(path).String()
	// Create the request; the context allows cancelling it from outside.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	// A failure here means the address could not form a request.
	if err != nil {
		// Return a fixed message.
		return errors.New("the address could not be used to build a request")
	} // end of the request check
	// Create a client that gives up after the timeout.
	client := &http.Client{Timeout: timeout}
	// Send the request and wait for the reply.
	resp, err := client.Do(req)
	// A failure here means no reply arrived at all.
	if err != nil {
		// Turn the technical error into a plain reason (reused from check.go).
		return errors.New(explainError(err))
	} // end of the send check
	// Always close the reply body when this function ends.
	defer resp.Body.Close()
	// Anything other than status 200 means this is not a healthy Ollama.
	if resp.StatusCode != http.StatusOK {
		// Report the status number; it contains no secrets.
		return fmt.Errorf("the server answered with status %d, not 200; it may not be Ollama", resp.StatusCode)
	} // end of the status check
	// Decode at most maxListReply bytes of the body into out.
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxListReply)).Decode(out); err != nil {
		// Not the expected JSON means something else answered.
		return errors.New("the reply was not the expected JSON, so it does not look like Ollama")
	} // end of the decode check
	// Everything worked.
	return nil
} // end of getJSON

// fetchInstalled returns every installed model, whatever its current state.
func fetchInstalled(ctx context.Context, base *url.URL, timeout time.Duration) ([]installedModel, error) {
	// Prepare a place to hold the decoded JSON.
	var reply tagsReply
	// Fetch /api/tags and decode it.
	if err := getJSON(ctx, base, "api/tags", timeout, &reply); err != nil {
		// Pass the safe error on, with no models.
		return nil, err
	} // end of the fetch check
	// Return the list (it may be empty on a machine with no models).
	return reply.Models, nil
} // end of fetchInstalled
