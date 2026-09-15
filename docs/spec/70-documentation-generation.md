# Bmake It — 70: Documentation Generation

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.
Implemented in `mk/mk.docs.mk`, verified end-to-end on `examples/myworkspace`.

## Tool and scope

C/C++ documentation is generated via **Doxygen** — the mainstream tool for
the language, not a bespoke format. The generation mechanism itself is
pluggable per language: extending Bmake It's language support must be able
to bring that language's own appropriate mainstream doc tool rather than
being forced through Doxygen (`REQ-doc-generation-per-language-tool-pluggable-req`).

Default scope is **public headers only** (a framework's `include/`).
Internal (public+local scope) generation is a distinct trigger — see
"QA-enforcement mode" below.

## Invocation and cross-framework linking

`bmake docs`:

- **From within a framework**: generates just that framework's own
  documentation.
- **From the workspace root**: generates documentation for every
  framework present in the workspace, plus a workspace-level aggregation
  page (`REQ-doc-generation-invocation-scope-req`).

Cross-framework links (e.g. `Hello`'s docs linking to a type defined in
`System`, its `PREREQS=`) use Doxygen's own `GENERATE_TAGFILE`/`TAGFILES`
mechanism: each framework emits `docs/<name>.tag` alongside its HTML, and
a dependent framework's `Doxyfile` references its `PREREQS=` frameworks'
tag files, chained in `PREREQS=` order — reliable for HTML cross-links;
PDF output renders a tag-file reference as plain text, not a live link, a
known Doxygen limitation, not a Bmake It bug
(`REQ-doc-generation-doxygen-based-req`).

The workspace-level `bmake docs` also produces an aggregation landing page
listing every framework and its generated docs — analogous to the
`AllNames.htm`/`main.htm` aggregation pattern from Dassault Systèmes'
CAADoc/mkmancpp, one of this design's real precedents alongside plain
Doxygen.

## PDF grouping (`DOCWITH=`)

PREREQS-order connectivity is **not** used to decide what gets bundled
into one PDF — a top-level framework's PREREQS chain can be large, and
naively embarking everything it transitively depends on into one PDF was
explicitly rejected. Instead, a framework's makefile may declare
`DOCWITH=<fw1> <fw2> ...` naming other frameworks to cluster into the same
PDF output, an explicit, opt-in grouping independent of the PREREQS graph
(`REQ-doc-pdf-docwith-explicit-grouping-req`).

## Project metadata

Doxygen's `PROJECT_NAME`/`PROJECT_NUMBER`/`PROJECT_BRIEF`/`PROJECT_LOGO`
and a license-notice `HTML_FOOTER` are auto-detected from conventional
files at the workspace root (`VERSION`, `LICENSE`, `docs/logo.{png,svg}`)
and silently omitted when absent — no separate documentation-metadata
mechanism. A workspace or framework overrides any of them via its own
`pre.mk` (see `50-makefile-macros.md` for the local-mk mechanism this
reuses), setting `DOC_PROJECT_NAME=`/`DOC_PROJECT_VERSION=`/
`DOC_PROJECT_BRIEF=`/`DOC_LOGO=`/`DOC_LICENSE_NOTICE=` before
`mk.docs.mk` computes its defaults
(`REQ-doc-project-metadata-conventions-req`).

## QA-enforcement mode

A distinct CLI trigger generates *internal* (public+local scope)
documentation and escalates Doxygen's undocumented/incomplete-
documentation warnings to hard build failures — for use as an internal-
documentation and quality-assurance-enforcement mechanism, separate from
the public-scope default (`REQ-doc-generation-local-qa-trigger-req`).

## Output

`docs/html/index.html` per framework (plus `docs/<name>.tag`); a
workspace-level `docs/index.html` aggregation page when invoked from the
workspace root. Generated output is not committed to the repository — see
`.gitignore`'s `examples/**/docs/` entry for the worked example.
