# Bmake It

A BSD-make-based, cross-platform build system for C/C++ (and lex/yacc),
inspired by Dassault Systèmes RADE/`mkmk` concepts (workspaces, frameworks,
modules, prerequisites) while staying idiomatic to BSD make. Shorthand: `bmk`.

## Layout

- [`impl/`](impl/) — the build system itself: `mk.*.mk` role makefiles,
  toolchain wrappers, and a worked example workspace. Start here to build
  something. See [`impl/README.md`](impl/README.md) for a quick start.
- [`specs/`](specs/) — design specification (`specs/spec/`), the
  discovery-driven-dev project model (`specs/project-model/`) tracking every
  requirement/decision/observation/implementation and their relationships,
  and the LaTeX package manual (`specs/docs/`).

## Methodology

`specs/project-model/` was built with **discovery-driven-dev**, a Claude Code
skill for keeping requirements, decisions, and implementation links in durable
files instead of conversation history. Bmake It was its first real testbed;
link to the skill's own repo to follow once it's published.

## License

BSD 3-Clause — see [`LICENSE`](LICENSE).
