// Package main tells Go that this test file belongs to the same program as findsite.go and findllm.go.
package main

import ( // import lists the standard-library packages this test file uses.
	// html turns character codes in the page back into characters.
	"html"
	// net/http gives the status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// reflect compares lists.
	"reflect"
	// strings searches the page text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// realListSample is the markup of the library list page as ollama.com wrote it on 2026-11-16 (read from the page on the test computer): the first entry is copied from the page (blank lines and the drawing of the icon shortened), the other two use the same structure with other names and labels. Only the structure matters here: if ollama.com changes it, the reader must notice.
const realListSample = `<ul role="list" class="grid grid-cols-1 gap-y-3">

    <li  class="flex items-baseline border-b border-neutral-200 py-6">
      <a href="/library/llama3.1" class="group w-full space-y-5">
        <div  title="llama3.1" class="flex flex-col">
          <h2 class="truncate text-xl font-medium underline-offset-2 md:text-2xl">
            <div class="flex space-x-2 items-center">
              <span class="group-hover:underline truncate">llama3.1</span>

            </div>
          </h2>
          <p class="max-w-lg break-words text-neutral-800 text-md">Llama 3.1 is a new state-of-the-art model from Meta available in 8B, 70B and 405B parameter sizes.</p>
        </div>
        <div class="flex flex-col space-y-2">
          <div class="flex flex-wrap space-x-2">

              <span  class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-600 sm:text-[13px]">tools</span>

              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">8b</span>

              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">70b</span>

              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">405b</span>

          </div>
          <p class="flex space-x-5 text-[13px] font-medium text-neutral-500">
              <span class="flex items-center">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="mr-1.5 h-[14px] w-[14px] sm:h-4 sm:w-4"><path d="M3 16.5v2.25"></path></svg>
                <span >121.2M</span>
                <span class="hidden sm:flex">&nbsp;Pulls</span>
              </span>
          </p>
        </div>
      </a>
    </li>
    <li  class="flex items-baseline border-b border-neutral-200 py-6">
      <a href="/library/decider" class="group w-full space-y-5">
        <div  title="decider" class="flex flex-col">
          <h2 class="truncate text-xl font-medium underline-offset-2 md:text-2xl">
            <div class="flex space-x-2 items-center">
              <span class="group-hover:underline truncate">decider</span>
            </div>
          </h2>
          <p class="max-w-lg break-words text-neutral-800 text-md">An invented decision model.</p>
        </div>
        <div class="flex flex-col space-y-2">
          <div class="flex flex-wrap space-x-2">
              <span  class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-600 sm:text-[13px]">decision</span>
              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">e4b</span>
          </div>
          <p class="flex space-x-5 text-[13px] font-medium text-neutral-500">
              <span class="flex items-center">
                <span >2.5M</span>
                <span class="hidden sm:flex">&nbsp;Pulls</span>
              </span>
          </p>
        </div>
      </a>
    </li>
    <li  class="flex items-baseline border-b border-neutral-200 py-6">
      <a href="/library/mixer" class="group w-full space-y-5">
        <div  title="mixer" class="flex flex-col">
          <h2 class="truncate text-xl font-medium underline-offset-2 md:text-2xl">
            <div class="flex space-x-2 items-center">
              <span class="group-hover:underline truncate">mixer</span>
            </div>
          </h2>
          <p class="max-w-lg break-words text-neutral-800 text-md">An invented mixture model.</p>
        </div>
        <div class="flex flex-col space-y-2">
          <div class="flex flex-wrap space-x-2">
              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">8x7b</span>
              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">128x17b</span>
          </div>
          <p class="flex space-x-5 text-[13px] font-medium text-neutral-500">
              <span class="flex items-center">
                <span >900K</span>
                <span class="hidden sm:flex">&nbsp;Pulls</span>
              </span>
          </p>
        </div>
      </a>
    </li>
</ul>`

// TestParseSiteListReadsTheRealMarkupSample checks the reader against the structure of the real page: names, abilities (including the new decision label), sizes (including mixtures such as 8x7b), download counts, and no unknown label.
func TestParseSiteListReadsTheRealMarkupSample(t *testing.T) {
	// Read the sample.
	got, err := parseSiteList(realListSample)
	// It must work.
	if err != nil {
		// Report.
		t.Fatalf("parseSiteList: %v", err)
	} // end of the error check
	// Three entries.
	if len(got) != 3 {
		// Report.
		t.Fatalf("got %d models, want 3", len(got))
	} // end of the count check
	// The first entry in full.
	want0 := siteModel{Name: "llama3.1", Description: "Llama 3.1 is a new state-of-the-art model from Meta available in 8B, 70B and 405B parameter sizes.", Abilities: []string{"tools"}, Sizes: []string{"8b", "70b", "405b"}, Pulls: "121.2M"}
	// Compare.
	if !reflect.DeepEqual(got[0], want0) {
		// Report.
		t.Errorf("first model = %+v, want %+v", got[0], want0)
	} // end of the first check
	// The decision model: decision is an ability, e4b a size, nothing is left over.
	if !reflect.DeepEqual(got[1].Abilities, []string{"decision"}) || !reflect.DeepEqual(got[1].Sizes, []string{"e4b"}) || len(got[1].Other) != 0 || got[1].Pulls != "2.5M" {
		// Report.
		t.Errorf("second model = %+v", got[1])
	} // end of the second check
	// The mixture model: both labels are sizes and nothing is left over.
	if !reflect.DeepEqual(got[2].Sizes, []string{"8x7b", "128x17b"}) || len(got[2].Other) != 0 || len(got[2].Abilities) != 0 {
		// Report.
		t.Errorf("third model = %+v", got[2])
	} // end of the third check
	// Every label is known, so there is nothing to report.
	if note := unknownLabelNote(got); note != "" {
		// Report.
		t.Errorf("unexpected unknown-label note: %s", note)
	} // end of the note check
} // end of TestParseSiteListReadsTheRealMarkupSample

// TestParamsBillionsReadsMixtures checks that a mixture size is the number of parts times the size of one part, and that half-written ones are refused.
func TestParamsBillionsReadsMixtures(t *testing.T) {
	// The cases: label, billions, class.
	for _, c := range []struct {
		// label is the page's size label.
		label string
		// want is the expected billions.
		want float64
		// class is the expected class key.
		class string
	}{{"8x7b", 56, "huge"}, {"16x17b", 272, "huge"}, {"128x17b", 2176, "huge"}, {"8x22b", 176, "huge"}, {"4x500m", 2, "small"}} {
		// Read the label.
		got, ok := paramsBillions(c.label)
		// It must be readable and equal.
		if !ok || got != c.want {
			// Report.
			t.Errorf("paramsBillions(%q) = %v, %v; want %v", c.label, got, ok, c.want)
		} // end of the value check
		// The class.
		if k := paramClassOf(got); k != c.class {
			// Report.
			t.Errorf("class of %q = %q, want %q", c.label, k, c.class)
		} // end of the class check
	} // end of the case loop
	// The page's size pattern accepts mixtures and plain sizes, and refuses words.
	for label, want := range map[string]bool{"8x7b": true, "128x17b": true, "e4b": true, "0.6b": true, "350m": true, "x8b": false, "8x": false, "latest": false, "decision": false} {
		// Compare.
		if sizeLabel.MatchString(label) != want {
			// Report.
			t.Errorf("sizeLabel(%q) = %v, want %v", label, !want, want)
		} // end of the compare
	} // end of the label loop
} // end of TestParamsBillionsReadsMixtures

// TestDecisionModelsAreNotChatModels checks that "Chat and writing" leaves out decision models and that the Decision tick finds them.
func TestDecisionModelsAreNotChatModels(t *testing.T) {
	// Chat and writing, with a decision model: not a chat model.
	if abilitiesMatch(findSelection{Chat: true}, map[string]bool{"decision": true}) {
		// Report.
		t.Error("a decision model passed Chat and writing")
	} // end of the chat check
	// Chat and writing, with a plain model: a chat model.
	if !abilitiesMatch(findSelection{Chat: true}, map[string]bool{"tools": true}) {
		// Report.
		t.Error("a plain model failed Chat and writing")
	} // end of the plain check
	// The Decision tick finds a decision model and not a plain one.
	sel := findSelection{Abilities: map[string]bool{"decision": true}}
	// The decision model.
	if !abilitiesMatch(sel, map[string]bool{"decision": true}) || abilitiesMatch(sel, map[string]bool{"tools": true}) {
		// Report.
		t.Error("the Decision tick did not separate decision models from the others")
	} // end of the tick check
	// The tick is one of the ability keys, so the form reads it.
	found := false
	// Look for it.
	for _, k := range abilityKeys {
		// The same key.
		if k == "decision" {
			// Found.
			found = true
		} // end of the key check
	} // end of the key loop
	// It must be there.
	if !found {
		// Report.
		t.Error("decision is not an ability key")
	} // end of the found check
} // end of TestDecisionModelsAreNotChatModels

// TestUnknownLabelNote checks the notice for labels this program does not know.
func TestUnknownLabelNote(t *testing.T) {
	// Nothing unknown: no notice.
	if n := unknownLabelNote([]siteModel{{Name: "a"}, {Name: "b", Abilities: []string{"tools"}}}); n != "" {
		// Report.
		t.Errorf("note for known labels: %q", n)
	} // end of the empty check
	// Two unknown labels on three models.
	n := unknownLabelNote([]siteModel{{Name: "a", Other: []string{"preview"}}, {Name: "b", Other: []string{"preview", "alpha-x"}}, {Name: "c"}})
	// Both labels with their numbers, in sorted order.
	if !strings.Contains(n, "alpha-x (1), preview (2)") || !strings.Contains(n, "does not know yet") {
		// Report.
		t.Errorf("note = %q", n)
	} // end of the note check
} // end of TestUnknownLabelNote

// TestFindPageHasTheDecisionTick checks that the starting page offers the Decision tick with its help text.
func TestFindPageHasTheDecisionTick(t *testing.T) {
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
	// The rig.
	rig := newThemeRig(t)
	// Ask for the page.
	status, _, body := get(t, rig.h, http.MethodGet, "/findllm")
	// It must be there.
	if status != http.StatusOK {
		// Report.
		t.Fatalf("status %d", status)
	} // end of the status check
	// The tick and the help text.
	for _, want := range []string{`name="ab_decision"`, "Decision models (classify, score, yes or no)", "Needs Ollama 0.35.0 or newer."} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the page lacks %q", want)
		} // end of the look
	} // end of the loop
} // end of TestFindPageHasTheDecisionTick

