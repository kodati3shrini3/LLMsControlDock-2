// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context lets a request be cancelled when the browser goes away.
	"context"
	// errors makes the named errors the pages can show.
	"errors"
	// fmt builds the error texts.
	"fmt"
	// html turns entities such as &amp; back into plain characters.
	"html"
	// io reads a limited part of the reply.
	"io"
	// net/http sends the read-only requests to the public library website.
	"net/http"
	// regexp finds the parts of the page.
	"regexp"
	// strconv turns the number text of a download size into a number.
	"strconv"
	// strings splits and trims text.
	"strings"
	// sync keeps the saved answer safe when two pages ask at once.
	"sync"
	// time limits how long a request may take and says how old the saved answer is.
	"time"
) // end of imports

// ollamaSite is the address of the public Ollama website; a variable so tests can point it at a fake and never touch the real network.
var ollamaSite = "https://ollama.com"

// findTimeout is how long one request to the website may take; a slow or missing connection must not freeze the page.
const findTimeout = 10 * time.Second

// findMaxPage is the biggest page that is read; the real list page is about 1 MB and the biggest tags page under 1 MB.
const findMaxPage = 4 << 20

// findCacheTTL is how long the last answer of the list page is reused, so repeated clicks do not ask the website again and again.
const findCacheTTL = time.Hour

// errLayout is returned when a page does not look the way the reader expects (the website may have changed); nothing is guessed then.
var errLayout = errors.New("the page does not look as expected, so nothing was read from it")

// siteModel is one model as the library list page shows it.
type siteModel struct {
	// Name is the library name, for example "qwen3".
	Name string
	// Description is the one-line description from the page.
	Description string
	// Abilities are the ability labels the page shows: tools, vision, thinking, embedding, audio.
	Abilities []string
	// Sizes are the size labels the page shows, for example "0.6b" or "350m".
	Sizes []string
	// Cloud is true when the page marks the model as cloud: it runs on Ollama's servers, not on this computer.
	Cloud bool
	// Other holds any label the reader does not know; shown as it is, never interpreted.
	Other []string
	// Pulls is the download count as the page writes it, for example "120.9M".
	Pulls string
} // end of siteModel

// siteTag is one downloadable version of a model as its tags page shows it.
type siteTag struct {
	// Tag is the full name to download, for example "granite4:1b-h".
	Tag string
	// SizeText is the download size as the page writes it, for example "1.6GB".
	SizeText string
	// SizeBytes is that size in bytes (decimal units, as the page's own numbers are rounded); 0 when the page showed none.
	SizeBytes int64
	// Context is the context length as the page writes it, for example "128K"; empty when not shown.
	Context string
	// Input is what the version accepts, as the page writes it, for example "Text input"; empty when not shown.
	Input string
	// Age is how long ago the version was updated, as the page writes it (for example "1 year ago"); empty when not shown. The page gives no exact date.
	Age string
	// AgeHours is that age in hours, rounded the way the words are (a month counts as 730 hours, a year as 8760); -1 when no age was shown, so it sorts last.
	AgeHours int64
} // end of siteTag

// listSplit cuts the list page at the start of every model entry.
var listSplit = regexp.MustCompile(`<li\s+class="flex items-baseline`)

// entryName finds the library name inside one entry.
var entryName = regexp.MustCompile(`href="/library/([A-Za-z0-9._-]+)"`)

// entryDesc finds the one-line description inside one entry.
var entryDesc = regexp.MustCompile(`(?s)<p class="max-w-lg[^>]*>(.*?)</p>`)

// entryBadge finds every label (ability or size) inside one entry.
var entryBadge = regexp.MustCompile(`<span\s+class="inline-flex[^"]*"[^>]*>([^<]+)</span>`)

// entryPulls finds the download count inside one entry.
var entryPulls = regexp.MustCompile(`<span >([^<]+)</span>\s*<span class="hidden sm:flex">&nbsp;Pulls`)

// sizeLabel recognises a size label such as 0.6b, 350m, 8b or e4b.
var sizeLabel = regexp.MustCompile(`^e?[0-9]+(\.[0-9]+)?[mb]$`)

// knownAbility is the set of ability labels the reader understands.
var knownAbility = map[string]bool{"tools": true, "vision": true, "thinking": true, "embedding": true, "audio": true}

