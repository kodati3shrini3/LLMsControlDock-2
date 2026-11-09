// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds the page in memory first.
	"bytes"
	// context limits how long the reads may take.
	"context"
	// embed stores the page template inside the program.
	_ "embed"
	// fmt builds the number texts.
	"fmt"
	// html/template fills the page and escapes every value.
	"html/template"
	// log reports a template error.
	"log"
	// net/http is the web server.
	"net/http"
	// os reads the home folder and one environment variable.
	"os"
	// regexp matches the keywords that assign a model to a field of use.
	"regexp"
	// sort orders the results.
	"sort"
	// strconv turns typed text into numbers.
	"strconv"
	// strings trims and joins text.
	"strings"
	// sync runs the tag reads side by side.
	"sync"
	// time gives the reading time its zone.
	"time"
) // end of imports

// findLLMTemplateText is the Find LLM page, stored inside the executable at build time.
//
//go:embed web/findllm.html
var findLLMTemplateText string

// maxFindResults is how many models get their tags page read and are shown; the most popular come first.
const maxFindResults = 10

// maxFindVersions is how many versions are listed under one model; the rest are counted.
const maxFindVersions = 6

// maxFindCloud is how many cloud-only models are shown in the cloud section; the rest are counted.
const maxFindCloud = 10

// The texts of the state icons' tooltips. Each is one short line, at most 130 characters, with no markup characters.
const (
	// tipCloud is for a cloud model.
	tipCloud = "Cloud model: runs on Ollama's servers, not on this computer, and may need an Ollama account. Nothing is downloaded here."
	// tipModelFits is for a model with at least one version that fits.
	tipModelFits = "At least one version of this model can be installed here with your choices."
	// tipModelNoFit is for a model with no version that fits.
	tipModelNoFit = "No version of this model can be installed here with your choices; the reasons are written under each version."
	// tipVersionFits is for a version that fits.
	tipVersionFits = "This version can be installed here: it fits your free disk space, memory and choices."
	// tipVersionNoFit is for a version that does not fit.
	tipVersionNoFit = "This version cannot be installed here with your choices; the reason is written under it."
)

// iconView is a state icon with its tooltip: Kind is fits, nofit or cloud (empty means no icon), Label is the hidden name for screen readers, ID names the tooltip, Text is the tooltip.
type iconView struct {
	// Kind picks the drawing and the colour.
	Kind string
	// Label is read by screen readers.
	Label string
	// ID links the icon to its tooltip.
	ID string
	// Text is the tooltip.
	Text string
} // end of iconView

// modelIcon makes the icon of a model from its state: fits, nofit, cloud, or empty for none.
func modelIcon(state, id string) iconView {
	// By state.
	switch state {
	// At least one version fits.
	case "fits":
		// The check mark.
		return iconView{Kind: "fits", Label: "Can be installed", ID: id, Text: tipModelFits}
	// No version fits.
	case "nofit":
		// The cross.
		return iconView{Kind: "nofit", Label: "Cannot be installed", ID: id, Text: tipModelNoFit}
	// A cloud model.
	case "cloud":
		// The cloud.
		return iconView{Kind: "cloud", Label: "Cloud model", ID: id, Text: tipCloud}
	} // end of the state switch
	// Unknown: no icon, never a guess.
	return iconView{}
} // end of modelIcon

// versionIcon makes the icon of one version: the check mark when it fits, the cross when it does not.
func versionIcon(fits bool, id string) iconView {
	// Fits.
	if fits {
		// The check mark.
		return iconView{Kind: "fits", Label: "Can be installed", ID: id, Text: tipVersionFits}
	} // end of the fit check
	// Does not fit.
	return iconView{Kind: "nofit", Label: "Cannot be installed", ID: id, Text: tipVersionNoFit}
} // end of versionIcon

// findParallel is how many tags pages are read at the same time.
const findParallel = 5

// paramClasses are the plain-language size classes, with the biggest number of billions each one holds (the last has no limit).
var paramClasses = []struct {
	// Key is the form field name.
	Key string
	// Label is the plain word shown.
	Label string
	// Range says what it means in numbers.
	Range string
	// Max is the largest number of billions in the class; 0 means no limit.
	Max float64
}{
	// Up to one billion.
	{"tiny", "Tiny", "up to 1 billion", 1},
	// Over one up to four.
	{"small", "Small", "over 1 up to 4 billion", 4},
	// Over four up to fourteen.
	{"medium", "Medium", "over 4 up to 14 billion", 14},
	// Over fourteen up to forty.
	{"large", "Large", "over 14 up to 40 billion", 40},
	// Over forty.
	{"huge", "Very large", "over 40 billion", 0},
} // end of paramClasses

// contextClasses are the plain-language classes for how much a model can remember of a conversation, with the biggest length in thousands each one holds (the last has no limit).
var contextClasses = []struct {
	// Key is the form field name.
	Key string
	// Label is the plain word shown.
	Label string
	// Range says what it means in numbers.
	Range string
	// Max is the largest length in thousands in the class; 0 means no limit.
	Max float64
}{
	// Under eight thousand.
	{"short", "Short", "under 8K", 7.999},
	// Eight up to thirty-two thousand.
	{"medium", "Medium", "8K to 32K", 32},
	// Over thirty-two up to one hundred twenty-eight.
	{"long", "Long", "over 32K to 128K", 128},
	// Over one hundred twenty-eight.
	{"verylong", "Very long", "over 128K", 0},
} // end of contextClasses

// paramsBillions turns a size label such as 0.6b, 350m or e4b into billions; ok is false for a label it cannot read.
func paramsBillions(label string) (float64, bool) {
	// An effective-size label such as e4b counts as its number.
	l := strings.TrimPrefix(strings.ToLower(label), "e")
	// The last letter is the unit.
	if len(l) < 2 {
		// Too short to read.
		return 0, false
	} // end of the length check
	// The number part.
	n, err := strconv.ParseFloat(l[:len(l)-1], 64)
	// Not a number.
	if err != nil {
		// Unknown.
		return 0, false
	} // end of the number check
	// Choose by unit.
	switch l[len(l)-1] {
	// Billions.
	case 'b':
		// As it is.
		return n, true
	// Millions.
	case 'm':
		// A thousandth of a billion.
		return n / 1000, true
	} // end of the unit switch
	// Unknown unit.
	return 0, false
} // end of paramsBillions

// paramClassOf returns the key of the size class of a number of billions.
func paramClassOf(b float64) string {
	// The first class that is large enough.
	for _, c := range paramClasses {
		// A class without a limit takes everything left.
		if c.Max == 0 || b <= c.Max {
			// Found it.
			return c.Key
		} // end of the limit check
	} // end of the class loop
	// Not reached: the last class has no limit.
	return "huge"
} // end of paramClassOf

