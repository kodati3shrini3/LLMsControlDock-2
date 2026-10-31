// Package main tells Go that this folder builds into a runnable program.
package main

// reference is one source that the comparison page cites. Every entry was opened and read, and its title, authors and address were copied from the page itself.
type reference struct {
	// N is the number shown in brackets in the text, starting at 1 without gaps.
	N int
	// Authors names the people or the organisation behind the source.
	Authors string
	// Title is the exact title of the source.
	Title string
	// Where says what kind of source it is and any version or date the page itself shows.
	Where string
	// URL is the exact address that was opened.
	URL string
	// Used says in one sentence what this page takes from the source.
	Used string
} // end of reference

// referencesChecked is the day the addresses were opened and read, written the way the page shows it.
const referencesChecked = "27 October 2026"

// compareReferences is the verified list of sources. Nothing may be added unless the page behind it was opened and read, and a test keeps the list, the markers in the page text and the allowed addresses in step.
var compareReferences = []reference{
	// Source 1.
	{
		// Number.
		N: 1,
		// Authors as the page shows them.
		Authors: "Vinh Nguyen, Wenwen Gao, Emily Apsey, Ganesh Kudleppanavar, Neelay Shah and Elias Bermudez (NVIDIA)",
		// Title as the page shows it.
		Title: "LLM Inference Benchmarking: Fundamental Concepts",
		// Kind and date.
		Where: "Blog article, 2 April 2025",
		// Address.
		URL: "https://developer.nvidia.com/blog/llm-benchmarking-fundamental-concepts",
		// What we take from it.
		Used: "Fix the workload and the sampling, leave the warm-up out, and match the test to the real use.",
	}, // end of source 1
	// Source 2.
	{
		// Number.
		N: 2,
		// Authors.
		Authors: "NVIDIA",
		// Title.
		Title: "Metrics (LLM section of the NVIDIA NIM Benchmarking Documentation)",
		// Kind and version.
		Where: "Documentation, version 2.0.0 (Latest); read again on 31 October 2026",
		// Address.
		URL: "https://docs.nvidia.com/nim/benchmarking/llm/metrics",
		// What we take from it.
		Used: "Definitions of the speed and delay figures, and the rule to compare results only when the definitions align.",
	}, // end of source 2
	// Source 3.
	{
		// Number.
		N: 3,
		// Authors.
		Authors: "Artificial Analysis",
		// Title.
		Title: "Artificial Analysis Language Model API Performance Benchmarking Methodology",
		// Kind and version.
		Where: "Methodology page, version 2.2.0 (2 March 2026) in its version history",
		// Address.
		URL: "https://artificialanalysis.ai/methodology/performance-benchmarking",
		// What we take from it.
		Used: "The median of repeated runs, the same settings for every model, and one common way of counting tokens so that models with different tokenizers can be compared.",
	}, // end of source 3
	// Source 4.
	{
		// Number.
		N: 4,
		// Authors.
		Authors: "Vijay Janapa Reddi and others",
		// Title.
		Title: "MLPerf Inference Benchmark",
		// Kind and date.
		Where: "arXiv preprint 1911.02549, version 2, 9 May 2020",
		// Address.
		URL: "https://arxiv.org/abs/1911.02549",
		// What we take from it.
		Used: "The one-query-at-a-time (single-stream) scenario, fixed rules for results that are to be compared, and the rule that results under different rules are not directly comparable.",
	}, // end of source 4
	// Source 5.
	{
		// Number.
		N: 5,
		// Authors.
		Authors: "Ollama",
		// Title.
		Title: "Usage (Ollama API documentation)",
		// Kind and date.
		Where: "Documentation page",
		// Address.
		URL: "https://docs.ollama.com/api/usage",
		// What we take from it.
		Used: "The meaning of the timing and token-count fields that every figure here is worked out from; durations are in nanoseconds.",
	}, // end of source 5
	// Source 6.
	{
		// Number.
		N: 6,
		// Authors.
		Authors: "Niklas Muennighoff, Nouamane Tazi, Loïc Magne and Nils Reimers",
		// Title.
		Title: "MTEB: Massive Text Embedding Benchmark",
		// Kind and date.
		Where: "arXiv preprint 2210.07316, version 3",
		// Address.
		URL: "https://arxiv.org/abs/2210.07316v3",
		// What we take from it.
		Used: "Embedding models are benchmarked on their own tasks, and no single embedding method wins on every task.",
	}, // end of source 6
} // end of compareReferences
