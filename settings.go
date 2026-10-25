// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds formatted text.
	"fmt"
	// math checks that numbers are finite and whole.
	"math"
	// sort puts lists in order so they can be compared.
	"sort"
	// strconv turns numbers into text and back.
	"strconv"
	// strings trims and splits text.
	"strings"
	// unicode finds control characters.
	"unicode"
	// unicode/utf8 counts characters and checks that text is valid.
	"unicode/utf8"
) // end of imports

// The kinds of setting.
const (
	// kindInt is a whole number.
	kindInt = "int"
	// kindFloat is a number with an optional decimal part.
	kindFloat = "float"
	// kindList is a list of texts (the stop words).
	kindList = "list"
) // end of the kinds

// The limits of the stop word list.
const (
	// maxStopWords is the most stop words one model may hold here.
	maxStopWords = 8
	// maxStopLength is the longest stop word, in characters.
	maxStopLength = 100
	// maxNumberText is the longest number text that is read.
	maxNumberText = 20
	// maxListText is the longest text accepted for the stop word box, in bytes (eight words of 100 four-byte characters fit).
	maxListText = 4000
) // end of the limits

// settingSpec describes one model setting: what it is called, what kind it is, Ollama's default and the limits this monitor enforces.
type settingSpec struct {
	// Key is the parameter name Ollama uses.
	Key string
	// Heading is the name shown to the person, also the key of its help text.
	Heading string
	// Kind is kindInt, kindFloat or kindList.
	Kind string
	// Default is Ollama's own default, in words, from the Modelfile reference.
	Default string
	// Min is the smallest value this monitor allows.
	Min float64
	// Max is the largest value this monitor allows (ignored when FromModel is set).
	Max float64
	// FromModel says the largest value is the model's own context length.
	FromModel bool
	// NoZero says zero is refused (an answer length of zero would produce nothing).
	NoZero bool
	// Special explains the special values in a few words, or is empty.
	Special string
} // end of settingSpec

// settingSpecs lists the ten settings in the order they are shown. The defaults come from Ollama's Modelfile reference (https://docs.ollama.com/modelfile); the minimum and maximum are this monitor's own limits, because Ollama sets none (a test on the real Ollama accepted any value, even text).
var settingSpecs = []settingSpec{
	// The context size; the documentation says 2048, but a test on Ollama 0.34.4 loaded a model at its own maximum.
	{Key: "num_ctx", Heading: "Context size", Kind: kindInt, Default: "automatic (docs: 2048)", Min: 512, FromModel: true},
	// Randomness of the answers.
	{Key: "temperature", Heading: "Temperature", Kind: kindFloat, Default: "0.8", Min: 0, Max: 2},
	// How many of the likeliest words are considered.
	{Key: "top_k", Heading: "Top-k", Kind: kindInt, Default: "40", Min: 1, Max: 1000},
	// How much of the probability is considered.
	{Key: "top_p", Heading: "Top-p", Kind: kindFloat, Default: "0.9", Min: 0.01, Max: 1},
	// The cut-off relative to the best word.
	{Key: "min_p", Heading: "Min-p", Kind: kindFloat, Default: "0 (off)", Min: 0, Max: 1},
	// How strongly repeats are punished.
	{Key: "repeat_penalty", Heading: "Repeat penalty", Kind: kindFloat, Default: "1 (off)", Min: 0.5, Max: 2},
	// How far back repeats are looked for; 0 is off and -1 is the whole context.
	{Key: "repeat_last_n", Heading: "Repeat window", Kind: kindInt, Default: "64", Min: -1, FromModel: true, Special: "0 switches it off; -1 uses the whole context size"},
	// The random seed.
	{Key: "seed", Heading: "Seed", Kind: kindInt, Default: "0", Min: 0, Max: 2147483647},
	// The longest answer; -1 means no limit.
	{Key: "num_predict", Heading: "Answer length limit", Kind: kindInt, Default: "-1 (no limit)", Min: -1, FromModel: true, NoZero: true, Special: "-1 means no limit"},
	// The words that end an answer.
	{Key: "stop", Heading: "Stop words", Kind: kindList, Default: "none"},
} // end of settingSpecs

// specByKey finds the spec of a parameter name; the second result is false for a name this page does not edit.
func specByKey(key string) (settingSpec, bool) {
	// Look through the list.
	for _, s := range settingSpecs {
		// A match.
		if s.Key == key {
			// Found.
			return s, true
		} // end of the match check
	} // end of the loop
	// Not one of ours.
	return settingSpec{}, false
} // end of specByKey

