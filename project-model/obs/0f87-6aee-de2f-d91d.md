---
schema_version: 2
id: 0f87-6aee-de2f-d91d
alias: path-characters-measured-obs
type: obs
status: recorded
origin: Claude, 2026-11-07, user asked to check names and full paths of workspace, framework and module on all supported OSes and to add harness tests for escaping through the chain of shell/makefile invocations
created: 2026-11-07
generator: model.py/2.4.0
checksum: d64aab686966
---

# Special characters in workspace, framework, module and install-directory names: 65 of 185 cells build on macOS, and = * ? build nothing yet succeed

Measured on macOS (bmake 20260406, /bin/sh) with 36 characters in 5 placements (module, framework, workspace, parent directory, mk directory). Builds: [ ] % ~ @ + ^ - e-acute and CJK everywhere. Stops at the shell: space, tab, quotes, backslash, $, backtick, ; & | < > ( ). Stops in make: # (an expression cut by the comment), : and ! (the name lands in a dependency line), { } (the order generator writes the name into a variable name of .gen-mod-order.mk). Stops at the linker: comma (-Wl,-rpath,path). SILENT SUCCESS: = * ? -- the dependency lines are read as an assignment or globbed, the module builds nothing and the workspace build reports complete with exit 0; bmake -C 'm=od.m' all also prints nothing and exits 0 (MAKEFLAGS re-reads the argument). A $ in a name rewrites it (m$m.m becomes m.m). Only 56 of 374 path expansions in mk recipes are quoted. Write-up: docs/spec/85-names-and-paths.md; repeated on every platform by case 116.
