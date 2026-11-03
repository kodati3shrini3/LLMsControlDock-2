// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the packages this file uses.
	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// fmt builds the texts that contain a number or an address.
	"fmt"
	// net/http provides requests and status codes.
	"net/http"
	// strings recognises which kind of finding a sentence is.
	"strings"
) // end of imports

// attentionJS opens the problem dialog of the System check page, stored inside the executable at build time.
//
//go:embed web/attention.js
var attentionJS []byte

// attentionHandler sends the script file.
func attentionHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser this is JavaScript.
	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	// Send it.
	w.Write(attentionJS)
} // end of attentionHandler

// fixStep is one step of a fix: a sentence and, when the step is a command, the command to type.
type fixStep struct {
	// Text is what to do.
	Text string
	// Cmd is the command to type for this step, or empty.
	Cmd string
} // end of fixStep

// fixLink is an official page that backs a fix, shown with its full address so the person can see where it leads.
type fixLink struct {
	// Text says what the page is.
	Text string
	// URL is the address of the page.
	URL string
} // end of fixLink

// problem is one thing the System check found that the person should fix, with the steps.
type problem struct {
	// Title is the short name of the problem.
	Title string
	// Why says in one sentence what is wrong and what it costs.
	Why string
	// Steps are the steps to fix it, in order; empty when there is no software fix.
	Steps []fixStep
	// NoFix is the honest sentence shown when no step can fix it.
	NoFix string
	// Links are the official pages the steps come from.
	Links []fixLink
} // end of problem

// The official pages the fix steps rely on; each address was read from the vendor's own page.
var (
	// ollamaDownloadLink is Ollama's download page.
	ollamaDownloadLink = fixLink{"Ollama download page", "https://ollama.com/download"}
	// ollamaFAQLink is Ollama's FAQ, which says how to update Ollama.
	ollamaFAQLink = fixLink{"Ollama FAQ: how to update Ollama", "https://github.com/ollama/ollama/blob/main/docs/faq.md"}
	// ollamaGPULink is Ollama's GPU page with the published minimums.
	ollamaGPULink = fixLink{"Ollama GPU page: the published minimums", "https://docs.ollama.com/gpu"}
	// nvidiaCudaLink is NVIDIA's list of CUDA graphics cards.
	nvidiaCudaLink = fixLink{"NVIDIA list of CUDA graphics cards", "https://developer.nvidia.com/cuda-gpus"}
	// nvidiaDriverLink is NVIDIA's own driver download page.
	nvidiaDriverLink = fixLink{"NVIDIA driver downloads", "https://www.nvidia.com/Download/index.aspx"}
	// ollamaDockerLink is the official Ollama image page.
	ollamaDockerLink = fixLink{"Ollama on Docker Hub", "https://hub.docker.com/r/ollama/ollama"}
) // end of the official pages

// The phrases by which the verdict sentences of judgeNvidia and judgeReport are recognised; a test keeps them in step with those sentences.
const (
	// phraseOldDriver is inside the sentence for a driver below the minimum.
	phraseOldDriver = "is older than the published minimum"
	// phraseOldCard is inside the sentence for a card below compute capability 5.0.
	phraseOldCard = "is below the published minimum of 5.0"
	// phraseNoCard is the start of the sentence for no confirmed card.
	phraseNoCard = "No graphics card could be confirmed"
) // end of the phrases