// TestFindSearchHandlesDecisionMixturesAndUnknownLabels runs whole searches against a fake library: Chat and writing leaves out the decision model, the Decision tick finds it, a mixture model counts in the Very large class, and an unknown label is reported.
func TestFindSearchHandlesDecisionMixturesAndUnknownLabels(t *testing.T) {
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
	// Start with an empty saved list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake library: a chat model, a decision model, a mixture model and a model with an unknown label.
	list := listEntry("alpha", "An invented chat model.", "tools", "1b") + listEntry("decider", "An invented decision model.", "decision", "1b") + listEntry("mixer", "An invented mixture model.", "8x7b") + listEntry("newbie", "Has a label nobody knows.", "zzz-new", "1b")
	// The pages.
	hits := fakeSite(t, map[string]string{
		"/library":              "<html><ul>" + list + "</ul></html>",
		"/library/alpha/tags":   tagEntry("alpha:1b", "700MB", "8K"),
		"/library/decider/tags": tagEntry("decider:1b", "700MB", "8K"),
		"/library/mixer/tags":   tagEntry("mixer:8x7b", "26GB", "32K"),
		"/library/newbie/tags":  tagEntry("newbie:1b", "700MB", "8K"),
	})
	// The rig.
	rig := newThemeRig(t)
	// Chat and writing, plenty of disk and memory.
	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"1000"}, "mem_gb": {"1000"}})
	// It must work.
	if status != http.StatusOK {
		// Report.
		t.Fatalf("status %d: %s", status, body)
	} // end of the status check
	// The chat model and the mixture model are listed, the decision model is not, and the unknown label is reported.
	if !strings.Contains(body, ">alpha<") || !strings.Contains(body, ">mixer<") || strings.Contains(body, ">decider<") || !strings.Contains(html.UnescapeString(body), "does not know yet: zzz-new (1)") {
		// Report.
		t.Errorf("chat search: unexpected page: %s", body)
	} // end of the chat check
	// The Decision tick alone finds the decision model.
	_, body = postFind(t, rig, url.Values{"token": {rig.token}, "ab_decision": {"on"}, "disk_gb": {"1000"}, "mem_gb": {"1000"}})
	// Only the decision model is listed.
	if !strings.Contains(body, ">decider<") || strings.Contains(body, ">alpha<") || !strings.Contains(body, "Abilities: decision") {
		// Report.
		t.Errorf("decision search: unexpected page: %s", body)
	} // end of the decision check
	// The Very large class finds the mixture model by its size, not as "no size".
	_, body = postFind(t, rig, url.Values{"token": {rig.token}, "sz_huge": {"on"}, "disk_gb": {"1000"}, "mem_gb": {"1000"}})
	// The mixture model is listed.
	if !strings.Contains(body, ">mixer<") || strings.Contains(body, ">alpha<") {
		// Report.
		t.Errorf("size search: unexpected page: %s", body)
	} // end of the size check
	// The library was asked at least once.
	if *hits == 0 {
		// Report.
		t.Error("the fake library was never asked")
	} // end of the hits check
} // end of TestFindSearchHandlesDecisionMixturesAndUnknownLabels

