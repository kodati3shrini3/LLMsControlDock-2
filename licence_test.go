// Package main tells Go that this test file belongs to the same program as about.go.
package main

// Imports: the standard library only.
import (
	// os reads the public project files.
	"os"
	// strings searches their text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// readProjectFile reads one public file from the project folder (the folder the tests run in) and fails the test when it is missing.
func readProjectFile(t *testing.T, name string) string {
	// Mark this as a helper.
	t.Helper()
	// Read it.
	b, err := os.ReadFile(name)
	// A missing file is a missing public file.
	if err != nil {
		// Report.
		t.Fatalf("%s is missing from the project folder: %v", name, err)
	} // end of the read check
	// The text.
	return string(b)
} // end of readProjectFile

// TestLicenceFilesAgreeWithThePage checks that the LICENSE file, the NOTICE file, the README and the About page all tell the same story: the same licence, the same copyright holder, and no leftover claim of "All rights reserved".
func TestLicenceFilesAgreeWithThePage(t *testing.T) {
	// The official licence text: its title and version line, and the end marker once.
	lic := readProjectFile(t, "LICENSE")
	// The title and the version.
	if !strings.Contains(lic, "Apache License") || !strings.Contains(lic, "Version 2.0, January 2004") {
		// Report.
		t.Error("LICENSE is not the Apache License 2.0")
	} // end of the licence check
	// The end of the terms, once.
	if strings.Count(lic, "END OF TERMS AND CONDITIONS") != 1 {
		// Report.
		t.Error("LICENSE must hold the end marker exactly once")
	} // end of the end-marker check
	// The page names the same licence as the file.
	if appLicence != "Apache License 2.0" {
		// Report.
		t.Errorf("the About page names %q, not the Apache License 2.0", appLicence)
	} // end of the name check
	// The copyright holder is the text of the page without the sign and the year.
	holder := strings.TrimSuffix(strings.TrimPrefix(appCopyright, "© 2026 "), ".")
	// The NOTICE names the same holder and the program.
	notice := readProjectFile(t, "NOTICE")
	// The holder.
	if !strings.Contains(notice, "Copyright 2026 "+holder) {
		// Report.
		t.Errorf("NOTICE does not say Copyright 2026 %s", holder)
	} // end of the holder check
	// The program name.
	if !strings.HasPrefix(notice, "LLMsControlDock\n") {
		// Report.
		t.Error("NOTICE must start with the program name")
	} // end of the name check
	// The README names the licence, the holder and the version of this program.
	readme := readProjectFile(t, "README.md")
	// Each fact.
	for _, want := range []string{"Apache License 2.0", "Copyright 2026 " + holder, "version " + appVersion} {
		// Look for it.
		if !strings.Contains(readme, want) {
			// Report.
			t.Errorf("README.md does not contain %q", want)
		} // end of the look
	} // end of the fact loop
	// No file may claim "All rights reserved" next to an open licence.
	for name, text := range map[string]string{"NOTICE": notice, "README.md": readme} {
		// Look for it.
		if strings.Contains(text, "All rights reserved") {
			// Report.
			t.Errorf("%s says All rights reserved", name)
		} // end of the look
	} // end of the claim loop
} // end of TestLicenceFilesAgreeWithThePage
