// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context carries the time limit of each request.
	"context"
	// errors tells a time-out from other failures.
	"errors"
	// fmt prints the report.
	"fmt"
	// io is the writer type the report goes to.
	"io"
	// net/http makes the requests.
	"net/http"
	// net/url holds the error type that wraps the network reason.
	"net/url"
	// strings builds the report lines.
	"strings"
	// time sets the limit of each request.
	"time"
) // end of imports

// linkTimeout is how long one address may take to answer before it counts as a failure.
const linkTimeout = 20 * time.Second

// linkResult is what happened when one reference address was opened.
type linkResult struct {
	// N is the number of the reference, as the comparison page shows it.
	N int
	// URL is the address that was asked for.
	URL string
	// Status is the HTTP status code of the final answer, or 0 when there was none.
	Status int
	// Final is the address the answer came from, which differs from URL after a redirect.
	Final string
	// Problem is the plain reason when there was no answer at all (empty when there was one).
	Problem string
} // end of linkResult

// ok says whether the address answered with a success code (200 to 299).
func (r linkResult) ok() bool {
	// Only a real answer in the success range counts.
	return r.Status >= 200 && r.Status <= 299
} // end of ok

// newLinkClient makes the client of this command: a time limit per request and at most 5 redirects.
func newLinkClient() *http.Client {
	// The client; the program talks to the internet only here, and only when the person typed -check-links.
	return &http.Client{
		// The time limit of one request, redirects included.
		Timeout: linkTimeout,
		// Stop after 5 redirects so a loop cannot run on.
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			// Too many redirects.
			if len(via) >= 5 {
				// Give up with a plain reason.
				return errors.New("more than 5 redirects")
			} // end of the limit check
			// Keep following.
			return nil
		}, // end of CheckRedirect
	} // end of the client
} // end of newLinkClient

// checkOneLink opens one address with a plain GET (many sites refuse HEAD) and reports what came back; the page body is never read.
func checkOneLink(ctx context.Context, client *http.Client, ref reference) linkResult {
	// The result so far.
	res := linkResult{N: ref.N, URL: ref.URL}
	// Build the request with the time limit of the context.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ref.URL, nil)
	// A bad address is reported, not run.
	if err != nil {
		// Say why.
		res.Problem = "not a valid address"
		// Hand it back.
		return res
	} // end of the request check
	// Say honestly who is asking; no data of the person is sent.
	req.Header.Set("User-Agent", "LLMsControlDock-check-links")
	// Send it.
	resp, err := client.Do(req)
	// No answer at all.
	if err != nil {
		// A short plain reason: the time limit, or the error text of the network layer.
		if errors.Is(err, context.DeadlineExceeded) || strings.Contains(err.Error(), "Client.Timeout") {
			// The site was too slow.
			res.Problem = fmt.Sprintf("no answer within %d seconds", int(linkTimeout/time.Second))
		} else {
			// Anything else, such as no network or an unknown name; the wrapper repeats the address, so only the reason inside is kept.
			res.Problem = err.Error()
			// Unwrap the reason.
			var ue *url.Error
			// Use it when it is there.
			if errors.As(err, &ue) {
				// The plain reason.
				res.Problem = ue.Err.Error()
			} // end of the unwrap
		} // end of the reason choice
		// Hand it back.
		return res
	} // end of the error check
	// The body is not needed; close it so the connection is released.
	defer resp.Body.Close()
	// Remember the code and where the answer came from.
	res.Status, res.Final = resp.StatusCode, resp.Request.URL.String()
	// Hand it back.
	return res
} // end of checkOneLink

// formatLinkResults writes one line per address and a closing summary, and says what to do about a failure.
func formatLinkResults(results []linkResult, readOn string) string {
	// The text being built.
	var b strings.Builder
	// How many answered with a success code.
	good := 0
	// Go through the results in order.
	for _, r := range results {
		// The start of the line: the number as the page shows it.
		fmt.Fprintf(&b, "[%d] ", r.N)
		// Choose the wording.
		switch {
		// A success code.
		case r.ok():
			// Count it and print it.
			good++
			fmt.Fprintf(&b, "OK    %d  %s\n", r.Status, r.URL)
			// A redirect is not a failure, but the address should be updated.
			if r.Final != r.URL {
				// Say where it went.
				fmt.Fprintf(&b, "      moved to %s (update the address in references.go)\n", r.Final)
			} // end of the redirect note
		// An answer that is not a success.
		case r.Status != 0:
			// Print the code.
			fmt.Fprintf(&b, "FAIL  %d  %s\n", r.Status, r.URL)
		// No answer at all.
		default:
			// Print the reason.
			fmt.Fprintf(&b, "FAIL  --  %s (%s)\n", r.URL, r.Problem)
		} // end of the wording choice
	} // end of the loop
	// The summary line.
	fmt.Fprintf(&b, "%d of %d addresses answered with a success code. The list was last read by hand on %s.\n", good, len(results), readOn)
	// Advice only when something failed.
	if good != len(results) {
		// What to do, and the honest caveat about sites that refuse programs.
		b.WriteString("For each FAIL: open the address in a browser. A 403 or 429 can mean the site refuses programs, not that the page is gone.\nIf the page is really gone or has moved, fix or remove the reference in references.go and update the date; nothing was changed by this command.\n")
	} // end of the advice
	// Hand back the text.
	return b.String()
} // end of formatLinkResults

// runCheckLinks opens every reference address one after another, prints the report, and returns the exit code (0 = all answered with a success code, 1 = at least one did not).
func runCheckLinks(refs []reference, client *http.Client, readOn string, out io.Writer) int {
	// The results in order.
	results := make([]linkResult, 0, len(refs))
	// Go through the references.
	for _, ref := range refs {
		// Ask for one address.
		results = append(results, checkOneLink(context.Background(), client, ref))
	} // end of the loop
	// Print the report.
	fmt.Fprint(out, formatLinkResults(results, readOn))
	// The exit code follows the results.
	for _, r := range results {
		// One failure is enough.
		if !r.ok() {
			// Failure code.
			return 1
		} // end of the failure check
	} // end of the loop
	// All good.
	return 0
} // end of runCheckLinks