// TestOllamaNeededReadsTheSentence checks the reader of the sentence "requires Ollama X or later" on a model page.
func TestOllamaNeededReadsTheSentence(t *testing.T) {
	// The cases: page text, expected version, whether a version is expected.
	for _, c := range []struct {
		// name describes the case.
		name string
		// text is the visible text of the page.
		text string
		// want is the expected version.
		want string
		// ok is whether a version is expected at all.
		ok bool
	}{
		// The wording of the real Clef page: the first sentence counts, the cloud sentence does not.
		{"clef", "Clef requires Ollama 0.35.1 or later. To use Clef in Ollama's cloud, use Ollama 0.40.6 or later.", "0.35.1", true},
		// A leading v and the word newer.
		{"v and newer", "This model requires Ollama v0.12.3 or newer to run.", "0.12.3", true},
		// Two numbers become three.
		{"two numbers", "It requires Ollama 0.35 or later.", "0.35.0", true},
		// The Python library is not Ollama.
		{"python library", "Use the Ollama Python library, version 0.6.3 or later:", "", false},
		// A page that says nothing.
		{"nothing", "nimble:latest 9.3GB 256K context window", "", false},
	} {
		// Read it.
		got, ok := ollamaNeeded(c.text)
		// Compare.
		if got != c.want || ok != c.ok {
			// Report.
			t.Errorf("%s: got %q, %v; want %q, %v", c.name, got, ok, c.want, c.ok)
		} // end of the compare
	} // end of the case loop
} // end of TestOllamaNeededReadsTheSentence

