// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the sentences.
	"fmt"
	// sort puts models in order.
	"sort"
	// strconv reads the number in a size label such as 4.3B.
	"strconv"
	// strings cleans and compares text.
	"strings"
	// time compares the days of two tests.
	"time"
) // end of imports

// sizeLimits are the upper edges, in billions of parameters, of the first four size classes; they are this program's own choice, not an industry standard, and the comparison page says so.
var sizeLimits = []float64{1, 5, 12, 36}

// sizeClassNames are the five size classes, from the smallest; the number of names is one more than the number of limits.
var sizeClassNames = []string{"Tiny (under 1B)", "Small (1B to under 5B)", "Medium (5B to under 12B)", "Large (12B to under 36B)", "Extra-large (36B and over)"}

// classUnknown marks a model whose size could not be worked out at all (no label and no memory figure).
const classUnknown = -1

// bytesPerBillion is the rough memory of one billion parameters at about 4 to 5 bits plus working space; it is only used to guess a size class when Ollama gave no size label, and every guess is marked as an estimate.
const bytesPerBillion = 0.6e9

// cmpSameSittingHours is how far apart, in hours, two tests of one group may be before the older one is flagged; it is this program's own rule.
const cmpSameSittingHours = 12

// parseParamBillions reads an Ollama size label such as 4.3B, 134.52M or 27.4B and returns the number of parameters in billions; false means the label could not be read.
func parseParamBillions(label string) (float64, bool) {
	// Remove blanks and use capital letters.
	l := strings.ToUpper(strings.TrimSpace(label))
	// An empty label has no size.
	if len(l) < 2 {
		// Not readable.
		return 0, false
	} // end of the length check
	// The last letter says the unit.
	unit := l[len(l)-1]
	// The number in front of it.
	num, err := strconv.ParseFloat(strings.TrimSpace(l[:len(l)-1]), 64)
	// Not a number, or not a size.
	if err != nil || num <= 0 {
		// Not readable.
		return 0, false
	} // end of the number check
	// Turn the unit into billions.
	switch unit {
	// Thousands.
	case 'K':
		// A thousand is a millionth of a billion.
		return num / 1e6, true
	// Millions.
	case 'M':
		// A million is a thousandth of a billion.
		return num / 1e3, true
	// Billions.
	case 'B':
		// Already billions.
		return num, true
	// Trillions.
	case 'T':
		// A trillion is a thousand billions.
		return num * 1e3, true
	} // end of the unit switch
	// An unknown unit.
	return 0, false
} // end of parseParamBillions

// sizeClassOf returns the index of the size class for a number of billions of parameters.
func sizeClassOf(billions float64) int {
	// Count the limits that the size has reached.
	idx := 0
	// Go through the limits.
	for _, lim := range sizeLimits {
		// At or above the limit: one class higher.
		if billions >= lim {
			// Next class.
			idx++
		} // end of the limit check
	} // end of the loop
	// The class.
	return idx
} // end of sizeClassOf

// classifySize returns the size class of a model: from the size label when there is one, otherwise a guess from its memory figure (marked as estimated), otherwise classUnknown.
func classifySize(label string, memBytes int64) (idx int, estimated bool) {
	// An exact label wins.
	if b, ok := parseParamBillions(label); ok {
		// The class, not estimated.
		return sizeClassOf(b), false
	} // end of the label check
	// Without a label, the memory figure gives a rough guess.
	if memBytes > 0 {
		// The class of the guessed size, marked as an estimate.
		return sizeClassOf(float64(memBytes) / bytesPerBillion), true
	} // end of the memory check
	// Nothing to go on.
	return classUnknown, true
} // end of classifySize

