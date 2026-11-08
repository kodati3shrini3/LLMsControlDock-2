// Package main tells Go that this folder builds into a runnable program.
package main

// abilityTagWords are the short words shown as tags for the abilities Ollama reports; embedding is left out because the group heading already says it.
var abilityTagWords = []struct {
	// Key is the word Ollama uses in its capability list.
	Key string
	// Word is the short word shown.
	Word string
}{
	// Pictures.
	{"vision", "Pictures"},
	// Audio.
	{"audio", "Audio"},
	// Tools.
	{"tools", "Tools"},
	// Step-by-step thinking.
	{"thinking", "Thinking"},
} // end of abilityTagWords

// installedTags gives the plain-word tags of one installed model: its size class, its memory-of-a-conversation class, and its abilities; a figure Ollama did not report gives no tag, never a guess.
func installedTags(m installedModel) []string {
	// The tags so far.
	var tags []string
	// The size class, from the parameter size Ollama reports (such as 27.3B).
	if b, ok := paramsBillions(m.Details.ParameterSize); ok {
		// Find the class and add its label.
		tags = append(tags, paramClassLabel(paramClassOf(b))+" model")
	} // end of the size check
	// The memory of a conversation: Ollama reports tokens, and the library pages count a K as 1024 tokens (128K is 131072), so the same unit is used here.
	if m.Details.ContextLength > 0 {
		// Thousands of tokens.
		k := float64(m.Details.ContextLength) / 1024
		// Find the class and add its label.
		tags = append(tags, contextClassLabel(contextClassOf(k))+" memory")
	} // end of the memory check
	// The abilities, in a fixed order.
	for _, a := range abilityTagWords {
		// Only the ones the model reports.
		if hasCapability(m.Capabilities, a.Key) {
			// Add the word.
			tags = append(tags, a.Word)
		} // end of the ability check
	} // end of the ability loop
	// The tags.
	return tags
} // end of installedTags

// paramClassLabel gives the plain word of a size class key.
func paramClassLabel(key string) string {
	// Look the key up in the approved table.
	for _, c := range paramClasses {
		// A match.
		if c.Key == key {
			// The word.
			return c.Label
		} // end of the match check
	} // end of the loop
	// Not reached for a key from paramClassOf.
	return key
} // end of paramClassLabel

// contextClassLabel gives the plain word of a memory class key.
func contextClassLabel(key string) string {
	// Look the key up in the approved table.
	for _, c := range contextClasses {
		// A match.
		if c.Key == key {
			// The word.
			return c.Label
		} // end of the match check
	} // end of the loop
	// Not reached for a key from contextClassOf.
	return key
} // end of contextClassLabel

// deletedTags gives the tags of a deleted model: from what was saved when it was deleted; if that has no size and no memory (an entry made by an earlier version), from the newest saved performance test of the model, which knows its size and memory but not its abilities; nothing is guessed from the name.
func deletedTags(d deletedModel, facts func(string) (string, int64, bool)) []string {
	// What was saved at deletion.
	m := installedModel{Capabilities: d.Capabilities, Details: modelDetails{ParameterSize: d.ParameterSize, ContextLength: d.ContextLength}}
	// Nothing about size or memory was saved: ask the saved tests.
	if d.ParameterSize == "" && d.ContextLength == 0 && facts != nil {
		// The newest facts, when there are any.
		if p, c, ok := facts(d.Name); ok {
			// Use them.
			m.Details.ParameterSize, m.Details.ContextLength = p, c
		} // end of the facts check
	} // end of the fallback
	// The same rules as for an installed model.
	return installedTags(m)
} // end of deletedTags