// contextThousands turns a context text such as 128K, 40K or 1M into thousands of tokens; ok is false for text it cannot read.
func contextThousands(text string) (float64, bool) {
	// Nothing shown on the page.
	if text == "" {
		// Unknown.
		return 0, false
	} // end of the empty check
	// The unit is the last letter, the number is the rest.
	unit := text[len(text)-1]
	// The number part.
	n, err := strconv.ParseFloat(text[:len(text)-1], 64)
	// Not a number.
	if err != nil {
		// Unknown.
		return 0, false
	} // end of the number check
	// Choose by unit.
	switch unit {
	// Thousands.
	case 'K', 'k':
		// As it is.
		return n, true
	// Millions count as a thousand thousands.
	case 'M', 'm':
		// Thousands of tokens.
		return n * 1000, true
	} // end of the unit switch
	// Unknown unit.
	return 0, false
} // end of contextThousands

// contextClassOf returns the key of the class of a number of thousands.
func contextClassOf(k float64) string {
	// The first class that is large enough.
	for _, c := range contextClasses {
		// A class without a limit takes everything left.
		if c.Max == 0 || k <= c.Max {
			// Found it.
			return c.Key
		} // end of the limit check
	} // end of the class loop
	// Not reached: the last class has no limit.
	return "verylong"
} // end of contextClassOf

// pullsNumber turns a download count such as 120.9M, 3.4K or 87 into a number, for sorting; unreadable text counts as 0.
func pullsNumber(text string) float64 {
	// Nothing.
	if text == "" {
		// Zero.
		return 0
	} // end of the empty check
	// The multiplier for the last letter.
	mult := 1.0
	// The number part starts as the whole text.
	num := text
	// Choose by unit.
	switch text[len(text)-1] {
	// Thousands.
	case 'K':
		// A thousand.
		mult, num = 1e3, text[:len(text)-1]
	// Millions.
	case 'M':
		// A million.
		mult, num = 1e6, text[:len(text)-1]
	// Billions.
	case 'B':
		// A billion.
		mult, num = 1e9, text[:len(text)-1]
	} // end of the unit switch
	// Read the number.
	f, err := strconv.ParseFloat(num, 64)
	// Unreadable.
	if err != nil {
		// Zero.
		return 0
	} // end of the number check
	// The value.
	return f * mult
} // end of pullsNumber

// findSelection is what the person chose on the page.
type findSelection struct {
	// Chat is true when "Chat and writing" is ticked: the model is not a search-and-similarity model.
	Chat bool
	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding).
	Abilities map[string]bool
	// Sort is how the models are ordered: "downloads" (the default, also when empty) or "name".
	Sort string
	// Domains are the ticked fields of use (keys of findDomains); empty means no filter.
	Domains map[string]bool
	// DomainAny is true when the person chose "Match ANY ticked" for the fields of use; false (the default) is "Match ALL ticked".
	DomainAny bool
	// Any is true when the person chose "Match ANY ticked": a model needs at least one ticked ability; false (the default) is "Match ALL ticked": it needs every one.
	Any bool
	// Sizes are the ticked size classes (empty means any size).
	Sizes map[string]bool
	// Contexts are the ticked memory classes (empty means any).
	Contexts map[string]bool
	// DiskGB is the free disk space in gigabytes; negative means not known.
	DiskGB float64
	// MemGB is the memory in gigabytes; negative means not known.
	MemGB float64
} // end of findSelection

// abilityKeys are the ability tick boxes, in the order shown; each is also the label the library list page uses.
var abilityKeys = []string{"tools", "vision", "audio", "thinking", "embedding"}

// parseGB reads a typed number of gigabytes; empty text means "not known" (-1); a bad or absurd number is an error.
func parseGB(text string) (float64, error) {
	// Trim spaces and allow a decimal comma.
	t := strings.ReplaceAll(strings.TrimSpace(text), ",", ".")
	// Empty: not known.
	if t == "" {
		// Not known.
		return -1, nil
	} // end of the empty check
	// Read it.
	f, err := strconv.ParseFloat(t, 64)
	// Not a number, or outside a sensible range.
	if err != nil || f < 0 || f > 100000 {
		// Refuse.
		return 0, fmt.Errorf("%q is not a number between 0 and 100000", strings.TrimSpace(text))
	} // end of the number check
	// A good number.
	return f, nil
} // end of parseGB

// parseFindForm reads the form fields into a selection; problems lists what was typed wrongly.
func parseFindForm(get func(string) string) (findSelection, []string) {
	// Start empty.
	sel := findSelection{Abilities: map[string]bool{}, Domains: map[string]bool{}, Sizes: map[string]bool{}, Contexts: map[string]bool{}}
	// The problems found.
	var problems []string
	// Chat and writing.
	sel.Chat = get("ab_chat") == "on"
	// Match ANY only when that exact choice was sent; anything else, or nothing, is the default Match ALL.
	sel.Any = get("ab_mode") == "any"
	// The order of the results: Name A to Z only when that exact choice was sent; anything else is the default, most downloaded.
	if get("sort") == "name" {
		// Name order.
		sel.Sort = "name"
	} // end of the sort check
	// The same for the fields of use.
	sel.DomainAny = get("dom_mode") == "any"
	// Each known field of use that is ticked.
	for _, d := range findDomains {
		// Ticked.
		if get("dom_"+d.Key) == "on" {
			// Remember it.
			sel.Domains[d.Key] = true
		} // end of the tick check
	} // end of the fields
	// Each ability.
	for _, k := range abilityKeys {
		// Ticked.
		if get("ab_"+k) == "on" {
			// Keep it.
			sel.Abilities[k] = true
		} // end of the tick check
	} // end of the ability loop
	// Each size class.
	for _, c := range paramClasses {
		// Ticked.
		if get("sz_"+c.Key) == "on" {
			// Keep it.
			sel.Sizes[c.Key] = true
		} // end of the tick check
	} // end of the size loop
	// Each memory class.
	for _, c := range contextClasses {
		// Ticked.
		if get("cx_"+c.Key) == "on" {
			// Keep it.
			sel.Contexts[c.Key] = true
		} // end of the tick check
	} // end of the context loop
	// The disk figure.
	d, err := parseGB(get("disk_gb"))
	// A bad figure.
	if err != nil {
		// Say which.
		problems = append(problems, "Free disk space: "+err.Error())
	} // end of the disk check
	// Keep it.
	sel.DiskGB = d
	// The memory figure.
	m, err := parseGB(get("mem_gb"))
	// A bad figure.
	if err != nil {
		// Say which.
		problems = append(problems, "Memory: "+err.Error())
	} // end of the memory check
	// Keep it.
	sel.MemGB = m
	// The result.
	return sel, problems
} // end of parseFindForm

