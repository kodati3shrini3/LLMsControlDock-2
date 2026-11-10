// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages the tests use.
	// net/url builds the form values.
	"net/url"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestAgeWordsAreRead checks the update age on a tags page: the words as written and their value in hours, for several units and for "an hour ago"; a block without an age gives -1.
func TestAgeWordsAreRead(t *testing.T) {
	// One block per age, in the page's own structure.
	block := func(tag, age string) string {
		// The same compact block as the real page, with the age words at the end.
		return "<a href=\"/library/" + tag + "\" class=\"md:hidden flex flex-col\">\n<span>" + tag + "</span> • 1.0GB • 8K context window • Text input • " + age + "\n</a>\n"
	} // end of block
	// The page: three ages and one block with none.
	page := block("m:a", "3 weeks ago") + block("m:b", "an hour ago") + block("m:c", "1 year ago") + block("m:d", "")
	// Read it.
	tags, err := parseSiteTags(page)
	// It must work.
	if err != nil || len(tags) != 4 {
		// Stop.
		t.Fatalf("parse: %v, %d tags", err, len(tags))
	} // end of the check
	// What each must give.
	want := []struct {
		age   string
		hours int64
	}{{"3 weeks ago", 504}, {"an hour ago", 1}, {"1 year ago", 8760}, {"", -1}}
	// Compare each.
	for i, w := range want {
		// The words and the hours.
		if tags[i].Age != w.age || tags[i].AgeHours != w.hours {
			// Report.
			t.Errorf("tag %d: %q %d, want %q %d", i, tags[i].Age, tags[i].AgeHours, w.age, w.hours)
		} // end of the check
	} // end of the loop
} // end of TestAgeWordsAreRead

// TestVersionsAreSortedByAgeThenSize checks the order of versions: the newest first, then the smaller download; no age or size comes last; equal versions keep the page's order.
func TestVersionsAreSortedByAgeThenSize(t *testing.T) {
	// The tags of one model, in a mixed order.
	tags := []siteTag{
		{Tag: "m:old-small", SizeBytes: 100, AgeHours: 8760},
		{Tag: "m:new-big", SizeBytes: 900, AgeHours: 24},
		{Tag: "m:new-small", SizeBytes: 300, AgeHours: 24},
		{Tag: "m:noage", SizeBytes: 50, AgeHours: -1},
		{Tag: "m:old-nosize", SizeBytes: 0, AgeHours: 8760},
		{Tag: "m:old-small-twin", SizeBytes: 100, AgeHours: 8760},
	}
	// Build the view; no limits are set, so every version fits.
	r := buildResult(siteModel{Name: "m"}, tags, "", findSelection{DiskGB: -1, MemGB: -1}, nil)
	// The tags in the order shown.
	var got []string
	// Each version.
	for _, v := range r.Versions {
		// One tag.
		got = append(got, v.Tag)
	} // end of the loop
	// The expected order.
	want := "m:new-small,m:new-big,m:old-small,m:old-small-twin,m:old-nosize,m:noage"
	// Compare.
	if strings.Join(got, ",") != want {
		// Report.
		t.Errorf("order %q, want %q", strings.Join(got, ","), want)
	} // end of the check
} // end of TestVersionsAreSortedByAgeThenSize

// TestFindPageShowsTheUpdateAge checks that a result page shows "updated 1 year ago" next to a version and explains the ages once.
func TestFindPageShowsTheUpdateAge(t *testing.T) {
	// The saved library list goes to a throw-away folder.
	isolateFindData(t)
	// Start with an empty saved list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake library.
	fakeSite(t, findTestPages())
	// The rig.
	rig := newThemeRig(t)
	// A search.
	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// The age is shown, and the note appears exactly once.
	if !strings.Contains(body, "updated 1 year ago") || strings.Count(body, "not an exact date") != 1 {
		// Report.
		t.Error("the results lack the update age or its note")
	} // end of the check
} // end of TestFindPageShowsTheUpdateAge
