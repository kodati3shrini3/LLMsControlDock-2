// Package main tells Go that this test file belongs to the same program as config.go.
package main

import ( // import lists the packages this test file uses.
	// strings checks whether text contains other text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestResolve checks which layer wins and what the result looks like.
func TestResolve(t *testing.T) {
	// A table of cases: each has a name, the two inputs, and the expected layer and address.
	cases := []struct {
		// name labels the case so a failure says which one broke.
		name string
		// flagValue is what the -ollama-url option would hold.
		flagValue string
		// envValue is what the LLMSCONTROLDOCK_OLLAMA_URL environment variable would hold.
		envValue string
		// wantSource is the layer we expect to win.
		wantSource string
		// wantURL is the address we expect, as printed with the password hidden.
		wantURL string
	}{
		// Nothing set: the default applies.
		{"default", "", "", sourceDefault, "http://127.0.0.1:11434"},
		// Only the environment variable is set.
		{"environment variable", "", "http://10.0.0.5:11434", sourceEnv, "http://10.0.0.5:11434"},
		// Both set: the option must win.
		{"option beats environment variable", "http://10.0.0.6:11434", "http://10.0.0.5:11434", sourceFlag, "http://10.0.0.6:11434"},
		// Spaces only counts as "not set", so the environment variable is used.
		{"blank option ignored", "   ", "http://10.0.0.5:11434", sourceEnv, "http://10.0.0.5:11434"},
		// A lone trailing slash is removed.
		{"trailing slash removed", "http://host.example:11434/", "", sourceFlag, "http://host.example:11434"},
		// A password is hidden when printed.
		{"password hidden", "https://me:secret@host.example:11434", "", sourceFlag, "https://me:xxxxx@host.example:11434"},
	} // end of the case table
	// Go through every case.
	for _, tc := range cases {
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Call the function under test.
			got, err := resolve(tc.flagValue, tc.envValue)
			// An error here is a failure; Fatalf stops this subtest at once.
			if err != nil {
				// Report the unexpected error.
				t.Fatalf("unexpected error: %v", err)
			} // end of the error check
			// Compare the layer that won.
			if got.Source != tc.wantSource {
				// Report the difference; Errorf notes the failure and carries on.
				t.Errorf("source = %q, want %q", got.Source, tc.wantSource)
			} // end of the source check
			// Compare the address, with any password hidden.
			if got.URL.Redacted() != tc.wantURL {
				// Report the difference.
				t.Errorf("address = %q, want %q", got.URL.Redacted(), tc.wantURL)
			} // end of the address check
		}) // end of the subtest
	} // end of the case loop
} // end of TestResolve

// TestResolveRejects checks that unusable addresses fail with a clear message and never echo a password.
func TestResolveRejects(t *testing.T) {
	// A table of bad inputs and a piece of text the error must contain.
	cases := []struct {
		// name labels the case.
		name string
		// flagValue is the bad address given through the option.
		flagValue string
		// wantInError is text the message must contain.
		wantInError string
	}{
		// No scheme: "localhost" is read as the scheme.
		{"missing scheme", "localhost:11434", "http:// or https://"},
		// Wrong scheme.
		{"ftp scheme", "ftp://host.example", "http:// or https://"},
		// A scheme but no host.
		{"no host", "http://", "no host name"},
		// A bad port makes the text unparsable; the password must still not leak.
		{"unparsable with password", "http://me:secret@host.example:notaport", "not a valid web address"},
	} // end of the case table
	// Go through every case.
	for _, tc := range cases {
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Call the function under test.
			_, err := resolve(tc.flagValue, "")
			// No error is a failure.
			if err == nil {
				// Stop this subtest; there is nothing more to check.
				t.Fatal("expected an error, got none")
			} // end of the nil check
			// The message must explain the problem.
			if !strings.Contains(err.Error(), tc.wantInError) {
				// Report the difference.
				t.Errorf("error %q does not contain %q", err.Error(), tc.wantInError)
			} // end of the message check
			// The message must name the layer that supplied the bad value.
			if !strings.Contains(err.Error(), sourceFlag) {
				// Report the difference.
				t.Errorf("error %q does not name the %s", err.Error(), sourceFlag)
			} // end of the layer check
			// The message must never contain the password.
			if strings.Contains(err.Error(), "secret") {
				// Report the leak.
				t.Errorf("error leaks the password: %q", err.Error())
			} // end of the leak check
		}) // end of the subtest
	} // end of the case loop
} // end of TestResolveRejects