// domainDef describes one field of use: how a model is assigned to it, from its name and from the first words of its description.
type domainDef struct {
	// Key is the short code in the form field name (dom_<key>).
	Key string
	// Label is the wording on the page.
	Label string
	// Tip is the very short help line; one line, no markup characters.
	Tip string
	// Name matches the library name of the model.
	Name *regexp.Regexp
	// Lead matches the first words of the description (the part that says what the model is for).
	Lead *regexp.Regexp
} // end of domainDef

// domainLeadRunes is how many characters of the description count: the opening, which says what the model is for, not the long list of side abilities after it.
const domainLeadRunes = 100

// findDomains are the fields of use of the first version. Pharma, legal and finance are left out until the official list has models for them.
var findDomains = []domainDef{
	// Healthcare and medicine.
	{"health", "Healthcare and medicine", "Medical models. Not validated for clinical use.",
		regexp.MustCompile(`(?i)\bmed(llama|gemma|iton)`),
		regexp.MustCompile(`(?i)\bmedical\b|\bmedicine\b|\bhealth(care)?\b|\bclinical\b|\bbiomedical\b|\bpatients?\b|\bdoctors?\b|\bdiagnos\w*`)},
	// Code and software.
	{"code", "Code and software", "Models made for writing and fixing code.",
		regexp.MustCompile(`(?i)code|devstral`),
		regexp.MustCompile(`(?i)\bcode (generation|completion|llm|language model|model|models)\b|\bcoding (model|models|agents|tasks)\b|\bcoding-focused\b|\bcode-specific\b|\bcode intelligence\b`)},
	// SQL and data.
	{"sql", "SQL and data", "Models that turn questions into SQL queries.",
		regexp.MustCompile(`(?i)sql`),
		regexp.MustCompile(`(?i)\bsql\b|\btext-to-sql\b`)},
	// Maths and science.
	{"math", "Maths and science", "Models made for maths problems and science.",
		regexp.MustCompile(`(?i)math`),
		regexp.MustCompile(`(?i)\bmath (language )?models?\b|\bmath problems\b|\bmath reasoning\b|\bscientific discovery\b|\btheorem`)},
	// Documents and OCR.
	{"docs", "Documents and OCR", "Models that read scans, pages and forms.",
		regexp.MustCompile(`(?i)ocr|docling|nuextract|reader-lm`),
		regexp.MustCompile(`(?i)\bocr\b|\binformation extraction\b|\bhtml (content )?to markdown\b|\bdocument understanding\b`)},
	// Translation and languages.
	{"lang", "Translation and languages", "Translation and models built for many languages.",
		regexp.MustCompile(`(?i)translate|^aya|sailor`),
		regexp.MustCompile(`(?i)\btranslat\w*|\bmultilingual\b|\bbilingual\b|\b\d+ languages\b|\b(chinese|korean|japanese|arabic|german) (dialogue|language)`)},
	// Safety and moderation.
	{"safety", "Safety and moderation", "Models that check prompts and answers for risk.",
		regexp.MustCompile(`(?i)guard|shield|safeguard`),
		regexp.MustCompile(`(?i)\bcontent safety\b|\bmoderat\w*|\bsafety (classification|reasoning)\b`)},
} // end of findDomains

// modelDomains returns the keys of the fields of use a model belongs to, judged from its name and the opening of its description. This is a guess from words, not a certification.
func modelDomains(m siteModel) map[string]bool {
	// The opening of the description, cut by characters so no letter is split.
	lead := []rune(m.Description)
	// Cut it.
	if len(lead) > domainLeadRunes {
		// Keep the opening.
		lead = lead[:domainLeadRunes]
	} // end of the cut
	// The result.
	out := map[string]bool{}
	// Each field of use.
	for _, d := range findDomains {
		// The name or the opening matches.
		if d.Name.MatchString(m.Name) || d.Lead.MatchString(string(lead)) {
			// The model belongs to it.
			out[d.Key] = true
		} // end of the match
	} // end of the fields
	// Done.
	return out
} // end of modelDomains

// domainMatch says whether a model satisfies the ticked fields of use: Match ALL (the default) needs every ticked field, Match ANY at least one; nothing ticked lets every model pass.
func domainMatch(sel findSelection, m siteModel) bool {
	// Nothing ticked: no filter.
	if len(sel.Domains) == 0 {
		// Every model passes.
		return true
	} // end of the empty check
	// The fields of this model.
	has := modelDomains(m)
	// How many ticked fields the model belongs to.
	hits := 0
	// Count them.
	for k := range sel.Domains {
		// A hit.
		if has[k] {
			// One more.
			hits++
		} // end of the hit
	} // end of the count
	// Match ANY: one is enough.
	if sel.DomainAny {
		// At least one.
		return hits > 0
	} // end of the any check
	// Match ALL: every ticked field.
	return hits == len(sel.Domains)
} // end of domainMatch

// modelBefore says whether model a is listed before model b: by name for the choice Name A to Z, otherwise most downloaded first, with equal counts keeping the name order so the list is stable.
func modelBefore(sel findSelection, a, b siteModel) bool {
	// Name A to Z.
	if sel.Sort == "name" {
		// By name.
		return a.Name < b.Name
	} // end of the name order
	// The download counts.
	pa, pb := pullsNumber(a.Pulls), pullsNumber(b.Pulls)
	// The higher count first.
	if pa != pb {
		// Decide by count.
		return pa > pb
	} // end of the count check
	// Then by name.
	return a.Name < b.Name
} // end of modelBefore

// abilitiesMatch says whether a model with the abilities in has satisfies the ticks of "What it should do": with Match ALL (the default) every ticked item must hold, with Match ANY at least one; with nothing ticked every model passes. "Chat and writing" holds for a model that is not a search-and-similarity model.
func abilitiesMatch(sel findSelection, has map[string]bool) bool {
	// How many items are ticked and how many of them the model satisfies.
	ticked, hits := 0, 0
	// Chat and writing: holds when the model is not an embedding model.
	if sel.Chat {
		// One more ticked item.
		ticked++
		// Satisfied by a model that is not an embedding model.
		if !has["embedding"] {
			// One more hit.
			hits++
		} // end of the chat check
	} // end of the chat item
	// Each ticked ability.
	for a := range sel.Abilities {
		// One more ticked item.
		ticked++
		// The model has it.
		if has[a] {
			// One more hit.
			hits++
		} // end of the ability check
	} // end of the ability loop
	// Nothing ticked: no filter.
	if ticked == 0 {
		// Every model passes.
		return true
	} // end of the empty check
	// Match ANY: one hit is enough.
	if sel.Any {
		// At least one.
		return hits > 0
	} // end of the any check
	// Match ALL: every ticked item.
	return hits == ticked
} // end of abilitiesMatch

