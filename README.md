# LLMsControlDock

A small program that watches an [Ollama](https://ollama.com) server and lets you control it from one web page: see which models are loaded, load and unload them, change their settings, test their speed and compare them. It runs on your own computer and needs nothing but Ollama and a web browser.

> **Status: pre-release, version 0.33.0 (first public release).** Early software, tested on two systems only. See "What is tested" below.

## What it does

- Shows whether Ollama is online, how fast it answers and which version it is, with charts and an event log.
- Shows the loaded and the installed models, with their memory use.
- Loads and unloads a model (it asks first, and warns about memory).
- Shows and changes a model's settings, and shows its Modelfile.
- Finds models: **Find LLM** reads the public Ollama model list, lets you search and sort it, and shows which models you already have.
- Tests a model's speed with one fixed built-in prompt, and compares the tested models (PDF and CSV). A built-in guide explains each figure in plain words.
- Has a Help page with 13 topics, each drawn as a swimlane diagram of who does what (You, LLMsControlDock, Ollama, ollama.com).
- Deletes a model and helps you restore it later (it shows the commands; you run them yourself).
- Checks your computer on the first start (processor, memory, graphics cards) and says plainly if it is not enough for running models.

## Privacy and safety

- The page listens on this computer only (`127.0.0.1:8765`) unless you change that in Settings.
- Only the program's own page can use the Stop and Unload buttons.
- No prompt or response text is stored.
- The only internet requests are read-only: a look-up of a model name in the public Ollama library before a delete; the public model list and version lists, read when you press Find LLM (your choices are not sent; the list is also kept in the program's data folder, so Find LLM can show it, dated, when the website cannot be reached); and the optional `-check-links` command.

## What is tested

| System | Tested with | Status |
|---|---|---|
| Linux arm64 (NVIDIA DGX Spark) | Ollama 0.34.4 | Tested |
| Windows 11 x64 | Ollama 0.21.2 | Tested on three computers; `-install` not yet tested on Windows |
| Linux x64, Windows arm64, macOS arm64 and x64 | none | Builds without errors; **not tested** |

## Start it

**Download:** each [release](https://github.com/kodati3shrini3/LLMsControlDock-2/releases) has one file per system and a `SHA256SUMS` file. Check the checksum before you run a file. The programs are not code-signed, so Windows SmartScreen may warn (macOS has not been tested). Or build it yourself: you need [Go](https://go.dev/doc/install) (the version named in `go.mod`) only to build, not to run.

```bash
git clone https://github.com/kodati3shrini3/LLMsControlDock-2.git && cd LLMsControlDock-2
```

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

Installing is optional: the program runs from wherever you put it and makes its folders when it first needs them. Run it once with `-install` to do everything up front, after it asks you: it shows the System check, makes its folders, copies itself to `~/.local/bin` (Windows: `%LocalAppData%\Programs\LLMsControlDock`) and creates the desktop icon. No administrator rights are needed. The About page shows where the files are.

| Option | Effect |
|---|---|
| `-listen host:port` | Where the page listens (default `127.0.0.1:8765`) |
| `-ollama-url URL` | Which Ollama to watch (default `http://127.0.0.1:11434`) |
| `-launch` | Open the page, starting the program in the background first if needed |
| `-check` | One check, one line; exit code 0 = online, 1 = offline |
| `-models` | Print the installed and loaded models as tables |
| `-check-links` | Open every reference address of the comparison page once |
| `-install` | Install for the current user, after asking (see above) |

The Ollama address can also come from the `LLMSCONTROLDOCK_OLLAMA_URL` environment variable.

## Important

LLMsControlDock monitors and controls Ollama. It is not a medical device, and it does not check what a model says. Anything a model writes that you use for health or other critical decisions must be checked against an official source.

LLMsControlDock is an independent tool. It is not affiliated with, endorsed by or sponsored by Ollama Inc.

## Contributing

Questions, bug reports and ideas are welcome as issues. Code contributions are not accepted for now.

## Licence

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
Copyright 2026 termGate Consulting Limited. Developed by Shrinivas Kodati, termGate Consulting Limited, with Claude (Anthropic) as an assistant.
