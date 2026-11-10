// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// os checks whether a folder exists already.
	"os"
	// strings changes the separators for Windows.
	"strings"
) // end of imports

// placeRow is one place on this computer where the program keeps something: what, where, and whether it exists yet.
type placeRow struct {
	// What names it in words.
	What string
	// Where is the full path.
	Where string
	// State says whether it exists yet, or when it is made.
	State string
} // end of placeRow

// systemPlaces is one kind of place, written for each system, so the About page can show where it is on Linux, Windows and macOS.
type systemPlaces struct {
	// What names it in words.
	What string
	// Linux, Windows and Mac are the paths on each system.
	Linux, Windows, Mac string
} // end of systemPlaces

// existsText says in words whether a path exists yet.
func existsText(path, later string) string {
	// No path: the system has no standard place.
	if path == "" {
		// Say so.
		return "no standard place on this system"
	} // end of the empty check
	// It exists.
	if _, err := os.Stat(path); err == nil {
		// Say so.
		return "exists"
	} // end of the exists check
	// Not yet: say when it is made.
	return "not yet: " + later
} // end of existsText

// placesHere lists the places on this computer, using the same functions that create them.
func placesHere() []placeRow {
	// The running program.
	exe, _ := executablePath()
	// The installed copy's standard place.
	target, _ := installTarget()
	// Whether -install placed it there.
	installed := "not installed (optional: run the program once with -install)"
	// The copy is there and is the one -install placed.
	if _, ok := installedCopy(stateRoot()); ok {
		// Say so.
		installed = "installed"
	} // end of the installed check
	// The rows, in the order the program creates them.
	return []placeRow{
		// The settings folder.
		{"Settings", configRoot(), existsText(configRoot(), "made when you press Continue on the System check or save a setting")},
		// The data folder.
		{"Results, saved copies and deleted models", dataRoot(), existsText(dataRoot(), "made at the first performance test, saved comparison, deleted model, Find LLM search, estimate or desktop icon")},
		// The state folder.
		{"Check history and log", stateRoot(), existsText(stateRoot(), "made when the desktop icon starts the program, or when saving the check history is turned on in Settings")},
		// The program that is running now.
		{"This program file (running now)", exe, "exists"},
		// The standard place of the installed copy.
		{"Installed program (placed by -install)", target, installed},
	} // end of the rows
} // end of placesHere

// placeFor writes where one kind of place is on a system, from the same function the program uses, with ~ and %Name% standing for the person's own folders.
func placeFor(goos, kind string) string {
	// The person's folders as placeholders, so the text is the same on every computer.
	getenv := func(name string) string {
		// Windows names its folders with variables.
		if name == "AppData" || name == "LocalAppData" {
			// The variable as people write it.
			return "%" + name + "%"
		} // end of the Windows names
		// No XDG override: the standard places.
		return ""
	} // end of the placeholder lookup
	// The home folder as people write it.
	home := func() (string, error) { return "~", nil }
	// The base folder from the real function.
	base, err := baseDirFor(goos, kind, getenv, home)
	// No standard place.
	if err != nil {
		// Say so.
		return "not known"
	} // end of the base check
	// Windows writes backslashes.
	if goos == "windows" {
		// The base and the program's folder.
		return strings.ReplaceAll(base, "/", `\`) + `\` + dataFolderName
	} // end of the Windows case
	// Linux and macOS write slashes.
	return base + "/" + dataFolderName
} // end of placeFor

// installPlaceFor writes the standard place of the installed program on a system, from the same function -install uses.
func installPlaceFor(goos string) string {
	// Windows names its folder with a variable.
	getenv := func(name string) string { return "%" + name + "%" }
	// The home folder as people write it.
	home := func() (string, error) { return "~", nil }
	// The path from the real function.
	p, err := installTargetFor(goos, getenv, home)
	// No standard place.
	if err != nil {
		// Say so.
		return "not known"
	} // end of the error check
	// The separators of that system (the function used this computer's).
	if goos == "windows" {
		// Backslashes.
		return strings.ReplaceAll(p, "/", `\`)
	} // end of the Windows case
	// Slashes.
	return strings.ReplaceAll(p, `\`, "/")
} // end of installPlaceFor

// placesBySystem lists every kind of place on Linux, Windows and macOS.
func placesBySystem() []systemPlaces {
	// The rows.
	return []systemPlaces{
		// The settings folder.
		{"Settings", placeFor("linux", kindConfig), placeFor("windows", kindConfig), placeFor("darwin", kindConfig)},
		// The data folder.
		{"Results, saved copies and deleted models", placeFor("linux", kindData), placeFor("windows", kindData), placeFor("darwin", kindData)},
		// The state folder.
		{"Check history and log", placeFor("linux", kindState), placeFor("windows", kindState), placeFor("darwin", kindState)},
		// The installed program.
		{"Installed program (placed by -install)", installPlaceFor("linux"), installPlaceFor("windows"), installPlaceFor("darwin")},
	} // end of the rows
} // end of placesBySystem