// precisionOf turns an Ollama quantization level such as Q4_K_M or F16 into its nominal number of bits and a short label; zero bits means it was not reported or not understood.
func precisionOf(quant string) (int, string) {
	// Clean the text.
	q := strings.ToUpper(strings.TrimSpace(quant))
	// Nothing reported.
	if q == "" {
		// Say so.
		return 0, "not reported"
	} // end of the empty check
	// The formats that name their bits directly.
	switch {
	// Full 32-bit floating point.
	case strings.HasPrefix(q, "F32"):
		// 32 bits.
		return 32, "32-bit (" + quant + ")"
	// 16-bit floating point, in either flavour.
	case strings.HasPrefix(q, "F16"), strings.HasPrefix(q, "BF16"):
		// 16 bits.
		return 16, "16-bit (" + quant + ")"
	// The 4-bit floating-point formats.
	case strings.HasPrefix(q, "MXFP4"), strings.HasPrefix(q, "NVFP4"), strings.HasPrefix(q, "FP4"):
		// 4 bits.
		return 4, "4-bit (" + quant + ")"
	// The 8-bit floating-point format.
	case strings.HasPrefix(q, "FP8"):
		// 8 bits.
		return 8, "8-bit (" + quant + ")"
	} // end of the direct formats
	// The Q and IQ families: the digit after the letters is the nominal number of bits.
	rest := q
	// The IQ family.
	if strings.HasPrefix(rest, "IQ") {
		// Drop the two letters.
		rest = rest[2:]
	} else if strings.HasPrefix(rest, "Q") {
		// Drop the one letter.
		rest = rest[1:]
	} else {
		// Not a family this program knows.
		return 0, "not recognised (" + quant + ")"
	} // end of the family check
	// The first character must be a digit from 1 to 9.
	if len(rest) > 0 && rest[0] >= '1' && rest[0] <= '9' {
		// The number of bits.
		bits := int(rest[0] - '0')
		// The label.
		return bits, fmt.Sprintf("%d-bit (%s)", bits, quant)
	} // end of the digit check
	// A family name without a digit.
	return 0, "not recognised (" + quant + ")"
} // end of precisionOf

// cmpModel is one tested model inside a comparison group.
type cmpModel struct {
	// Run is the saved test.
	Run perfRun
	// Name is the model name, with a note when Ollama no longer has the model.
	Name string
	// Params is the size label, or a note that it is estimated or unknown.
	Params string
	// ClassIdx is the size class (classUnknown when nothing is known); embedding models do not use it.
	ClassIdx int
	// ClassEstimated is true when the class was guessed from memory use.
	ClassEstimated bool
	// Quant is the quantization label with its nominal bits.
	Quant string
	// Bits is the nominal number of bits (zero when unknown).
	Bits int
	// Reasons are the cautions that keep the model out of the ranking; empty means it can be ranked.
	Reasons []string
	// Rank is the place in the like-for-like ranking, or zero when the model is not ranked.
	Rank int
	// SizeB is the size in billions of parameters used to list the largest first: the size Ollama reports, or an estimate from the memory used.
	SizeB float64
} // end of cmpModel

// cmpGroup is one comparison group: models that may be compared with each other.
type cmpGroup struct {
	// Title is the heading, for example "Chat · Small (1B to under 5B)".
	Title string
	// Why says in plain words why these models are compared together, with reference markers.
	Why string
	// Embedding is true for the group of embedding models.
	Embedding bool
	// ClassIdx is the size class of a chat group.
	ClassIdx int
	// Models are the members, ranked ones first.
	Models []cmpModel
	// Ranked is how many models have a place in the ranking (zero or at least two).
	Ranked int
	// Headline is the sentence about the fastest model, or empty when there is no ranking.
	Headline string
	// Notes are extra sentences: why there is no ranking, or that the model has no peer.
	Notes []string
} // end of cmpGroup

// modeInt returns the most common value among the numbers above zero; ties go to the higher number; zero when there are none.
func modeInt(vals []int64) int64 {
	// Count each value.
	count := map[int64]int{}
	// Go through the values.
	for _, v := range vals {
		// Zero means not reported.
		if v > 0 {
			// Count it.
			count[v]++
		} // end of the check
	} // end of the loop
	// The best value so far.
	var best int64
	// Its count.
	bestN := 0
	// Look at each counted value.
	for v, n := range count {
		// More common, or equally common and higher.
		if n > bestN || (n == bestN && v > best) {
			// Keep it.
			best, bestN = v, n
		} // end of the comparison
	} // end of the loop
	// The mode.
	return best
} // end of modeInt

