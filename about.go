// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the packages this file uses.
	// bytes builds the page in memory before it is sent.
	"bytes"
	// html/template builds the page and escapes every inserted text.
	"html/template"
	// embed stores the page template inside the executable.
	_ "embed"
	// log writes the real reason for an error for the person running the program.
	"log"
	// net/http provides the request and response types.
	"net/http"
	// runtime/debug reads what the Go tool recorded about this build.
	"runtime/debug"
	// runtime tells the Go version and the platform.
	"runtime"
	// time reads and shows the revision date.
	"time"
) // end of imports

// aboutTemplateText holds the About page, stored inside the executable at build time.
//
//go:embed web/about.html
var aboutTemplateText string

// appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
const appVersion = "0.22.0"

// appDeveloper is the name of the developer, shown on the About page.
const appDeveloper = "Shrinivas Kodati"

// appDeveloperProfile is the developer's public LinkedIn profile, linked from the About page.
const appDeveloperProfile = "https://www.linkedin.com/in/shrinikodati/"

// appAssistant names the assistant and the model version that helped write the program; it is written by hand when the version changes.
const appAssistant = "Claude (Sonnet 5.5), Anthropic"

// appDedication is the dedication shown on the About page.
const appDedication = "Dedicated to Ms. Meghna Kodati, without whom I would never have had the inspiration to develop this."

// appCopyright is the copyright line shown on the About page.
const appCopyright = "© 2026 Shrinivas Kodati. All rights reserved."

// appRepository is the address of the source code; the repository is private, so only its owner can open it.
const appRepository = "https://github.com/kodatishrini-beep/OllamaControlCenter"

// companyName is the developer's company, shown in the header, the footer bar and the About page.
const companyName = "termGate Consulting"

// companyTagline is the company's own tagline, as shown on its website.
const companyTagline = "Transforming Healthcare through Data & Technology."

// companyAILine connects this program to the company's work: models that run on the person's own hardware keep data on that computer.
const companyAILine = "Private AI on your own hardware."

// companySite is the company website; the program only links to it and never contacts it by itself.
const companySite = "https://www.termgate.com/"

// companyLink builds the address of the company website for one place on the page; the tag is all lowercase, names only this program and the place, and carries nothing about the person or the computer.
func companyLink(placement string) string {
	// The site, then the fixed source tags, then the place (header, footer or about-card).
	return companySite + "?utm_source=ollama-control-center&utm_medium=app&utm_campaign=app-link&utm_content=" + placement
} // end of companyLink

// companyService is one service of the company, shown on the About page.
type companyService struct {
	// Name is the service name.
	Name string
	// Detail is a short line about it.
	Detail string
} // end of companyService

// companyServices lists the services in the order shown: the one that fits this program's audience first. The wording follows the company website and must be checked by the company before release.
var companyServices = []companyService{
	// The service closest to people who run local models.
	{"AI & Prompt Engineering", "clinical prompt design, language processing of clinical text, generative AI for decision support"},
	// Terminology mapping.
	{"Clinical Data Mapping", "SNOMED CT, LOINC, ICD-10, RxNorm, MedDRA, UCUM"},
	// Data models.
	{"Clinical Data Modeling", "HL7 FHIR, openEHR, OMOP CDM"},
	// Strategy.
	{"Strategy & Advisory", "IT product roadmaps, clinical use case design, regulatory and compliance guidance"},
	// Training.
	{"Clinical Terminology Training", "SNOMED CT fundamentals and implementation, LOINC mapping"},
}

// companyLogo is the company's logo, cropped and shrunk to 178 by 96 pixels (shown at 40 pixels high), stored inside the executable so nothing is downloaded from another site.
//
//go:embed web/termgate-logo.png
var companyLogo []byte

// readBuildInfo reads the facts the Go tool recorded in the program; a test replaces it.
var readBuildInfo = debug.ReadBuildInfo

