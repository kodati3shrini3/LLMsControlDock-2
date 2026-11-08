// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context lets the check be cancelled when the browser goes away.
	"context"
	// crypto/sha256 computes the fingerprint of the library's manifest, the same way Ollama does for the model ID.
	"crypto/sha256"
	// encoding/hex writes the fingerprint as text.
	"encoding/hex"
	// io reads a limited part of the reply.
	"io"
	// net/http sends the read-only question to the library.
	"net/http"
	// regexp checks that every part of a model name is made only of safe characters.
	"regexp"
	// strings splits and compares names.
	"strings"
	// time limits how long the question may take.
	"time"
) // end of imports

// registryBase is the address of the public Ollama library; a variable so tests can point it at a fake and never touch the real network.
var registryBase = "https://registry.ollama.ai"

// libraryTimeout is how long the monitor waits for the library; a slow or missing internet connection must not freeze the delete page.
const libraryTimeout = 6 * time.Second

// maxManifest is the biggest library reply that is read; a real manifest is a few kilobytes.
const maxManifest = 1 << 20

// Library states: what the check found out.
const (
	// libSame means the library has this name and its fingerprint equals the one the person has (or had).
	libSame = "same"
	// libDifferent means the library has this name, but with another fingerprint (a newer build, or the local copy was changed).
	libDifferent = "different"
	// libMissing means the library answered that it has no such name and tag.
	libMissing = "missing"
	// libUnknown means the library could not be asked, or gave an answer that is not understood.
	libUnknown = "unknown"
	// libOther means the name does not belong to the Ollama library (another host such as hf.co), so it was not asked.
	libOther = "other"
) // end of constants

// namePart is the characters one part of a model name may contain; anything else is never put into an address.
var namePart = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// libraryPath turns a model name into the library address path, for example "smollm2:135m" into "library/smollm2" and "135m"; ok is false for names from other sources.
func libraryPath(name string) (repo, tag string, ok bool) {
	// The tag is whatever follows the last colon of the last part; no colon means "latest".
	tag = "latest"
	// Work on a copy of the name.
	base := name
	// The last slash separates the parts; the colon must come after it to belong to the tag.
	if i := strings.LastIndex(base, ":"); i >= 0 && i > strings.LastIndex(base, "/") {
		// The tag.
		tag = base[i+1:]
		// The name without the tag.
		base = base[:i]
	} // end of the tag split
	// The parts of the name.
	parts := strings.Split(base, "/")
	// A single part belongs to the official "library" namespace; two parts are a user namespace; more mean another host or a deeper path.
	switch len(parts) {
	// One part.
	case 1:
		// Official models live under "library".
		parts = []string{"library", parts[0]}
	// Two parts: a first part with a dot or colon is a host name, not a user.
	case 2:
		// A host name such as hf.co.
		if strings.ContainsAny(parts[0], ".:") {
			// Not the Ollama library.
			return "", "", false
		} // end of the host check
	// Anything else.
	default:
		// Not the Ollama library.
		return "", "", false
	} // end of the switch
	// Every part, and the tag, must be made of safe characters only.
	for _, p := range append(append([]string{}, parts...), tag) {
		// Reject empty or odd parts.
		if !namePart.MatchString(p) {
			// Never build an address from it.
			return "", "", false
		} // end of the character check
	} // end of the loop
	// Hand back the path and the tag.
	return parts[0] + "/" + parts[1], tag, true
} // end of libraryPath

// normalDigest removes a leading "sha256:" and lower-cases the rest, so fingerprints written in different styles compare equal.
func normalDigest(d string) string {
	// Without the prefix, in lower case.
	return strings.ToLower(strings.TrimPrefix(strings.TrimSpace(d), "sha256:"))
} // end of normalDigest