// modeString returns the most common non-empty text; ties go to the text that sorts last (so the newer version wins); empty when there is none.
func modeString(vals []string) string {
	// Count each value.
	count := map[string]int{}
	// Go through the values.
	for _, v := range vals {
		// Empty means not reported.
		if v != "" {
			// Count it.
			count[v]++
		} // end of the check
	} // end of the loop
	// The best value so far.
	best := ""
	// Its count.
	bestN := 0
	// Look at each counted value.
	for v, n := range count {
		// More common, or equally common and later in order.
		if n > bestN || (n == bestN && v > best) {
			// Keep it.
			best, bestN = v, n
		} // end of the comparison
	} // end of the loop
	// The mode.
	return best
} // end of modeString

// resolveDetails picks what is known about a model: the details saved with the test come first, then what Ollama reports now.
func resolveDetails(r perfRun, installed map[string]modelDetails) modelDetails {
	// What the test saved.
	d := modelDetails{Family: r.Family, ParameterSize: r.ParameterSize, QuantizationLevel: r.Quantization}
	// A model that is still installed fills the gaps.
	if now, ok := installed[r.Model]; ok {
		// A missing size label.
		if d.ParameterSize == "" {
			// Use the live one.
			d.ParameterSize = now.ParameterSize
		} // end of the size check
		// A missing quantization.
		if d.QuantizationLevel == "" {
			// Use the live one.
			d.QuantizationLevel = now.QuantizationLevel
		} // end of the quantization check
		// A missing family.
		if d.Family == "" {
			// Use the live one.
			d.Family = now.Family
		} // end of the family check
	} // end of the installed check
	// What is known.
	return d
} // end of resolveDetails

// speedKey is the figure a model is ranked by: characters per second for a chat model (higher is better), embedding time for an embedding model (lower is better, so it is negated to make higher better).
func speedKey(r perfRun) float64 {
	// An embedding model: the shorter time wins; a missing time is the worst.
	if r.Kind == "embedding" {
		// No figure.
		if r.WarmTotalSec <= 0 {
			// The worst possible.
			return -1e18
		} // end of the figure check
		// Shorter is better.
		return -r.WarmTotalSec
	} // end of the embedding case
	// A chat model: characters per second.
	return r.CharSpeed
} // end of speedKey

// groupRuns sorts the latest runs into comparison groups, flags every condition that makes a row not comparable like for like, and ranks the models that have no flag. Every run lands in exactly one group.
func groupRuns(runs []perfRun, installed map[string]modelDetails, known bool) []cmpGroup {
	// The groups by key: the size class for chat models, -2 for the one group of embedding models.
	byKey := map[int][]cmpModel{}
	// Go through the runs.
	for _, r := range runs {
		// What is known about the model.
		d := resolveDetails(r, installed)
		// The model, with its name and notes.
		m := cmpModel{Run: r, Name: r.Model}
		// A model that Ollama no longer has gets a note (only when the list was read).
		if known {
			// Is it still there?
			if _, ok := installed[r.Model]; !ok {
				// Note it.
				m.Name += " (no longer installed)"
			} // end of the installed check
		} // end of the known check
		// The size used for the listing order: the reported size when it can be read.
		if b, ok := parseParamBillions(d.ParameterSize); ok {
			// Use it.
			m.SizeB = b
		} else {
			// Otherwise the same estimate that classifySize uses: memory divided by 0.6 GB per billion.
			m.SizeB = float64(r.ModelBytes) / 0.6e9
		} // end of the size check
		// The nominal precision.
		m.Bits, m.Quant = precisionOf(d.QuantizationLevel)
		// The size label to show.
		m.Params = d.ParameterSize
		// A chat model is grouped by size class.
		key := -2
		// Embedding models share one group.
		if r.Kind != "embedding" {
			// Work out the class.
			m.ClassIdx, m.ClassEstimated = classifySize(d.ParameterSize, r.ModelBytes)
			// The group key is the class.
			key = m.ClassIdx
		} else {
			// The class is not used for embedding models.
			m.ClassIdx = classUnknown
		} // end of the kind check
		// A size label that is empty gets a note.
		if m.Params == "" {
			// Say so.
			m.Params = "not reported"
		} // end of the label check
		// An estimated class gets a note beside the label.
		if m.ClassEstimated && key != classUnknown && r.Kind != "embedding" {
			// Say that it is a guess.
			m.Params += " (class estimated from memory use)"
		} // end of the estimate note
		// Put the model into its group.
		byKey[key] = append(byKey[key], m)
	} // end of the loop
	// The keys in the order the groups are shown: chat classes from the largest, then unknown, then embedding.
	var keys []int
	// Collect them.
	for k := range byKey {
		// One key.
		keys = append(keys, k)
	} // end of the loop
	// Sort: classes 4..0 first (largest first), then unknown, then embedding.
	sort.Slice(keys, func(i, j int) bool {
		// A rank for each key.
		return keyOrder(keys[i]) < keyOrder(keys[j])
	}) // end of the sort
	// The groups.
	var groups []cmpGroup
	// Build each group.
	for _, k := range keys {
		// The members.
		g := buildGroup(k, byKey[k])
		// Keep it.
		groups = append(groups, g)
	} // end of the loop
	// Name the nearest neighbour of every group that has no peer, now that all groups are known.
	for i := range groups {
		// A group with a single model, which is not an embedding group.
		if len(groups[i].Models) == 1 && !groups[i].Embedding {
			// The note.
			groups[i].Notes = append(groups[i].Notes, singleNote(groups, i))
		} // end of the single check
	} // end of the loop
	// Hand them back.
	return groups
} // end of groupRuns