// aboutPage is everything the About page needs.
type aboutPage struct {
	// Theme is the saved colour theme, or empty to follow the system.
	Theme string
	// Size is the saved text size, or empty for the browser's own size.
	Size string
	// Version is appVersion.
	Version string
	// Developer is appDeveloper.
	Developer string
	// DeveloperProfile is appDeveloperProfile.
	DeveloperProfile string
	// Assistant is appAssistant.
	Assistant string
	// Dedication is appDedication.
	Dedication string
	// Copyright is appCopyright.
	Copyright string
	// Repository is appRepository.
	Repository string
	// Revision is the short source revision, or empty when the build did not record one.
	Revision string
	// Modified is true when the source had uncommitted changes at build time.
	Modified bool
	// RevisionDate is the date of the source revision in UTC, with the zone written out, or empty.
	RevisionDate string
	// CompanyName is companyName.
	CompanyName string
	// CompanyTagline is companyTagline.
	CompanyTagline string
	// CompanyAILine is companyAILine.
	CompanyAILine string
	// CompanyURL is the company website address for the About card.
	CompanyURL string
	// Services are the company's services.
	Services []companyService
	// Platform is the Go version, the operating system and the processor type.
	Platform string
} // end of aboutPage

// revisionFromBuild picks the short revision, the modified flag and the revision date (always shown in UTC) out of the recorded build facts.
func revisionFromBuild() (string, bool, string) {
	// Ask the Go tool's record.
	info, ok := readBuildInfo()
	// Nothing recorded, for example under "go run" or when built outside a git folder.
	if !ok {
		// Empty means "not recorded".
		return "", false, ""
	} // end of the record check
	// The three facts.
	var rev, when string
	// Whether the source differed from the revision.
	modified := false
	// Go through the recorded settings.
	for _, s := range info.Settings {
		// Pick the ones we show.
		switch s.Key {
		// The full commit hash.
		case "vcs.revision":
			// Keep it.
			rev = s.Value
		// The time of the commit, in UTC.
		case "vcs.time":
			// Keep it.
			when = s.Value
		// Whether there were uncommitted changes.
		case "vcs.modified":
			// The Go tool writes "true" or "false".
			modified = s.Value == "true"
		} // end of the key switch
	} // end of the loop
	// Twelve characters are enough to find a commit.
	if len(rev) > 12 {
		// Cut it.
		rev = rev[:12]
	} // end of the length check
	// The date, shown with its zone.
	shown := ""
	// Read the recorded time.
	if t, err := time.Parse(time.RFC3339, when); err == nil {
		// Always UTC, written as such, so no one has to guess the zone.
		shown = t.UTC().Format("2 Jan 2006 15:04 MST")
	} // end of the time check
	// Hand back.
	return rev, modified, shown
} // end of revisionFromBuild

// aboutHandler builds the handler of the read-only About page; it changes nothing and needs no token.
func aboutHandler() http.HandlerFunc {
	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
	page := template.Must(template.New("about").Parse(aboutTemplateText))
	// The handler itself.
	return func(w http.ResponseWriter, r *http.Request) {
		// The recorded build facts.
		rev, modified, when := revisionFromBuild()
		// Fill in what the template shows.
		data := aboutPage{
			// The saved theme.
			Theme: themeFromRequest(r),
			// The saved text size.
			Size: sizeFromRequest(r),
			// The version.
			Version: appVersion,
			// The developer.
			Developer: appDeveloper,
			// The developer's profile address.
			DeveloperProfile: appDeveloperProfile,
			// The assistant.
			Assistant: appAssistant,
			// The dedication.
			Dedication: appDedication,
			// The copyright line.
			Copyright: appCopyright,
			// The source address.
			Repository: appRepository,
			// The revision.
			Revision: rev,
			// Uncommitted changes.
			Modified: modified,
			// The revision date in UTC.
			RevisionDate: when,
			// The company name.
			CompanyName: companyName,
			// The company tagline.
			CompanyTagline: companyTagline,
			// The AI line.
			CompanyAILine: companyAILine,
			// The company website, tagged for this place.
			CompanyURL: companyLink("about-card"),
			// The services.
			Services: companyServices,
			// Go version, system and processor.
			Platform: runtime.Version() + " on " + runtime.GOOS + "/" + runtime.GOARCH,
		} // end of the data
		// Build the page in memory first, so a template error produces a clean 500 and not a half page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason.
			log.Printf("about page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of the handler
} // end of aboutHandler