// findCandidates applies the choices that the list page can answer: cloud-only models are left out, abilities and size classes are checked; the count of models without a readable size is returned when a size class is chosen. A model that carries the cloud label but also lists sizes (for example gemma4 or gpt-oss) has versions that run on this computer, so it stays; its cloud versions are dropped later, when its versions are listed.
func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noSize int, cloud int) {
	// Look at every model.
	for _, m := range models {
		// Cloud-only models run on Ollama's servers, not on this computer, and may need an account; a cloud label together with sizes means local versions exist too.
		if m.Cloud && len(m.Sizes) == 0 {
			// Count and skip.
			cloud++
			// Next.
			continue
		} // end of the cloud check
		// The model's abilities as a set.
		has := map[string]bool{}
		// Fill it.
		for _, a := range m.Abilities {
			// One ability.
			has[a] = true
		} // end of the fill
		// The ticks of "What it should do": all of them or any of them, as chosen.
		if !abilitiesMatch(sel, has) {
			// Next.
			continue
		} // end of the ability check
		// The ticked fields of use: all of them or any of them, as chosen.
		if !domainMatch(sel, m) {
			// Next.
			continue
		} // end of the field check
		// Size classes: at least one of the model's sizes must be in a ticked class.
		if len(sel.Sizes) > 0 {
			// Whether any size matches, and whether any size could be read.
			match, readable := false, false
			// Check each size label.
			for _, s := range m.Sizes {
				// Read it.
				if b, ok := paramsBillions(s); ok {
					// At least one size is readable.
					readable = true
					// In a ticked class.
					if sel.Sizes[paramClassOf(b)] {
						// A match.
						match = true
					} // end of the class check
				} // end of the read check
			} // end of the size loop
			// No readable size: count it, and leave the model out of a size search.
			if !readable {
				// Count it.
				noSize++
				// Next.
				continue
			} // end of the readable check
			// No matching size.
			if !match {
				// Next.
				continue
			} // end of the match check
		} // end of the size filter
		// It passed.
		out = append(out, m)
	} // end of the model loop
	// The chosen order: most downloaded first (the default) or Name A to Z.
	sort.SliceStable(out, func(i, j int) bool {
		// Compare as chosen.
		return modelBefore(sel, out[i], out[j])
	}) // end of the sort
	// The result.
	return out, noSize, cloud
} // end of findCandidates

// findCloudModels returns the cloud-only models that match the ticked abilities, most downloaded first, for the cloud section; skipped is true when a size or memory class is ticked, because those classes describe this computer and do not apply to a model that runs on Ollama's servers (its size is not listed either).
func findCloudModels(models []siteModel, sel findSelection) (out []siteModel, skipped bool) {
	// A class describes what runs on this computer: leave the cloud models out of such a search.
	if len(sel.Sizes) > 0 || len(sel.Contexts) > 0 {
		// Say that they were left out.
		return nil, true
	} // end of the class check
	// Look at every model.
	for _, m := range models {
		// Only cloud-only models: the cloud label and no local size.
		if !m.Cloud || len(m.Sizes) > 0 {
			// Next.
			continue
		} // end of the cloud-only check
		// The model's abilities as a set.
		has := map[string]bool{}
		// Fill it.
		for _, a := range m.Abilities {
			// One ability.
			has[a] = true
		} // end of the fill
		// The ticks of "What it should do": all of them or any of them, as chosen.
		if abilitiesMatch(sel, has) && domainMatch(sel, m) {
			// Keep the match.
			out = append(out, m)
		} // end of the match check
	} // end of the model loop
	// The chosen order: most downloaded first (the default) or Name A to Z.
	sort.SliceStable(out, func(i, j int) bool {
		// Compare as chosen.
		return modelBefore(sel, out[i], out[j])
	}) // end of the sort
	// The result.
	return out, false
} // end of findCloudModels

// cloudView makes the view of a cloud-only model: no versions are read for it, because nothing is downloaded.
func cloudView(m siteModel) resultView {
	// The basic facts, with the cloud state.
	return resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Pulls: m.Pulls, URL: ollamaSite + "/library/" + m.Name, State: "cloud"}
} // end of cloudView

// versionReason says why a version does not fit this computer; empty text means it fits.
func versionReason(t siteTag, sel findSelection) string {
	// The size in gigabytes (decimal), when the page showed one.
	gb := float64(t.SizeBytes) / 1e9
	// Disk space.
	if sel.DiskGB >= 0 && t.SizeBytes > 0 && gb > sel.DiskGB {
		// Too big for the disk.
		return fmt.Sprintf("needs %s of disk space; you have %s free", findGBText(gb), findGBText(sel.DiskGB))
	} // end of the disk check
	// Memory: a model larger than all the memory cannot be loaded completely.
	if sel.MemGB >= 0 && t.SizeBytes > 0 && gb > sel.MemGB {
		// Too big for the memory.
		return fmt.Sprintf("needs about %s of memory; you have %s", findGBText(gb), findGBText(sel.MemGB))
	} // end of the memory check
	// Memory-of-conversation classes.
	if len(sel.Contexts) > 0 {
		// Read the context length.
		k, ok := contextThousands(t.Context)
		// Unknown length: leave the version out of a context search.
		if !ok {
			// Say so.
			return "the page does not show its context length"
		} // end of the readable check
		// Not in a ticked class.
		if !sel.Contexts[contextClassOf(k)] {
			// Say so.
			return "its context length (" + t.Context + ") is not in the classes you ticked"
		} // end of the class check
	} // end of the context check
	// It fits.
	return ""
} // end of versionReason

// findGBText writes a number of gigabytes for a person.
func findGBText(gb float64) string {
	// One decimal, and the unit.
	return strconv.FormatFloat(gb, 'f', 1, 64) + " GB"
} // end of findGBText