// keyOrder gives the display order of a group key.
func keyOrder(k int) int {
	// Embedding models last.
	if k == -2 {
		// After everything.
		return 1000
	} // end of the embedding check
	// Unknown size just before them.
	if k == classUnknown {
		// After the classes.
		return 900
	} // end of the unknown check
	// The classes, largest first: class 4 (extra-large) gets the lowest number.
	return len(sizeClassNames) - 1 - k
} // end of keyOrder

// groupTitle writes the heading of a group.
func groupTitle(key int) string {
	// The embedding group.
	if key == -2 {
		// Its name.
		return "Embedding models"
	} // end of the embedding check
	// Unknown size.
	if key == classUnknown {
		// Its name.
		return "Chat · size not known"
	} // end of the unknown check
	// A size class.
	return "Chat · " + sizeClassNames[key]
} // end of groupTitle

// groupWhy writes the plain-words reason that the models of a group are compared together; the numbers in brackets point to the reference list.
func groupWhy(key int) string {
	// Embedding models.
	if key == -2 {
		// Why they are separate.
		return "Embedding models produce numbers, not text, and are benchmarked on their own tasks, so they are never ranked against chat models [6]. They are compared on the time they need for the same fixed text, under the same conditions [1][2]."
	} // end of the embedding case
	// Unknown size.
	if key == classUnknown {
		// Why this group exists.
		return "Ollama did not report a size for these models and no memory figure was saved, so they cannot be placed in a size class. They are listed so that none is left out, but they are not ranked."
	} // end of the unknown case
	// A size class.
	return "These are chat models of the same size class. A bigger model is expected to be slower, so models are compared only with models of similar size, run with the same prompt, answer length and settings [1][2]. The size-class limits are this program's own choice, not an industry standard."
} // end of groupWhy

