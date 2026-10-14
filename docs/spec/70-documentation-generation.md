# Bmake It — 70: Documentation Generation

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.
Implemented in `mk/mk.docs.mk`, verified end-to-end on `examples/myworkspace`.

## Tool and scope

C/C++ documentation is generated via **Doxygen** — the mainstream tool for
the language, not a bespoke format. The generation mechanism itself is
pluggable per language: extending Bmake It's language support must be able
to bring that language's own appropriate mainstream doc tool rather than
being forced through Doxygen (`REQ-doc-generation-per-language-tool-pluggable-req`).

Default scope is **public headers only** (a framework's `include/`);
a framework may add directories with `DOC_INPUT_EXTRA=` (see "Extra
inputs and warnings" below). Internal (public+local scope) generation is a distinct trigger — see
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

## Scoping (`bmake-docs-scoping-fix-req`)

Not every framework gets documentation, and the landing page doesn't live
where a project's own hand-written docs might already be:

- **`DOCS=no`** on a framework opts it out entirely — no `Doxyfile`, no
  output, no warnings, just a one-line "docs skipped" message.
- **A framework with no public `include/`** (local-only — an app-only
  framework exposing nothing to `PREREQS=` consumers, or one built
  entirely from `IMPORT=`-resolved modules with nothing of this
  project's own to document) is skipped the same way, automatically —
  rather than running Doxygen against a nonexistent `INPUT` and
  producing an empty page plus `INPUT ... does not exist`/`No files to
  be processed` warnings (found in real use: a Viewer-class, app-only
  framework).
- **The workspace landing page lives under `WS_DOCS_DIR`** (default
  `build/docs/`, matching this project's own generated-output
  convention), never the bare `docs/` a project's own hand-written
  documentation commonly already occupies (found in real use: the
  landing page silently overwrote content inside the project's own
  `docs/`). Per-framework `DOCS_DIR` — where each framework's *own*
  docs live — is unchanged; the landing page's own relative links are
  computed from `WS_DOCS_DIR`'s own path depth, and only list a
  framework whose docs were actually generated.

## Extra inputs and warnings (`docs-input-extra-warn-knobs-req`)

Opt-in, per-framework knobs, set in the framework's `makefile` before
`.include <mk.framework.mk>`. Their defaults reproduce the plain
public-headers Doxyfile exactly:

| Macro | Default | Effect |
|---|---|---|
| `DOC_INPUT_EXTRA=` | empty | Directories, relative to the framework, appended to `INPUT` after `include/` (e.g. `local/include openrider.m/src`). When set, `FILE_PATTERNS` is restricted to headers (`DOC_FILE_PATTERNS`, default `*.h *.hh *.hpp *.hxx *.h++`), so a module's `.c`/`.cpp` sources in the same directory are not scanned. |
| `DOC_WARN_IF_UNDOCUMENTED=` | `NO` | Passed through to Doxygen's `WARN_IF_UNDOCUMENTED`; `YES` makes Doxygen report every undocumented entity in `INPUT`. |
| `DOC_EXTRACT_PRIVATE=` | `NO` | Passed through to `EXTRACT_PRIVATE` (written only when not `NO`). |

A framework with no public `include/` but a non-empty `DOC_INPUT_EXTRA`
is **documented**, from the extra directories alone, rather than skipped
(see "Scoping" above): an app-only framework that keeps its code in
`local/include` can opt into documentation without inventing a public
`include/`. Example:

```make
PREREQS=System
DOC_INPUT_EXTRA=local/include openrider.m/src
DOC_WARN_IF_UNDOCUMENTED=YES
.include <mk.framework.mk>
```

These knobs make undocumented entities *visible*; escalating them to
hard failures is the separate QA trigger below.

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
workspace-level `build/docs/index.html` aggregation page when invoked
from the workspace root. Generated output is not committed to the
repository — see `.gitignore`'s `examples/**/docs/` entry for the worked
example.