// limits returns the smallest and largest allowed value for a setting; modelMax is the model's context length (0 when unknown) and ok is false when a model-dependent limit cannot be known.
func (s settingSpec) limits(modelMax int64) (min, max float64, ok bool) {
	// A limit that follows the model needs the model's maximum.
	if s.FromModel {
		// Unknown: this setting cannot be edited safely.
		if modelMax <= 0 {
			// No limit known.
			return 0, 0, false
		} // end of the unknown check
		// The model's own value is the top.
		return s.Min, float64(modelMax), true
	} // end of the model case
	// A fixed range.
	return s.Min, s.Max, true
} // end of limits

// fmtNum writes a number the way Ollama prints it: no trailing zeros, no exponent.
func fmtNum(f float64) string {
	// Shortest exact form.
	return strconv.FormatFloat(f, 'f', -1, 64)
} // end of fmtNum

// rangeText describes the allowed values in plain words for the page.
func (s settingSpec) rangeText(modelMax int64) string {
	// The stop words have their own rule.
	if s.Kind == kindList {
		// Say it.
		return fmt.Sprintf("up to %d words, each 1 to %d characters, one per line", maxStopWords, maxStopLength)
	} // end of the list case
	// The numbers.
	min, max, ok := s.limits(modelMax)
	// Unknown model limit.
	if !ok {
		// Say why nothing can be edited.
		return "needs the model maximum, which Ollama does not report"
	} // end of the unknown check
	// The basic range.
	text := fmtNum(min) + " to " + fmtNum(max)
	// An answer length of -1 and then 1 to the maximum.
	if s.NoZero {
		// Spell it out.
		text = "-1, or " + fmtNum(1) + " to " + fmtNum(max)
	} // end of the no-zero case
	// Add the special values.
	if s.Special != "" {
		// Append them.
		text += " (" + s.Special + ")"
	} // end of the special case
	// Hand back the text.
	return text
} // end of rangeText

// parseNumber checks a typed number against the rules of one setting; it returns the number, or zero and the reason in plain words.
func (s settingSpec) parseNumber(raw string, modelMax int64) (float64, string) {
	// Spaces around the number do not matter.
	t := strings.TrimSpace(raw)
	// An absurdly long text is refused before anything else.
	if len(t) > maxNumberText {
		// Say so.
		return 0, "That number is too long."
	} // end of the length check
	// The limits.
	min, max, ok := s.limits(modelMax)
	// Without them nothing can be checked.
	if !ok {
		// Say so.
		return 0, "No safe limit is known for this model, so this setting cannot be changed."
	} // end of the limit check
	// Read the characters: digits, one leading minus where negatives are allowed, one decimal point for decimals.
	dots, digits := 0, 0
	// Go through the characters.
	for i, r := range t {
		// A digit.
		if r >= '0' && r <= '9' {
			// Count it.
			digits++
			// Next character.
			continue
		} // end of the digit check
		// A leading minus where a negative value is meaningful.
		if r == '-' && i == 0 && min < 0 {
			// Fine.
			continue
		} // end of the minus check
		// One decimal point in a decimal setting.
		if r == '.' && s.Kind == kindFloat && dots == 0 && digits > 0 {
			// Count it.
			dots++
			// Next character.
			continue
		} // end of the point check
		// Anything else is refused.
		if s.Kind == kindFloat {
			// Say what is expected.
			return 0, "Use digits and at most one decimal point, such as 0.7."
		} // end of the decimal wording
		// Whole numbers.
		return 0, "Use digits only, as a whole number such as 40."
	} // end of the character loop
	// A decimal point must be followed by a digit, and there must be at least one digit.
	if digits == 0 || strings.HasSuffix(t, ".") {
		// Say what is expected.
		return 0, "That is not a number."
	} // end of the digit-count check
	// Read it; it cannot fail now, but never trust that.
	v, err := strconv.ParseFloat(t, 64)
	// A failure or a value that is not finite.
	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) {
		// Say so.
		return 0, "That is not a number."
	} // end of the parse check
	// Zero is refused for the answer length.
	if s.NoZero && v == 0 {
		// Say why.
		return 0, "0 would produce no answer at all. Use -1 for no limit, or a number from 1."
	} // end of the zero check
	// Too small.
	if v < min {
		// Say so with the range.
		return 0, fmt.Sprintf("%s is too small. Allowed: %s.", fmtNum(v), s.rangeText(modelMax))
	} // end of the small check
	// Too large.
	if v > max {
		// Say so with the range.
		return 0, fmt.Sprintf("%s is too large. Allowed: %s.", fmtNum(v), s.rangeText(modelMax))
	} // end of the large check
	// All good.
	return v, ""
} // end of parseNumber