// buildGroup turns the models of one group into a ranked group.
func buildGroup(key int, models []cmpModel) cmpGroup {
	// The group.
	g := cmpGroup{Title: groupTitle(key), Why: groupWhy(key), Embedding: key == -2, ClassIdx: key}
	// The reference conditions are the most common ones in the group.
	var bits, ctx []int64
	// The versions as text.
	var vers []string
	// The newest test.
	var newest time.Time
	// Collect them.
	for _, m := range models {
		// The precision.
		bits = append(bits, int64(m.Bits))
		// The context length.
		ctx = append(ctx, m.Run.ContextLength)
		// The version.
		vers = append(vers, m.Run.OllamaVersion)
		// The newest time.
		if m.Run.Time.After(newest) {
			// Keep it.
			newest = m.Run.Time
		} // end of the time check
	} // end of the loop
	// The most common precision, version and context.
	refBits, refCtx, refVer := int(modeInt(bits)), modeInt(ctx), modeString(vers)
	// The label of the reference precision.
	_, refLabel := precisionOf("")
	// Find a label for the reference bits from a model that has them.
	for _, m := range models {
		// A model with the reference precision.
		if m.Bits == refBits && refBits > 0 {
			// Its label, without the exact level, so the sentence reads well.
			refLabel = fmt.Sprintf("%d-bit", refBits)
			// Done.
			break
		} // end of the match
	} // end of the loop
	// Flag the conditions of every model.
	for i := range models {
		// A pointer keeps the changes.
		m := &models[i]
		// The conditions.
		m.Reasons = reasonsFor(*m, key == -2, refBits, refLabel, refCtx, refVer, newest)
	} // end of the loop
	// The models without a flag can be ranked.
	var fair []int
	// Find them.
	for i := range models {
		// No reasons.
		if len(models[i].Reasons) == 0 {
			// Keep the index.
			fair = append(fair, i)
		} // end of the check
	} // end of the loop
	// Rank by speed, best first; a stable sort keeps the saved order for ties.
	sort.SliceStable(fair, func(a, b int) bool { return speedKey(models[fair[a]].Run) > speedKey(models[fair[b]].Run) })
	// A ranking needs at least two models that can be compared.
	if len(fair) >= 2 {
		// Number them.
		for place, idx := range fair {
			// Place 1 is the best.
			models[idx].Rank = place + 1
		} // end of the loop
		// How many are ranked.
		g.Ranked = len(fair)
	} // end of the ranking
	// List the models largest first; models of the same size are listed fastest first, then by name. The ranking is shown in its own column.
	sort.SliceStable(models, func(a, b int) bool {
		// A larger model first.
		if models[a].SizeB != models[b].SizeB {
			// Larger is first.
			return models[a].SizeB > models[b].SizeB
		} // end of the size case
		// The same size: faster first.
		if speedKey(models[a].Run) != speedKey(models[b].Run) {
			// Higher is better.
			return speedKey(models[a].Run) > speedKey(models[b].Run)
		} // end of the speed case
		// Then by name.
		return models[a].Name < models[b].Name
	}) // end of the sort
	// The members.
	g.Models = models
	// The sentence about the winner, or why there is none.
	g.Headline, g.Notes = groupSentences(g)
	// The group.
	return g
} // end of buildGroup

// reasonsFor lists the conditions that make one model not comparable like for like with the rest of its group.
func reasonsFor(m cmpModel, embedding bool, refBits int, refLabel string, refCtx int64, refVer string, newest time.Time) []string {
	// The list.
	var out []string
	// The run.
	r := m.Run
	// A guessed or unknown size class cannot support a like-for-like claim (embedding models are not grouped by size).
	if !embedding && m.ClassIdx == classUnknown {
		// Unknown.
		out = append(out, "size class unknown (no size reported and no memory figure saved)")
	} else if !embedding && m.ClassEstimated {
		// A guess.
		out = append(out, "size class only estimated from memory use")
	} // end of the size check
	// Precision.
	if m.Bits == 0 {
		// Not reported.
		out = append(out, "precision not reported")
	} else if refBits > 0 && m.Bits != refBits {
		// A different precision.
		out = append(out, fmt.Sprintf("different precision (%d-bit; most models here use %s)", m.Bits, refLabel))
	} // end of the precision check
	// A test made long before the newest one of the group.
	if newest.Sub(r.Time) > cmpSameSittingHours*time.Hour {
		// Say how the rule reads.
		out = append(out, fmt.Sprintf("tested more than %d hours before the newest test in this group", cmpSameSittingHours))
	} // end of the time check
	// A different Ollama version.
	if r.OllamaVersion != "" && refVer != "" && r.OllamaVersion != refVer {
		// Name both.
		out = append(out, fmt.Sprintf("different Ollama version (%s; most use %s)", r.OllamaVersion, refVer))
	} // end of the version check
	// A different context length.
	if r.ContextLength > 0 && refCtx > 0 && r.ContextLength != refCtx {
		// Name both.
		out = append(out, fmt.Sprintf("different context length (%d; most use %d)", r.ContextLength, refCtx))
	} // end of the context check
	// Part of the model on the processor.
	if r.ModelBytes > 0 && r.GPUBytes < r.ModelBytes {
		// Say so.
		out = append(out, "part of the model ran on the processor, not only on the graphics card")
	} // end of the split check
	// A busy machine.
	if r.Busy {
		// Say so.
		out = append(out, "the machine looked busy")
	} // end of the busy check
	// Other models in memory.
	if len(r.OtherLoaded) > 0 {
		// Say so.
		out = append(out, "other models were loaded during the test")
	} // end of the others check
	// The figure the ranking needs.
	if embedding {
		// A missing time.
		if r.WarmTotalSec <= 0 {
			// Say so.
			out = append(out, "no embedding time was saved")
		} // end of the time figure check
	} else {
		// A missing character count (tests made by older versions of this program).
		if r.CharSpeed <= 0 {
			// Say so, and what to do.
			out = append(out, "no character count was saved (older test): test the model again")
		} // end of the character check
		// An answer that ended early did less work than planned.
		if r.TokensOut > 0 && r.TokensOut < perfAnswerTokens {
			// Say so.
			out = append(out, fmt.Sprintf("the answer was shorter than the planned %d tokens", perfAnswerTokens))
		} // end of the length check
	} // end of the figure check
	// The list.
	return out
} // end of reasonsFor

