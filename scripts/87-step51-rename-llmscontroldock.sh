#!/usr/bin/env bash
# Script 87 (rename the product to LLMsControlDock, version 0.31.0): the program, its pages, its files and its build now carry the name LLMsControlDock. Nothing is lost for existing installs: the first start renames the old OllamaControlCenter settings, data and state folders, and replaces an old desktop icon by one with the new name. The environment variable is now LLMSCONTROLDOCK_OLLAMA_URL (the old OCC_OLLAMA_URL still works). Ten new tests.
# Run it from the project folder, on its own branch (never on main): cd ~/OllamaControlCenter && bash scripts/87-step51-rename-llmscontroldock.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as on main after PR 38), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE[".github/workflows/build.yml"]="3939dc8652296181485b32c1cdf61861e993e2cb2d84c075753fd010098ea866"
BEFORE[".gitignore"]="0d7954d3778904b48fdf2ddb2ef2e91ced806d5d8b607e19505c410853ae6203"
BEFORE["about.go"]="48a7029ec4bf2b0d59e7b41d233a4368468d694bb3ba68d3c4a5592a8a51a49a"
BEFORE["about_test.go"]="7f0cffa902b36160539e61c574ebbd14505936cfbb49961a1aa21e62557a2a37"
BEFORE["brand_test.go"]="4bb0f611be445dc5bc464eea4f8395e67b58956ba0084b3c8eac2726f8c5c63f"
BEFORE["checklinks.go"]="c142f2bf02dbb5382ee773938149e22de351b750ddfc6ac25e1fb3669c35c5ee"
BEFORE["checklinks_test.go"]="2eeae0103739dad55c53247d59947846f12585323e2a659b4fff63d27bcccd01"
BEFORE["compreport.go"]="e547032209b75f33920fc57b4f5a5e23110c41460ae8b80d1d09b0d612a87252"
BEFORE["compreport_test.go"]="0f336217ef06b70e205249e000fd22ab29eed027590c3fc646d8bd321ab84657"
BEFORE["config.go"]="472068765aaa262d76885d4bb1627a1d5b5e47ff1f75c3120ad68f844adb3da9"
BEFORE["config_test.go"]="9aabcd44c6e74939f6f36baf4f6eb3616369f04694795422068219c2f218fddb"
BEFORE["datafolder.go"]="ba5bf3d93be2efd46127811ead68139ec98a9229d6fb49a09d997a1c2e3e5dd8"
BEFORE["datafolder_test.go"]="c994a59e45aefc805d0a8d5f315530320f438b74dde707a676d99613af472186"
BEFORE["delete_test.go"]="2a1fe9ee96c5b23393811926601d76495a90e9ed1001a9acaddc9ecf6c7d62c8"
BEFORE["desktopicon.go"]="0d9c20cb79b59f163f919ecbce45524b3541ac5f441f174e4b8d3d60e5e252ee"
BEFORE["desktopicon_test.go"]="6ce6dcfca2cfa9a90d9511ae033400ecdee63d7dd9c0fc61decb6161e3d19d29"
BEFORE["history_test.go"]="6e4e54c75cc67acf7df0779b22406214e7be00f174f60e7fdcf6571c4c31a780"
BEFORE["launch.go"]="f388c386615e9c84b4b050a02225232da22bfc5022ed114616a8f4d8fca3678d"
BEFORE["launchers.go"]="7df069c6dc819305e533298d31ead6d87874eb58fd029eed5bfcf62da3979ce7"
BEFORE["launchers_test.go"]="9e4e4b997ef2486c452850a8aa51362b9f7cf60426fb3804390f1f5036b14944"
BEFORE["library.go"]="47f9e6a1b2d8d99d0e84986812e762f6881d75dea30c9f78a49a480acf81d20f"
BEFORE["main.go"]="4f72e27c12ae1b85d92de6be899d43aa546277b278b450f3c0522faaa22c6a03"
BEFORE["pdf.go"]="e27f7d3d5d5a8b906cad794def3ba0a6fb38aa933e91e3338bcd28c322681d35"
BEFORE["pdf_test.go"]="2a67f9ab4a379ace10ea2cc50d0b692a218313491f8cef7212c5bf59bf2b35a9"
BEFORE["perf_test.go"]="4ff83adbb9217ff80574ae8289efbbe8a709b10a6bded2ab91965d909d92e3db"
BEFORE["perfstore_rename_test.go"]="fc4e8798340b222d19f47f0d7aec6c233df2d67022f4eb2c9f0db40ee4f1ead1"
BEFORE["portbusy.go"]="4887cfc85ffaac892802bef4ed9684536276a1eabf3e0b026ee66f9e23692f8d"
BEFORE["portbusy_test.go"]="fa9fc24578b5a31dcc37af5d7b466038bb985b714de90fffb337259aefc12e12"
BEFORE["signals.go"]="0c44d2dbcd8a6434f233df37624bab5283b8415a4a77d3d748fcd7607718492d"
BEFORE["web.go"]="b8129b2aafa4dcee0fbbcf1263b1f2d555e72f8d9a6a957e75b08ec09cfe3284"
BEFORE["web/about.html"]="db0152c6f524c93df04b586fe0a57116289a4ddd6700ec67a9adf36c0f62f172"
BEFORE["web/compare-saved.html"]="8f5b5fa3f4a47ac163b0fb53d253ec60f78505e1a5f00807df08bd042440b352"
BEFORE["web/compare.html"]="c58b7f2ec23d137e9a61ced8ae9badfcfa67381f526898077b825dde8ead585d"
BEFORE["web/control.html"]="1dcb036f487b92d1484e8119dd62fb94c847de6861653f478ef1e7c13efe8bd6"
BEFORE["web/delete.html"]="79720a52ad841a934d9414ae0b6ac2ceee7a4165fb6e80a774d128ad9b99e76b"
BEFORE["web/gear.html"]="39b28b58812dbc2f3734b0c3a2165735a0227caa7245af0e5b35a0fae019f929"
BEFORE["web/index.html"]="772211e3084d10c6ad0c487ea499b85117ba6827000fe3c23ca6679adf1849e0"
BEFORE["web/load.html"]="e787a1e2e99d9450bf33ddfb496d8029fd29f84240af1682c54c8ffbb0d7d65b"
BEFORE["web/modelfile.html"]="3f400299904aeefd1c318cac82069d47c1401fc6c4561f8952026c98016c423b"
BEFORE["web/performance.html"]="e9d426672cd90eeb04bf29910313a2bc1e9dba0a9ee81a8cc29f724140bdde16"
BEFORE["web/retest.html"]="d17ddc85136886a5ed31f8d8c46883a4e001bad84995c5f058eb0cd508fccf1c"
BEFORE["web/systemcheck.html"]="04f8ef03680388d5b31fe3b4bbe6d07c65a1e6dbedb31564c27cb59549d37adc"
BEFORE["web/unload.html"]="66ac3b23aaf2ad1a9aed3b86068d319587c6c9da219ae2ef35642055b3a95d58"
BEFORE["web_test.go"]="e3cc8a388ee60b071e9012613eff890a73e1c2a11ccda9f6e80947e90ce21799"
AFTER[".github/workflows/build.yml"]="2c838ab3d0dce7446792f516c314aeaec8d734aae81642aa7a6925e7b9fd2720"
AFTER[".gitignore"]="a06ce2e2658a4bdc2d607bdd2f65d5377ec59d84688176924915d57a5cbde963"
AFTER["about.go"]="f47af5ffefafb3e6287a6d163ce25b862ee4dcb65c54265aebe5275ca666db27"
AFTER["about_test.go"]="264edde3e2416df45b5b8f5bf1376a685d9db97193d6d1cbf572a0c03a7a9473"
AFTER["brand_test.go"]="f5ff3adb6a5a7d8c17b37ea9b9f9c684b0fad367758b9f7f8ae48039910a24e6"
AFTER["checklinks.go"]="c35c2843e5c7b3571c4eb97eb196c019b638b4b633d77549ee29a001d2e7dd66"
AFTER["checklinks_test.go"]="dbd876c4041280c987efebbb186ba958870720254255687e52663135a301ca2b"
AFTER["compreport.go"]="e71b2732a0264cf3cd3003da753a94ff173c44a4e234590e547be1c90accfafa"
AFTER["compreport_test.go"]="d52d11c9af48bd35a322826854624edf48fa984a5c3caf87bcd7f34a81300ad8"
AFTER["config.go"]="d5b37f104bf04eca4bd57fca8d106c31d943071e0839961dd475d83536ee2cdc"
AFTER["config_test.go"]="c2a7cd9abb2eb2d44b433e748ae5654b7bd9269dcbd5c7783247fa45276c8717"
AFTER["datafolder.go"]="962b837aef13f3da356459c6ba1768e8906f847409338072cb06940ca6afae83"
AFTER["datafolder_test.go"]="a868f9df26d846bed64fdcc97dbe7c67c6cc67e2d89388714f55baaa7a617c56"
AFTER["delete_test.go"]="97ac350fe59406fc0666e200193d26791717a59702204bc622909d7d36d71e94"
AFTER["desktopicon.go"]="762383d577c744997fa7e4649362ee3dd7f08710664ba10d5b83e1e2c22084b5"
AFTER["desktopicon_test.go"]="43e02c68b8aed00daa03bb1af44d6944e643636c3e9499b0da3b6e0cd1193315"
AFTER["history_test.go"]="e979c5ab814b31720d9b3568637701da47d174d89800ae4c65c1760c65cecea6"
AFTER["launch.go"]="8c4b0b3dea257c74981b9432c9fdaacbc109dd2b716e73d64ba0d48f2b377d5a"
AFTER["launchers.go"]="cdff06717cfe5f4c445cb08e2b8cbf168aff138322406724d98ad29f23cbcc82"
AFTER["launchers_test.go"]="3167d615c007016c2ec78589f71c91f4541463fe73c96db88075f11ac77ad33c"
AFTER["legacyname.go"]="0cea9c5cd1b66281feb1c327f905eb9518447e277bf2d05567aeebeb074189e4"
AFTER["legacyname_test.go"]="df950666c5f3d5a82970ffbbd6906ba6d72ce47e5eeec8f857e4e3fb64811441"
AFTER["library.go"]="c59d9ef558a4cae1f8651de3b6753eb2047466a9219010cfecc8be0c5e64de1f"
AFTER["main.go"]="19458dfad25ad5a01d4af1e8ff251378e0b0feb3f7b62474d37eb8cc148a4c23"
AFTER["pdf.go"]="fa983390734f2f35eab94a976c9d071a9292e55f3985e6607ac435504f5fd97c"
AFTER["pdf_test.go"]="f54893f58e039e2b836582537ec76347c17ca3e979fd845409a7eda8bfc60815"
AFTER["perf_test.go"]="dac3db91024276247bc97b406809903c57ebd1d616093c7ffa19f783c350f917"
AFTER["perfstore_rename_test.go"]="4b60b2d9294bccb08276e785a60408481618a4aca097de2e693539d3b1983167"
AFTER["portbusy.go"]="b25b0f8036fc1d759668c2403a3a3d964e7b0b67df15189d87f926b98809e744"
AFTER["portbusy_test.go"]="76f7fe720ff4dd074c4333c73100be1fd306ac504770eafb226449b5126289f6"
AFTER["signals.go"]="1a9cdc12643a636965904e7ceb523eb9921ddd9882f31596c96aa13efe4825b5"
AFTER["web.go"]="54f85e9f3626983f458caf905f1807521ea151d8c1e87c09f519a466b876688c"
AFTER["web/about.html"]="ec81bc2f758af5f1bed4e10666f9d5c45cfcaf776a64d6dedf10262e69733584"
AFTER["web/compare-saved.html"]="af2a20da17d2032e2b59e2b2560305b5280c2187b61232c33aaa804598461619"
AFTER["web/compare.html"]="22a96b32b257ebae722d071e2d3caa2fba3561b050fd2fbf9772e25137c05aa8"
AFTER["web/control.html"]="1b4a18482829dab6e05897cd37b9ab408578ff1e626b05dc8ded6e0bb83347b3"
AFTER["web/delete.html"]="a34a45660a4bad36f065308bd05da84ee185440cebdf0bc1b8f34e84592a39f7"
AFTER["web/gear.html"]="a6e281eb56a4ce5040a0fb684b06a9d2a6557bcb7d5dd962ce4b7de91623ae27"
AFTER["web/index.html"]="56f9d711d086a245f776b2d227cab2b4bf0e21240e680aa843458f3e14320035"
AFTER["web/load.html"]="d8c62d901786b055c6d395f70ab428ae9886f641d7ab6638bf96f5e73d9f8f41"
AFTER["web/modelfile.html"]="fbc9a8090cec0487d14e6b35d691f776e4adaa7172f7a99e5b5a1c862b3bc758"
AFTER["web/performance.html"]="637f89913eca7ab516f115880d86d8506c9ee791c9be373380f667be071ce841"
AFTER["web/retest.html"]="aa543e85800c39cdf1c8ab88f994ae1da8e32d8693c556819d48efdc00d1f2e7"
AFTER["web/systemcheck.html"]="ee820e04cb6a61c33cc648d22e0e245f5169aef65d215009739be22b991d9219"
AFTER["web/unload.html"]="e1da342271b9ceb96c0f9e1f2b6b208649ac7210eca7431bbe22328986332505"
AFTER["web_test.go"]="2e8b774c906a7541c157a0439fbbc84d452442fdfc1058fa8fb48d854e9649de"

# Count of passed checks.
PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; this script belongs on its own branch (rename/llmscontroldock)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 86 must be in this branch: its new file exists.
[ -e portbusy.go ] || fail "portbusy.go is missing: script 86 (merged as PR 38) must be in this branch"
# Report it.
pass "script 86 is in this branch (portbusy.go exists)"

# Refuse to run twice: the new file exists when the change was applied before.
if [ -e legacyname.go ]; then fail "legacyname.go exists: this script was already applied"; fi
# Report it.
pass "the rename is not applied yet (script not applied before)"

