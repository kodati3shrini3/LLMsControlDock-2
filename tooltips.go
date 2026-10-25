// Package main tells Go that this folder builds into a runnable program.
package main

// tooltip is the help text for one heading: three short parts, plus an optional "also known as" line.
type tooltip struct {
	// Plain says what the heading means, in plain words.
	Plain string
	// Example gives a real case, taken from the six models this project was built with.
	Example string
	// Decide says what the person can decide with it.
	Decide string
	// AlsoKnown lists the common machine-learning task names (empty when there are none).
	AlsoKnown string
} // end of tooltip

// installedColumns are the ten column titles of the Installed table, in order; a test checks they match render.go.
var installedColumns = []string{"Model", "State", "Size on disk", "Family", "Parameters", "Quantization", "Max context length", "Embedding length", "Last modified", "Abilities"}

// loadedColumns are the five column titles of the Loaded table, in order; a test checks they match render.go.
var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Loaded context length", "Time until unload"}

// gearHeadings are the headings on the settings page and the Load page that have a help bubble, in the order they appear; a test checks each has a text.
var gearHeadings = []string{"Context size", "Model maximum", "Smallest allowed", "Saved in the model", "Other saved settings", "Keep-alive time"}

// helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
// The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
var helpTexts = map[string]tooltip{
	// The model name, shared by both tables.
	"Model": {
		// What it means.
		Plain: "The model's name. The part after the colon is a version or size tag.",
		// A real case.
		Example: "medgemma:latest and medgemma:27b are two versions of one model.",
		// What it helps with.
		Decide: "Which exact model you are looking at.",
	}, // end of Model
	// The abilities list.
	"Abilities": {
		// What it means.
		Plain: "The things this model says it can do, in Ollama's own words.",
		// A real case.
		Example: "gemma4:e4b lists completion, vision, audio, tools and thinking.",
		// What it helps with.
		Decide: "Whether the model fits the job: images, audio, tool use or plain chat.",
	}, // end of Abilities
	// The size on disk.
	"Size on disk": {
		// What it means.
		Plain: "How much storage the model files take.",
		// A real case.
		Example: "medgemma:latest takes 3.3 GB (gigabytes); medgemma:27b takes 17.4 GB (gigabytes).",
		// What it helps with.
		Decide: "Whether it fits your disk, and a hint of how much memory it needs.",
	}, // end of Size on disk
	// The model family.
	"Family": {
		// What it means.
		Plain: "The model's family: the design it was built from.",
		// A real case.
		Example: "Both medgemma models belong to the gemma3 family.",
		// What it helps with.
		Decide: "Spotting models that were built the same way.",
	}, // end of Family
	// The parameter count.
	"Parameters": {
		// What it means.
		Plain: "A rough count of the numbers the model learned; B means billions. More is usually smarter but slower.",
		// A real case.
		Example: "medgemma:27b has 27.4B (billions); medgemma:latest has 4.3B (billions).",
		// What it helps with.
		Decide: "Quality versus speed.",
	}, // end of Parameters
	// The quantization level.
	"Quantization": {
		// What it means.
		Plain: "How tightly the numbers are squeezed to save memory. Q4 squeezes more; F16 keeps full detail.",
		// A real case.
		Example: "Your chat models use Q4_K_M; your embedding models use F16.",
		// What it helps with.
		Decide: "Smaller and faster, or more precise.",
	}, // end of Quantization
	// The last-modified time.
	"Last modified": {
		// What it means.
		Plain: "When the model files last changed, shown in UTC (coordinated universal time).",
		// A real case.
		Example: "medgemma:27b changed on 2026-10-24 at 17:40 UTC (coordinated universal time).",
		// What it helps with.
		Decide: "Telling fresh models from old ones.",
	}, // end of Last modified
	// The loaded or not-loaded state.
	"State": {
		// What it means.
		Plain: "In memory now (● Loaded, with [the time until Ollama unloads it]) or only on disk (○ Not loaded).",
		// A real case.
		Example: "A ○ Not loaded model needs a moment to load before it answers.",
		// What it helps with.
		Decide: "Whether the next question answers at once or after a load.",
	}, // end of State
	// The largest context the model supports.
	"Max context length": {
		// What it means.
		Plain: "The most text the model can keep in mind at once, counted in tokens (word pieces).",
		// A real case.
		Example: "The medgemma models: 131072. qwen3.6:27b: 262144.",
		// What it helps with.
		Decide: "Whether it can handle long documents.",
	}, // end of Max context length
	// The embedding length.
	"Embedding length": {
		// What it means.
		Plain: "How many numbers the model uses to describe one piece of text.",
		// A real case.
		Example: "rjmalagon/gte-qwen2-instruct:1.5b-f16 uses 1536 numbers.",
		// What it helps with.
		Decide: "Matching a model to the search index it feeds.",
	}, // end of Embedding length
	// The size of a loaded model.
	"Size (as reported)": {
		// What it means.
		Plain: "The size Ollama reports for the model while it is in memory.",
		// A real case.
		Example: "medgemma:latest: 3.8 GB (gigabytes) in memory, 3.3 GB (gigabytes) on disk.",
		// What it helps with.
		Decide: "How much room it takes while running.",
	}, // end of Size (as reported)
	// The graphics memory in use.
	"Memory on GPU": {
		// What it means.
		Plain: "How much memory on the GPU (graphics processing unit) the model is using.",
		// A real case.
		Example: "medgemma:latest: 3.8 GB (gigabytes).",
		// What it helps with.
		Decide: "Whether the GPU (graphics processing unit) has room for it.",
	}, // end of Memory on GPU
	// The context length of a loaded model.
	"Loaded context length": {
		// What it means.
		Plain: "The context size set for this loaded copy. A bigger one needs more memory.",
		// A real case.
		Example: "medgemma:latest: 131072.",
		// What it helps with.
		Decide: "Why memory use changes from one load to another.",
	}, // end of Loaded context length
	// The countdown to unloading.
	"Time until unload": {
		// What it means.
		Plain: "A countdown until Ollama frees the model from memory.",
		// A real case.
		Example: "5 min 0 s right after a load with the default keep time.",
		// What it helps with.
		Decide: "When memory will free up by itself.",
	}, // end of Time until unload
	// The embedding category.
	"Search and similarity (embedding)": {
		// What it means.
		Plain: "These models don't chat. They turn text into numbers so a computer can find texts with similar meaning.",
		// A real case.
		Example: "rjmalagon/gte-qwen2-instruct:1.5b-f16",
		// What it helps with.
		Decide: "Use for search or retrieval, not for answers.",
		// The common task names.
		AlsoKnown: "Feature Extraction, Sentence Similarity",
	}, // end of the embedding category
	// The multimodal category.
	"Chat with images or audio (multimodal)": {
		// What it means.
		Plain: "Chat models that can also look at pictures or listen to audio.",
		// A real case.
		Example: "medgemma:27b (images), gemma4:e4b (images and audio)",
		// What it helps with.
		Decide: "Use when your input is not only text.",
		// The common task names.
		AlsoKnown: "Image-Text-to-Text, Audio-Text-to-Text",
	}, // end of the multimodal category
	// The text-only category.
	"Chat and writing (text only)": {
		// What it means.
		Plain: "Chat models that read and write text only.",
		// A real case: honest about having none.
		Example: "None of your six models are in this group right now.",
		// What it helps with.
		Decide: "A lighter choice when no images are needed.",
		// The common task names.
		AlsoKnown: "Text Generation",
	}, // end of the text-only category
	// The catch-all category.
	"Not yet classified": {
		// What it means.
		Plain: "The abilities list did not tell us what this is, so it is shown here instead of being hidden.",
		// A real case: honest about when it appears.
		Example: "Appears only if a model reports no known abilities.",
		// What it helps with.
		Decide: "Check the model's own page to see what it does.",
	}, // end of the catch-all category
	// The context size setting.
	"Context size": {
		// What it means.
		Plain: "How much text the model keeps in mind at once, counted in tokens (word pieces). Bigger needs more memory.",
		// A real case, measured on the machine this project was built on.
		Example: "medgemma:latest used 3.8 GB (gigabytes) at 131072 and 3.0 GB (gigabytes) at 8192.",
		// What it helps with.
		Decide: "How much memory to spend against how long a text it can handle.",
	}, // end of Context size
	// The model's own limit.
	"Model maximum": {
		// What it means.
		Plain: "The largest context size this model was built for. This page refuses anything above it.",
		// A real case.
		Example: "medgemma:latest: 131072. qwen3.6:27b: 262144.",
		// What it helps with.
		Decide: "The top of the range you can choose.",
	}, // end of Model maximum
	// This monitor's own lowest value.
	"Smallest allowed": {
		// What it means.
		Plain: "The lowest context size this monitor lets you save. Ollama itself sets no lowest value.",
		// A real case.
		Example: "512. Ollama accepted a size of 1 in a test, which would make the model unusable.",
		// What it helps with.
		Decide: "It stops a value that would break the model.",
	}, // end of Smallest allowed
	// What is stored in the model.
	"Saved in the model": {
		// What it means.
		Plain: "Settings stored inside the model in Ollama. Programs that do not send their own value use them.",
		// A real case.
		Example: "After saving 8192, the next load of the model starts at 8192.",
		// What it helps with.
		Decide: "What every program gets when it loads this model.",
	}, // end of Saved in the model
	// The other stored settings.
	"Other saved settings": {
		// What it means.
		Plain: "Other settings stored in the model, such as stop words. They are shown here and kept as they are.",
		// A real case.
		Example: "medgemma:latest has the stop word end_of_turn.",
		// What it helps with.
		Decide: "What the model already does before you change anything.",
	}, // end of Other saved settings
	// The keep-alive time on the Load page.
	"Keep-alive time": {
		// What it means.
		Plain: "How long the model stays in memory after its last use, before Ollama unloads it by itself.",
		// A real case.
		Example: "5 minutes is Ollama's default. Never unload keeps it until you press Unload.",
		// What it helps with.
		Decide: "Fast answers against memory kept free for other work.",
	}, // end of Keep-alive time
} // end of helpTexts

// helpFor returns the tooltip for a heading, and false when there is none.
func helpFor(heading string) (tooltip, bool) {
	// Look the heading up in the table.
	t, ok := helpTexts[heading]
	// Hand back both answers.
	return t, ok
} // end of helpFor
