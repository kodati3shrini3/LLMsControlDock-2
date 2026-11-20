# LLMsControlDock 0.34.0 (pre-release)

LLMsControlDock is a small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, find and manage models, change their settings, test their speed and compare them. It runs on your own computer, needs nothing but Ollama and a web browser, and is one file with no other dependencies (Go standard library only).

This release builds on 0.33.0 and mostly improves **Find LLM**. It is still a pre-release: early software, used by hand on two systems only (see "Known limits").

## What is new

| Where | What you see |
|---|---|
| Find LLM, Sort by | A new choice, **Updated: new to old**, is the first choice and the default. It lists the model that ollama.com updated most recently first. **Most downloaded** and **Name A to Z** are still there. |
| Find LLM, each result | A line "Matched your choices" says which of your choices made the model qualify. |
| Find LLM, newer Ollama | The program reads each listed model's page. When the page says the model needs a newer Ollama than yours, the result shows a warning symbol, "Fits, after you update Ollama", and a folded "How to update Ollama" with the steps for Windows and macOS, Linux and Docker. |
| Find LLM, sizes | A folded table, "Compare sizes", puts the sizes of one model side by side (download size, context, and whether it fits on this computer). |
| Find LLM, decision models | A new tick finds decision models. They classify text, answer yes or no, or score text, and they do not chat. They need Ollama 0.35.0 or newer. |
| Find LLM, labels | Mixed sizes such as 8x7b are now counted as their total (56 billion). A label that ollama.com shows and this program does not know yet is named in a notice, with a request to report it. |
| Docker and Kubernetes | The commands on Find LLM and on the Delete page now use `-it` (`docker exec -it`, `kubectl exec -it`), so they work in a terminal. |
| Help and README | The Find LLM Help topic and the README describe the changes above. The Help also now describes the Pause and Resume of the monitor page and the estimate on the About page, which it did not mention before. |
| Behind the scenes | The README links straight to the issues page. The GitHub start-up check follows the first-start redirect to the System check. Four automated tests that failed on Windows in 0.33.0 are fixed. |

## Things to know about the new Find LLM features

- **The update order uses rounded words.** ollama.com writes how long ago a model was updated in rounded words such as "6 days ago" or "1 month ago", not as a date. Models with the same words are listed by name A to Z, and a model without such words is listed last. A note under the results says so.
- **The newer-Ollama warning depends on the wording of the model page.** The program looks for a sentence such as "requires Ollama 0.35.1 or later". A model whose page does not say this gets no warning, even if it needs a newer Ollama. Only a few pages were checked by hand.
- **One more internet request per listed model.** Find LLM now also reads the public page of each listed model, and asks your own Ollama server which version it is. The request carries only the model's name in the address; your choices are not sent.

## Downloads

Each file is one program for one system. Pick the one that matches your computer.

| System | File | Tested |
|---|---|---|
| Linux, ARM64 (Ubuntu on NVIDIA DGX Spark) | `LLMsControlDock-linux-arm64` | **Used by hand**, including the Find LLM changes of this release |
| Windows 11, x86-64 | `LLMsControlDock-windows-amd64.exe` | Used by hand with 0.33.0; the changes of this release have **not** been tried by hand on Windows |
| Linux, x86-64 | `LLMsControlDock-linux-amd64` | Not used by hand |
| Windows, ARM64 | `LLMsControlDock-windows-arm64.exe` | Not used by hand |
| macOS, Apple silicon | `LLMsControlDock-darwin-arm64` | Not used by hand |
| macOS, Intel | `LLMsControlDock-darwin-amd64` | Not used by hand |

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

- An automated suite of about 515 tests passes on Linux ARM64 (DGX Spark) for the final code of this release, and the program compiles for all six systems (Linux, Windows and macOS, each for x86-64 and ARM64 or Apple silicon).
- The GitHub start-up check, which also runs the automated tests, passed on all six systems for an earlier state of this version (run `43981980700`). It has **not** been run on the final files of this release.
- Used by hand on Ubuntu ARM64 (DGX Spark): the Find LLM changes of this release. Used by hand on Windows 11 x86-64 with 0.33.0.
- Run on 2026-11-20 on Linux ARM64 (DGX Spark, Ollama 0.34.4) with the final files of this release: the smoke and load test (41 checks; 10 parallel readers for 20 seconds, about 15,000 requests, none failed, 95th percentile 45 ms) and the functional regression test (55 checks: every page and button, checked against Ollama's own API, including delete and download again). All passed.
- The files in this release were built on the author's computer.

## Known limits

- Used by hand on two systems only (table above). The other four have not been used with a real Ollama by anyone.
- The executables are unsigned (see "First start").
- `-install` has been tested by hand on Linux only.
- The speed-test limits (for example the 1000 ms response-time limit used in the load test) are the author's own choice, not a standard.
- From 0.33.0: memory use grew from 15 MB to 19 MB over about 14,700 requests in one run. One run cannot show whether that is a leak.
- The new Find LLM limits are described above ("Things to know about the new Find LLM features").

## Important

LLMsControlDock monitors and controls Ollama. It is not a medical device and it does not check what a model says. Anything a model writes that you use for health or other critical decisions must be checked against an official source. It is an independent tool, not affiliated with, endorsed by or sponsored by Ollama Inc.

## Licence

Apache License 2.0. Copyright 2026 termGate Consulting Limited. Developed by Shrinivas Kodati, termGate Consulting Limited, with Claude (Anthropic) as an assistant.