// checkLibrary asks the Ollama library, read-only, whether it has this model name and whether its fingerprint equals have; only the model name leaves this computer.
func checkLibrary(ctx context.Context, name, have string) string {
	// Names from other sources are not sent anywhere.
	repo, tag, ok := libraryPath(name)
	// Not the Ollama library.
	if !ok {
		// Say so.
		return libOther
	} // end of the source check
	// Build the request address: the standard registry path for a manifest.
	target := registryBase + "/v2/" + repo + "/manifests/" + tag
	// A request that stops with the browser's request or after the timeout.
	ctx, cancel := context.WithTimeout(ctx, libraryTimeout)
	// Release the timer at the end.
	defer cancel()
	// Create the request.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	// A failure here means the address could not be built.
	if err != nil {
		// Unknown.
		return libUnknown
	} // end of the request check
	// Ask for the manifest in the format Ollama itself uses.
	req.Header.Set("Accept", "application/vnd.docker.distribution.manifest.v2+json")
	// Say who is asking.
	req.Header.Set("User-Agent", "LLMsControlDock")
	// Send it.
	resp, err := http.DefaultClient.Do(req)
	// No answer: no internet, or the library is down.
	if err != nil {
		// Unknown.
		return libUnknown
	} // end of the send check
	// Close the reply at the end.
	defer resp.Body.Close()
	// The library says it has no such name or tag.
	if resp.StatusCode == http.StatusNotFound {
		// Missing.
		return libMissing
	} // end of the 404 case
	// Anything but a normal answer is not understood.
	if resp.StatusCode != http.StatusOK {
		// Unknown.
		return libUnknown
	} // end of the status check
	// Read the manifest, but never more than the limit.
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxManifest+1))
	// A broken or oversized reply.
	if err != nil || len(data) > maxManifest || len(data) == 0 {
		// Unknown.
		return libUnknown
	} // end of the read check
	// The fingerprint of the manifest is what Ollama shows as the model ID and reports as "digest".
	sum := sha256.Sum256(data)
	// Compare it with the one we have.
	if hex.EncodeToString(sum[:]) == normalDigest(have) {
		// Identical.
		return libSame
	} // end of the same case
	// Another fingerprint.
	return libDifferent
} // end of checkLibrary

// libraryNote words what the check found, for the delete page (phase "delete") or the restore page (phase "restore"); class is "ok" for good news and "warn" otherwise.
func libraryNote(state, phase string) (text, class string) {
	// Choose by state.
	switch state {
	// Same fingerprint.
	case libSame:
		// Good news, in the right tense.
		if phase == "delete" {
			// Before deleting.
			return "Good: the Ollama library has this exact version, so Restore can bring back an identical copy.", "ok"
		} // end of the delete wording
		// After deleting.
		return "The Ollama library still has this exact version, so a download brings back an identical copy.", "ok"
	// Other fingerprint.
	case libDifferent:
		// Before deleting.
		if phase == "delete" {
			// Careful wording: either newer, or changed here.
			return "Careful: the Ollama library has a different version of this name than yours (a newer one, or yours was changed here, for example by editing its parameters). Restore would give you the library's version, not this exact copy.", "warn"
		} // end of the delete wording
		// After deleting.
		return "The Ollama library now has a different version of this name than the one you deleted (probably a newer one, or yours had been changed here), so a download gives you the library's version.", "warn"
	// Not in the library.
	case libMissing:
		// Before deleting.
		if phase == "delete" {
			// The strong caution.
			return "Careful: the Ollama library does not have this name, so it cannot be restored. Deleting it is permanent.", "warn"
		} // end of the delete wording
		// After deleting.
		return "The Ollama library does not have this name, so a download will fail. This model cannot be restored from there.", "warn"
	// Another source.
	case libOther:
		// Same wording for both phases.
		return "This model comes from outside the Ollama library (another site, or made on this computer), so the monitor cannot check whether it can be restored. Treat deleting it as permanent.", "warn"
	} // end of the switch
	// Not known.
	if phase == "delete" {
		// Before deleting.
		return "Could not check the Ollama library just now (no internet?), so it is not known whether this model can be restored.", "warn"
	} // end of the delete wording
	// After deleting.
	return "Could not check the Ollama library just now. The command below will tell you if the model is not available.", "warn"
} // end of libraryNote
