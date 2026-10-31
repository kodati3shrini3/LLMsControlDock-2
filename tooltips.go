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
var gearHeadings = []string{"Set in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}

// healthHeadings are the headings of the Ollama status panel on the main page that have a help bubble; a test checks each has a text.
var healthHeadings = []string{"Monitoring details", "API health", "Event log"}

// perfHeadings are the indicator names on the performance page that have a help bubble; a test checks each has a text.
var perfHeadings = []string{"Answer speed", "Prompt reading speed", "Load time", "Total time", "Time to first word", "Tokens counted", "Embedding time", "Vector length", "Processor split", "Memory used", "Change since the previous run", "CPU cores", "CPU load", "Memory free", "Swap in use", "Other models loaded", "GPU"}

// helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
// The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
var helpTexts = map[string]tooltip{
	// The twistie that folds the status panel and the event log away.
	"Monitoring details": {
		// What it means.
		Plain: "Folds the API health and Event log boxes away to save space; this browser remembers your choice.",
		// A real case.
		Example: "Folded, one line stays and the Installed models box moves up.",
		// What it helps with.
		Decide: "Whether you want the status in view or more room for the models.",
	}, // end of Monitoring details
	// The Ollama status panel on the main page.
	"API health": {
		// What it means.
		Plain: "Ollama status: does Ollama answer, how many checks failed, and when it last answered correctly.",
		// A real case.
		Example: "3 failed in a row means Ollama has not answered the last 3 checks.",
		// What it helps with.
		Decide: "Whether Ollama is steady enough to rely on right now.",
	}, // end of API health
	// The event log under it.
	"Event log": {
		// What it means.
		Plain: "What changed: models loaded or unloaded, models added or removed, and Ollama going offline or back.",
		// A real case.
		Example: "A line Model loaded: gemma4:e4b means that model was just put into memory.",
		// What it helps with.
		Decide: "Whether a change explains a slow answer or a missing model.",
	}, // end of Event log
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
	// What is stored in the model.
	"Set in the model": {
		// What it means.
		Plain: "Settings stored inside the model in Ollama. Programs that do not send their own value use them.",
		// A real case.
		Example: "After saving 8192, the next load of the model starts at 8192.",
		// What it helps with.
		Decide: "What every program gets when it loads this model.",
	}, // end of Set in the model
	// The default column.
	"Ollama's default": {
		// What it means.
		Plain: "The value Ollama uses for this setting when the model has none saved and a program sends none.",
		// A real case.
		Example: "Temperature 0.8 and top-k 40. The context size is chosen by Ollama when the model loads.",
		// What it helps with.
		Decide: "Whether changing the setting would change anything at all.",
	}, // end of Ollama's default
	// The allowed range column.
	"Allowed values": {
		// What it means.
		Plain: "The range this monitor accepts. Ollama sets no range itself, so these limits protect the model from bad values.",
		// A real case.
		Example: "Temperature 0 to 2. The context size goes up to what the model supports.",
		// What it helps with.
		Decide: "What you can type before the monitor refuses it.",
	}, // end of Allowed values
	// The temperature setting.
	"Temperature": {
		// What it means.
		Plain: "How random the answers are. Low is predictable, high is more varied.",
		// A real case.
		Example: "0.2 suits code and facts; 1 suits chat and stories.",
		// What it helps with.
		Decide: "How exact or how creative you want the answers.",
	}, // end of Temperature
	// The top-k setting.
	"Top-k": {
		// What it means.
		Plain: "Each next word is chosen only from the K likeliest words. Smaller is safer.",
		// A real case.
		Example: "40 is Ollama's default; 1 always takes the single likeliest word.",
		// What it helps with.
		Decide: "How much variety to allow in the choice of words.",
	}, // end of Top-k
	// The top-p setting.
	"Top-p": {
		// What it means.
		Plain: "Each next word comes from the likeliest words whose chances add up to this share.",
		// A real case.
		Example: "0.9 keeps the likeliest words that together make up 90% (percent).",
		// What it helps with.
		Decide: "Lower is more focused, higher is more varied.",
	}, // end of Top-p
	// The min-p setting.
	"Min-p": {
		// What it means.
		Plain: "Drops words that are far less likely than the best one. 0 switches it off.",
		// A real case.
		Example: "0.05 drops words below 5% (percent) of the best word's chance.",
		// What it helps with.
		Decide: "A way to cut odd words while keeping variety.",
	}, // end of Min-p
	// The repeat penalty setting.
	"Repeat penalty": {
		// What it means.
		Plain: "How strongly repeating itself is discouraged. 1 means no penalty.",
		// A real case.
		Example: "1.1 is a mild penalty; 1.5 is strong and can make text odd.",
		// What it helps with.
		Decide: "Raise it a little if the model loops or repeats.",
	}, // end of Repeat penalty
	// The repeat window setting.
	"Repeat window": {
		// What it means.
		Plain: "How many recent tokens (word pieces) are checked for repeats. 0 is off, -1 is the whole context size.",
		// A real case.
		Example: "64 is Ollama's default.",
		// What it helps with.
		Decide: "How far back a repeat is noticed.",
	}, // end of Repeat window
	// The seed setting.
	"Seed": {
		// What it means.
		Plain: "A starting number for the random choices. The same seed gives the same answer.",
		// A real case.
		Example: "With seed 42 the same question gives the same text each time.",
		// What it helps with.
		Decide: "Set it only when you need repeatable answers.",
	}, // end of Seed
	// The answer length setting.
	"Answer length limit": {
		// What it means.
		Plain: "The most tokens (word pieces) one answer may have. -1 means no limit.",
		// A real case.
		Example: "512 stops every answer after about 380 words.",
		// What it helps with.
		Decide: "Stops runaway answers; too small cuts answers short.",
	}, // end of Answer length limit
	// The stop words setting.
	"Stop words": {
		// What it means.
		Plain: "Text that makes the model stop writing when it produces it. You can give several.",
		// A real case.
		Example: "medgemma:latest stops at the text end_of_turn.",
		// What it helps with.
		Decide: "Changing it can make answers end too early or never.",
	}, // end of Stop words
	// The keep-alive time on the Load page.
	"Keep-alive time": {
		// What it means.
		Plain: "How long the model stays in memory after its last use, before Ollama unloads it by itself.",
		// A real case.
		Example: "5 minutes is Ollama's default. Never unload keeps it until you press Unload.",
		// What it helps with.
		Decide: "Fast answers against memory kept free for other work.",
	}, // end of Keep-alive time
	// The performance page: speed of the answer.
	"Answer speed": {
		// What it tells you.
		Plain: "How fast the model writes, in tokens per second. A token is a piece of a word.",
		// A real case from the test machine.
		Example: "medgemma:latest writes about 80 tokens a second, qwen3.6:27b about 36.",
		// What it helps with.
		Decide: "Whether the model feels quick enough for the work you give it.",
	}, // end of Answer speed
	// The performance page: speed of reading the prompt.
	"Prompt reading speed": {
		// What it tells you.
		Plain: "How fast the model reads your question or document before it starts to answer, in tokens per second.",
		// A real case from the test machine.
		Example: "With a short prompt, medgemma:latest read about 640 tokens a second and qwen3.6:27b about 168.",
		// What it helps with.
		Decide: "Whether long documents will make you wait.",
	}, // end of Prompt reading speed
	// The performance page: load time.
	"Load time": {
		// What it tells you.
		Plain: "The time to bring the model from disk into memory. It is near zero when the model is already loaded.",
		// A real case from the test machine.
		Example: "qwen3.6:27b needed 7.0 s to load, medgemma:latest 3.7 s.",
		// What it helps with.
		Decide: "Whether to keep the model loaded longer between uses.",
	}, // end of Load time
	// The performance page: total time.
	"Total time": {
		// What it tells you.
		Plain: "The whole request from start to finish, with the model already loaded.",
		// A real case from the test machine.
		Example: "A 64-token answer took 1.9 s with qwen3.6:27b and 0.78 s with medgemma:latest.",
		// What it helps with.
		Decide: "How long a typical short request takes.",
	}, // end of Total time
	// The performance page: time to first word.
	"Time to first word": {
		// What it tells you.
		Plain: "How long you wait before the first text appears. Warm means the model was loaded; cold includes loading it.",
		// A real case from the test machine.
		Example: "medgemma:latest started writing after 0.03 s when warm.",
		// What it helps with.
		Decide: "Whether the model feels responsive in a chat.",
	}, // end of Time to first word
	// The performance page: tokens counted.
	"Tokens counted": {
		// What it tells you.
		Plain: "How many tokens the test prompt had and how many the model wrote. The test is the same every time.",
		// A real case.
		Example: "About 200 tokens in and at most 64 out.",
		// What it helps with.
		Decide: "Whether two runs can be compared fairly: the same prompt version means yes.",
	}, // end of Tokens counted
	// The performance page: embedding time.
	"Embedding time": {
		// What it tells you.
		Plain: "How long the model needs to turn the fixed text into numbers, with the model already loaded.",
		// A real case from the test machine.
		Example: "rjmalagon/gte-qwen2-instruct needed 0.043 s for a short text.",
		// What it helps with.
		Decide: "Whether it is fast enough to prepare many documents for search.",
	}, // end of Embedding time
	// The performance page: vector length.
	"Vector length": {
		// What it tells you.
		Plain: "How many numbers the model produces for one text. It belongs to the model, not to the machine.",
		// A real case from the test machine.
		Example: "rjmalagon/gte-qwen2-instruct gives 1536 numbers.",
		// What it helps with.
		Decide: "Whether it fits the search system that will store the numbers.",
	}, // end of Vector length
	// The performance page: processor split.
	"Processor split": {
		// What it tells you.
		Plain: "How much of the model sits in the graphics card's memory, and how much is left to the processor and main memory.",
		// A real case from the test machine.
		Example: "qwen3.6:27b ran 100% on the graphics card.",
		// What it helps with.
		Decide: "A processor share explains slow answers; a smaller model may fit on the graphics card.",
	}, // end of Processor split
	// The performance page: memory used.
	"Memory used": {
		// What it tells you.
		Plain: "The memory Ollama reports for the loaded model.",
		// A real case from the test machine.
		Example: "qwen3.6:27b: 18.8 GB (gigabytes).",
		// What it helps with.
		Decide: "Whether another model still fits next to it.",
	}, // end of Memory used
	// The comparison page: when the test was made.
	"Tested on": {
		// What it tells you.
		Plain: "The date and time of the saved test whose figures are shown.",
		// A real case.
		Example: "Only the latest test of each model is shown, so two rows can come from different days.",
		// What it helps with.
		Decide: "Whether the figures are recent enough to trust.",
	}, // end of Tested on
	// The comparison page: place in the ranking of the group.
	"Speed vs fastest": {
		// What it tells you.
		Plain: "Its place among the like-for-like models of its group, and how many times slower than the first it is.",
		// A real case.
		Example: "#1, fastest leads its group. \"not ranked\" means a caution in the last column keeps the row out of the ranking.",
		// What it helps with.
		Decide: "Which model to pick when speed matters, without comparing unlike models.",
	}, // end of Speed vs fastest
	// The comparison page: speed in characters per second.
	"Characters per second": {
		// What it tells you.
		Plain: "How many characters the model writes each second. Counted the same way for every model, so makers can be compared.",
		// A real case.
		Example: "Models cut text into tokens differently, so 40 tokens/s from two makers can differ; characters do not.",
		// What it helps with.
		Decide: "Which model is really faster at writing the same kind of answer.",
	}, // end of Characters per second
	// The comparison page: load speed.
	"Load speed from disk": {
		// What it tells you.
		Plain: "The model's size divided by its cold load time: how fast it was brought into memory.",
		// A real case from the test machine.
		Example: "qwen3.6:27b: 18.8 GB (gigabytes) in 7.0 s is about 2.7 GB (gigabytes) a second.",
		// What it helps with.
		Decide: "How long a model keeps you waiting after it was unloaded.",
	}, // end of Load speed from disk
	// The comparison page: busy machine.
	"Machine busy": {
		// What it tells you.
		Plain: "Whether the machine looked busy when the test ran. A busy machine makes the figures too low.",
		// A real case.
		Example: "A test made while another model was answering shows lower speeds than an idle machine.",
		// What it helps with.
		Decide: "Whether to repeat the test when the machine is idle.",
	}, // end of Machine busy
	// The comparison page: whether a row can be ranked.
	"Fair to rank?": {
		// What it tells you.
		Plain: "Whether this test is like the others of its group. If not, the reasons are shown and the row is not ranked.",
		// A real case.
		Example: "A model tested two days before the others, or with a different precision, is not ranked.",
		// What it helps with.
		Decide: "Whether to trust a ranking, or to test the models again together.",
	}, // end of Fair to rank
	// The performance page: change since the previous run.
	"Change since the previous run": {
		// What it tells you.
		Plain: "How much a figure moved compared with the last test of the same model, as a percentage.",
		// A real case.
		Example: "38 tokens/s before and 31 tokens/s now is -18%, which is slower.",
		// What it helps with.
		Decide: "Whether a setting, an update or a busy machine made the model faster or slower.",
	}, // end of Change since the previous run
	// The performance page: processor cores.
	"CPU cores": {
		// What it tells you.
		Plain: "How many processor cores the computer has.",
		// A real case from the test machine.
		Example: "20 on this computer.",
		// What it helps with.
		Decide: "How much room the processor has when part of a model spills onto it.",
	}, // end of CPU cores
	// The performance page: processor load.
	"CPU load": {
		// What it tells you.
		Plain: "How busy the processor was during the last minute. Compare it with the number of cores.",
		// A real case from the test machine.
		Example: "A load of 1.8 on 20 cores is quiet.",
		// What it helps with.
		Decide: "Whether other work disturbed the test.",
	}, // end of CPU load
	// The performance page: free memory.
	"Memory free": {
		// What it tells you.
		Plain: "The memory the system could still hand out, before the test and with the model loaded.",
		// A real case from the test machine.
		Example: "About 114 GB (gigabytes) before and 105 GB (gigabytes) with medgemma:latest loaded.",
		// What it helps with.
		Decide: "Whether the machine was short of memory.",
	}, // end of Memory free
	// The performance page: swap.
	"Swap in use": {
		// What it tells you.
		Plain: "Memory that spilled over to the disk, which is far slower than real memory.",
		// A real case from the test machine.
		Example: "0 GB (gigabytes) in use on this computer.",
		// What it helps with.
		Decide: "Why a run was very slow.",
	}, // end of Swap in use
	// The performance page: other models in memory.
	"Other models loaded": {
		// What it tells you.
		Plain: "Models that were already in memory when the test started. They share the machine with the tested model.",
		// A real case from the test machine.
		Example: "None during the first experiments.",
		// What it helps with.
		Decide: "Whether the figures are fair.",
	}, // end of Other models loaded
	// The performance page: graphics card.
	"GPU": {
		// What it tells you.
		Plain: "The graphics card the monitor could see, and how busy it was then. Shared memory shows as not reported.",
		// A real case from the test machine.
		Example: "The NVIDIA graphics card in this computer was 0% busy before the test.",
		// What it helps with.
		Decide: "Whether the graphics card was shared with other work.",
	}, // end of GPU
} // end of helpTexts

// helpFor returns the tooltip for a heading, and false when there is none.
func helpFor(heading string) (tooltip, bool) {
	// Look the heading up in the table.
	t, ok := helpTexts[heading]
	// Hand back both answers.
	return t, ok
} // end of helpFor
