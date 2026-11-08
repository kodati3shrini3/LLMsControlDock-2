// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds formatted error messages.
	"fmt"
	// net/url parses and checks web addresses (URL, Uniform Resource Locator).
	"net/url"
	// strings trims spaces and compares text.
	"strings"
)

// defaultOllamaURL is used when neither the option nor the environment variable is given: this machine only (requirement S1).
const defaultOllamaURL = "http://127.0.0.1:11434"

// envOllamaURL is the environment variable that can supply the address.
const envOllamaURL = "LLMSCONTROLDOCK_OLLAMA_URL"

// envOllamaURLOld is the name the variable had before the program was renamed to LLMsControlDock; it is still read when the new name is not set, so nobody's setup breaks.
const envOllamaURLOld = "OCC_OLLAMA_URL"

// ollamaFromEnv returns the address from the environment: the new variable first, then the old one; empty text when neither is set.
func ollamaFromEnv(getenv func(string) string) string {
	// The new name wins.
	if v := getenv(envOllamaURL); v != "" {
		// Use it.
		return v
	} // end of the new-name check
	// Otherwise the old name.
	return getenv(envOllamaURLOld)
} // end of ollamaFromEnv

// These three texts name the layer that supplied the address, so the program can print where it came from.
const (
	// sourceFlag means the address came from the -ollama-url command-line option.
	sourceFlag = "command-line option"
	// sourceEnv means the address came from the LLMSCONTROLDOCK_OLLAMA_URL environment variable (or the older OCC_OLLAMA_URL).
	sourceEnv = "environment variable"
	// sourceDefault means nobody set an address, so the built-in default is used.
	sourceDefault = "default"
	// sourceSaved means the value came from the Settings page (the settings file).
	sourceSaved = "saved setting"
) // end of the source names

// ollamaAddress holds the chosen address and the layer that supplied it.
type ollamaAddress struct {
	// URL is the parsed, validated address.
	URL *url.URL
	// Source says which layer supplied it (one of the source names above).
	Source string
} // end of ollamaAddress

// resolve picks the address by precedence: option, then environment variable, then default; an empty text counts as "not set".
func resolve(flagValue, envValue string) (ollamaAddress, error) {
	// No saved setting.
	return resolveWithSaved(flagValue, envValue, "")
} // end of resolve

// resolveWithSaved picks the address by precedence: option, then environment variable, then the saved setting, then default.
func resolveWithSaved(flagValue, envValue, savedValue string) (ollamaAddress, error) {
	// Start from the default layer.
	raw := defaultOllamaURL
	// Remember that the default supplied it, until a stronger layer overrides.
	source := sourceDefault
	// The saved setting beats the default.
	if strings.TrimSpace(savedValue) != "" {
		// Use the saved text.
		raw = strings.TrimSpace(savedValue)
		// Record the layer.
		source = sourceSaved
	} // end of the saved check
	// If the environment variable has real content, it beats the default.
	if strings.TrimSpace(envValue) != "" {
		// Use the environment variable's text.
		raw = strings.TrimSpace(envValue)
		// Record the layer.
		source = sourceEnv
	} // end of the environment check
	// If the command-line option has real content, it beats everything else.
	if strings.TrimSpace(flagValue) != "" {
		// Use the option's text.
		raw = strings.TrimSpace(flagValue)
		// Record the layer.
		source = sourceFlag
	} // end of the option check
	// Check the chosen text and turn it into a parsed address.
	parsed, err := parseOllamaURL(raw)
	// If the text is not a usable address, report which layer supplied the bad value.
	if err != nil {
		// The message never repeats the bad text, because it might contain a password.
		return ollamaAddress{}, fmt.Errorf("the Ollama address from the %s is not usable: %w", source, err)
	} // end of the error check
	// Everything is fine: return the address and where it came from.
	return ollamaAddress{URL: parsed, Source: source}, nil
} // end of resolveWithSaved

// parseOllamaURL checks that text is an http or https address with a host, and returns it parsed.
func parseOllamaURL(raw string) (*url.URL, error) {
	// Parse the text; the error from url.Parse is dropped on purpose, because it would echo the text (and any password).
	parsed, err := url.Parse(raw)
	// If parsing failed outright, say so without echoing the text.
	if err != nil {
		// Return a fixed, safe message.
		return nil, fmt.Errorf("it is not a valid web address; expected a form like http://host:11434")
	} // end of the parse check
	// Only http and https are supported (HTTPS = HTTP Secure); "localhost:11434" parses with scheme "localhost" and fails here.
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		// Explain what is expected.
		return nil, fmt.Errorf("it must start with http:// or https://, for example http://127.0.0.1:11434")
	} // end of the scheme check
	// A host name or IP (Internet Protocol) address is required.
	if parsed.Host == "" {
		// Explain what is missing.
		return nil, fmt.Errorf("it has no host name, for example http://127.0.0.1:11434")
	} // end of the host check
	// A trailing slash is harmless but would make later joins messy, so remove a lone "/".
	if parsed.Path == "/" {
		// Clear the path.
		parsed.Path = ""
	} // end of the path tidy
	// Return the validated address.
	return parsed, nil
} // end of parseOllamaURL