// TestApplyOllamaNeed checks the three judgements: older, new enough, and not readable.
func TestApplyOllamaNeed(t *testing.T) {
	// Older: a warning state with the running version in the sentence.
	var r resultView
	// Judge it.
	applyOllamaNeed(&r, "0.35.1", checkResult{Online: true, Version: "0.34.4"})
	// Check.
	if r.OllamaState != "old" || !strings.Contains(r.OllamaNote, "Needs Ollama 0.35.1 or newer") || !strings.Contains(r.OllamaNote, "Your Ollama is 0.34.4") {
		// Report.
		t.Errorf("old: %q %q", r.OllamaState, r.OllamaNote)
	} // end of the old check
	// New enough (a larger minor number is higher: 0.100.0 is newer than 0.35.1).
	r = resultView{}
	// Judge it.
	applyOllamaNeed(&r, "0.35.1", checkResult{Online: true, Version: "0.100.0"})
	// Check.
	if r.OllamaState != "ok" || !strings.Contains(r.OllamaNote, "is new enough") {
		// Report.
		t.Errorf("ok: %q %q", r.OllamaState, r.OllamaNote)
	} // end of the ok check
	// Ollama not reachable: nothing can be compared, and the sentence says so.
	r = resultView{}
	// Judge it.
	applyOllamaNeed(&r, "0.35.1", checkResult{})
	// Check.
	if r.OllamaState != "unknown" || !strings.Contains(r.OllamaNote, "could not read the version") {
		// Report.
		t.Errorf("unknown: %q %q", r.OllamaState, r.OllamaNote)
	} // end of the unknown check
} // end of TestApplyOllamaNeed