# Every file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files to change are the expected versions before the change"
# go.mod differs between computers (the Go version line), so only its module line is checked: it must be the old name, exactly.
grep -qx 'module github.com/kodati3shrini3/OllamaControlCenter' go.mod || fail "the module line of go.mod is not the expected old one"
# Report it.
pass "go.mod: the module line is the expected old one"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_87_END'
diff --git a/.github/workflows/build.yml b/.github/workflows/build.yml
index 7d11b1b..ef7b78f 100644
--- a/.github/workflows/build.yml
+++ b/.github/workflows/build.yml
@@ -1,4 +1,4 @@
-# Build and test OllamaControlCenter on GitHub, only for the systems you tick. It runs ONLY when a person clicks "Run workflow" in the Actions tab; it never runs by itself and it never publishes a release.
+# Build and test LLMsControlDock on GitHub, only for the systems you tick. It runs ONLY when a person clicks "Run workflow" in the Actions tab; it never runs by itself and it never publishes a release.
 name: Build and test (manual, per system)
 
 # The only trigger is the manual button; each system has its own tick box, so a run costs only what is ticked (macOS minutes cost about ten times Linux minutes on a private repository).
@@ -130,7 +130,7 @@ jobs:
       - name: Build the executable
         shell: bash
         env:
-          FILE: OllamaControlCenter-${{ matrix.system }}${{ matrix.ext }}
+          FILE: LLMsControlDock-${{ matrix.system }}${{ matrix.ext }}
         run: |
           set -eu
           mkdir dist
@@ -142,7 +142,7 @@ jobs:
       - name: Start-up check
         shell: bash
         env:
-          FILE: OllamaControlCenter-${{ matrix.system }}${{ matrix.ext }}
+          FILE: LLMsControlDock-${{ matrix.system }}${{ matrix.ext }}
           VERSION: ${{ steps.version.outputs.version }}
         run: |
           set -eu
@@ -161,7 +161,7 @@ jobs:
           done
           if [ "$ok" != "1" ]; then echo "The program did not answer within 30 seconds"; cat run.log; exit 1; fi
           # The main page names the program, the About page carries the version, the Settings page answers.
-          grep -q "<title>OllamaControlCenter</title>" main.html
+          grep -q "<title>LLMsControlDock</title>" main.html
           curl -fsS http://127.0.0.1:8765/about | grep -q "$VERSION"
           curl -fsS -o /dev/null http://127.0.0.1:8765/settings
           echo "PASS: $FILE answered on $RUNNER_OS $RUNNER_ARCH"
@@ -169,14 +169,14 @@ jobs:
       # Keep this system's file for 14 days so it can be downloaded and tested; the name carries the version and the system, so every system has its own download.
       - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
         with:
-          name: OllamaControlCenter-${{ steps.version.outputs.version }}-${{ matrix.system }}
-          path: dist/OllamaControlCenter-${{ matrix.system }}${{ matrix.ext }}
+          name: LLMsControlDock-${{ steps.version.outputs.version }}-${{ matrix.system }}
+          path: dist/LLMsControlDock-${{ matrix.system }}${{ matrix.ext }}
           if-no-files-found: error
           retention-days: 14
       # The checksum goes next to it in its own small download, so the executable's download is just the one file.
       - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
         with:
-          name: OllamaControlCenter-${{ steps.version.outputs.version }}-${{ matrix.system }}-SHA256SUMS
+          name: LLMsControlDock-${{ steps.version.outputs.version }}-${{ matrix.system }}-SHA256SUMS
           path: dist/SHA256SUMS
           if-no-files-found: error
           retention-days: 14
diff --git a/.gitignore b/.gitignore
index 8ffe18f..9886310 100644
--- a/.gitignore
+++ b/.gitignore
@@ -35,4 +35,5 @@ settings.json
 .DS_Store
 
 # Stray files from saving a comparison with the browser (PDF and CSV): they must never reach GitHub
+LLMsControlDock-comparison*
 OllamaControlCenter-comparison*