// versionView is one version as the page shows it.
type versionView struct {
	// Tag is the full name to download.
	Tag string
	// Command is the command that downloads it.
	Command string
	// Size is the download size as the page writes it.
	Size string
	// Context is the context length as the page writes it.
	Context string
	// Input is what it accepts.
	Input string
	// Fits is true when it fits this computer and the ticked classes.
	Fits bool
	// Reason says why it does not fit.
	Reason string
	// Installed is true when this exact version is installed in Ollama now.
	Installed bool
	// Note is the line shown for an installed version: its saved answer speed with the date of the test, or that it was not tested yet (empty when not installed).
	Note string
	// Icon is the can-be-installed or cannot-be-installed symbol with its tooltip.
	Icon iconView
} // end of versionView

// resultView is one model as the page shows it.
type resultView struct {
	// Name is the library name.
	Name string
	// Description is the one-line description.
	Description string
	// Abilities and Sizes are the labels shown.
	Abilities, Sizes string
	// Pulls is the download count as written on the page.
	Pulls string
	// URL is the official model page.
	URL string
	// Versions are the versions listed (the ones that fit first).
	Versions []versionView
	// More counts the versions not listed.
	More int
	// FitCount is how many versions fit.
	FitCount int
	// Unavailable says the tags page could not be read (empty when it was).
	Unavailable string
	// State is fits (at least one version fits), nofit (none does), cloud (runs on Ollama's servers) or empty (not known).
	State string
	// Icon is the symbol of the state with its tooltip.
	Icon iconView
} // end of resultView

// isCloudTag says whether a version name is a cloud version: Ollama names them name:cloud or name:size-cloud.
func isCloudTag(tag string) bool {
	// The part after the colon.
	part := tag
	// Cut at the colon.
	if i := strings.LastIndex(tag, ":"); i >= 0 {
		// The tag part.
		part = tag[i+1:]
	} // end of the cut
	// Exactly cloud, or ending in -cloud.
	return part == "cloud" || strings.HasSuffix(part, "-cloud")
} // end of isCloudTag

// installedFirst puts the installed versions before the others and keeps the order inside each part, so an installed version is never hidden among "more versions".
func installedFirst(vs []versionView) []versionView {
	// The two parts.
	var have, other []versionView
	// Sort each version into its part.
	for _, v := range vs {
		// Installed ones go first.
		if v.Installed {
			// Keep it.
			have = append(have, v)
		} else {
			// The rest.
			other = append(other, v)
		} // end of the part check
	} // end of the loop
	// Installed first.
	return append(have, other...)
} // end of installedFirst

// installedName makes a model name comparable: Ollama writes a model without a tag as name:latest.
func installedName(name string) string {
	// No tag part: it is the latest one.
	if !strings.Contains(name, ":") {
		// Add the tag Ollama adds.
		return name + ":latest"
	} // end of the tag check
	// Already complete.
	return name
} // end of installedName

// speedNote writes the line for an installed version from the saved tests: the newest answer speed with the date, or that it was not tested yet. An embedding model has no answer speed; it says so when an embedding test is saved.
func speedNote(store *perfStore, name string) string {
	// No saved tests at all.
	if store == nil {
		// Never guess.
		return "Installed, not tested yet"
	} // end of the store check
	// The chat tests, newest first.
	for _, r := range store.forModel(name, "generate") {
		// The newest one that measured a speed.
		if r.AnswerSpeed > 0 {
			// The speed and the date, with the computer's own time zone.
			return "Installed \u00b7 " + strconv.FormatFloat(r.AnswerSpeed, 'f', 1, 64) + " tokens per second \u00b7 tested " + r.Time.Local().Format("2 Jan 2006 15:04 MST")
		} // end of the speed check
	} // end of the loop
	// An embedding model is tested differently and writes no answers.
	if emb := store.forModel(name, "embedding"); len(emb) > 0 {
		// Say what was tested.
		return "Installed \u00b7 embedding test saved " + emb[0].Time.Local().Format("2 Jan 2006 15:04 MST") + " (no answer speed for embedding models)"
	} // end of the embedding check
	// Nothing saved for this version.
	return "Installed, not tested yet"
} // end of speedNote

// installedMarker makes the function that says, for a version name, whether it is installed and what to show; a nil list (Ollama could not be read) gives nil, so nothing is marked.
func installedMarker(list []installedModel, store *perfStore, ok bool) func(string) (bool, string) {
	// Ollama could not be read: mark nothing rather than guess.
	if !ok {
		// No marker.
		return nil
	} // end of the read check
	// The installed names, in the complete form.
	have := map[string]string{}
	// Walk the list.
	for _, m := range list {
		// Keep the name as Ollama wrote it, for the saved tests.
		have[installedName(m.Name)] = m.Name
	} // end of the loop
	// The marker.
	return func(tag string) (bool, string) {
		// The installed model of that name, if any.
		name, found := have[installedName(tag)]
		// Not installed.
		if !found {
			// No mark.
			return false, ""
		} // end of the found check
		// Installed: the line from the saved tests.
		return true, speedNote(store, name)
	}
} // end of installedMarker

// buildResult turns a model and its versions into the view; tags is nil when the tags page could not be read, and why says what went wrong.
func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mark func(string) (bool, string)) resultView {
	// The basic facts.
	r := resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Sizes: strings.Join(m.Sizes, ", "), Pulls: m.Pulls, URL: ollamaSite + "/library/" + m.Name}
	// The tags page could not be read: say so, never guess.
	if tags == nil {
		// The reason.
		r.Unavailable = "details are not available right now (" + why + ")"
		// Done.
		return r
	} // end of the unavailable case
	// Judge every version.
	var fit, nofit []versionView
	// Look at each.
	for _, t := range tags {
		// A cloud version runs on Ollama's servers, not on this computer: it is not offered here.
		if isCloudTag(t.Tag) {
			// Next version.
			continue
		} // end of the cloud check
		// Its view.
		v := versionView{Tag: t.Tag, Command: "ollama pull " + t.Tag, Size: t.SizeText, Context: t.Context, Input: t.Input}
		// Whether this version is installed here, and what the saved tests say about it.
		if mark != nil {
			// Ask the marker.
			v.Installed, v.Note = mark(t.Tag)
		} // end of the marker check
		// Why it does not fit, if it does not.
		v.Reason = versionReason(t, sel)
		// Fits when there is no reason.
		v.Fits = v.Reason == ""
		// Sort into the two lists.
		if v.Fits {
			// Fits.
			fit = append(fit, v)
		} else {
			// Does not fit.
			nofit = append(nofit, v)
		} // end of the sorting
	} // end of the version loop
	// Every version was a cloud version: nothing here can run on this computer.
	if len(fit)+len(nofit) == 0 {
		// Say so; the template adds the pointer to the official page.
		r.Unavailable = "all its versions run on Ollama's servers (cloud), not on this computer"
		// It is a cloud model after all.
		r.State = "cloud"
		// Done.
		return r
	} // end of the empty check
	// The count that fit.
	r.FitCount = len(fit)
	// The state of the model: at least one version fits, or none does.
	r.State = "nofit"
	// At least one fits.
	if r.FitCount > 0 {
		// The check mark state.
		r.State = "fits"
	} // end of the state choice
	// The versions that fit first, then the others; inside each group the installed ones come first, then the page's order.
	all := append(installedFirst(fit), installedFirst(nofit)...)
	// Cut the list.
	if len(all) > maxFindVersions {
		// Count the rest.
		r.More = len(all) - maxFindVersions
		// Keep the first ones.
		all = all[:maxFindVersions]
	} // end of the cut
	// Keep them.
	r.Versions = all
	// The finished view.
	return r
} // end of buildResult