// TestSizeRowsCompareThePlainSizes checks the size table: plain size tags only, latest dropped when it is another row, smallest download first, and no table for fewer than two rows.
func TestSizeRowsCompareThePlainSizes(t *testing.T) {
	// The versions of an invented model, in the page's order.
	vs := []versionView{
		{Tag: "m:latest", sizeBytes: 4_900_000_000, Size: "4.9GB"},
		{Tag: "m:405b", sizeBytes: 243_000_000_000, Size: "243GB"},
		{Tag: "m:8b", sizeBytes: 4_900_000_000, Size: "4.9GB"},
		{Tag: "m:70b", sizeBytes: 43_000_000_000, Size: "43GB"},
		{Tag: "m:8b-instruct-q2_K", sizeBytes: 3_200_000_000, Size: "3.2GB"},
	}
	// Build the rows.
	rows := sizeRows(vs)
	// The tags in order.
	var tags []string
	// Collect them.
	for _, v := range rows {
		// One tag.
		tags = append(tags, v.Tag)
	} // end of the loop
	// Smallest first, latest and the quantized version left out.
	if !reflect.DeepEqual(tags, []string{"m:8b", "m:70b", "m:405b"}) {
		// Report.
		t.Errorf("rows = %v", tags)
	} // end of the check
	// One plain size is not a comparison.
	if got := sizeRows([]versionView{{Tag: "m:latest", sizeBytes: 1}, {Tag: "m:q4", sizeBytes: 2}}); got != nil {
		// Report.
		t.Errorf("a single row gave a table: %v", got)
	} // end of the single check
	// A latest that is the only version of its size stays, so two sizes still compare.
	if got := sizeRows([]versionView{{Tag: "m:latest", sizeBytes: 1}, {Tag: "m:8b", sizeBytes: 2}}); len(got) != 2 {
		// Report.
		t.Errorf("latest of its own size was dropped: %v", got)
	} // end of the latest check
} // end of TestSizeRowsCompareThePlainSizes

// TestQualifyReasonsNamesTheChoicesMatched checks the "Matched your choices" list.
func TestQualifyReasonsNamesTheChoicesMatched(t *testing.T) {
	// A model with tools and two sizes, and a code name.
	m := siteModel{Name: "starcoder-x", Description: "A code generation model.", Abilities: []string{"tools"}, Sizes: []string{"3b", "15b"}}
	// Chat, tools, the code field, the medium size class.
	sel := findSelection{Chat: true, Abilities: map[string]bool{"tools": true, "vision": true}, Domains: map[string]bool{"code": true}, Sizes: map[string]bool{"medium": true}, Contexts: map[string]bool{}}
	// The reasons.
	got := qualifyReasons(m, sel)
	// Vision is ticked but the model lacks it, so it is not listed; with the Medium class ticked neither 3b (small) nor 15b (large) counts.
	want := []string{"Chat and writing", "Uses tools", "Field of use: Code and software"}
	// Compare.
	if !reflect.DeepEqual(got, want) {
		// Report.
		t.Errorf("reasons = %v, want %v", got, want)
	} // end of the compare
	// Tick the small class too: 3b qualifies.
	sel.Sizes = map[string]bool{"small": true}
	// The reasons again.
	got = qualifyReasons(m, sel)
	// The size line is there.
	if got[len(got)-1] != "Size 3b (Small)" {
		// Report.
		t.Errorf("reasons = %v", got)
	} // end of the size check
	// Nothing ticked: nothing to say.
	if got := qualifyReasons(m, findSelection{}); len(got) != 0 {
		// Report.
		t.Errorf("reasons without choices = %v", got)
	} // end of the empty check
} // end of TestQualifyReasonsNamesTheChoicesMatched