// parseSiteList reads the library list page; it returns errLayout when no entry can be read, and an entry without a name is an error too, so a changed page is noticed instead of half-read.
func parseSiteList(page string) ([]siteModel, error) {
	// Cut the page into entries; the first piece is everything before the first entry.
	pieces := listSplit.Split(page, -1)
	// No entry at all means the page is not the list page.
	if len(pieces) < 2 {
		// Say so.
		return nil, errLayout
	} // end of the entry check
	// The result.
	var out []siteModel
	// Read each entry.
	for _, p := range pieces[1:] {
		// The name is required.
		nm := entryName.FindStringSubmatch(p)
		// No name: the layout is not what we expect.
		if nm == nil {
			// Stop, rather than return half the list.
			return nil, errLayout
		} // end of the name check
		// Start the model.
		m := siteModel{Name: nm[1]}
		// The description is optional.
		if d := entryDesc.FindStringSubmatch(p); d != nil {
			// Plain text without entities and extra spaces.
			m.Description = strings.Join(strings.Fields(html.UnescapeString(d[1])), " ")
		} // end of the description
		// The labels.
		for _, b := range entryBadge.FindAllStringSubmatch(p, -1) {
			// The label text.
			label := strings.TrimSpace(html.UnescapeString(b[1]))
			// Decide what kind of label it is.
			switch {
			// A cloud model.
			case label == "cloud":
				// Mark it.
				m.Cloud = true
			// A known ability.
			case knownAbility[label]:
				// Keep it.
				m.Abilities = append(m.Abilities, label)
			// A size.
			case sizeLabel.MatchString(label):
				// Keep it.
				m.Sizes = append(m.Sizes, label)
			// Anything else is kept as it is.
			default:
				// Keep it.
				m.Other = append(m.Other, label)
			} // end of the label switch
		} // end of the label loop
		// The download count is optional.
		if pl := entryPulls.FindStringSubmatch(p); pl != nil {
			// As written.
			m.Pulls = strings.TrimSpace(pl[1])
		} // end of the pulls
		// Add the model.
		out = append(out, m)
	} // end of the entry loop
	// The finished list.
	return out, nil
} // end of parseSiteList

// tagBlock finds the compact block the tags page writes for every version.
var tagBlock = regexp.MustCompile(`(?s)<a href="/library/([A-Za-z0-9._:-]+)" class="md:hidden[^>]*>(.*?)</a>`)

// htmlTag finds any HTML tag, to strip it from a block.
var htmlTag = regexp.MustCompile(`<[^>]+>`)

// tagSize finds a download size such as 708MB or 3.3GB.
var tagSize = regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?)\s*(KB|MB|GB|TB)`)

// tagContext finds a context length such as 128K or 1M.
var tagContext = regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?[KM]?) context window`)

// tagAge finds the update age such as "1 year ago", "3 weeks ago" or "an hour ago".
var tagAge = regexp.MustCompile(`\b(\d+|an?) (second|minute|hour|day|week|month|year)s? ago\b`)

// ageHours turns the words of an age into hours, rounded the way the words are; unreadable words give -1.
func ageHours(count, unit string) int64 {
	// "a" and "an" mean one.
	n := int64(1)
	// A written number.
	if count != "a" && count != "an" {
		// Read it; a failure means unreadable.
		v, err := strconv.ParseInt(count, 10, 64)
		// Unreadable.
		if err != nil {
			// Not known.
			return -1
		} // end of the read check
		// Use it.
		n = v
	} // end of the number check
	// Hours in one unit.
	per := map[string]int64{"second": 0, "minute": 0, "hour": 1, "day": 24, "week": 168, "month": 730, "year": 8760}
	// The unit must be known.
	h, ok := per[unit]
	// Unknown unit.
	if !ok {
		// Not known.
		return -1
	} // end of the unit check
	// The age in hours.
	return n * h
} // end of ageHours

// tagInput finds the input kinds such as "Text input" or "Text, Image input".
var tagInput = regexp.MustCompile(`((?:Text|Image|Audio|Video)(?:, (?:Text|Image|Audio|Video))* input)`)

// sizeBytes turns a number and a unit into bytes (decimal units); an unknown unit gives 0.
func sizeBytes(number, unit string) int64 {
	// Read the number.
	f, err := strconv.ParseFloat(number, 64)
	// An unreadable number gives 0.
	if err != nil {
		// Nothing known.
		return 0
	} // end of the number check
	// The multiplier for the unit.
	var mult float64
	// Choose by unit.
	switch unit {
	// Kilobytes.
	case "KB":
		// One thousand.
		mult = 1e3
	// Megabytes.
	case "MB":
		// One million.
		mult = 1e6
	// Gigabytes.
	case "GB":
		// One billion.
		mult = 1e9
	// Terabytes.
	case "TB":
		// One trillion.
		mult = 1e12
	// Anything else.
	default:
		// Nothing known.
		return 0
	} // end of the unit switch
	// Round to a whole byte.
	return int64(f*mult + 0.5)
} // end of sizeBytes

