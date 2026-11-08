#!/usr/bin/env bash
# Script 88 (NOTICE file and README, no code change): adds the two public project files NOTICE (the copyright card of Apache-2.0) and README.md (the front page of the repository). The official LICENSE file must already be in the project folder (step 8). Nothing else is changed.
# Run it from the project folder, on the same branch as script 87 (never on main): cd ~/OllamaControlCenter && bash scripts/88-step52-notice-and-readme.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two files this script writes.
README_SHA="0335fbd87d0a015c2691844daf465322d3c67377cdd6649f47e453dbc2f5e5ed"
NOTICE_SHA="ef6b9090bba8b8ee028a5fcaf301432589b45bc15527476604e47899ac2d128f"

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
[ "$BRANCH" != "main" ] || fail "you are on main; this script belongs on the rename branch (rename/llmscontroldock)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 87 must be applied: its new file exists.
[ -e legacyname.go ] || fail "legacyname.go is missing: script 87 (rename) must be applied first"
# Report it.
pass "script 87 was applied (legacyname.go exists)"

# Refuse to run twice.
if [ -e README.md ] || [ -e NOTICE ]; then fail "README.md or NOTICE exists: this script was already applied"; fi
# Report it.
pass "README.md and NOTICE do not exist yet"

# The official licence must be in place and look like the Apache License 2.0.
[ -f LICENSE ] || fail "LICENSE is missing: do step 8 (download the official text) first"
# Its first non-empty line.
FIRST="$(grep -m1 -v '^[[:space:]]*$' LICENSE | sed 's/^[[:space:]]*//')"
# It must be the title of the licence.
[ "$FIRST" = "Apache License" ] || fail "LICENSE does not start with the title Apache License (it starts with: $FIRST)"
# The version line must be there.
grep -q 'Version 2.0, January 2004' LICENSE || fail "LICENSE lacks the line Version 2.0, January 2004"
# The end marker must be there exactly once.
[ "$(grep -c 'END OF TERMS AND CONDITIONS' LICENSE)" = "1" ] || fail "LICENSE lacks the end marker END OF TERMS AND CONDITIONS (or has it twice)"
# Report it.
pass "LICENSE is the Apache License 2.0 (title, version line, end marker)"

# The README names the version; it must be the version in the program.
VERSION="$(sed -n 's/^const appVersion = "\(.*\)"$/\1/p' about.go)"
# It must be 0.31.0, the version script 87 set.
[ "$VERSION" = "0.31.0" ] || fail "about.go has version $VERSION, but this README says 0.31.0"
# Report it.
pass "the program version is $VERSION, as the README says"

# Write README.md; the quoted marker stops the shell from changing anything inside.
cat > README.md <<'OCC_README_88_END'
# LLMsControlDock

A small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, load and unload them, change their settings, test their speed and compare them. It runs on your own computer and needs nothing but Ollama and a web browser.

> **Status: pre-release, version 0.31.0.** Not yet ready for everyday use. See "What is tested" below.

## What it does

- Shows whether Ollama is online, how fast it answers and which version it is, with charts and an event log.
- Shows the loaded and the installed models, with their memory use.
- Loads and unloads a model (it asks first, and warns about memory).
- Shows and changes a model's settings, and shows its Modelfile.
- Tests a model's speed with one fixed built-in prompt, and compares the tested models (PDF and CSV).
- Deletes a model and helps you restore it later (it shows the commands; you run them yourself).
- Checks your computer on the first start (processor, memory, graphics cards) and says plainly if it is not enough for running models.

## Privacy and safety

- The page listens on this computer only (`127.0.0.1:8765`) unless you change that in Settings.
- Only the program's own page can use the Stop and Unload buttons.
- No prompt or response text is stored.
- The only internet requests are a read-only look-up of a model name in the public Ollama library before a delete, and the optional `-check-links` command.

## What is tested

| System | Tested with | Status |
|---|---|---|
| Linux arm64 (NVIDIA DGX Spark) | Ollama 0.34.4 | Tested |
| Windows 11 x64 | Ollama 0.21.2 | Tested in part; a fix for the model categories awaits a re-test |
| Linux x64, Windows arm64, macOS arm64 and x64 | none | Builds without errors; **not tested** |

## Start it

There are no ready-made downloads yet; the first release will be a 0.x version with one file per system. Until then, build it yourself. You need [Go](https://go.dev/doc/install) (the version named in `go.mod`) only to build, not to run.

```bash
# Linux and macOS
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock .
./bin/LLMsControlDock
```

```powershell
# Windows (PowerShell)
$env:CGO_ENABLED = "0"
go build -trimpath -o bin\LLMsControlDock.exe .
.\bin\LLMsControlDock.exe
```

Then open http://127.0.0.1:8765/ in your browser. On the first start you see a System check of your computer.

| Option | Effect |
|---|---|
| `-listen host:port` | Where the page listens (default `127.0.0.1:8765`) |
| `-ollama-url URL` | Which Ollama to watch (default `http://127.0.0.1:11434`) |
| `-launch` | Open the page, starting the program in the background first if needed |
| `-check` | One check, one line; exit code 0 = online, 1 = offline |
| `-models` | Print the installed and loaded models as tables |
| `-check-links` | Open every reference address of the comparison page once |

The Ollama address can also come from the `LLMSCONTROLDOCK_OLLAMA_URL` environment variable.

## Important

LLMsControlDock monitors and controls Ollama. It is not a medical device, and it does not check what a model says. Anything a model writes that you use for health or other critical decisions must be checked against an official source.

LLMsControlDock is an independent tool. It is not affiliated with, endorsed by or sponsored by Ollama Inc.

## Contributing

Questions, bug reports and ideas are welcome as issues. Code contributions are not accepted for now.

## Licence

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
Copyright 2026 termGate Consulting Limited. Developed by Shrinivas Kodati, termGate Consulting Limited, with Claude (Anthropic) as an assistant.
OCC_README_88_END
# Write NOTICE the same way.
cat > NOTICE <<'OCC_NOTICE_88_END'
LLMsControlDock
Copyright 2026 termGate Consulting Limited

Developed by Shrinivas Kodati, termGate Consulting Limited, with Claude (Anthropic) as an assistant.

This product is licensed under the Apache License, Version 2.0 (see the file LICENSE).

This product includes software from the Go standard library, Copyright The Go Authors.
Its licence is at https://go.dev/LICENSE

LLMsControlDock is an independent tool. It is not affiliated with, endorsed by or sponsored by Ollama Inc.
OCC_NOTICE_88_END

# The two files must be exactly what was written in the sandbox.
[ "$(sha README.md)" = "$README_SHA" ] || fail "README.md has an unexpected sha256"
# And the NOTICE.
[ "$(sha NOTICE)" = "$NOTICE_SHA" ] || fail "NOTICE has an unexpected sha256"
# Report it.
pass "README.md and NOTICE have the expected sha256"

# The public files must not carry the old name or the working word we keep out of all documentation.
if grep -n -i -E 'ollamacontrolcenter|ollama control center|kiss' README.md NOTICE; then fail "a word that must not be in the public files was found (see above)"; fi
# Report it.
pass "no old name and no excluded word in README.md or NOTICE"

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  read README.md and NOTICE once (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short | grep -E 'LICENSE|NOTICE|README' || true