// TestFindSearchShowsReasonsVersionFlagAndSizeTable runs a whole search against a fake library: the "Matched your choices" line, the warning for a model that needs a newer Ollama than the fake one (0.34.4) with the update help, the calm note for one that does not, and the size table.
func TestFindSearchShowsReasonsVersionFlagAndSizeTable(t *testing.T) {
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
	// Start with an empty saved list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// Two models with tools and two sizes each.
	list := listEntry("newer", "Needs a newer Ollama.", "tools", "1b", "8b") + listEntry("older", "Runs on an older Ollama.", "tools", "1b", "8b")
	// The pages: the model pages carry the sentence in some markup.
	fakeSite(t, map[string]string{
		"/library":            "<html><ul>" + list + "</ul></html>",
		"/library/newer":      "<html><body><div><p>Newer <b>requires</b> Ollama 9.9.9 or later.</p></div></body></html>",
		"/library/older":      "<html><body><p>Older requires Ollama 0.30.0 or later.</p></body></html>",
		"/library/newer/tags": tagEntry("newer:1b", "700MB", "8K") + tagEntry("newer:8b", "5GB", "32K") + tagEntry("newer:latest", "5GB", "32K"),
		"/library/older/tags": tagEntry("older:1b", "700MB", "8K") + tagEntry("older:8b", "5GB", "32K"),
	})
	// The rig (its fake Ollama reports version 0.34.4).
	rig := newThemeRig(t)
	// Tools ticked, plenty of disk and memory.
	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_tools": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// It must work.
	if status != http.StatusOK {
		// Report.
		t.Fatalf("status %d: %s", status, body)
	} // end of the status check
	// The page text with the character codes turned back into characters.
	text := html.UnescapeString(body)
	// Each expected piece of the page.
	for _, want := range []string{
		// The reasons.
		"Matched your choices:</strong> Uses tools", "A version fits 100.0 GB free disk and 64.0 GB memory",
		// The warning for the model that needs a newer Ollama, with the update help.
		"Needs Ollama 9.9.9 or newer", "Your Ollama is 0.34.4", "How to update Ollama", "docker pull ollama/ollama",
		// The calm note for the other model.
		"Needs Ollama 0.30.0 or newer (the model page says so); yours (0.34.4) is new enough.",
		// The size table, with the rows in size order.
		"Compare sizes (2 versions)",
		// The model that needs a newer Ollama gets the warning symbol and the changed wording, in the list and in the size table.
		"stateicon state-warn", "Fits, after you update Ollama:", "fits (update Ollama first)",
		// The other model keeps the normal wording and the check mark.
		"<strong>Fits:</strong>", "stateicon state-fits",
	} {
		// Look for it.
		if !strings.Contains(text, want) {
			// Report.
			t.Errorf("the results lack %q", want)
		} // end of the look
	} // end of the loop
	// The warning wording is only on the model that needs a newer Ollama: its listed versions (1b, 8b and latest give up to three) all carry it, and the normal model has none.
	if n := strings.Count(text, "Fits, after you update Ollama:"); n < 1 || n > 3 {
		// Report.
		t.Errorf("the warning wording appears %d times, want 1 to 3", n)
	} // end of the warning count
	// The update help is shown once: only the model that needs a newer Ollama has it.
	if n := strings.Count(text, "How to update Ollama"); n != 1 {
		// Report.
		t.Errorf("the update help appears %d times, want 1", n)
	} // end of the count check
} // end of TestFindSearchShowsReasonsVersionFlagAndSizeTable