// findMachine is what this computer says about itself, for the prefilled fields.
type findMachine struct {
	// DiskGB is the free disk space in gigabytes, or -1 when not known.
	DiskGB float64
	// DiskWhere is the folder the figure was taken from.
	DiskWhere string
	// MemGB is the total memory in gigabytes, or -1 when not known.
	MemGB float64
	// GPU is the graphics card name, or empty when none was found.
	GPU string
	// Remote is true when Ollama runs on another computer, so none of these figures describe it.
	Remote bool
} // end of findMachine

// readFindMachine reads the machine facts; for Ollama on another computer it reports only that.
func readFindMachine(ctx context.Context, local bool) findMachine {
	// Start with "not known".
	fm := findMachine{DiskGB: -1, MemGB: -1, Remote: !local}
	// Another computer: these figures would describe the wrong one.
	if !local {
		// Stop.
		return fm
	} // end of the remote case
	// The memory and the graphics card come from the same reading the monitor uses.
	snap := snapshotMachine(ctx, true)
	// Memory.
	if snap.MemTotalGB > 0 {
		// Keep it.
		fm.MemGB = snap.MemTotalGB
	} // end of the memory check
	// The graphics card.
	fm.GPU = snap.GPUName
	// The folder whose disk matters: the model folder when it is set, otherwise the home folder.
	where := os.Getenv("OLLAMA_MODELS")
	// Not set or not there: the home folder.
	if st, err := os.Stat(where); where == "" || err != nil || !st.IsDir() {
		// The home folder.
		where, _ = os.UserHomeDir()
	} // end of the folder choice
	// Read the free space.
	if where != "" {
		// Ask the system.
		if free, err := osFreeDiskBytes(where); err == nil {
			// In gigabytes (decimal, like every size shown).
			fm.DiskGB = float64(free) / 1e9
			// Where it was read.
			fm.DiskWhere = where
		} // end of the read check
	} // end of the folder check
	// The facts.
	return fm
} // end of readFindMachine

// findPage is everything the Find LLM template shows.
type findPage struct {
	// Theme and Size are the saved look choices.
	Theme, Size string
	// Token proves the form comes from this page.
	Token string
	// Tips are the help bubbles by name.
	Tips map[string]tipView
	// Abilities are the tick boxes with their state.
	Abilities []findTick
	// Sizes and Contexts are the class tick boxes with their state.
	Sizes, Contexts []findTick
	// Chat is whether "Chat and writing" is ticked.
	Chat bool
	// AnyMode is whether "Match ANY ticked" is chosen; false means "Match ALL ticked".
	AnyMode bool
	// Domains are the boxes of the fields of use.
	Domains []domainTick
	// SortName is whether Name A to Z is chosen; false means most downloaded.
	SortName bool
	// DomainAnyMode is whether "Match ANY ticked" is chosen for the fields of use.
	DomainAnyMode bool
	// Disk and Mem are the typed numbers, as text.
	Disk, Mem string
	// DiskNote and MemNote explain where the numbers come from.
	DiskNote, MemNote string
	// GPU is the graphics card line.
	GPU string
	// Problems are the things wrong with what was typed.
	Problems []string
	// Searched is true after a search, so the results block is drawn.
	Searched bool
	// Error is the reason the library could not be read (empty when it could).
	Error string
	// ReadAt is when the list was read, with its zone.
	ReadAt string
	// Results are the models shown.
	Results []resultView
	// Summary is the sentence above the results: how many models match, which are shown, when the list was read, and what was left out.
	Summary string
	// CopyNote says that the list is a saved copy, with its date and why; empty when the list was read live.
	CopyNote string
	// ShowCopy is true when at least one version fits, so the page carries Copy buttons and the monitor's own copy script.
	ShowCopy bool
	// CloudResults are the cloud-only models shown in their own section.
	CloudResults []resultView
	// CloudMore counts the cloud-only models that match but are not shown.
	CloudMore int
	// InstalledCount is how many of the listed versions are installed here.
	InstalledCount int
	// InstalledNote says that the installed models could not be read, so no version is marked (empty when they could).
	InstalledNote string
} // end of findPage

// domainTick is one box of the fields of use.
type domainTick struct {
	// Name is the form field name.
	Name string
	// Label is the wording.
	Label string
	// Tip is the very short help line.
	Tip string
	// TipID is the id of its tooltip.
	TipID string
	// On is true when ticked.
	On bool
} // end of domainTick

// findTick is one tick box.
type findTick struct {
	// Name is the form field name.
	Name string
	// Label is the plain wording.
	Label string
	// Range is the number explanation (for classes).
	Range string
	// On is true when ticked.
	On bool
	// Tip is the help bubble.
	Tip tipView
} // end of findTick