// parseSiteTags reads a tags page; it returns errLayout when no version can be read.
func parseSiteTags(page string) ([]siteTag, error) {
	// Every compact block.
	blocks := tagBlock.FindAllStringSubmatch(page, -1)
	// None: not a tags page.
	if len(blocks) == 0 {
		// Say so.
		return nil, errLayout
	} // end of the block check
	// The result, and the names already seen (a version may be written twice).
	var out []siteTag
	// The seen set.
	seen := map[string]bool{}
	// Read each block.
	for _, b := range blocks {
		// The full tag name.
		name := b[1]
		// Skip a repeat.
		if seen[name] {
			// Already read.
			continue
		} // end of the repeat check
		// Remember it.
		seen[name] = true
		// The block as plain text on one line.
		text := strings.Join(strings.Fields(html.UnescapeString(htmlTag.ReplaceAllString(b[2], " "))), " ")
		// Start the version.
		t := siteTag{Tag: name}
		// The download size.
		if s := tagSize.FindStringSubmatch(text); s != nil {
			// As written.
			t.SizeText = s[1] + s[2]
			// In bytes.
			t.SizeBytes = sizeBytes(s[1], s[2])
		} // end of the size
		// The context length.
		if c := tagContext.FindStringSubmatch(text); c != nil {
			// As written.
			t.Context = c[1]
		} // end of the context
		// The input kinds.
		if in := tagInput.FindStringSubmatch(text); in != nil {
			// As written.
			t.Input = in[1]
		} // end of the input
		// The update age, with no age as -1.
		t.AgeHours = -1
		// The age words.
		if a := tagAge.FindStringSubmatch(text); a != nil {
			// As written.
			t.Age = a[0]
			// In hours.
			t.AgeHours = ageHours(a[1], a[2])
		} // end of the age
		// Add the version.
		out = append(out, t)
	} // end of the block loop
	// The finished list.
	return out, nil
} // end of parseSiteTags

// fetchSitePage reads one page of the public website, read-only; only the address leaves this computer, and nothing about the person or their selections.
func fetchSitePage(ctx context.Context, path string) (string, error) {
	// A request that stops with the caller's context or after the timeout.
	ctx, cancel := context.WithTimeout(ctx, findTimeout)
	// Release the timer at the end.
	defer cancel()
	// Create the request.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ollamaSite+path, nil)
	// A failure here means the address could not be built.
	if err != nil {
		// Report it.
		return "", err
	} // end of the request check
	// Say who is asking, and nothing else.
	req.Header.Set("User-Agent", "LLMsControlDock")
	// Send it.
	resp, err := http.DefaultClient.Do(req)
	// No answer: no internet, or the website is down.
	if err != nil {
		// Report it.
		return "", err
	} // end of the send check
	// Close the reply at the end.
	defer resp.Body.Close()
	// Anything but a normal answer is a failure.
	if resp.StatusCode != http.StatusOK {
		// Report the status.
		return "", fmt.Errorf("the website answered %d", resp.StatusCode)
	} // end of the status check
	// Read the page, but never more than the limit.
	data, err := io.ReadAll(io.LimitReader(resp.Body, findMaxPage+1))
	// A broken reply.
	if err != nil {
		// Report it.
		return "", err
	} // end of the read check
	// An oversized reply is not read at all.
	if len(data) > findMaxPage {
		// Report it.
		return "", errors.New("the page is larger than expected, so it was not read")
	} // end of the size check
	// The page text.
	return string(data), nil
} // end of fetchSitePage

// fetchSiteTags reads the tags page of one library model; the name must be plain, so nothing odd is ever put into an address.
func fetchSiteTags(ctx context.Context, model string) ([]siteTag, error) {
	// Only plain names are asked for.
	if !namePart.MatchString(model) {
		// Never build an address from it.
		return nil, errors.New("not a plain model name")
	} // end of the name check
	// Read the page.
	page, err := fetchSitePage(ctx, "/library/"+model+"/tags")
	// A failure.
	if err != nil {
		// Report it.
		return nil, err
	} // end of the fetch check
	// Read the versions.
	return parseSiteTags(page)
} // end of fetchSiteTags

// listCache keeps the last answer of the list page for a while.
type listCache struct {
	// mu keeps two pages from changing it at the same time.
	mu sync.Mutex
	// at is when the answer was read.
	at time.Time
	// models is the answer.
	models []siteModel
} // end of listCache

// theListCache is the one saved answer of the program.
var theListCache listCache

// liveSiteList returns the current library list: the saved answer if it is younger than an hour, otherwise a fresh read; it also says when the answer was read.
func liveSiteList(ctx context.Context, now func() time.Time) ([]siteModel, time.Time, error) {
	// Only one caller at a time.
	theListCache.mu.Lock()
	// Let go at the end.
	defer theListCache.mu.Unlock()
	// A young enough saved answer is reused.
	if theListCache.models != nil && now().Sub(theListCache.at) < findCacheTTL {
		// Return it with its real age.
		return theListCache.models, theListCache.at, nil
	} // end of the cache check
	// Read the page.
	page, err := fetchSitePage(ctx, "/library")
	// A failure keeps the older answer untouched.
	if err != nil {
		// Report it.
		return nil, time.Time{}, err
	} // end of the fetch check
	// Read the models.
	models, err := parseSiteList(page)
	// A page that does not look right keeps the older answer untouched.
	if err != nil {
		// Report it.
		return nil, time.Time{}, err
	} // end of the parse check
	// Keep the answer and its time.
	theListCache.models, theListCache.at = models, now()
	// Hand it back.
	return models, theListCache.at, nil
} // end of liveSiteList
