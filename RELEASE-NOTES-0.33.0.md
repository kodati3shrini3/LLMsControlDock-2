# LLMsControlDock 0.33.0: first public release (pre-release)

LLMsControlDock is a small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, find and manage models, change their settings, test their speed and compare them. It runs on your own computer, needs nothing but Ollama and a web browser, and is one file with no other dependencies (Go standard library only).

Earlier version numbers were development builds and were not published. This is the first release anyone can download, so expect rough edges (see "Known limits").

## What you can do

| Task | What the program does |
|---|---|
| Check your computer | A System check on first start looks at processor, memory and graphics cards and says plainly if the machine is not enough for running models. |
| Watch Ollama | Online or offline, response time and version, with charts and an event log. |
| Find a model | **Find LLM** reads the public Ollama model list, lets you search and sort, and shows which models you already have. The list is also kept locally, so it can be shown (dated) when the website cannot be reached. |
| Load and unload | Asks first and warns about memory. |
| Tune a model | Shows a model's saved settings and its Modelfile; a change is reviewed before it is saved. |
| Test speed | One fixed built-in prompt: a warm-up request loads the model (reported as the cold figure), then three timed requests; each result is the median of the three. Only numbers are saved, never text. |
| Compare models | Side by side, with fairness flags, a re-test of a group, and PDF and CSV export. |
| Read the results | A built-in guide explains each figure in plain words. |
| Delete and restore | Asks first and, for a deleted model, shows how to get it back. |
| Get help | 13 Help topics, each drawn as a swimlane diagram (You, LLMsControlDock, Ollama, ollama.com) with the same steps listed in text. |
| Install (optional) | `LLMsControlDock -install` shows the plan, asks, then makes the folders, copies the program and creates a desktop icon. No administrator rights. Uninstall removes only what it placed. |

## Downloads

Each file is one program for one system. Pick the one that matches your computer.

| System | File | Tested |
|---|---|---|
| Linux, ARM64 (Ubuntu on NVIDIA DGX Spark) | `LLMsControlDock-linux-arm64` | **Used by hand**; start-up check on GitHub passed |
| Windows 11, x86-64 | `LLMsControlDock-windows-amd64.exe` | **Used by hand** (`-install` not yet tested by hand on Windows); start-up check on GitHub passed |
| Linux, x86-64 | `LLMsControlDock-linux-amd64` | Not used by hand; start-up check on GitHub passed |
| Windows, ARM64 | `LLMsControlDock-windows-arm64.exe` | Not used by hand; start-up check on GitHub passed |
| macOS, Apple silicon | `LLMsControlDock-darwin-arm64` | Not used by hand; start-up check on GitHub passed |
| macOS, Intel | `LLMsControlDock-darwin-amd64` | Not used by hand; start-up check on GitHub passed |

`SHA256SUMS` lists the checksum of every file. Check yours before running it:

```bash
# Linux and macOS: run in the folder with the downloaded files
sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS
```

```powershell
# Windows (PowerShell): compare the printed value with the line in SHA256SUMS
(Get-FileHash .\LLMsControlDock-windows-amd64.exe -Algorithm SHA256).Hash
```

## First start

1. Linux and macOS only: make the file runnable once, for example `chmod +x LLMsControlDock-linux-arm64` (use the name of your file).
2. Start the program; it prints the address (default `http://127.0.0.1:8765/`) and you open it in your browser.
3. The System check page opens first. Press **Continue**.
4. The executables are **not code-signed**. Windows SmartScreen may warn that the publisher is unknown: choose "More info" and "Run anyway" only if the checksum matched. macOS may also block an unsigned program; this has not been tested.

## Verified so far

- An automated suite of about 490 tests runs on every change.
- A 39-check smoke and load test and a 54-check functional regression test (every page and button, checked against Ollama's own API) pass on the DGX Spark. These two are developer tools and are not part of the download.
- Used by hand on Ubuntu ARM64 (DGX Spark) and on Windows 11 x86-64.
- On 2026-11-13 GitHub built the same Go code on six machines (Linux x86-64 and ARM64, Windows x86-64 and ARM64, macOS Apple silicon and Intel). On each, the program started, answered its first page (the System check), showed version 0.33.0 on the About page and answered the Settings page. No Ollama was installed on these machines. [See the run](https://github.com/kodati3shrini3/LLMsControlDock-2/actions/runs/43384050578).
- The automated tests passed on Linux x86-64, Linux ARM64 and both macOS systems. On both Windows systems four tests failed (see "Known limits").
- The files in this release were built on the author's computer. GitHub built the same Go code separately, so its check did not run these exact files.

## Known limits

- Used by hand on two systems only (table above). The other four started and answered their pages on GitHub's machines, but nobody has used them with a real Ollama.
- Four automated tests fail on Windows: `TestGuardedRoot`, `TestRunInstall`, `TestLicenceFilesAgreeWithThePage` and `TestMeasureSelfUsesTheSystemCheck`. Three of them look like tests that assume Linux paths, file permissions or line endings, and the cause of the fourth is not yet confirmed. They will be looked at in a later version.
- The executables are unsigned (see "First start").
- `-install` has been tested by hand on Linux only.
- The speed-test limits (for example the 1000 ms response-time limit used in the load test) are the author's own choice, not a standard.
- Memory use grew from 15 MB to 19 MB over about 14,700 requests in one run. One run cannot show whether that is a leak.

## Important

LLMsControlDock monitors and controls Ollama. It is not a medical device and it does not check what a model says. Anything a model writes that you use for health or other critical decisions must be checked against an official source. It is an independent tool, not affiliated with, endorsed by or sponsored by Ollama Inc.

## Licence

Apache License 2.0. Copyright 2026 termGate Consulting Limited. Developed by Shrinivas Kodati, termGate Consulting Limited, with Claude (Anthropic) as an assistant.