// findLLMHandlers makes the two handlers of the Find LLM page: the first shows the choices, the second reads the library and shows the models; the second asks the public website, and only the address of its page leaves this computer.
func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc) {
	// Parse the template once.
	page := template.Must(template.New("findllm").Parse(findLLMTemplateText + tipsTemplateText))
	// Whether Ollama runs on this computer.
	local := isLocalAddress(addr.URL)
	// The help bubbles, by name.
	tips := map[string]tipView{}
	// Build them from the table of texts.
	for key, heading := range findTipHeadings {
		// One bubble.
		tips[key] = makeFindTip("tip-find-"+key, heading)
	} // end of the bubble loop
	// render draws the page for a selection.
	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, cloudRes []resultView, cloudMore int, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
		// The tick boxes.
		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, DomainAnyMode: sel.DomainAny, SortName: sel.Sort == "name", Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
		// The abilities.
		for _, k := range abilityKeys {
			// One box.
			data.Abilities = append(data.Abilities, findTick{Name: "ab_" + k, Label: findAbilityLabels[k], On: sel.Abilities[k], Tip: tips[k]})
		} // end of the abilities
		// The size classes.
		for _, c := range paramClasses {
			// One box.
			data.Sizes = append(data.Sizes, findTick{Name: "sz_" + c.Key, Label: c.Label, Range: c.Range, On: sel.Sizes[c.Key]})
		} // end of the sizes
		// The memory classes.
		for _, c := range contextClasses {
			// One box.
			data.Contexts = append(data.Contexts, findTick{Name: "cx_" + c.Key, Label: c.Label, Range: c.Range, On: sel.Contexts[c.Key]})
		} // end of the contexts
		// The boxes of the fields of use.
		for _, d := range findDomains {
			// One box.
			data.Domains = append(data.Domains, domainTick{Name: "dom_" + d.Key, Label: d.Label, Tip: d.Tip, TipID: "tip-dom-" + d.Key, On: sel.Domains[d.Key]})
		} // end of the fields
		// The typed numbers.
		data.Disk, data.Mem = numberText(sel.DiskGB), numberText(sel.MemGB)
		// Where the disk number comes from.
		switch {
		// Ollama is elsewhere.
		case fm.Remote:
			// Say so.
			data.DiskNote = "Ollama is on another computer, so nothing was measured here. Type the free space on that computer, or leave it empty to skip this check."
		// Measured.
		case fm.DiskWhere != "":
			// Say where.
			data.DiskNote = "Measured on the disk of " + fm.DiskWhere + ". If Ollama runs in Docker or keeps its models on another disk, type the free space of that disk instead."
		// Not measured.
		default:
			// Say so.
			data.DiskNote = "The free space could not be measured. Type it, or leave it empty to skip this check."
		} // end of the disk note
		// Where the memory number comes from.
		switch {
		// Ollama is elsewhere.
		case fm.Remote:
			// Say so.
			data.MemNote = "Type the memory of the computer Ollama runs on, or leave it empty to skip this check."
		// Measured.
		case fm.MemGB >= 0:
			// Say so.
			data.MemNote = "Measured: the total memory of this computer. On a computer with a graphics card that has its own memory, use that memory instead."
		// Not measured.
		default:
			// Say so.
			data.MemNote = "The memory could not be measured. Type it, or leave it empty to skip this check."
		} // end of the memory note
		// The graphics card.
		switch {
		// Ollama is elsewhere.
		case fm.Remote:
			// Say so.
			data.GPU = "Not known (Ollama is on another computer)"
		// Found.
		case fm.GPU != "":
			// The name.
			data.GPU = "Found: " + fm.GPU
		// Not found.
		default:
			// Say so.
			data.GPU = "Not found by the graphics tool; models would run on the processor"
		} // end of the graphics note
		// The state icons, each with its own tooltip name, so no two tooltips share a name.
		for ri := range data.Results {
			// The model's icon.
			data.Results[ri].Icon = modelIcon(data.Results[ri].State, fmt.Sprintf("tipstate-%d", ri))
			// Each version's icon.
			for vi := range data.Results[ri].Versions {
				// One version.
				data.Results[ri].Versions[vi].Icon = versionIcon(data.Results[ri].Versions[vi].Fits, fmt.Sprintf("tipver-%d-%d", ri, vi))
			} // end of the version loop
		} // end of the model loop
		// The cloud section's icons.
		for ci := range data.CloudResults {
			// One cloud model.
			data.CloudResults[ci].Icon = modelIcon("cloud", fmt.Sprintf("tipcloud-%d", ci))
		} // end of the cloud loop
		// Copy buttons are offered only next to versions that fit.
		for _, res := range data.Results {
			// Look at each version.
			for _, v := range res.Versions {
				// Count the installed versions.
				if v.Installed {
					// One more.
					data.InstalledCount++
				} // end of the installed count
				// One that fits is enough.
				if v.Fits {
					// Show the buttons.
					data.ShowCopy = true
				} // end of the fit check
			} // end of the version loop
		} // end of the model loop
		// Build the page in memory first, so a template error gives a clean 500.
		var buf bytes.Buffer
		// Fill the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason.
			log.Printf("find LLM page error: %v", err)
			// A plain 500.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop.
			return
		} // end of the template check
		// A page with Copy buttons may run the monitor's own script file, and nothing else.
		if data.ShowCopy {
			// Replace the strict policy by the one that allows the script file.
			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
		} // end of the script policy
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// The status.
		w.WriteHeader(status)
		// Send the page.
		w.Write(buf.Bytes())
	} // end of render
	// show draws the choices with the defaults and the measured machine figures; it asks nothing from the internet.
	show := func(w http.ResponseWriter, r *http.Request) {
		// Read the machine.
		fm := readFindMachine(r.Context(), local)
		// The starting choices: chat and writing, small and medium models, no ability or memory filter.
		sel := findSelection{Chat: true, Abilities: map[string]bool{}, Sizes: map[string]bool{"small": true, "medium": true}, Contexts: map[string]bool{}, DiskGB: fm.DiskGB, MemGB: fm.MemGB}
		// Draw.
		render(w, r, sel, fm, nil, false, nil, nil, 0, 0, 0, 0, "", "", "", "", http.StatusOK)
	} // end of show
	// search reads the library and shows the models.
	search := func(w http.ResponseWriter, r *http.Request) {
		// Only the page's own form may start a search (it reads the internet).
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "forbidden", http.StatusForbidden)
			// Stop.
			return
		} // end of the token check
		// Read the machine again, for the notes.
		fm := readFindMachine(r.Context(), local)
		// The typed choices.
		sel, problems := parseFindForm(r.PostFormValue)
		// Typed wrongly: show the form again, read nothing.
		if len(problems) > 0 {
			// Draw with the problems.
			render(w, r, sel, fm, problems, false, nil, nil, 0, 0, 0, 0, "", "", "", "", http.StatusBadRequest)
			// Stop.
			return
		} // end of the problem check
		// Read the current list from the library.
		models, at, err := liveSiteList(r.Context(), time.Now)
		// Whether the list is a saved copy, and the note that says so.
		var copyNote string
		// It could not be read live: use the saved copy, clearly dated, or say why nothing is shown.
		if err != nil {
			// The saved copy of the last successful reading.
			saved, savedAt, cerr := loadLibraryCopy()
			// No usable copy: say why, show no data.
			if cerr != nil {
				// Draw with the reason.
				render(w, r, sel, fm, nil, true, nil, nil, 0, 0, 0, 0, "The Ollama library could not be read just now: "+err.Error()+". No saved copy of the list exists yet (one is saved after each successful search), so nothing is shown rather than something that may be out of date.", "", "", "", http.StatusOK)
				// Stop.
				return
			} // end of the copy check
			// Work with the copy.
			models, at = saved, savedAt
			// The note, with the reason and the date.
			copyNote = "ollama.com could not be reached just now (" + err.Error() + "). This is a saved copy of the library list from " + at.Format("2006-01-02 15:04:05 MST (UTC-07:00)") + ", so it may be out of date. The versions and sizes of each model cannot be checked now; open the official page of a model to see them."
		} else {
			// A live reading is kept for the next time ollama.com cannot be reached.
			saveLibraryCopy(models, at)
		} // end of the read check
		// Apply the choices the list can answer.
		cands, noSize, cloud := findCandidates(models, sel)
		// The first ones get their tags pages read.
		shown := cands
		// Cut the list.
		if len(shown) > maxFindResults {
			// Keep the most downloaded.
			shown = shown[:maxFindResults]
		} // end of the cut
		// What is installed here now, so installed versions can be marked; if Ollama cannot be read, nothing is marked and the page says so.
		inst, instErr := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// The marker for the versions (nil when the list could not be read).
		mark := installedMarker(inst, store, instErr == nil)
		// The results, filled side by side.
		results := make([]resultView, len(shown))
		// Wait for all of them.
		var wg sync.WaitGroup
		// At most findParallel at the same time.
		gate := make(chan struct{}, findParallel)
		// Start one read per model.
		for i := range shown {
			// One more to wait for.
			wg.Add(1)
			// Take a place.
			gate <- struct{}{}
			// Run it.
			go func(i int) {
				// Free the place and report done.
				defer func() { <-gate; wg.Done() }()
				// A saved copy means ollama.com is not reachable: do not wait for it again for every model.
				if copyNote != "" {
					// Never guess: the model is listed without versions.
					results[i] = buildResult(shown[i], nil, "ollama.com could not be reached", sel, mark)
					// Done.
					return
				} // end of the copy check
				// Read the tags page.
				tags, terr := fetchSiteTags(r.Context(), shown[i].Name)
				// A failure.
				if terr != nil {
					// Never guess: the model is listed without versions.
					results[i] = buildResult(shown[i], nil, terr.Error(), sel, mark)
					// Done.
					return
				} // end of the failure check
				// The model with its versions.
				results[i] = buildResult(shown[i], tags, "", sel, mark)
			}(i) // end of the goroutine
		} // end of the model loop
		// Wait.
		wg.Wait()
		// Models with a fitting version first (the order of popularity is kept inside each group).
		sort.SliceStable(results, func(i, j int) bool {
			// A model that fits somewhere comes first.
			return (results[i].FitCount > 0) && (results[j].FitCount == 0)
		}) // end of the sort
		// When the installed models could not be read, say so, because then no version is marked (not needed for a saved copy, which shows no versions).
		var instNote string
		// The reading failed while versions are shown.
		if instErr != nil && copyNote == "" {
			// The reason, in plain words.
			instNote = "The installed models could not be read just now (" + instErr.Error() + "), so installed versions are not marked."
		} // end of the note check
		// The cloud-only models get their own section: no versions are read for them, because nothing is downloaded.
		cloudModels, cloudSkipped := findCloudModels(models, sel)
		// How many are shown and how many are only counted.
		var cloudRes []resultView
		// The most downloaded ones.
		for i, m := range cloudModels {
			// Stop at the limit.
			if i >= maxFindCloud {
				// The rest are counted.
				break
			} // end of the limit check
			// One more.
			cloudRes = append(cloudRes, cloudView(m))
		} // end of the cloud loop
		// The ones not shown.
		cloudMore := len(cloudModels) - len(cloudRes)
		// Cloud-only models count as "left out" only when a size or memory class was ticked, which does not apply to them; otherwise they are shown below.
		cloudLeft := 0
		// A class was ticked.
		if cloudSkipped {
			// Say how many were left out.
			cloudLeft = cloud
		} // end of the class check
		// Draw the results, with the time the list was read and its zone.
		render(w, r, sel, fm, nil, true, results, cloudRes, cloudMore, len(cands), cloudLeft, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), copyNote, instNote, http.StatusOK)
	} // end of search
	// Hand back both.
	return show, search
} // end of findLLMHandlers