// parseStopWords checks the typed stop words (one per line) and returns the list, or nil and the reason; blank lines are skipped.
func parseStopWords(raw string) ([]string, string) {
	// An absurdly long text is refused first.
	if len(raw) > maxListText {
		// Say so.
		return nil, "That is too much text for stop words."
	} // end of the length check
	// Unify the line breaks a browser may send.
	text := strings.ReplaceAll(strings.ReplaceAll(raw, "\r\n", "\n"), "\r", "\n")
	// The result.
	var out []string
	// Go through the lines.
	for _, line := range strings.Split(text, "\n") {
		// A blank line holds nothing.
		if strings.TrimSpace(line) == "" {
			// Next line.
			continue
		} // end of the blank check
		// The text must be valid and printable (a tab or other control character would be invisible).
		if !utf8.ValidString(line) || strings.IndexFunc(line, unicode.IsControl) >= 0 {
			// Say so.
			return nil, "A stop word may contain letters, digits, spaces and symbols, but no control characters."
		} // end of the character check
		// Too long.
		if utf8.RuneCountInString(line) > maxStopLength {
			// Say so.
			return nil, fmt.Sprintf("A stop word may have at most %d characters.", maxStopLength)
		} // end of the long check
		// Keep it exactly as typed.
		out = append(out, line)
	} // end of the line loop
	// Too many.
	if len(out) > maxStopWords {
		// Say so.
		return nil, fmt.Sprintf("At most %d stop words are allowed.", maxStopWords)
	} // end of the count check
	// The same word twice is a typing slip.
	seen := map[string]bool{}
	// Check each.
	for _, w := range out {
		// A repeat.
		if seen[w] {
			// Say which.
			return nil, "The same stop word is listed twice."
		} // end of the repeat check
		// Remember it.
		seen[w] = true
	} // end of the duplicate loop
	// Hand back the list.
	return out, ""
} // end of parseStopWords

// settingValue is one setting's value, either a number or a list of texts.
type settingValue struct {
	// Num is the number for number settings.
	Num float64
	// List holds the texts for the stop words.
	List []string
} // end of settingValue

// text writes the value for the page.
func (v settingValue) text(s settingSpec) string {
	// The stop words are shown quoted, joined by commas.
	if s.Kind == kindList {
		// Quote each.
		parts := make([]string, len(v.List))
		// Go through them.
		for i, w := range v.List {
			// Quote with Go's rules (the same ones Ollama uses when printing).
			parts[i] = strconv.Quote(w)
		} // end of the loop
		// Join.
		return strings.Join(parts, ", ")
	} // end of the list case
	// A number.
	return fmtNum(v.Num)
} // end of text

// equal says whether two values are the same for the given setting.
func (v settingValue) equal(o settingValue, s settingSpec) bool {
	// Lists compare as sets, because Ollama may print them in another order.
	if s.Kind == kindList {
		// Copy and sort both.
		a, b := append([]string{}, v.List...), append([]string{}, o.List...)
		// Sort.
		sort.Strings(a)
		// Sort.
		sort.Strings(b)
		// Different sizes.
		if len(a) != len(b) {
			// Not equal.
			return false
		} // end of the size check
		// Compare each.
		for i := range a {
			// A difference.
			if a[i] != b[i] {
				// Not equal.
				return false
			} // end of the compare
		} // end of the loop
		// Equal.
		return true
	} // end of the list case
	// Numbers.
	return v.Num == o.Num
} // end of equal

// savedMap collects the saved parameters by name; a name can appear several times (the stop words).
func savedMap(lines []paramLine) map[string][]string {
	// The result.
	m := map[string][]string{}
	// Go through the lines.
	for _, l := range lines {
		// Add the value under its name.
		m[l.Name] = append(m[l.Name], l.Value)
	} // end of the loop
	// Hand back the map.
	return m
} // end of savedMap

// readSaved turns the printed lines of one setting into a value; the second result is false when nothing is saved, and the third when something is saved but cannot be read.
func readSaved(s settingSpec, raws []string) (settingValue, bool, bool) {
	// Nothing saved.
	if len(raws) == 0 {
		// Not present.
		return settingValue{}, false, true
	} // end of the nothing case
	// The stop words are quoted texts.
	if s.Kind == kindList {
		// The list.
		var list []string
		// Each line.
		for _, r := range raws {
			// Remove the quotes with Go's rules; fall back to the raw text when it is not quoted.
			if u, err := strconv.Unquote(r); err == nil {
				// Use it.
				list = append(list, u)
			} else {
				// Keep it as printed.
				list = append(list, r)
			} // end of the unquote check
		} // end of the loop
		// Present and readable.
		return settingValue{List: list}, true, true
	} // end of the list case
	// A number: the last line wins, like in a Modelfile.
	f, err := strconv.ParseFloat(raws[len(raws)-1], 64)
	// Not a number, or not finite.
	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
		// Present but unreadable.
		return settingValue{}, true, false
	} // end of the number check
	// Present and readable.
	return settingValue{Num: f}, true, true
} // end of readSaved
