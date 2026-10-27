// Package main tells Go that this folder builds into a runnable program.
package main

// LEGAL REVIEW: the wording of the notices below is a draft written without legal advice. It lives only in this file so that a qualified lawyer can replace it without touching any other code. A test checks that every page and download carries whatever text is here.

// noticeShort is the one-paragraph notice shown at the top of the comparison page and in the footer of every page of the PDF.
const noticeShort = "Informational only. These figures measure speed and memory use on one computer. They are not a clinical validation and must not be used to decide whether a model is suitable or safe for patient care."

// noticeTitle is the heading of the full notice.
const noticeTitle = "Notice and limitation of liability"

// noticeFull is the full notice, one paragraph per entry; each starts with a short label so that it can be read in pieces.
var noticeFull = []string{
	// What the figures are.
	"Purpose. The figures here are informational measurements of speed and memory use, made on one computer at the times shown, with a fixed test prompt. They say nothing about the quality, accuracy or safety of the answers a model gives.",
	// What they must not be used for.
	"Not for clinical use. They are not a clinical validation, a medical-device assessment, a regulatory submission or a certification, and must not be used to decide whether a model is suitable or safe for patient care or for any clinical, diagnostic or treatment decision.",
	// Whose responsibility it is.
	"Your responsibility. Results can differ on other hardware, software versions, settings or days. You are responsible for validating any model for your intended use, under the rules that apply to you.",
	// The liability clause, using the names kept in about.go.
	"No warranty and no liability. This software and these results are provided \"as is\", without warranty of any kind, express or implied. To the fullest extent permitted by applicable law, " + companyName + " (termgate.com), the developer (" + appDeveloper + ") and any contributors accept no liability for any loss, damage or decision arising from the use or misinterpretation of this software, these figures or any file made from them. Nothing here limits any liability that cannot be limited by law.",
	// Third parties.
	"Third parties. Names of benchmarks, models, products and publications belong to their owners. They are mentioned for reference only and do not mean that their owners endorse, or are connected with, this software or " + companyName + ".",
} // end of noticeFull
