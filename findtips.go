// Package main tells Go that this folder builds into a runnable program.
package main

// findAbilityLabels are the plain words shown for the ability tick boxes, by the label the library list page uses.
var findAbilityLabels = map[string]string{
	// Tools.
	"tools": "Uses tools",
	// Vision.
	"vision": "Understands pictures",
	// Audio.
	"audio": "Understands audio",
	// Thinking.
	"thinking": "Shows its step-by-step thinking",
	// Embedding.
	"embedding": "Search and similarity (embedding)",
} // end of findAbilityLabels

// findTipHeadings maps the name of each help bubble on the Find LLM page to the heading its text is stored under.
var findTipHeadings = map[string]string{
	// The page itself.
	"page": "Find LLM",
	// The mandatory computer figures.
	"disk": "Free disk space",
	// Memory.
	"memory": "Memory to run a model",
	// The graphics card.
	"gpu": "Graphics card",
	// Chat and writing.
	"chat": "Chat and writing",
	// The five abilities.
	"tools": "Uses tools", "vision": "Understands pictures", "audio": "Understands audio", "thinking": "Shows its step-by-step thinking", "embedding": "Search and similarity (embedding)",
	// The class groups.
	"size": "Model size", "context": "Memory of a conversation",
	// The two fixed ticks.
	"supported": "Supported by Ollama", "installable": "Can be installed with Ollama",
} // end of findTipHeadings

// findTexts are the help texts of the Find LLM page, in the same four-part form as the rest of the program: what it means, a real case, and what it helps you decide. Every example comes from the saved library pages of 2026-11-08 (CET).
var findTexts = map[string]tooltip{
	// The page.
	"Find LLM": {
		// What it means.
		Plain: "Lists only models that Ollama supports and that you can install with Ollama. This page installs nothing.",
		// A real case.
		Example: "qwen3:0.6b-q4_K_M is listed with the command ollama pull qwen3:0.6b-q4_K_M.",
		// What it helps with.
		Decide: "Which model to try next, before you download anything.",
	}, // end of Find LLM
	// Free disk space.
	"Free disk space": {
		// What it means.
		Plain: "The space free where Ollama keeps its models. Versions that do not fit are greyed out. Required.",
		// A real case.
		Example: "granite4:1b-h needs 1.6 GB (gigabytes); granite4:1b needs 3.3 GB (gigabytes).",
		// What it helps with.
		Decide: "Which versions you can download without running out of space.",
	}, // end of Free disk space
	// Memory.
	"Memory to run a model": {
		// What it means.
		Plain: "The memory of the computer that runs the model. A model larger than that cannot be loaded completely. Required.",
		// A real case.
		Example: "granite4:1b is 3.3 GB (gigabytes), so it needs a computer with more memory than that.",
		// What it helps with.
		Decide: "Which models your computer can really run.",
	}, // end of Memory to run a model
	// Graphics card.
	"Graphics card": {
		// What it means.
		Plain: "Whether a graphics card, called a GPU (graphics processing unit), was found. Models run much faster on one. Required.",
		// A real case.
		Example: "Without one, a model runs on the processor and answers more slowly.",
		// What it helps with.
		Decide: "How fast to expect answers.",
	}, // end of Graphics card
	// Chat and writing.
	"Chat and writing": {
		// What it means.
		Plain: "Models that write text, as opposed to search-and-similarity models. Ticked by default.",
		// A real case.
		Example: "granite4 is a chat model; nomic-embed-text is a search-and-similarity model.",
		// What it helps with.
		Decide: "Whether you want a model to talk with or one to search with.",
	}, // end of Chat and writing
	// Tools.
	"Uses tools": {
		// What it means.
		Plain: "The model can ask a program to do something, such as look up a value, and use the answer.",
		// A real case.
		Example: "qwen3, llama3.2 and granite4 carry the label tools on the library page.",
		// What it helps with.
		Decide: "Whether you need the model to work with other programs.",
	}, // end of Uses tools
	// Pictures.
	"Understands pictures": {
		// What it means.
		Plain: "The model can read pictures you give it, not only text.",
		// A real case.
		Example: "llava carries the label vision on the library page.",
		// What it helps with.
		Decide: "Whether you want to ask questions about images.",
	}, // end of Understands pictures
	// Audio.
	"Understands audio": {
		// What it means.
		Plain: "The model can listen to sound you give it, not only read text.",
		// A real case.
		Example: "Seven models carry the label audio on the library page of 2026-11-08.",
		// What it helps with.
		Decide: "Whether you want to ask questions about recordings.",
	}, // end of Understands audio
	// Thinking.
	"Shows its step-by-step thinking": {
		// What it means.
		Plain: "The model writes out its reasoning before the answer. Answers take longer.",
		// A real case.
		Example: "qwen3 carries the label thinking; granite4 does not.",
		// What it helps with.
		Decide: "Whether you value seeing the reasoning over speed.",
	}, // end of thinking
	// Embedding.
	"Search and similarity (embedding)": {
		// What it means.
		Plain: "The model turns text into numbers so that similar texts can be found. It does not chat.",
		// A real case.
		Example: "nomic-embed-text and bge-m3 carry the label embedding.",
		// What it helps with.
		Decide: "Whether you need to search documents by meaning.",
	}, // end of embedding
	// Model size.
	"Model size": {
		// What it means.
		Plain: "How many numbers the model learned, in billions. Bigger is usually smarter and needs more memory.",
		// A real case.
		Example: "qwen3 comes in 0.6b, 1.7b, 4b and 8b among others; 0.6b is Tiny.",
		// What it helps with.
		Decide: "How much quality to buy with your memory and disk.",
	}, // end of Model size
	// Memory of a conversation.
	"Memory of a conversation": {
		// What it means.
		Plain: "How much text the model can keep in mind at once (context length). K means thousand, M million.",
		// A real case.
		Example: "granite4:1b-h shows 1M; qwen3:0.6b shows 40K.",
		// What it helps with.
		Decide: "Whether long documents or long chats will fit.",
	}, // end of Memory of a conversation
	// Supported by Ollama.
	"Supported by Ollama": {
		// What it means.
		Plain: "Always on. Every model listed here is in the official Ollama library, so Ollama can run it.",
		// A real case.
		Example: "A model that exists only on another website is not listed.",
		// What it helps with.
		Decide: "Nothing to decide; it cannot be changed.",
	}, // end of Supported by Ollama
	// Installable with Ollama.
	"Can be installed with Ollama": {
		// What it means.
		Plain: "Always on. Each model is listed with the command that downloads it with Ollama.",
		// A real case.
		Example: "ollama pull granite4:1b-h",
		// What it helps with.
		Decide: "Nothing to decide; it cannot be changed.",
	}, // end of Can be installed with Ollama
} // end of findTexts

// makeFindTip builds one help bubble of the Find LLM page from its heading.
func makeFindTip(id, heading string) tipView {
	// A heading without a text gives empty parts; a test makes sure that never happens.
	t := findTexts[heading]
	// Build the view.
	return tipView{Title: heading, ID: id, Plain: t.Plain, Example: t.Example, Decide: t.Decide, AlsoKnown: t.AlsoKnown}
} // end of makeFindTip