// collectProblems lists what needs fixing, in the order of the page; it returns nothing when everything is fine, so no dialog is shown. Lines of level "info" are never problems.
func collectProblems(online bool, address, goos string, env envView, findings []finding) []problem {
	// The list.
	var out []problem
	// Ollama does not answer.
	if !online {
		// The problem and its steps.
		out = append(out, problem{
			Title: "Ollama was not found",
			Why:   fmt.Sprintf("Nothing answered at %s. This tool works with Ollama only, so it can show nothing useful until Ollama runs.", address),
			Steps: []fixStep{
				{Text: "Install Ollama on the computer that should run your models, if it is not installed yet (see the download page below)."},
				{Text: "Start Ollama and wait until it is running. If you use Docker, check that the Ollama container is running and that its port is published."},
				{Text: "If Ollama runs at another address or port, open Settings in this tool and enter that address."},
				{Text: "Open the System check again (reload this page). The problem is gone when Ollama answers."},
			},
			Links: []fixLink{ollamaDownloadLink},
		})
	} // end of the offline case
	// The Ollama version is older than the fully tested one, or was tested only in part.
	if env.OllamaVerdict.Level == "warn" {
		// The steps depend on how Ollama is installed; the official FAQ names these ways.
		steps := []fixStep{}
		// The way for this operating system.
		switch goos {
		// Linux: run the install script again (Ollama FAQ).
		case "linux":
			// The command from the FAQ.
			steps = append(steps, fixStep{Text: "If Ollama was installed with the install script, run the script again to update it:", Cmd: "curl -fsSL https://ollama.com/install.sh | sh"})
		// Windows and macOS: Ollama updates itself; restart to finish (Ollama FAQ).
		default:
			// The FAQ steps.
			steps = append(steps, fixStep{Text: "Ollama downloads updates by itself. Click the Ollama icon in the taskbar or menu bar and choose \"Restart to update\". You can also download the latest version by hand from the download page below."})
		} // end of the system switch
		// Docker is a common way to run Ollama on a server.
		steps = append(steps, fixStep{Text: "If Ollama runs in Docker, pull the newer image, then stop and start the container again so it uses it:", Cmd: "docker pull ollama/ollama"})
		// Then check.
		steps = append(steps, fixStep{Text: "Open the System check again (reload this page). Under \"Ollama, found here\" the version should now be the minimum shown above or newer."})
		// The problem.
		out = append(out, problem{
			Title: "The Ollama version is older than the one this tool was fully tested on",
			Why:   env.OllamaVerdict.Text,
			Steps: steps,
			Links: []fixLink{ollamaFAQLink, ollamaDownloadLink, ollamaDockerLink},
		})
	} // end of the version case
	// The graphics findings.
	for _, f := range findings {
		// Only warnings are problems.
		if f.Level != "warn" {
			// Skip ok and info lines.
			continue
		} // end of the level check
		// Which kind?
		switch {
		// The driver is too old: a software fix exists.
		case strings.Contains(f.Text, phraseOldDriver):
			// The problem.
			out = append(out, problem{
				Title: "The NVIDIA driver is older than Ollama's published minimum",
				Why:   f.Text,
				Steps: []fixStep{
					{Text: "Look up the driver you have now:", Cmd: "nvidia-smi"},
					{Text: "Download and install a newer driver for your card from NVIDIA's own driver page (below). Ollama's page says 550 or newer, and 570 or newer for cards with compute capability 5.0 to 6.2."},
					{Text: "Restart the computer, then restart Ollama."},
					{Text: "Open the System check again (reload this page). The problem is gone when the driver is at least the minimum."},
				},
				Links: []fixLink{nvidiaDriverLink, ollamaGPULink},
			})
		// The card itself is too old: no software fix.
		case strings.Contains(f.Text, phraseOldCard):
			// The problem.
			out = append(out, problem{
				Title: "The graphics card is too old for Ollama",
				Why:   f.Text,
				NoFix: "No software update fixes this: Ollama supports NVIDIA cards with compute capability 5.0 or higher. Models will run on the processor, which is much slower, unless you use a newer card or another computer.",
				Links: []fixLink{nvidiaCudaLink, ollamaGPULink},
			})
		// No card confirmed at all.
		case strings.HasPrefix(f.Text, phraseNoCard):
			// The problem.
			out = append(out, problem{
				Title: "No supported graphics card was confirmed",
				Why:   f.Text,
				Steps: []fixStep{
					{Text: "If this computer has an NVIDIA card, check that its driver is installed and working:", Cmd: "nvidia-smi"},
					{Text: "If that command fails or lists no card, install the driver from NVIDIA's driver page (below), restart the computer, and restart Ollama."},
					{Text: "Compare your card with NVIDIA's list: Ollama needs compute capability 5.0 or higher."},
					{Text: "Open the System check again (reload this page)."},
				},
				NoFix: "If the computer has no supported card, there is nothing to install: Ollama then uses the processor, and the speeds you measure are not the speeds of a graphics card.",
				Links: []fixLink{nvidiaDriverLink, nvidiaCudaLink, ollamaGPULink},
			})
		} // end of the kind switch
	} // end of the findings loop
	// Hand the list back; empty means no dialog.
	return out
} // end of collectProblems