// findSummary writes the sentence above the results in correct singular and plural.
func findSummary(shown, total, cloud, noSize int, readAt string) string {
	// Nothing matched.
	if total == 0 {
		// Say so, with the same facts.
		return "No model matches your choices. Try ticking fewer of them. The library list was read on " + readAt + "." + findLeftOut(cloud, noSize)
	} // end of the empty case
	// How many are shown.
	which := "all are shown"
	// Fewer shown than matching.
	if shown < total {
		// Say how many.
		which = fmt.Sprintf("the %d most downloaded are shown", shown)
	} // end of the count check
	// The verb agrees with the number.
	verb := "match"
	// One model.
	if total == 1 {
		// Singular.
		verb = "matches"
	} // end of the verb choice
	// The sentence.
	return countText(total) + " " + verb + " your choices; " + which + ". The library list was read on " + readAt + "." + findLeftOut(cloud, noSize)
} // end of findSummary

// findLeftOut says what was left out of the list and why; empty when nothing was.
func findLeftOut(cloud, noSize int) string {
	// The text so far.
	s := ""
	// Cloud models.
	switch {
	// One.
	case cloud == 1:
		// Singular.
		s += " 1 cloud model (it runs on Ollama's servers, not on this computer) is not shown because you chose a size or a memory class, which does not apply to it."
	// Several.
	case cloud > 1:
		// Plural.
		s += fmt.Sprintf(" %d cloud models (they run on Ollama's servers, not on this computer) are not shown because you chose a size or a memory class, which does not apply to them.", cloud)
	} // end of the cloud switch
	// Models without a readable size.
	switch {
	// One.
	case noSize == 1:
		// Singular.
		s += " 1 model that shows no size was left out because you chose a size."
	// Several.
	case noSize > 1:
		// Plural.
		s += fmt.Sprintf(" %d models that show no size were left out because you chose a size.", noSize)
	} // end of the size switch
	// The text.
	return s
} // end of findLeftOut

// numberText writes a number for a text box: empty when not known.
func numberText(v float64) string {
	// Not known.
	if v < 0 {
		// Empty.
		return ""
	} // end of the unknown case
	// One decimal.
	return strconv.FormatFloat(v, 'f', 1, 64)
} // end of numberText