// cmpBest returns the model in first place of the ranking (the list is ordered by size, so it is searched for).
func cmpBest(models []cmpModel) cmpModel {
	// Look for place one.
	for _, m := range models {
		// Found.
		if m.Rank == 1 {
			// Done.
			return m
		} // end of the check
	} // end of the loop
	// Nothing is ranked (callers check this first).
	return cmpModel{}
} // end of cmpBest

// groupSentences writes the headline of a group (only when it is ranked) and the notes that explain why there is no ranking.
func groupSentences(g cmpGroup) (string, []string) {
	// A ranked group names its fastest model.
	if g.Ranked >= 2 {
		// The best model is the one in first place.
		best := cmpBest(g.Models)
		// How many others were compared with it fairly.
		others := g.Ranked - 1
		// The word for the others.
		word := "models"
		// One other.
		if others == 1 {
			// Singular.
			word = "model"
		} // end of the word check
		// An embedding group.
		if g.Embedding {
			// The sentence.
			return fmt.Sprintf("%s embeds fastest in this group (%s), compared like for like with %d other %s.", best.Name, fmtSecs(best.Run.WarmTotalSec), others, word), nil
		} // end of the embedding case
		// A chat group.
		return fmt.Sprintf("%s writes fastest in this group (%.0f characters per second), compared like for like with %d other %s.", best.Name, best.Run.CharSpeed, others, word), nil
	} // end of the ranked case
	// A single model has no peer.
	if len(g.Models) == 1 {
		// The note about the neighbour is added later, when all groups are known.
		return "", nil
	} // end of the single case
	// Several models, but fewer than two that can be compared.
	return "", []string{"No ranking: fewer than two models in this group can be compared like for like. The flags in the last column say why; \"Re-test\" the models that can be fixed by testing them again."}
} // end of groupSentences

// singleNote writes the note for a group that has one model: no peer, and which group is nearest.
func singleNote(groups []cmpGroup, i int) string {
	// The start of the note.
	note := "Only model in this group, so there is no like-for-like peer yet and it is shown without a rank."
	// The nearest other chat group by size class.
	best, bestDist := -1, 1<<30
	// Look at the others.
	for j, o := range groups {
		// Not itself, and only chat groups with a real class.
		if j == i || o.Embedding || o.ClassIdx < 0 || groups[i].ClassIdx < 0 {
			// Skip.
			continue
		} // end of the skip check
		// The distance in classes.
		d := o.ClassIdx - groups[i].ClassIdx
		// Make it positive.
		if d < 0 {
			// Flip the sign.
			d = -d
		} // end of the sign check
		// Nearer, or equally near and smaller.
		if d < bestDist || (d == bestDist && o.ClassIdx < groups[best].ClassIdx) {
			// Keep it.
			best, bestDist = j, d
		} // end of the nearest check
	} // end of the loop
	// A neighbour exists.
	if best >= 0 {
		// Name it, without ranking across groups.
		note += " The nearest group is \"" + groups[best].Title + "\"; models of different groups are not ranked against each other."
	} // end of the neighbour check
	// The note.
	return note
} // end of singleNote