diff --git a/about.go b/about.go
index bcc8d3b..377e00f 100644
--- a/about.go
+++ b/about.go
@@ -25,8 +25,8 @@ import ( // import lists the packages this file uses.
 //go:embed web/about.html
 var aboutTemplateText string
 
-// appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.30.2"
+// appVersion is the version of LLMsControlDock; it is raised by hand when a release is made.
+const appVersion = "0.31.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
@@ -44,7 +44,7 @@ const appDedication = "Dedicated to my daughter Meghna, without whom I would nev
 const appCopyright = "© 2026 Shrinivas Kodati. All rights reserved."
 
 // appRepository is the address of the source code; the repository is private, so only its owner can open it.
-const appRepository = "https://github.com/kodati3shrini3/OllamaControlCenter"
+const appRepository = "https://github.com/kodati3shrini3/LLMsControlDock"
 
 // companyName is the developer's company, shown in the header, the footer bar and the About page.
 const companyName = "termGate Consulting"
@@ -61,7 +61,7 @@ const companySite = "https://www.termgate.com/"
 // companyLink builds the address of the company website for one place on the page; the tag is all lowercase, names only this program and the place, and carries nothing about the person or the computer.
 func companyLink(placement string) string {
 	// The site, then the fixed source tags, then the place (header, footer or about-card).
-	return companySite + "?utm_source=ollama-control-center&utm_medium=app&utm_campaign=app-link&utm_content=" + placement
+	return companySite + "?utm_source=llms-control-dock&utm_medium=app&utm_campaign=app-link&utm_content=" + placement
 } // end of companyLink
 
 // companyService is one service of the company, shown on the About page.
diff --git a/about_test.go b/about_test.go
index f76305a..bc47d3c 100644
--- a/about_test.go
+++ b/about_test.go
@@ -49,7 +49,7 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 	// What must be there, word for word.
 	for _, want := range []string{
 		// The heading.
-		"About Ollama Control Center",
+		"About LLMsControlDock",
 		// The developer.
 		"Shrinivas Kodati",
 		// The developer's LinkedIn profile, safe to follow.
@@ -69,7 +69,7 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		// The licence line.
 		"2026 Shrinivas Kodati. All rights reserved.",
 		// The repository link, safe to follow.
-		`href="https://github.com/kodati3shrini3/OllamaControlCenter" target="_blank" rel="noopener noreferrer"`,
+		`href="https://github.com/kodati3shrini3/LLMsControlDock" target="_blank" rel="noopener noreferrer"`,
 		// The way back.
 		`href="/"`,
 	} { // end of the list
diff --git a/brand_test.go b/brand_test.go
index 1a4e2e5..8251d19 100644
--- a/brand_test.go
+++ b/brand_test.go
@@ -27,7 +27,7 @@ func TestCompanyLinkIsTaggedAndLowercase(t *testing.T) {
 		// Build the address.
 		got := companyLink(place)
 		// The exact text, so nothing can slip in.
-		want := "https://www.termgate.com/?utm_source=ollama-control-center&utm_medium=app&utm_campaign=app-link&utm_content=" + place
+		want := "https://www.termgate.com/?utm_source=llms-control-dock&utm_medium=app&utm_campaign=app-link&utm_content=" + place
 		// Compare.
 		if got != want {
 			// Report the difference.
@@ -50,7 +50,7 @@ func TestMainPageShowsTheCompany(t *testing.T) {
 	// What must be there; the template escapes & as &amp; inside an address.
 	for _, want := range []string{
 		// The header line with the company name as a link.
-		`<p class="brandline">by <a href="https://www.termgate.com/?utm_source=ollama-control-center&amp;utm_medium=app&amp;utm_campaign=app-link&amp;utm_content=header" target="_blank" rel="noopener noreferrer">termGate Consulting`,
+		`<p class="brandline">by <a href="https://www.termgate.com/?utm_source=llms-control-dock&amp;utm_medium=app&amp;utm_campaign=app-link&amp;utm_content=header" target="_blank" rel="noopener noreferrer">termGate Consulting`,
 		// The AI line.
 		"Private AI on your own hardware.",
 		// The footer bar.
diff --git a/checklinks.go b/checklinks.go
index e55f64b..56e6aa0 100644
--- a/checklinks.go
+++ b/checklinks.go
@@ -76,7 +76,7 @@ func checkOneLink(ctx context.Context, client *http.Client, ref reference) linkR
 		return res
 	} // end of the request check
 	// Say honestly who is asking; no data of the person is sent.
-	req.Header.Set("User-Agent", "OllamaControlCenter-check-links")
+	req.Header.Set("User-Agent", "LLMsControlDock-check-links")
 	// Send it.
 	resp, err := client.Do(req)
 	// No answer at all.
diff --git a/checklinks_test.go b/checklinks_test.go
index c52ac07..81b8c81 100644
--- a/checklinks_test.go
+++ b/checklinks_test.go
@@ -97,7 +97,7 @@ func TestCheckLinksReportsEachCase(t *testing.T) {
 	// Every request was a plain GET with our own name, nothing else.
 	for _, a := range agents {
 		// Check it.
-		if a != "GET OllamaControlCenter-check-links" {
+		if a != "GET LLMsControlDock-check-links" {
 			// Report it.
 			t.Errorf("unexpected request %q", a)
 		} // end of the check
diff --git a/compreport.go b/compreport.go
index 53036fc..8519f2b 100644
--- a/compreport.go
+++ b/compreport.go
@@ -32,7 +32,7 @@ var pageSymbols = strings.NewReplacer("✓ ", "", "⚠ ", "")
 // footerLine is the line printed under the notice on every page of the PDF.
 func footerLine(when time.Time) string {
 	// Program, version and time.
-	return fmt.Sprintf("OllamaControlCenter %s  -  made %s", appVersion, when.UTC().Format("2006-01-02 15:04 UTC"))
+	return fmt.Sprintf("LLMsControlDock %s  -  made %s", appVersion, when.UTC().Format("2006-01-02 15:04 UTC"))
 } // end of footerLine
 
 // writeNoticeBlock prints the full notice: a line, the heading and every paragraph, kept together at the start.
@@ -55,11 +55,11 @@ func writeNoticeBlock(d *pdfDoc, p comparePage) {
 // writeComparePDF turns the comparison page into a PDF; the full notice is printed once, at the end, and a short notice is at the foot of every page.
 func writeComparePDF(p comparePage, when time.Time) []byte {
 	// The document.
-	d := newPDF("OllamaControlCenter model comparison", p.NoticeShort, p.NoticeShort, footerLine(when), when)
+	d := newPDF("LLMsControlDock model comparison", p.NoticeShort, p.NoticeShort, footerLine(when), when)
 	// The title.
 	d.text("Model comparison", 18, true, 0)
 	// The origin.
-	d.text(fmt.Sprintf("Made by OllamaControlCenter %s on %s, from tests saved on this computer.", appVersion, when.UTC().Format("2006-01-02 15:04 UTC")), 9, false, 0)
+	d.text(fmt.Sprintf("Made by LLMsControlDock %s on %s, from tests saved on this computer.", appVersion, when.UTC().Format("2006-01-02 15:04 UTC")), 9, false, 0)
 	// A little air.
 	d.gap(6)
 	// The full notice is printed once, at the end; the short notice is at the foot of every page, so it is on the first page too.
@@ -212,7 +212,7 @@ func writeCompareCSV(p comparePage, when time.Time) []byte {
 	// A first record that carries the notice, so it travels with the data.
 	w.Write([]string{"NOTICE", csvSafe(p.NoticeShort)})
 	// Where the file comes from.
-	w.Write([]string{"MADE BY", "OllamaControlCenter " + appVersion + " on " + when.UTC().Format("2006-01-02 15:04 UTC")})
+	w.Write([]string{"MADE BY", "LLMsControlDock " + appVersion + " on " + when.UTC().Format("2006-01-02 15:04 UTC")})
 	// The header row.
 	w.Write(csvHeader)
 	// Every group.
@@ -374,7 +374,7 @@ func compareDownloadHandlers(addr ollamaAddress, token string, store *perfStore)
 			// The file.
 			body := render(data, now)
 			// The name carries the time to the second.
-			name := "OllamaControlCenter-comparison-" + now.Format("20060102-150405Z0700") + "." + extension
+			name := "LLMsControlDock-comparison-" + now.Format("20060102-150405Z0700") + "." + extension
 			// The file is written by the program into the results folder, so the person never has to choose a place.
 			if dir := savedCopyFolder(store); dir != "" {
 				// Write it.
diff --git a/compreport_test.go b/compreport_test.go
index 624dde9..cb15dab 100644
--- a/compreport_test.go
+++ b/compreport_test.go
@@ -77,7 +77,7 @@ func TestComparePDFCarriesEverything(t *testing.T) {
 		// The footer text.
 		text := flat([][]pdfTextLine{f})
 		// The checks.
-		if !strings.Contains(text, noticeShort) || !strings.Contains(text, "page "+string(rune('0'+i+1))+" of ") || !strings.Contains(text, "OllamaControlCenter "+appVersion) || !strings.Contains(text, "made 2026-10-27 19:30 UTC") {
+		if !strings.Contains(text, noticeShort) || !strings.Contains(text, "page "+string(rune('0'+i+1))+" of ") || !strings.Contains(text, "LLMsControlDock "+appVersion) || !strings.Contains(text, "made 2026-10-27 19:30 UTC") {
 			// Report it.
 			t.Errorf("footer of page %d: %q", i+1, text)
 		} // end of the check
@@ -268,7 +268,7 @@ func savedFileOf(t *testing.T, res *http.Response, folder, ext string) []byte {
 		t.Fatalf("%s: status %d, type %q, disposition %q", ext, res.StatusCode, res.Header.Get("Content-Type"), res.Header.Get("Content-Disposition"))
 	} // end of the page check
 	// The folder and the name as the page shows them.
-	m := regexp.MustCompile(`<code class="savedpath">([^<]*)</code>.*<code class="savedname">(OllamaControlCenter-comparison-\d{8}-\d{6}Z\.` + ext + `)</code>`).FindStringSubmatch(strings.ReplaceAll(page, "\n", " "))
+	m := regexp.MustCompile(`<code class="savedpath">([^<]*)</code>.*<code class="savedname">(LLMsControlDock-comparison-\d{8}-\d{6}Z\.` + ext + `)</code>`).FindStringSubmatch(strings.ReplaceAll(page, "\n", " "))
 	// Both must be there.
 	if m == nil {
 		// Stop the test.
@@ -391,7 +391,7 @@ func TestCompareDownloadRoutes(t *testing.T) {
 	// Look through the folder of the results.
 	_ = filepath.WalkDir(filepath.Dir(histFile), func(p string, d os.DirEntry, err error) error {
 		// Count by ending.
-		if err == nil && strings.HasPrefix(d.Name(), "OllamaControlCenter-comparison-") {
+		if err == nil && strings.HasPrefix(d.Name(), "LLMsControlDock-comparison-") {
 			// A PDF copy.
 			if strings.HasSuffix(d.Name(), ".pdf") {
 				// Count it.
diff --git a/config.go b/config.go
index 2e13be2..58b4d75 100644
--- a/config.go
+++ b/config.go
@@ -13,14 +13,28 @@ import ( // import lists the standard-library packages this file uses.
 // defaultOllamaURL is used when neither the option nor the environment variable is given: this machine only (requirement S1).
 const defaultOllamaURL = "http://127.0.0.1:11434"
 
-// envOllamaURL is the environment variable that can supply the address (OCC = OllamaControlCenter).
-const envOllamaURL = "OCC_OLLAMA_URL"
+// envOllamaURL is the environment variable that can supply the address.
+const envOllamaURL = "LLMSCONTROLDOCK_OLLAMA_URL"
+
+// envOllamaURLOld is the name the variable had before the program was renamed to LLMsControlDock; it is still read when the new name is not set, so nobody's setup breaks.
+const envOllamaURLOld = "OCC_OLLAMA_URL"
+
+// ollamaFromEnv returns the address from the environment: the new variable first, then the old one; empty text when neither is set.
+func ollamaFromEnv(getenv func(string) string) string {
+	// The new name wins.
+	if v := getenv(envOllamaURL); v != "" {
+		// Use it.
+		return v
+	} // end of the new-name check
+	// Otherwise the old name.
+	return getenv(envOllamaURLOld)
+} // end of ollamaFromEnv
 
 // These three texts name the layer that supplied the address, so the program can print where it came from.
 const (
 	// sourceFlag means the address came from the -ollama-url command-line option.
 	sourceFlag = "command-line option"
-	// sourceEnv means the address came from the OCC_OLLAMA_URL environment variable.
+	// sourceEnv means the address came from the LLMSCONTROLDOCK_OLLAMA_URL environment variable (or the older OCC_OLLAMA_URL).
 	sourceEnv = "environment variable"
 	// sourceDefault means nobody set an address, so the built-in default is used.
 	sourceDefault = "default"
diff --git a/config_test.go b/config_test.go
index bccf85a..965b453 100644
--- a/config_test.go
+++ b/config_test.go
@@ -16,7 +16,7 @@ func TestResolve(t *testing.T) {
 		name string
 		// flagValue is what the -ollama-url option would hold.
 		flagValue string
-		// envValue is what the OCC_OLLAMA_URL environment variable would hold.
+		// envValue is what the LLMSCONTROLDOCK_OLLAMA_URL environment variable would hold.
 		envValue string
 		// wantSource is the layer we expect to win.
 		wantSource string
diff --git a/datafolder.go b/datafolder.go
index 96526d0..9dc8ae2 100644
--- a/datafolder.go
+++ b/datafolder.go
@@ -21,7 +21,7 @@ import ( // import lists the standard-library packages this file uses.
 ) // end of imports
 
 // dataFolderName is the program's own folder inside each of the three base folders (config, data, state).
-const dataFolderName = "OllamaControlCenter"
+const dataFolderName = "LLMsControlDock"
 
 // maxMigrateBytes is the largest file that is copied from an old folder; a bigger file is never one of this program's own.
 var maxMigrateBytes int64 = 100 << 20
@@ -194,7 +194,7 @@ func looksOurs(name string) bool {
 		return false
 	} // end of the kind check
 	// The two fixed names, the saved copies and the dated files.
-	return name == "performance.json" || name == deletedFileName || strings.HasPrefix(name, "OllamaControlCenter-") || stampedName.MatchString(name)
+	return name == "performance.json" || name == deletedFileName || strings.HasPrefix(name, "LLMsControlDock-") || strings.HasPrefix(name, legacyAppName+"-") || stampedName.MatchString(name)
 } // end of looksOurs
 
 // copyOne copies one file into a new file that only this user can read; an existing file is never overwritten.
diff --git a/datafolder_test.go b/datafolder_test.go
index 108e6ef..ec80e8c 100644
--- a/datafolder_test.go
+++ b/datafolder_test.go
@@ -45,9 +45,9 @@ func TestLooksOurs(t *testing.T) {
 		// A snapshot with a date.
 		"2026-11-02_17-54-00+0100_llama3-8b.json": true,
 		// A saved copy of a download.
-		"OllamaControlCenter-comparison-20261102-175400+0100.pdf": true,
+		"LLMsControlDock-comparison-20261102-175400+0100.pdf": true,
 		// A saved copy as a table.
-		"OllamaControlCenter-comparison-20261102-175400+0100.csv": true,
+		"LLMsControlDock-comparison-20261102-175400+0100.csv": true,
 		// Somebody else's JSON file.
 		"settings-backup.json": false,
 		// Somebody else's text file.
@@ -78,7 +78,7 @@ func TestDataRootAndOldDataRoot(t *testing.T) {
 	// Data and state follow the same fake folder.
 	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// The new folder.
-	if got := dataRoot(); got != filepath.Join("/cfg", "OllamaControlCenter") {
+	if got := dataRoot(); got != filepath.Join("/cfg", "LLMsControlDock") {
 		// Report the problem.
 		t.Errorf("dataRoot = %q", got)
 	} // end of the new-folder check
@@ -94,9 +94,9 @@ func TestDataRootAndOldDataRoot(t *testing.T) {
 		t.Errorf("dataRoot without a folder = %q", got)
 	} // end of the empty check
 	// A program inside bin: the project folder above it.
-	executablePath = func() (string, error) { return "/p/OllamaControlCenter/bin/occ", nil }
+	executablePath = func() (string, error) { return "/p/LLMsControlDock/bin/occ", nil }
 	// The old folder.
-	if got := oldDataRoot(); got != filepath.FromSlash("/p/OllamaControlCenter") {
+	if got := oldDataRoot(); got != filepath.FromSlash("/p/LLMsControlDock") {
 		// Report the problem.
 		t.Errorf("old root from bin = %q", got)
 	} // end of the bin check
@@ -121,11 +121,11 @@ func TestMigrateOldData(t *testing.T) {
 	// A fresh place for the old and the new folders.
 	base := t.TempDir()
 	// The old project folder and the new data folder.
-	oldRoot, newRoot := filepath.Join(base, "project"), filepath.Join(base, "cfg", "OllamaControlCenter")
+	oldRoot, newRoot := filepath.Join(base, "project"), filepath.Join(base, "cfg", "LLMsControlDock")
 	// Old results, with a saved copy and a stranger's file.
 	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "RESULTS")
 	// A saved copy.
-	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "OllamaControlCenter-comparison-1.pdf"), "PDF")
+	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "LLMsControlDock-comparison-1.pdf"), "PDF")
 	// A stranger's file in the same folder.
 	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "my-notes.txt"), "NOTES")
 	// The deleted-models list.
@@ -149,7 +149,7 @@ func TestMigrateOldData(t *testing.T) {
 		// The results.
 		"performanceCompare/performance.json": "RESULTS",
 		// The saved copy.
-		"performanceCompare/OllamaControlCenter-comparison-1.pdf": "PDF",
+		"performanceCompare/LLMsControlDock-comparison-1.pdf": "PDF",
 		// The deleted models.
 		"deletedHistory/deleted-models.json": "DELETED",
 		// The snapshot.
@@ -240,7 +240,7 @@ func TestMigrateRules(t *testing.T) {
 	// A small result and a large one.
 	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "ok")
 	// A file bigger than the limit set below.
-	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "OllamaControlCenter-big.pdf"), "0123456789")
+	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "LLMsControlDock-big.pdf"), "0123456789")
 	// A small limit.
 	maxMigrateBytes = 5
 	// A leftover temporary folder from an earlier attempt.
@@ -251,7 +251,7 @@ func TestMigrateRules(t *testing.T) {
 		t.Fatalf("messages: %q", msgs)
 	} // end of the message check
 	// The big file stayed behind.
-	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare", "OllamaControlCenter-big.pdf")); err == nil {
+	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare", "LLMsControlDock-big.pdf")); err == nil {
 		// Report the problem.
 		t.Error("a file over the limit was copied")
 	} // end of the size check
@@ -304,7 +304,7 @@ func TestStartupCopiesOldData(t *testing.T) {
 	// Build the web interface the way the program does.
 	handlerFor(t, "http://127.0.0.1:11434")
 	// The old results are now in the data folder.
-	if b, err := os.ReadFile(filepath.Join(cfg, "OllamaControlCenter", "performanceCompare", "performance.json")); err != nil || string(b) != `{"runs":[]}` {
+	if b, err := os.ReadFile(filepath.Join(cfg, "LLMsControlDock", "performanceCompare", "performance.json")); err != nil || string(b) != `{"runs":[]}` {
 		// Report the problem.
 		t.Errorf("not copied at start-up: %q, %v", b, err)
 	} // end of the copy check
@@ -395,7 +395,7 @@ func TestThreeRootsAndMoves(t *testing.T) {
 	// The three roots.
 	cfg, data, state := configRoot(), dataRoot(), stateRoot()
 	// Each has the program's own folder.
-	if cfg != filepath.Join(base, "c", "OllamaControlCenter") || data != filepath.Join(base, "d", "OllamaControlCenter") || state != filepath.Join(base, "s", "OllamaControlCenter") {
+	if cfg != filepath.Join(base, "c", "LLMsControlDock") || data != filepath.Join(base, "d", "LLMsControlDock") || state != filepath.Join(base, "s", "LLMsControlDock") {
 		// Report the problem.
 		t.Fatalf("roots: %q %q %q", cfg, data, state)
 	} // end of the roots check
diff --git a/delete_test.go b/delete_test.go
index 81bd9a4..b1f7934 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -297,7 +297,7 @@ func delRig(t *testing.T) (themeRig, *delFake, string) {
 	// The token is 32 characters.
 	tok := body[i+len(`name="token" value="`) : i+len(`name="token" value="`)+32]
 	// Hand back everything.
-	return themeRig{h: h, token: tok}, f, filepath.Join(dir, "OllamaControlCenter")
+	return themeRig{h: h, token: tok}, f, filepath.Join(dir, "LLMsControlDock")
 } // end of delRig
 
 // digestOf returns the fingerprint the fake reports for a model.
@@ -672,7 +672,7 @@ func TestDeletedStoreFile(t *testing.T) {
 		t.Errorf("path %q is not in the deletedHistory folder beside performanceCompare", got)
 	} // end of the path check
 	// With another results folder, the new folder sits beside the results file.
-	if got := deletedPathFor(filepath.Join(dir, "OllamaControlCenter", "performance.json")); got != filepath.Join(dir, "OllamaControlCenter", "deletedHistory", deletedFileName) {
+	if got := deletedPathFor(filepath.Join(dir, "LLMsControlDock", "performance.json")); got != filepath.Join(dir, "LLMsControlDock", "deletedHistory", deletedFileName) {
 		// Report it.
 		t.Errorf("path %q for the fallback folder", got)
 	} // end of the fallback check
diff --git a/desktopicon.go b/desktopicon.go
index f35db73..e85101c 100644
--- a/desktopicon.go
+++ b/desktopicon.go
@@ -35,7 +35,7 @@ var appIcon []byte
 const desktopChoiceFileName = "desktop-icon.json"
 
 // desktopFileName is the name of the launcher on the desktop.
-const desktopFileName = "OllamaControlCenter.desktop"
+const desktopFileName = "LLMsControlDock.desktop"
 
 // iconFileName is where the icon picture is kept inside the settings folder, so the launcher can point at it.
 const iconFileName = "icon.png"
@@ -197,7 +197,7 @@ func desktopFileText(exe, icon string) string {
 		// The version of the specification the file follows.
 		"Version=1.0\n" +
 		// The name shown under the icon.
-		"Name=OllamaControlCenter\n" +
+		"Name=LLMsControlDock\n" +
 		// The tooltip.
 		"Comment=Monitor and control Ollama\n" +
 		// The command: the program with the -launch option, which starts the monitor if needed and opens the page.
@@ -419,8 +419,21 @@ func (d desktopIcon) staleness() (bool, string, string) {
 	return true, old, icon
 } // end of staleness
 
-// create writes the icon picture next to the data and the launcher on the desktop, then remembers the answer.
+// create writes the icon picture next to the data and the launcher on the desktop, then remembers the answer; a launcher of the same program under its old name (before version 0.31.0) is removed afterwards, so the desktop never shows two icons.
 func (d desktopIcon) create() error {
+	// Make the launcher under the current name.
+	if err := d.createCurrent(); err != nil {
+		// Report the failure; the old launcher, if any, is left alone.
+		return err
+	} // end of the create check
+	// The new launcher is there: remove the old one (best effort; it still starts the program, so a failure is harmless).
+	d.removeLegacyLauncher()
+	// Done.
+	return nil
+} // end of create
+
+// createCurrent writes the icon picture and the launcher under the current name, then remembers the answer.
+func (d desktopIcon) createCurrent() error {
 	// A desktop must exist.
 	dir, ok := d.env.desktopDir()
 	// Refuse without one.
@@ -467,7 +480,7 @@ func (d desktopIcon) create() error {
 	d.env.trust(target)
 	// Remember the answer.
 	return d.remember("created")
-} // end of create
+} // end of createCurrent
 
 // removeFiles deletes the launcher and the picture and remembers nothing (the uninstall uses this, because remembering would re-create the settings folder).
 func (d desktopIcon) removeFiles() error {
@@ -479,6 +492,8 @@ func (d desktopIcon) removeFiles() error {
 			return err
 		} // end of the delete check
 	} // end of the launcher case
+	// A launcher left from before the rename goes too.
+	d.removeLegacyLauncher()
 	// The pictures: the PNG of the Linux launcher and the ICO of the Windows shortcut.
 	if d.iconDir() != "" {
 		// Both names; a missing file is fine.
diff --git a/desktopicon_test.go b/desktopicon_test.go
index 55f729b..49baaf2 100644
--- a/desktopicon_test.go
+++ b/desktopicon_test.go
@@ -66,7 +66,7 @@ func newFakeDesktop(t *testing.T) fakeDesktop {
 		t.Fatal(err)
 	} // end of the folder check
 	// The pretend program.
-	exe := filepath.Join(home, "OllamaControlCenter", "bin", "OllamaControlCenter")
+	exe := filepath.Join(home, "LLMsControlDock", "bin", "LLMsControlDock")
 	// Its folder.
 	if err := os.MkdirAll(filepath.Dir(exe), 0o755); err != nil {
 		// Stop.
@@ -157,9 +157,9 @@ func TestDesktopDirDetection(t *testing.T) {
 // TestDesktopFileText checks the launcher text.
 func TestDesktopFileText(t *testing.T) {
 	// Build it.
-	got := desktopFileText("/opt/occ/OllamaControlCenter", "/home/u/.config/OllamaControlCenter/icon.png")
+	got := desktopFileText("/opt/occ/LLMsControlDock", "/home/u/.config/LLMsControlDock/icon.png")
 	// The lines it must hold.
-	for _, w := range []string{"[Desktop Entry]\n", "Type=Application\n", "Name=OllamaControlCenter\n", "Exec=/opt/occ/OllamaControlCenter -launch\n", "Icon=/home/u/.config/OllamaControlCenter/icon.png\n", "Terminal=false\n"} {
+	for _, w := range []string{"[Desktop Entry]\n", "Type=Application\n", "Name=LLMsControlDock\n", "Exec=/opt/occ/LLMsControlDock -launch\n", "Icon=/home/u/.config/LLMsControlDock/icon.png\n", "Terminal=false\n"} {
 		// Look for it.
 		if !strings.Contains(got, w) {
 			// Report it.
@@ -173,7 +173,7 @@ func TestDesktopCreateAndRemove(t *testing.T) {
 	// The pretend desktop and a settings folder.
 	f := newFakeDesktop(t)
 	// The settings folder.
-	set := filepath.Join(f.home, ".config", "OllamaControlCenter")
+	set := filepath.Join(f.home, ".config", "LLMsControlDock")
 	// The manager.
 	d := desktopIcon{env: f.env, dir: set}
 	// It is available and nothing was answered yet.
@@ -247,7 +247,7 @@ func TestDesktopCreateRefusals(t *testing.T) {
 	// A pretend desktop whose program path holds a space.
 	f := newFakeDesktop(t)
 	// The settings folder.
-	set := filepath.Join(f.home, ".config", "OllamaControlCenter")
+	set := filepath.Join(f.home, ".config", "LLMsControlDock")
 	// The spaced path.
 	spaced := filepath.Join(f.home, "my programs")
 	// Make it.
@@ -309,7 +309,7 @@ func newDesktopRig(t *testing.T) *desktopRig {
 	// The pretend desktop.
 	f := newFakeDesktop(t)
 	// The settings folder inside it.
-	set := filepath.Join(f.home, ".config", "OllamaControlCenter")
+	set := filepath.Join(f.home, ".config", "LLMsControlDock")
 	// The monitor with a store there.
 	mon := newMonitorWith(openSettingsStore(set, ""))
 	// The pretend desktop.
@@ -343,7 +343,7 @@ func TestDesktopBannerAndButtons(t *testing.T) {
 	// The main page asks.
 	_, _, page := get(t, r.h, http.MethodGet, "/")
 	// The words of the banner.
-	for _, w := range []string{"Create a desktop icon for OllamaControlCenter?", "Yes, create it", "No, don't ask again", r.f.desk, r.f.exe, "Allow Launching", `action="/desktopicon"`, `<link rel="icon"`, `class="appicon"`} {
+	for _, w := range []string{"Create a desktop icon for LLMsControlDock?", "Yes, create it", "No, don't ask again", r.f.desk, r.f.exe, "Allow Launching", `action="/desktopicon"`, `<link rel="icon"`, `class="appicon"`} {
 		// Look for it.
 		if !strings.Contains(page, w) {
 			// Report it.
@@ -441,7 +441,7 @@ func TestDesktopBannerAndButtons(t *testing.T) {
 		t.Errorf("launcher not created: %v", err)
 	} // end of the launcher check
 	// The banner is gone from the main page.
-	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for OllamaControlCenter?") {
+	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for LLMsControlDock?") {
 		// Report it.
 		t.Errorf("the banner stayed after the answer")
 	} // end of the banner check
@@ -468,7 +468,7 @@ func TestDesktopBannerAndButtons(t *testing.T) {
 		t.Errorf("launcher stayed: %v", err)
 	} // end of the gone check
 	// The banner stays away.
-	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for OllamaControlCenter?") {
+	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for LLMsControlDock?") {
 		// Report it.
 		t.Errorf("the banner came back after a removal")
 	} // end of the stay-away check
@@ -496,7 +496,7 @@ func TestDesktopDeclineAndNoDesktop(t *testing.T) {
 		t.Errorf("decline created the launcher: %v", err)
 	} // end of the launcher check
 	// The banner is gone, and a new run (a new store) still remembers.
-	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for OllamaControlCenter?") {
+	if _, _, p := get(t, r.h, http.MethodGet, "/"); strings.Contains(p, "Create a desktop icon for LLMsControlDock?") {
 		// Report it.
 		t.Errorf("the banner stayed after No")
 	} // end of the banner check
@@ -531,9 +531,9 @@ func TestDesktopStaleness(t *testing.T) {
 	// The pretend desktop and the two folders.
 	f := newFakeDesktop(t)
 	// The settings folder.
-	set := filepath.Join(f.home, ".config", "OllamaControlCenter")
+	set := filepath.Join(f.home, ".config", "LLMsControlDock")
 	// The data folder, where the picture lives now.
-	data := filepath.Join(f.home, ".local", "share", "OllamaControlCenter")
+	data := filepath.Join(f.home, ".local", "share", "LLMsControlDock")
 	// The manager.
 	d := desktopIcon{env: f.env, dir: set, dataDir: data}
 	// No launcher: nothing to refresh.
diff --git a/history_test.go b/history_test.go
index 9bd460f..52d5868 100644
--- a/history_test.go
+++ b/history_test.go
@@ -316,11 +316,11 @@ func TestDefaultHistoryDir(t *testing.T) {
 	// Data and state follow the same fake folder.
 	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// A program inside bin, and one elsewhere: the same answer.
-	for _, exe := range []string{"/p/OllamaControlCenter/bin/occ", "/p/occ"} {
+	for _, exe := range []string{"/p/LLMsControlDock/bin/occ", "/p/occ"} {
 		// Use this program place.
 		executablePath = func() (string, error) { return exe, nil }
 		// The folder.
-		if d, _ := defaultHistoryDir(); d != filepath.Join("/cfg", "OllamaControlCenter", "history") {
+		if d, _ := defaultHistoryDir(); d != filepath.Join("/cfg", "LLMsControlDock", "history") {
 			// Report it.
 			t.Errorf("exe %q gave %q", exe, d)
 		} // end of the check
diff --git a/launch.go b/launch.go
index a4b496a..fad9734 100644
--- a/launch.go
+++ b/launch.go
@@ -136,7 +136,7 @@ func startMonitor(logDir string) error {
 			return err
 		} // end of the folder check
 		// The file.
-		sink = filepath.Join(logDir, "OllamaControlCenter.log")
+		sink = filepath.Join(logDir, "LLMsControlDock.log")
 		// A file that grew too big is started again.
 		if info, err := os.Stat(sink); err == nil && info.Size() > maxLogFile {
 			// Remove it.
diff --git a/launchers.go b/launchers.go
index 3cfec47..3c95e21 100644
--- a/launchers.go
+++ b/launchers.go
@@ -32,9 +32,9 @@ const icoFileName = "icon.ico"
 // The names of the launcher on each system.
 const (
 	// windowsLauncherName is a real Windows Shell Link.
-	windowsLauncherName = "OllamaControlCenter.lnk"
+	windowsLauncherName = "LLMsControlDock.lnk"
 	// macLauncherName is an application bundle.
-	macLauncherName = "OllamaControlCenter.app"
+	macLauncherName = "LLMsControlDock.app"
 ) // end of the launcher names
 
 // launcherName is the name of the launcher on the desktop of the given system.
@@ -146,7 +146,7 @@ func shQuote(s string) string {
 // macScript is the program inside the application bundle: it starts the program with -launch, which starts the monitor if needed and opens the page.
 func macScript(exe string) string {
 	// A shell script; exec replaces the shell by the program.
-	return "#!/bin/sh\n# Starts OllamaControlCenter (the monitor if needed) and opens the page in the browser.\nexec " + shQuote(exe) + " -launch\n"
+	return "#!/bin/sh\n# Starts LLMsControlDock (the monitor if needed) and opens the page in the browser.\nexec " + shQuote(exe) + " -launch\n"
 } // end of macScript
 
 // macInfoPlist is the property list that makes the folder an application bundle (Apple's standard keys).
@@ -156,10 +156,10 @@ func macInfoPlist() string {
 <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
 <plist version="1.0">
 <dict>
-	<key>CFBundleName</key><string>OllamaControlCenter</string>
-	<key>CFBundleDisplayName</key><string>OllamaControlCenter</string>
-	<key>CFBundleIdentifier</key><string>com.termgate.ollamacontrolcenter</string>
-	<key>CFBundleExecutable</key><string>OllamaControlCenter</string>
+	<key>CFBundleName</key><string>LLMsControlDock</string>
+	<key>CFBundleDisplayName</key><string>LLMsControlDock</string>
+	<key>CFBundleIdentifier</key><string>com.termgate.llmscontroldock</string>
+	<key>CFBundleExecutable</key><string>LLMsControlDock</string>
 	<key>CFBundlePackageType</key><string>APPL</string>
 	<key>CFBundleIconFile</key><string>icon</string>
 	<key>CFBundleShortVersionString</key><string>` + appVersion + `</string>
@@ -308,7 +308,7 @@ func (d desktopIcon) createMac(dir string) error {
 		// The icon.
 		{"Contents/Resources/icon.icns", icns, 0o644},
 		// The script; it is named like CFBundleExecutable.
-		{"Contents/MacOS/OllamaControlCenter", []byte(macScript(exe)), 0o755},
+		{"Contents/MacOS/LLMsControlDock", []byte(macScript(exe)), 0o755},
 	} { // end of the file list
 		// Write it.
 		if err := os.WriteFile(filepath.Join(app, filepath.FromSlash(f.path)), f.data, f.mode); err != nil {
@@ -328,7 +328,7 @@ func (d desktopIcon) createMac(dir string) error {
 // removeLauncher deletes the launcher on the desktop; a missing one is fine, and a bundle is removed only when it carries the program's own name.
 func removeLauncher(path string) error {
 	// A bundle is a folder.
-	if filepath.Base(path) == macLauncherName {
+	if base := filepath.Base(path); base == macLauncherName || base == legacyMacLauncherName {
 		// Delete it with everything in it.
 		return os.RemoveAll(path)
 	} // end of the bundle case
diff --git a/launchers_test.go b/launchers_test.go
index 479087c..7662fa7 100644
--- a/launchers_test.go
+++ b/launchers_test.go
@@ -324,7 +324,7 @@ func TestCreateMacBundle(t *testing.T) {
 		t.Fatal(err)
 	} // end of the read check
 	// The keys.
-	for _, want := range []string{"<key>CFBundleExecutable</key><string>OllamaControlCenter</string>", "<key>CFBundlePackageType</key><string>APPL</string>", "<key>CFBundleIconFile</key><string>icon</string>", "<string>" + appVersion + "</string>", "com.termgate.ollamacontrolcenter"} {
+	for _, want := range []string{"<key>CFBundleExecutable</key><string>LLMsControlDock</string>", "<key>CFBundlePackageType</key><string>APPL</string>", "<key>CFBundleIconFile</key><string>icon</string>", "<string>" + appVersion + "</string>", "com.termgate.llmscontroldock"} {
 		// Each must be there.
 		if !strings.Contains(string(plist), want) {
 			// Report it.
@@ -332,7 +332,7 @@ func TestCreateMacBundle(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 	// The script holds the quoted program path.
-	script, err := os.ReadFile(filepath.Join(app, "Contents", "MacOS", "OllamaControlCenter"))
+	script, err := os.ReadFile(filepath.Join(app, "Contents", "MacOS", "LLMsControlDock"))
 	// It must exist.
 	if err != nil || string(script) != macScript(r.exe) {
 		// Report it.
@@ -344,7 +344,7 @@ func TestCreateMacBundle(t *testing.T) {
 		t.Errorf("icon: %v", err)
 	} // end of the icon check
 	// The script is executable (Windows has no such bit).
-	if st, err := os.Stat(filepath.Join(app, "Contents", "MacOS", "OllamaControlCenter")); err != nil || (modesApply() && st.Mode().Perm() != 0o755) {
+	if st, err := os.Stat(filepath.Join(app, "Contents", "MacOS", "LLMsControlDock")); err != nil || (modesApply() && st.Mode().Perm() != 0o755) {
 		// Report it.
 		t.Errorf("script mode: %v %v", st, err)
 	} // end of the mode check
@@ -392,7 +392,7 @@ func TestMacScriptRuns(t *testing.T) {
 		t.Fatal(err)
 	} // end of the create check
 	// Run its script.
-	if err := exec.Command(filepath.Join(r.desk, macLauncherName, "Contents", "MacOS", "OllamaControlCenter")).Run(); err != nil {
+	if err := exec.Command(filepath.Join(r.desk, macLauncherName, "Contents", "MacOS", "LLMsControlDock")).Run(); err != nil {
 		// Stop.
 		t.Fatal(err)
 	} // end of the run check
diff --git a/legacyname.go b/legacyname.go
new file mode 100644
index 0000000..e78685b
--- /dev/null
+++ b/legacyname.go
@@ -0,0 +1,156 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+// Imports: the standard library only.
+import (
+	// fmt builds the sentences for the log.
+	"fmt"
+	// os renames folders and looks at files.
+	"os"
+	// path/filepath joins folder and file names.
+	"path/filepath"
+) // end of imports
+
+// Before version 0.31.0 the program was called OllamaControlCenter. These are the names it used on a computer; this file renames them once, so nobody loses saved data or keeps two desktop icons.
+const (
+	// legacyAppName is the old program name; it was also the name of the program's own folder inside the config, data and state base folders.
+	legacyAppName = "OllamaControlCenter"
+	// legacyDesktopFileName is the old Linux desktop launcher.
+	legacyDesktopFileName = "OllamaControlCenter.desktop"
+	// legacyWindowsLauncherName is the old Windows shortcut.
+	legacyWindowsLauncherName = "OllamaControlCenter.lnk"
+	// legacyMacLauncherName is the old macOS application bundle.
+	legacyMacLauncherName = "OllamaControlCenter.app"
+) // end of the old names
+
+// renameLegacyRoot renames one old program folder to the new name, once: nothing happens when the old folder is missing or is not a plain folder (a link is never followed), and the new folder is never touched when it exists already. It returns a sentence for the log, or empty text.
+func renameLegacyRoot(oldDir, newDir string) string {
+	// Look at the old folder without following a link.
+	st, err := os.Lstat(oldDir)
+	// Missing, a link, or not a folder: nothing to do.
+	if err != nil || !st.IsDir() {
+		// Nothing to do.
+		return ""
+	} // end of the old-folder check
+	// Does the new folder exist already?
+	if _, err := os.Lstat(newDir); err == nil {
+		// Both exist: nothing is moved, and the person is told where the old data is.
+		return fmt.Sprintf("An older folder %s was found next to %s and was left untouched; saved data from before the rename to LLMsControlDock is still in it.", oldDir, newDir)
+	} // end of the new-folder check
+	// Rename in one step; both folders are inside the same base folder, so this is a move, not a copy.
+	if err := os.Rename(oldDir, newDir); err != nil {
+		// Say so; the data stays where it is.
+		return fmt.Sprintf("The folder %s could not be renamed to %s (%v); the saved data was left where it is.", oldDir, newDir, err)
+	} // end of the rename check
+	// Done: tell the person.
+	return fmt.Sprintf("The program is now called LLMsControlDock: its folder %s was renamed to %s; nothing was lost.", oldDir, newDir)
+} // end of renameLegacyRoot
+
+// migrateLegacyRoots renames the old settings, data and state folders to the new name, once; on macOS the three are the same folder and it is renamed once. It returns the sentences for the log.
+func migrateLegacyRoots() []string {
+	// The sentences.
+	var msgs []string
+	// The folders already handled (macOS has one folder for all three kinds).
+	seen := map[string]bool{}
+	// The three new folders.
+	for _, root := range []string{configRoot(), dataRoot(), stateRoot()} {
+		// An unknown folder, or one handled already: skip.
+		if root == "" || seen[root] {
+			// Next folder.
+			continue
+		} // end of the skip check
+		// Remember it.
+		seen[root] = true
+		// The old folder sits next to the new one, inside the same base folder.
+		old := filepath.Join(filepath.Dir(root), legacyAppName)
+		// Rename it.
+		if msg := renameLegacyRoot(old, root); msg != "" {
+			// Keep the sentence.
+			msgs = append(msgs, msg)
+		} // end of the message check
+	} // end of the folder loop
+	// Hand them back.
+	return msgs
+} // end of migrateLegacyRoots
+
+// legacyLauncherPath is the full path of the old launcher on the desktop ("" when there is no desktop).
+func (d desktopIcon) legacyLauncherPath() string {
+	// The desktop folder.
+	dir, ok := d.env.desktopDir()
+	// None.
+	if !ok {
+		// No path.
+		return ""
+	} // end of the desktop check
+	// The old name for this system.
+	name := legacyDesktopFileName
+	// Windows and macOS had their own kinds.
+	switch d.env.goos {
+	// A shortcut.
+	case "windows":
+		// Its name.
+		name = legacyWindowsLauncherName
+	// An application bundle.
+	case "darwin":
+		// Its name.
+		name = legacyMacLauncherName
+	} // end of the system switch
+	// The path.
+	return filepath.Join(dir, name)
+} // end of legacyLauncherPath
+
+// legacyLauncherExists says whether the old launcher is on the desktop now.
+func (d desktopIcon) legacyLauncherExists() bool {
+	// Its path.
+	p := d.legacyLauncherPath()
+	// No desktop, no launcher.
+	if p == "" {
+		// Not there.
+		return false
+	} // end of the path check
+	// A plain existence check.
+	_, err := os.Lstat(p)
+	// There when the check worked.
+	return err == nil
+} // end of legacyLauncherExists
+
+// removeLegacyLauncher deletes the old launcher if it is there; it is best effort, because the old launcher still starts the program, so a failure does no harm.
+func (d desktopIcon) removeLegacyLauncher() {
+	// Its path.
+	p := d.legacyLauncherPath()
+	// No desktop: nothing to remove.
+	if p == "" {
+		// Done.
+		return
+	} // end of the path check
+	// Delete it; the result is ignored on purpose (see above).
+	_ = removeLauncher(p)
+} // end of removeLegacyLauncher
+
+// migrateLegacyLauncher replaces an old launcher by one with the new name, but only for someone who chose to have a desktop icon: when the old launcher is there and the new one is not, the new one is made (which removes the old one); when both are there, the old one is removed. It returns a sentence for the log, or empty text.
+func migrateLegacyLauncher(d desktopIcon) string {
+	// Without a desktop there is nothing to do.
+	if !d.available() || !d.legacyLauncherExists() {
+		// Nothing to do.
+		return ""
+	} // end of the presence check
+	// Both launchers exist: the old one is a duplicate.
+	if d.exists() {
+		// Remove the duplicate.
+		d.removeLegacyLauncher()
+		// Tell the person.
+		return "The desktop icon under the old name OllamaControlCenter was removed; the LLMsControlDock icon stays."
+	} // end of the duplicate case
+	// Only someone who chose an icon gets a new one; the old file is left alone for everyone else.
+	if d.choice() != "created" {
+		// Nothing to do.
+		return ""
+	} // end of the choice check
+	// Make the new launcher (this also removes the old one).
+	if err := d.create(); err != nil {
+		// Say so; the old launcher still works.
+		return fmt.Sprintf("The desktop icon could not be renamed to LLMsControlDock (%v); the old icon still works.", err)
+	} // end of the create check
+	// Done.
+	return "The desktop icon was renamed to LLMsControlDock."
+} // end of migrateLegacyLauncher
diff --git a/legacyname_test.go b/legacyname_test.go
new file mode 100644
index 0000000..9988ccc
--- /dev/null
+++ b/legacyname_test.go
@@ -0,0 +1,343 @@
+// Package main tells Go that this test file belongs to the same program as legacyname.go.
+package main
+
+// Imports: the standard library only.
+import (
+	// os reads and writes the folders of the tests.
+	"os"
+	// path/filepath joins file names.
+	"path/filepath"
+	// runtime tells which system the test runs on.
+	"runtime"
+	// strings searches the log sentences.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// pointFoldersAt makes the program use three pretend base folders (config, data, state) for one test and puts the real lookups back afterwards; it returns the three base folders.
+func pointFoldersAt(t *testing.T) (cfg, data, state string) {
+	// Mark this as a helper.
+	t.Helper()
+	// Three separate temporary base folders.
+	cfg, data, state = t.TempDir(), t.TempDir(), t.TempDir()
+	// Keep the real lookups.
+	oc, od, os2 := userConfigDir, userDataDir, userStateDir
+	// Put them back at the end.
+	t.Cleanup(func() { userConfigDir, userDataDir, userStateDir = oc, od, os2 })
+	// The pretend lookups.
+	userConfigDir = func() (string, error) { return cfg, nil }
+	userDataDir = func() (string, error) { return data, nil }
+	userStateDir = func() (string, error) { return state, nil }
+	// Hand the folders back.
+	return cfg, data, state
+} // end of pointFoldersAt
+
+// TestMigrateLegacyRootsRenamesAllThree checks that the old settings, data and state folders get the new name with their content, and that a second start changes nothing.
+func TestMigrateLegacyRootsRenamesAllThree(t *testing.T) {
+	// Three pretend base folders.
+	cfg, data, state := pointFoldersAt(t)
+	// An old folder with one file in each.
+	for _, base := range []string{cfg, data, state} {
+		// The file keeps the base folder's name inside, to tell them apart.
+		writeTestFile(t, filepath.Join(base, legacyAppName, "keep.json"), filepath.Base(base))
+	} // end of the fixture loop
+	// First start after the rename.
+	msgs := migrateLegacyRoots()
+	// One sentence per folder.
+	if len(msgs) != 3 {
+		// Report.
+		t.Fatalf("want 3 sentences, got %d: %v", len(msgs), msgs)
+	} // end of the count check
+	// Each folder now has the new name and its own file; the old name is gone.
+	for _, base := range []string{cfg, data, state} {
+		// The file inside the new folder.
+		got, err := os.ReadFile(filepath.Join(base, dataFolderName, "keep.json"))
+		// It must be there with the right content.
+		if err != nil || string(got) != filepath.Base(base) {
+			// Report.
+			t.Errorf("%s: new folder lost the file (%v, %q)", base, err, got)
+		} // end of the content check
+		// The old folder must be gone.
+		if _, err := os.Lstat(filepath.Join(base, legacyAppName)); err == nil {
+			// Report.
+			t.Errorf("%s: the old folder is still there", base)
+		} // end of the old-folder check
+	} // end of the check loop
+	// A second start finds nothing to do.
+	if again := migrateLegacyRoots(); len(again) != 0 {
+		// Report.
+		t.Errorf("second start must be silent, got %v", again)
+	} // end of the repeat check
+} // end of TestMigrateLegacyRootsRenamesAllThree
+
+// TestMigrateLegacyRootsSameFolderOnce checks the macOS case: one folder for all three kinds is renamed once, without a complaint about itself.
+func TestMigrateLegacyRootsSameFolderOnce(t *testing.T) {
+	// Three pretend base folders, then all three pointed at the first.
+	cfg, _, _ := pointFoldersAt(t)
+	// One shared base.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
+	// The old folder.
+	writeTestFile(t, filepath.Join(cfg, legacyAppName, "keep.json"), "x")
+	// Rename.
+	msgs := migrateLegacyRoots()
+	// Exactly one sentence, and it is the success one.
+	if len(msgs) != 1 || strings.Contains(msgs[0], "untouched") || strings.Contains(msgs[0], "could not") {
+		// Report.
+		t.Fatalf("want one success sentence, got %v", msgs)
+	} // end of the sentence check
+	// The file is in the new folder.
+	if _, err := os.Stat(filepath.Join(cfg, dataFolderName, "keep.json")); err != nil {
+		// Report.
+		t.Errorf("file missing after rename: %v", err)
+	} // end of the file check
+} // end of TestMigrateLegacyRootsSameFolderOnce
+
+// TestRenameLegacyRootRules checks the refusals: no old folder, both folders present, and an old name that is a link.
+func TestRenameLegacyRootRules(t *testing.T) {
+	// A pretend base.
+	base := t.TempDir()
+	// No old folder: silent.
+	if msg := renameLegacyRoot(filepath.Join(base, "old"), filepath.Join(base, "new")); msg != "" {
+		// Report.
+		t.Errorf("missing old folder must be silent, got %q", msg)
+	} // end of the missing check
+	// Both folders exist: nothing moves and the sentence names both.
+	writeTestFile(t, filepath.Join(base, "old2", "a.json"), "old")
+	// The new one.
+	writeTestFile(t, filepath.Join(base, "new2", "b.json"), "new")
+	// Ask.
+	msg := renameLegacyRoot(filepath.Join(base, "old2"), filepath.Join(base, "new2"))
+	// The sentence says the old folder was left untouched.
+	if !strings.Contains(msg, "untouched") {
+		// Report.
+		t.Errorf("both folders: want the untouched sentence, got %q", msg)
+	} // end of the sentence check
+	// Both are still as they were.
+	if _, err := os.Stat(filepath.Join(base, "old2", "a.json")); err != nil {
+		// Report.
+		t.Errorf("old folder was changed: %v", err)
+	} // end of the old check
+	// The new one holds only its own file.
+	if _, err := os.Stat(filepath.Join(base, "new2", "a.json")); err == nil {
+		// Report.
+		t.Error("the old file was moved into an existing new folder")
+	} // end of the new check
+	// A link is never followed (links need extra rights on Windows).
+	if runtime.GOOS != "windows" {
+		// A real folder elsewhere and a link to it with the old name.
+		target := filepath.Join(base, "elsewhere")
+		// Make the target.
+		writeTestFile(t, filepath.Join(target, "c.json"), "x")
+		// The link.
+		if err := os.Symlink(target, filepath.Join(base, "old3")); err != nil {
+			// The fixture failed.
+			t.Fatal(err)
+		} // end of the link check
+		// Ask.
+		if msg := renameLegacyRoot(filepath.Join(base, "old3"), filepath.Join(base, "new3")); msg != "" {
+			// Report.
+			t.Errorf("a link must be ignored, got %q", msg)
+		} // end of the ignore check
+		// The new name was not created.
+		if _, err := os.Lstat(filepath.Join(base, "new3")); err == nil {
+			// Report.
+			t.Error("a link was renamed")
+		} // end of the creation check
+	} // end of the link case
+} // end of TestRenameLegacyRootRules
+
+// TestOllamaFromEnv checks the new variable first, the old one as a fallback, and nothing when neither is set.
+func TestOllamaFromEnv(t *testing.T) {
+	// A pretend environment.
+	env := func(m map[string]string) func(string) string {
+		// The lookup.
+		return func(k string) string { return m[k] }
+	} // end of env
+	// Both set: the new name wins.
+	if got := ollamaFromEnv(env(map[string]string{envOllamaURL: "http://new:1", envOllamaURLOld: "http://old:2"})); got != "http://new:1" {
+		// Report.
+		t.Errorf("both set: got %q", got)
+	} // end of the both case
+	// Only the old name: it still works.
+	if got := ollamaFromEnv(env(map[string]string{envOllamaURLOld: "http://old:2"})); got != "http://old:2" {
+		// Report.
+		t.Errorf("old only: got %q", got)
+	} // end of the old case
+	// Neither: empty.
+	if got := ollamaFromEnv(env(nil)); got != "" {
+		// Report.
+		t.Errorf("none: got %q", got)
+	} // end of the none case
+	// The two names are what the documents say.
+	if envOllamaURL != "LLMSCONTROLDOCK_OLLAMA_URL" || envOllamaURLOld != "OCC_OLLAMA_URL" {
+		// Report.
+		t.Errorf("variable names changed: %s %s", envOllamaURL, envOllamaURLOld)
+	} // end of the name check
+} // end of TestOllamaFromEnv
+
+// TestLooksOursKnowsBothPrefixes checks that saved copies made before the rename are still recognised.
+func TestLooksOursKnowsBothPrefixes(t *testing.T) {
+	// Both prefixes, a CSV and a PDF.
+	for _, name := range []string{"LLMsControlDock-comparison-20261102.pdf", "OllamaControlCenter-comparison-20261102.csv"} {
+		// Recognised.
+		if !looksOurs(name) {
+			// Report.
+			t.Errorf("%s should be recognised", name)
+		} // end of the check
+	} // end of the loop
+	// Somebody else's file is not.
+	if looksOurs("OllamaControlCenter-notes.txt") {
+		// Report.
+		t.Error("a text file must not be recognised")
+	} // end of the stranger check
+} // end of TestLooksOursKnowsBothPrefixes
+
+// legacyIcon builds a desktopIcon on the pretend desktop and puts an old-named launcher on it; it returns the icon and the old launcher's path.
+func legacyIcon(t *testing.T) (desktopIcon, fakeDesktop, string) {
+	// Mark this as a helper.
+	t.Helper()
+	// The pretend desktop (skipped on Windows).
+	f := newFakeDesktop(t)
+	// A pretend settings folder.
+	d := desktopIcon{env: f.env, dir: t.TempDir(), dataDir: t.TempDir()}
+	// The old launcher.
+	old := filepath.Join(f.desk, legacyDesktopFileName)
+	// Write it.
+	writeTestFile(t, old, "[Desktop Entry]\nName=OllamaControlCenter\n")
+	// Hand everything back.
+	return d, f, old
+} // end of legacyIcon
+
+// TestMigrateLegacyLauncherReplacesForSomeoneWhoChoseAnIcon checks that the old icon becomes a new one, and the old one is gone.
+func TestMigrateLegacyLauncherReplacesForSomeoneWhoChoseAnIcon(t *testing.T) {
+	// The setup.
+	d, f, old := legacyIcon(t)
+	// The person had chosen an icon.
+	if err := d.remember("created"); err != nil {
+		// The fixture failed.
+		t.Fatal(err)
+	} // end of the choice check
+	// Migrate.
+	msg := migrateLegacyLauncher(d)
+	// The sentence says it was renamed.
+	if !strings.Contains(msg, "renamed to LLMsControlDock") {
+		// Report.
+		t.Errorf("sentence: %q", msg)
+	} // end of the sentence check
+	// The new launcher is there, the old one is gone.
+	if _, err := os.Stat(filepath.Join(f.desk, desktopFileName)); err != nil {
+		// Report.
+		t.Errorf("new launcher missing: %v", err)
+	} // end of the new check
+	// The old one.
+	if _, err := os.Lstat(old); err == nil {
+		// Report.
+		t.Error("old launcher still there")
+	} // end of the old check
+	// The new launcher starts the running program under its new name.
+	got, err := os.ReadFile(filepath.Join(f.desk, desktopFileName))
+	// It must be readable and name the program.
+	if err != nil || !strings.Contains(string(got), "LLMsControlDock") || strings.Contains(string(got), "OllamaControlCenter") {
+		// Report.
+		t.Errorf("new launcher text: %v %q", err, got)
+	} // end of the text check
+	// A second start is silent.
+	if again := migrateLegacyLauncher(d); again != "" {
+		// Report.
+		t.Errorf("second start must be silent, got %q", again)
+	} // end of the repeat check
+} // end of TestMigrateLegacyLauncherReplacesForSomeoneWhoChoseAnIcon
+
+// TestMigrateLegacyLauncherLeavesOthersAlone checks that someone who never chose an icon keeps the old file untouched and gets no new one.
+func TestMigrateLegacyLauncherLeavesOthersAlone(t *testing.T) {
+	// The setup, with no remembered choice.
+	d, f, old := legacyIcon(t)
+	// Migrate.
+	if msg := migrateLegacyLauncher(d); msg != "" {
+		// Report.
+		t.Errorf("sentence: %q", msg)
+	} // end of the sentence check
+	// The old launcher is still there.
+	if _, err := os.Stat(old); err != nil {
+		// Report.
+		t.Errorf("old launcher was touched: %v", err)
+	} // end of the old check
+	// No new one was made.
+	if _, err := os.Stat(filepath.Join(f.desk, desktopFileName)); err == nil {
+		// Report.
+		t.Error("a new launcher was made without a choice")
+	} // end of the new check
+} // end of TestMigrateLegacyLauncherLeavesOthersAlone
+
+// TestMigrateLegacyLauncherRemovesDuplicate checks that when both launchers exist, only the old one goes.
+func TestMigrateLegacyLauncherRemovesDuplicate(t *testing.T) {
+	// The setup.
+	d, f, old := legacyIcon(t)
+	// Make the new launcher too.
+	writeTestFile(t, filepath.Join(f.desk, desktopFileName), "new")
+	// Migrate.
+	msg := migrateLegacyLauncher(d)
+	// The sentence says the old one was removed.
+	if !strings.Contains(msg, "removed") {
+		// Report.
+		t.Errorf("sentence: %q", msg)
+	} // end of the sentence check
+	// The old one is gone.
+	if _, err := os.Lstat(old); err == nil {
+		// Report.
+		t.Error("old launcher still there")
+	} // end of the old check
+	// The new one is untouched.
+	if got, _ := os.ReadFile(filepath.Join(f.desk, desktopFileName)); string(got) != "new" {
+		// Report.
+		t.Errorf("new launcher changed: %q", got)
+	} // end of the new check
+} // end of TestMigrateLegacyLauncherRemovesDuplicate
+
+// TestUninstallAlsoRemovesTheOldLauncher checks that removing the icon files leaves no old-named launcher behind.
+func TestUninstallAlsoRemovesTheOldLauncher(t *testing.T) {
+	// The setup.
+	d, _, old := legacyIcon(t)
+	// Remove everything the icon owns.
+	if err := d.removeFiles(); err != nil {
+		// Report.
+		t.Fatal(err)
+	} // end of the remove check
+	// The old launcher is gone.
+	if _, err := os.Lstat(old); err == nil {
+		// Report.
+		t.Error("old launcher survived the uninstall")
+	} // end of the old check
+} // end of TestUninstallAlsoRemovesTheOldLauncher
+
+// TestRemoveLauncherKnowsTheOldBundle checks that a macOS bundle with the old name is removed as a whole folder, and a bundle with another name is not.
+func TestRemoveLauncherKnowsTheOldBundle(t *testing.T) {
+	// A pretend desktop folder.
+	base := t.TempDir()
+	// An old bundle with a file inside.
+	old := filepath.Join(base, legacyMacLauncherName)
+	// Make it.
+	writeTestFile(t, filepath.Join(old, "Contents", "x"), "x")
+	// Remove it.
+	if err := removeLauncher(old); err != nil {
+		// Report.
+		t.Fatal(err)
+	} // end of the remove check
+	// It is gone as a whole.
+	if _, err := os.Lstat(old); err == nil {
+		// Report.
+		t.Error("old bundle was not removed")
+	} // end of the gone check
+	// Somebody else's folder with another name is not removed as a bundle (removing a folder with os.Remove fails because it is not empty).
+	other := filepath.Join(base, "Other.app")
+	// Make it.
+	writeTestFile(t, filepath.Join(other, "Contents", "x"), "x")
+	// Try; the call fails or does nothing, and the content survives.
+	_ = removeLauncher(other)
+	// Still there.
+	if _, err := os.Stat(filepath.Join(other, "Contents", "x")); err != nil {
+		// Report.
+		t.Errorf("a foreign folder was removed: %v", err)
+	} // end of the survive check
+} // end of TestRemoveLauncherKnowsTheOldBundle
diff --git a/library.go b/library.go
index 8d19551..93837fd 100644
--- a/library.go
+++ b/library.go
@@ -122,7 +122,7 @@ func checkLibrary(ctx context.Context, name, have string) string {
 	// Ask for the manifest in the format Ollama itself uses.
 	req.Header.Set("Accept", "application/vnd.docker.distribution.manifest.v2+json")
 	// Say who is asking.
-	req.Header.Set("User-Agent", "OllamaControlCenter")
+	req.Header.Set("User-Agent", "LLMsControlDock")
 	// Send it.
 	resp, err := http.DefaultClient.Do(req)
 	// No answer: no internet, or the library is down.
diff --git a/main.go b/main.go
index f2a6d4f..662e97e 100644
--- a/main.go
+++ b/main.go
@@ -114,7 +114,7 @@ func main() {
 	// Define a -listen option: its name, its default value, and the help text shown by -h.
 	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
 	// Define an -ollama-url option; empty means "not given", so the environment variable or the default is used.
-	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the OCC_OLLAMA_URL environment variable (default http://127.0.0.1:11434)")
+	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the LLMSCONTROLDOCK_OLLAMA_URL environment variable, or the older OCC_OLLAMA_URL (default http://127.0.0.1:11434)")
 	// Define a -launch switch: what a double-click on the desktop icon runs; it opens the page and starts the monitor first when it is not running.
 	launchFlag := flag.Bool("launch", false, "open the monitor page in the browser, starting the monitor in the background first when it is not running (this is what the desktop icon runs)")
 	// Define a -check switch: false unless given on the command line.
@@ -149,6 +149,11 @@ func main() {
 	} // end of the links mode
 
 	// Choose the Ollama address by precedence: option, then environment variable, then default.
+	// Before version 0.31.0 the program had another name (see legacyname.go) and its three folders carried it; rename them once, before anything reads or creates a folder, so the saved settings, results and history are found.
+	for _, msg := range migrateLegacyRoots() {
+		// Say so in the log.
+		log.Print(msg)
+	} // end of the rename loop
 	// The saved settings are read first (a damaged file is ignored with a note).
 	dir, dirNote := settingsFolder()
 	// Version 0.25.0 kept the check history and the icon picture in the configuration folder; copy them once to the state and data folders (the old files are left in place).
@@ -166,7 +171,7 @@ func main() {
 		log.Print(n)
 	} // end of the note check
 	// The address: option, then environment variable, then saved setting, then default.
-	addr, err := resolveWithSaved(*ollamaFlag, os.Getenv(envOllamaURL), store.get().OllamaURL)
+	addr, err := resolveWithSaved(*ollamaFlag, ollamaFromEnv(os.Getenv), store.get().OllamaURL)
 	// If the address is unusable, stop with a clear message and a failure exit code.
 	if err != nil {
 		// log.Fatalf prints the message and exits with code 1.
@@ -230,7 +235,7 @@ func main() {
 		os.Exit(1)
 	} // end of the listen check
 	// Tell the person which address we are about to serve on.
-	log.Printf("OllamaControlCenter listening on http://%s (from %s; press Ctrl+C to stop)", listenAddr, listenSource)
+	log.Printf("LLMsControlDock listening on http://%s (from %s; press Ctrl+C to stop)", listenAddr, listenSource)
 	// Closed when the shutdown that the Stop button started has finished.
 	stopped := make(chan struct{})
 	// The last step of every stop (the Stop button, Ctrl+C, a termination request): shut the web server down, waiting at most 5 seconds for requests that are still running; onceStop makes it run only the first time it is asked.
@@ -264,7 +269,7 @@ func main() {
 		// Wait until the shutdown has finished.
 		<-stopped
 		// Say why the program ends: from its page, or by Ctrl+C or a termination request.
-		log.Printf("OllamaControlCenter stopped %s", currentStopReason())
+		log.Printf("LLMsControlDock stopped %s", currentStopReason())
 		// Leave with the success code.
 		return
 	} // end of the normal stop
diff --git a/pdf.go b/pdf.go
index 9957884..c3eccfa 100644
--- a/pdf.go
+++ b/pdf.go
@@ -334,7 +334,7 @@ func (d *pdfDoc) bytes() []byte {
 	// Object 4: the bold font.
 	obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
 	// Object 5: the document information.
-	obj(fmt.Sprintf("<< /Title (%s) /Subject (%s) /Producer (OllamaControlCenter %s) /Creator (OllamaControlCenter) /CreationDate (D:%s) >>", pdfEscape(d.title), pdfEscape(d.subject), appVersion, d.created.Format("20060102150405Z0700")))
+	obj(fmt.Sprintf("<< /Title (%s) /Subject (%s) /Producer (LLMsControlDock %s) /Creator (LLMsControlDock) /CreationDate (D:%s) >>", pdfEscape(d.title), pdfEscape(d.subject), appVersion, d.created.Format("20060102150405Z0700")))
 	// Each page and its content.
 	for i, page := range d.pages {
 		// The footer on this page.
diff --git a/pdf_test.go b/pdf_test.go
index 36588e0..59e2076 100644
--- a/pdf_test.go
+++ b/pdf_test.go
@@ -384,7 +384,7 @@ func TestPDFStructureAndPaging(t *testing.T) {
 		last = at
 	} // end of the loop
 	// The properties are in the file, with the brackets escaped.
-	if !bytes.Contains(data, []byte(`/Title (Title \(with brackets\))`)) || !bytes.Contains(data, []byte("/CreationDate (D:20261027193005Z)")) || !bytes.Contains(data, []byte("/Producer (OllamaControlCenter "+appVersion+")")) {
+	if !bytes.Contains(data, []byte(`/Title (Title \(with brackets\))`)) || !bytes.Contains(data, []byte("/CreationDate (D:20261027193005Z)")) || !bytes.Contains(data, []byte("/Producer (LLMsControlDock "+appVersion+")")) {
 		// Report it.
 		t.Errorf("document information wrong")
 	} // end of the information check
diff --git a/perf_test.go b/perf_test.go
index 3c7e246..81ef129 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -328,7 +328,7 @@ func perfRig(t *testing.T, f *perfFake) (themeRig, string) {
 	// The token is 32 characters after the marker.
 	tok := body[i+len(`name="token" value="`) : i+len(`name="token" value="`)+32]
 	// Hand back the rig and the file path.
-	return themeRig{h: h, token: tok}, filepath.Join(dir, "OllamaControlCenter", "performanceCompare", "performance.json")
+	return themeRig{h: h, token: tok}, filepath.Join(dir, "LLMsControlDock", "performanceCompare", "performance.json")
 } // end of perfRig
 
 // perfPost sends a form to a performance route as the page's own form would.
@@ -1099,13 +1099,13 @@ func TestDefaultHistoryPath(t *testing.T) {
 	// Data and state follow the same fake folder.
 	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// Wherever the program is, the answer is the same.
-	for _, exe := range []string{"/home/u/OllamaControlCenter/bin/OllamaControlCenter", "/opt/occ/OllamaControlCenter", ""} {
+	for _, exe := range []string{"/home/u/LLMsControlDock/bin/LLMsControlDock", "/opt/occ/LLMsControlDock", ""} {
 		// Use this program place.
 		executablePath = func() (string, error) { return exe, nil }
 		// Ask.
 		got, note := defaultHistoryPath()
 		// Compare.
-		if filepath.ToSlash(got) != "/cfg/OllamaControlCenter/performanceCompare/performance.json" || note != "" {
+		if filepath.ToSlash(got) != "/cfg/LLMsControlDock/performanceCompare/performance.json" || note != "" {
 			// Report it.
 			t.Errorf("exe %q: path %q note %q", exe, got, note)
 		} // end of the check
diff --git a/perfstore_rename_test.go b/perfstore_rename_test.go
index 854b163..159a899 100644
--- a/perfstore_rename_test.go
+++ b/perfstore_rename_test.go
@@ -31,7 +31,7 @@ func TestOldResultsFolderIsRenamed(t *testing.T) {
 		t.Fatal(err)
 	} // end of the folder check
 	// Its files.
-	for _, f := range []string{"performance.json", "OllamaControlCenter-comparison-1.pdf"} {
+	for _, f := range []string{"performance.json", "LLMsControlDock-comparison-1.pdf"} {
 		// Write one.
 		if err := os.WriteFile(filepath.Join(old, f), []byte(f), 0o600); err != nil {
 			// Stop the test.
@@ -44,7 +44,7 @@ func TestOldResultsFolderIsRenamed(t *testing.T) {
 		t.Fatalf("message %q", msg)
 	} // end of the rename check
 	// The files are under the new name.
-	for _, f := range []string{"performance.json", "OllamaControlCenter-comparison-1.pdf"} {
+	for _, f := range []string{"performance.json", "LLMsControlDock-comparison-1.pdf"} {
 		// Read one.
 		if b, err := os.ReadFile(filepath.Join(root, historyFolderName, f)); err != nil || string(b) != f {
 			// Report it.
@@ -92,7 +92,7 @@ func TestOldResultsFolderIsRenamed(t *testing.T) {
 		} // end of the two-folders check
 	} // end of the old folder
 	// A fallback folder is never touched.
-	if msg := moveOldHistoryFolder(filepath.Join(root, "OllamaControlCenter", "performance.json")); msg != "" {
+	if msg := moveOldHistoryFolder(filepath.Join(root, "LLMsControlDock", "performance.json")); msg != "" {
 		// Report it.
 		t.Errorf("message %q for a fallback folder", msg)
 	} // end of the fallback check
diff --git a/portbusy.go b/portbusy.go
index 176593c..ba44861 100644
--- a/portbusy.go
+++ b/portbusy.go
@@ -28,7 +28,7 @@ func isAddrInUse(err error) bool {
 	return errors.Is(err, syscall.EADDRINUSE) || errors.Is(err, syscall.Errno(10048))
 } // end of isAddrInUse
 
-// probeIsOurs asks whatever answers at the address whether it is an OllamaControlCenter monitor: its read-only About page always answers and names the program. A test replaces it.
+// probeIsOurs asks whatever answers at the address whether it is an LLMsControlDock monitor: its read-only About page always answers and names the program. A test replaces it.
 var probeIsOurs = func(url string) bool {
 	// A short time limit: this runs while the program is leaving anyway.
 	c := &http.Client{Timeout: 2 * time.Second}
@@ -48,8 +48,8 @@ var probeIsOurs = func(url string) bool {
 	} // end of the status check
 	// Read the first 64 KB; the name is in the page title.
 	body, _ := io.ReadAll(io.LimitReader(res.Body, 64*1024))
-	// Ours when the page names the program.
-	return strings.Contains(string(body), "OllamaControlCenter")
+	// Ours when the page names the program, under its present name or the one it had before version 0.31.0 (an older copy may still be running during an upgrade).
+	return strings.Contains(string(body), "LLMsControlDock") || strings.Contains(string(body), legacyAppName)
 } // end of probeIsOurs
 
 // nextPortAddress suggests the same address with the next port number, or the empty text when the address cannot be read.
@@ -77,7 +77,7 @@ func listenFailureMessage(listen string, err error) string {
 	// Another reason than a busy port: say it as it is.
 	if !isAddrInUse(err) {
 		// The real reason follows.
-		return fmt.Sprintf("OllamaControlCenter cannot listen on %s: %v", listen, err)
+		return fmt.Sprintf("LLMsControlDock cannot listen on %s: %v", listen, err)
 	} // end of the other-reason case
 	// The address a browser on this computer opens.
 	url := launchURL(listen)
@@ -93,7 +93,7 @@ func listenFailureMessage(listen string, err error) string {
 	// Is the program on that port one of ours?
 	if probeIsOurs(url) {
 		// Say so, and say what to do.
-		return fmt.Sprintf("OllamaControlCenter is already running and answers at %s. Open that address in your browser. To stop it, use its Stop button, or press Ctrl+C in the window where it runs.%s", url, hint)
+		return fmt.Sprintf("LLMsControlDock is already running and answers at %s. Open that address in your browser. To stop it, use its Stop button, or press Ctrl+C in the window where it runs.%s", url, hint)
 	} // end of the ours case
 	// The option for another port, when one can be named.
 	other := ""
@@ -103,5 +103,5 @@ func listenFailureMessage(listen string, err error) string {
 		other = fmt.Sprintf(" For example: -listen %s", next)
 	} // end of the option
 	// Something else uses the port.
-	return fmt.Sprintf("Port %s is already used by another program, which is not OllamaControlCenter. Stop that program, or start this one on another port.%s", listen[strings.LastIndex(listen, ":")+1:], other)
+	return fmt.Sprintf("Port %s is already used by another program, which is not LLMsControlDock. Stop that program, or start this one on another port.%s", listen[strings.LastIndex(listen, ":")+1:], other)
 } // end of listenFailureMessage
diff --git a/portbusy_test.go b/portbusy_test.go
index fa027ba..868eb57 100644
--- a/portbusy_test.go
+++ b/portbusy_test.go
@@ -106,7 +106,7 @@ func TestFailureMessages(t *testing.T) {
 	// The message.
 	m = listenFailureMessage("127.0.0.1:8765", syscall.EADDRINUSE)
 	// It says another program, with the port, and offers another port.
-	for _, want := range []string{"Port 8765", "another program", "not OllamaControlCenter", "For example: -listen 127.0.0.1:8766"} {
+	for _, want := range []string{"Port 8765", "another program", "not LLMsControlDock", "For example: -listen 127.0.0.1:8766"} {
 		// Check each.
 		if !strings.Contains(m, want) {
 			// Report it.
@@ -127,7 +127,7 @@ func TestFailureMessages(t *testing.T) {
 	} // end of the check
 } // end of TestFailureMessages
 
-// TestProbeIsOurs checks the real probe against fake programs: a page that names OllamaControlCenter, a page that does not, an error page, and nothing at all.
+// TestProbeIsOurs checks the real probe against fake programs: a page that names LLMsControlDock, a page that does not, an error page, and nothing at all.
 func TestProbeIsOurs(t *testing.T) {
 	// A program that looks like ours.
 	ours := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
@@ -139,7 +139,7 @@ func TestProbeIsOurs(t *testing.T) {
 			return
 		} // end of the path check
 		// The title names the program.
-		w.Write([]byte("<title>About - OllamaControlCenter</title>"))
+		w.Write([]byte("<title>About - LLMsControlDock</title>"))
 	}))
 	// Stop it at the end.
 	defer ours.Close()
@@ -148,7 +148,7 @@ func TestProbeIsOurs(t *testing.T) {
 	// Stop it at the end.
 	defer other.Close()
 	// A program that always fails.
-	broken := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "OllamaControlCenter", 500) }))
+	broken := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "LLMsControlDock", 500) }))
 	// Stop it at the end.
 	defer broken.Close()
 	// The cases.
@@ -166,6 +166,17 @@ func TestProbeIsOurs(t *testing.T) {
 		// Report it.
 		t.Error("an error page was taken for ours")
 	} // end of the broken check
+	// A copy that still has the old name (an upgrade in progress) is ours too.
+	older := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+		w.Write([]byte("<title>About OllamaControlCenter</title>"))
+	}))
+	// Stop it at the end.
+	defer older.Close()
+	// Recognised.
+	if !probeIsOurs(older.URL + "/") {
+		// Report it.
+		t.Error("a copy with the old name was not recognised")
+	} // end of the older check
 	// Nothing answering.
 	if probeIsOurs("http://127.0.0.1:1/") {
 		// Report it.
diff --git a/signals.go b/signals.go
index 700dfcd..28733e8 100644
--- a/signals.go
+++ b/signals.go
@@ -94,7 +94,7 @@ func watchStopSignals(sigs <-chan os.Signal, act signalActions) {
 			// Remember why we stop, so the last log line can say it.
 			stopReason.Store(reasonSignal)
 			// Tell the person what is happening and how to hurry it up.
-			act.logf("OllamaControlCenter received %v: stopping cleanly (press Ctrl+C again to quit at once)", sig)
+			act.logf("LLMsControlDock received %v: stopping cleanly (press Ctrl+C again to quit at once)", sig)
 			// Work that is still running is cut short; say which.
 			if work := act.running(); len(work) > 0 {
 				// One line naming the work.
@@ -106,7 +106,7 @@ func watchStopSignals(sigs <-chan os.Signal, act signalActions) {
 			continue
 		} // end of the first-signal case
 		// A second signal: the person does not want to wait.
-		act.logf("OllamaControlCenter received %v again: quitting at once; nothing more is saved", sig)
+		act.logf("LLMsControlDock received %v again: quitting at once; nothing more is saved", sig)
 		// Leave with a failure code, because the clean stop did not finish.
 		act.force(1)
 		// Stop reading signals.
diff --git a/web.go b/web.go
index e64ffa1..3ee8ea4 100644
--- a/web.go
+++ b/web.go
@@ -154,6 +154,11 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	mux.HandleFunc("POST /textsize", sizeHandler(token))
 	// The desktop icon: the launcher, and the answer to the first-run question.
 	desktop := desktopIcon{env: mon.denv, dir: mon.store.dir, dataDir: dataRoot()}
+	// An icon made before version 0.31.0 carries the old program name: replace it once (only for someone who chose an icon).
+	if msg := migrateLegacyLauncher(desktop); msg != "" {
+		// Say so in the log.
+		log.Print(msg)
+	} // end of the icon check
 	// Route: a POST request for "/desktopicon" creates or removes the launcher, or records "no".
 	mux.HandleFunc("POST /desktopicon", desktopHandler(token, desktop))
 	// The System check: the hardware report, Continue, and the uninstall (see syscheck.go).
diff --git a/web/about.html b/web/about.html
index 7ac8552..e277f00 100644
--- a/web/about.html
+++ b/web/about.html
@@ -8,7 +8,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>About Ollama Control Center</title>
+<title>About LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
@@ -20,7 +20,7 @@
 {{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
 <span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The name of the program. */}}
-<h1>About Ollama Control Center</h1>
+<h1>About LLMsControlDock</h1>
 {{/* One line that says what it is. */}}
 <p class="muted aboutlead">A local monitor and control page for Ollama.</p>
 {{/* What it does, in plain words. */}}
@@ -70,7 +70,7 @@
 {{end}}
 </ul>
 {{/* The company website, in a new window with no link back and no referrer. */}}
-<p><a class="brandbtn brandbtn-main" href="{{.CompanyURL}}" target="_blank" rel="noopener noreferrer">Visit termgate.com &#8599;<span class="sr-only"> (opens in a new window)</span></a> <span class="muted brandnote">Opens in a new window. The link carries only a source tag (utm_source=ollama-control-center); nothing about you or your computer.</span></p>
+<p><a class="brandbtn brandbtn-main" href="{{.CompanyURL}}" target="_blank" rel="noopener noreferrer">Visit termgate.com &#8599;<span class="sr-only"> (opens in a new window)</span></a> <span class="muted brandnote">Opens in a new window. The link carries only a source tag (utm_source=llms-control-dock); nothing about you or your computer.</span></p>
 {{/* End of the company card. */}}
 </section>
 {{/* A link back. */}}
diff --git a/web/compare-saved.html b/web/compare-saved.html
index c410ed0..a5fc548 100644
--- a/web/compare-saved.html
+++ b/web/compare-saved.html
@@ -8,7 +8,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>Comparison saved - OllamaControlCenter</title>
+<title>Comparison saved - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
diff --git a/web/compare.html b/web/compare.html
index bea8e07..6411621 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -8,7 +8,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>Compare models - OllamaControlCenter</title>
+<title>Compare models - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
diff --git a/web/control.html b/web/control.html
index b0f2fc4..95d18fa 100644
--- a/web/control.html
+++ b/web/control.html
@@ -10,7 +10,7 @@
 {{/* Both colour schemes are supported. */}}
 <meta name="color-scheme" content="light dark">
 {{/* The title shown on the browser tab. */}}
-<title>{{if eq .Kind "stopped"}}Stopped{{else}}Stop the monitor{{end}} - OllamaControlCenter</title>
+<title>{{if eq .Kind "stopped"}}Stopped{{else}}Stop the monitor{{end}} - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
@@ -26,7 +26,7 @@
 {{/* Version 1: the question. */}}
 {{if eq .Kind "stopask"}}
 <h1>Stop the monitor?</h1>
-<p>This closes OllamaControlCenter. Ollama and its models are not touched: whatever is loaded stays loaded.</p>
+<p>This closes LLMsControlDock. Ollama and its models are not touched: whatever is loaded stays loaded.</p>
 {{/* What is running right now, with the symbol and words so colour is never the only signal. */}}
 {{if .Work}}
 <p class="warn" role="alert"><strong>⚠ Something is running right now:</strong></p>
@@ -34,7 +34,7 @@
 {{range .Work}}<li>{{.}}</li>{{end}}
 </ul>
 {{end}}
-<p class="muted">You can start it again with <code>./bin/OllamaControlCenter</code>.</p>
+<p class="muted">You can start it again with <code>./bin/LLMsControlDock</code>.</p>
 {{/* The two choices side by side. */}}
 <div class="choices">
 {{/* The confirm form sends the page token to the real stop. */}}
@@ -49,7 +49,7 @@
 {{else}}
 <h1>The monitor has stopped</h1>
 <p>Nothing is running any more. Ollama and its models were not touched.</p>
-<p class="muted">Start it again with <code>./bin/OllamaControlCenter</code> and reload this page.</p>
+<p class="muted">Start it again with <code>./bin/LLMsControlDock</code> and reload this page.</p>
 {{end}}
 {{/* End of the panel. */}}
 </section>
diff --git a/web/delete.html b/web/delete.html
index 96e1778..d518c39 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -8,7 +8,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>Delete a model - OllamaControlCenter</title>
+<title>Delete a model - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
diff --git a/web/gear.html b/web/gear.html
index 3ca9bd6..2aef97b 100644
--- a/web/gear.html
+++ b/web/gear.html
@@ -8,7 +8,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>Model settings - OllamaControlCenter</title>
+<title>Model settings - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
diff --git a/web/index.html b/web/index.html
index 561a51e..0affd34 100644
--- a/web/index.html
+++ b/web/index.html
@@ -10,7 +10,7 @@
 {{/* Tell the browser the page supports both light and dark colours. */}}
 <meta name="color-scheme" content="light dark">
 {{/* The product name is the page title. */}}
-<title>OllamaControlCenter</title>
+<title>LLMsControlDock</title>
 {{/* Load our own stylesheet; the safety policy allows only styles from this same address. */}}
 <link rel="stylesheet" href="/app.css">
 {{/* The program's icon on the browser tab. */}}
@@ -26,7 +26,7 @@
 {{if .DesktopBanner}}
 <section class="panel" role="region" aria-label="Desktop icon">
 {{/* The question. */}}
-<p class="iconquestion"><img class="appicon" src="/icon.png" width="40" height="40" alt=""> <strong>Create a desktop icon for OllamaControlCenter?</strong></p>
+<p class="iconquestion"><img class="appicon" src="/icon.png" width="40" height="40" alt=""> <strong>Create a desktop icon for LLMsControlDock?</strong></p>
 {{/* What it does and where it goes. */}}
 <p class="muted">One click on it starts the monitor (if it is not running) and opens this page in your browser. It is created in <code>{{.DesktopDir}}</code> and points to <code>{{.DesktopExe}}</code>. {{.DesktopHint}} You can remove it later on the Settings page.</p>
 {{/* The two answers: one small form with the page token. */}}
@@ -51,7 +51,7 @@
 {{/* The program's icon; it is decoration, so its text alternative is empty. */}}
 <img class="appicon" src="/icon.png" width="44" height="44" alt="">
 {{/* The main heading. */}}
-<h1>OllamaControlCenter</h1>
+<h1>LLMsControlDock</h1>
 {{/* End of the icon and heading. */}}
 </div>
 {{/* A quiet line under the title: who is behind the program, with a link that opens in a new window. */}}
@@ -101,7 +101,7 @@
 {{/* The area that opens the tip. */}}
 <span class="tipbox">
 <button type="submit" class="unload ctlbtn" aria-describedby="tipstop"><svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1.5"/></svg> Stop</button>
-<span class="tip tip-icon" role="tooltip" id="tipstop">Stop this OllamaControlCenter monitor program (it asks first; Ollama and its models are not touched)</span>
+<span class="tip tip-icon" role="tooltip" id="tipstop">Stop this LLMsControlDock monitor program (it asks first; Ollama and its models are not touched)</span>
 </span>
 {{/* End of the stop form. */}}
 </form>
diff --git a/web/load.html b/web/load.html
index c89f06a..6b721f4 100644
--- a/web/load.html
+++ b/web/load.html
@@ -8,7 +8,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>Load a model - OllamaControlCenter</title>
+<title>Load a model - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
diff --git a/web/modelfile.html b/web/modelfile.html
index db24d84..d0a5eb8 100644
--- a/web/modelfile.html
+++ b/web/modelfile.html
@@ -8,7 +8,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>Modelfile - OllamaControlCenter</title>
+<title>Modelfile - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
diff --git a/web/performance.html b/web/performance.html
index edbddd2..61750e5 100644
--- a/web/performance.html
+++ b/web/performance.html
@@ -97,7 +97,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>Performance - OllamaControlCenter</title>
+<title>Performance - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 {{/* The waiting-message script, only on the start page. */}}
diff --git a/web/retest.html b/web/retest.html
index 1188c90..46f673f 100644
--- a/web/retest.html
+++ b/web/retest.html
@@ -10,7 +10,7 @@
 {{/* While the re-test runs, the page asks again every 5 seconds; when it ends, the page stays as it is. No script is needed. */}}
 {{if and (eq .Kind "status") .Running}}<meta http-equiv="refresh" content="5">{{end}}
 {{/* The title shown on the browser tab. */}}
-<title>Re-test a group - OllamaControlCenter</title>
+<title>Re-test a group - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
diff --git a/web/systemcheck.html b/web/systemcheck.html
index f97cb24..b7d24d3 100644
--- a/web/systemcheck.html
+++ b/web/systemcheck.html
@@ -10,7 +10,7 @@
 {{/* Both colour schemes are supported. */}}
 <meta name="color-scheme" content="light dark">
 {{/* The title shown on the browser tab. */}}
-<title>{{if eq .Kind "report"}}System check{{else}}Uninstall{{end}} - OllamaControlCenter</title>
+<title>{{if eq .Kind "report"}}System check{{else}}Uninstall{{end}} - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
@@ -26,7 +26,7 @@
 {{/* Version 1: the report. */}}
 {{if eq .Kind "report"}}
 <h1>System check</h1>
-<p>OllamaControlCenter helps you switch between models while you develop applications, and shows how large language models perform. Here is what this computer offers.</p>
+<p>LLMsControlDock helps you switch between models while you develop applications, and shows how large language models perform. Here is what this computer offers.</p>
 <h2>This computer</h2>
 {{/* The facts of this computer; a figure the system did not give says "not reported". */}}
 <table class="settingtable"><tbody>
@@ -94,7 +94,7 @@
 {{end}}
 {{/* Version 2: the uninstall question. */}}
 {{else if eq .Kind "uninstall"}}
-<h1>Uninstall OllamaControlCenter</h1>
+<h1>Uninstall LLMsControlDock</h1>
 {{/* After the tool has been in use: the impact, in words, before anything else. */}}
 {{if not .First}}
 <p class="warn" role="alert"><strong>&#9888; This cannot be undone.</strong> Uninstalling permanently deletes what this tool has collected on this computer:</p>
diff --git a/web/unload.html b/web/unload.html
index ea4aeec..3eb8c0a 100644
--- a/web/unload.html
+++ b/web/unload.html
@@ -8,7 +8,7 @@
 {{/* Fit the page to the width of the screen on phones. */}}
 <meta name="viewport" content="width=device-width, initial-scale=1">
 {{/* The title shown on the browser tab. */}}
-<title>Unload a model - OllamaControlCenter</title>
+<title>Unload a model - LLMsControlDock</title>
 {{/* Our one stylesheet. */}}
 <link rel="stylesheet" href="/app.css">
 </head>{{/* end of the head. */}}
diff --git a/web_test.go b/web_test.go
index 551f6bf..a31ab22 100644
--- a/web_test.go
+++ b/web_test.go
@@ -94,7 +94,7 @@ func TestPageOnline(t *testing.T) {
 		t.Errorf("Content-Type = %q", got)
 	} // end of the type check
 	// Every expected piece of text must appear.
-	for _, want := range []string{"<title>OllamaControlCenter</title>", "✔", "<strong>Online</strong>", "version 0.34.4", srv.URL, "(from command-line option)"} {
+	for _, want := range []string{"<title>LLMsControlDock</title>", "✔", "<strong>Online</strong>", "version 0.34.4", srv.URL, "(from command-line option)"} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the difference.
OCC_PATCH_87_END

# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The module name in go.mod follows the new repository name (this line is the only change in go.mod; the Go version line stays as it is).
sed -i 's|^module github.com/kodati3shrini3/OllamaControlCenter$|module github.com/kodati3shrini3/LLMsControlDock|' go.mod
# Check that the line is now exactly the new one.
grep -qx 'module github.com/kodati3shrini3/LLMsControlDock' go.mod || fail "the module line of go.mod was not changed"
# Report it.
pass "go.mod: module github.com/kodati3shrini3/LLMsControlDock"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# No spelling of the old name may be left in the program, its pages, tests or workflow (the old scripts folder and the legacy names kept on purpose for the migration are excluded).
LEFT="$(grep -rIl --exclude-dir=.git --exclude-dir=scripts --exclude=legacyname.go --exclude=legacyname_test.go --exclude=portbusy.go --exclude=portbusy_test.go --exclude=.gitignore --exclude=MANIFEST.txt -E 'OllamaControlCenter|Ollama Control Center|ollama-control-center' . || true)"
# Anything listed is a failure.
[ -z "$LEFT" ] || fail "the old name is still in: $LEFT"
# Report it.
pass "the old name is gone from the program, pages, tests and workflow"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# The upgrade check in a throw-away place: old-named folders must be renamed with their content, and a second start must change nothing.
SMOKE="$(mktemp -d)"
# Make the three old folders, each with one file.
mkdir -p "$SMOKE/c/OllamaControlCenter" "$SMOKE/d/OllamaControlCenter" "$SMOKE/s/OllamaControlCenter"
# The files.
echo c > "$SMOKE/c/OllamaControlCenter/keep.txt"; echo d > "$SMOKE/d/OllamaControlCenter/keep.txt"; echo s > "$SMOKE/s/OllamaControlCenter/keep.txt"
# Start once in a mode that ends at once; it must say it renamed the folders. The settings and data lookups point at the throw-away place only.
OUT="$(HOME="$SMOKE" XDG_CONFIG_HOME="$SMOKE/c" XDG_DATA_HOME="$SMOKE/d" XDG_STATE_HOME="$SMOKE/s" bin/LLMsControlDock -check -ollama-url http://127.0.0.1:1 2>&1 || true)"
# The three sentences must be there.
[ "$(echo "$OUT" | grep -c 'was renamed to')" = "3" ] || fail "the upgrade did not rename the three folders: $OUT"
# The content must have moved with the folders.
[ "$(cat "$SMOKE/c/LLMsControlDock/keep.txt")$(cat "$SMOKE/d/LLMsControlDock/keep.txt")$(cat "$SMOKE/s/LLMsControlDock/keep.txt")" = "cds" ] || fail "the files did not arrive in the new folders"
# The old folders must be gone.
[ ! -e "$SMOKE/c/OllamaControlCenter" ] && [ ! -e "$SMOKE/d/OllamaControlCenter" ] && [ ! -e "$SMOKE/s/OllamaControlCenter" ] || fail "an old folder is still there"
# Report it.
pass "upgrade check: three old folders renamed with their content"
# A second start must stay silent about it.
OUT2="$(HOME="$SMOKE" XDG_CONFIG_HOME="$SMOKE/c" XDG_DATA_HOME="$SMOKE/d" XDG_STATE_HOME="$SMOKE/s" bin/LLMsControlDock -check -ollama-url http://127.0.0.1:1 2>&1 || true)"
# No rename sentence the second time.
[ "$(echo "$OUT2" | grep -c 'was renamed to')" = "0" ] || fail "the second start renamed again: $OUT2"
# Report it.
pass "upgrade check: a second start changes nothing"
# Remove the throw-away place (it is a folder this script made itself).
rm -rf "$SMOKE"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and look at the pages (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
