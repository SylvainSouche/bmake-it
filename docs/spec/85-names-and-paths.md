# Names and paths: special characters through the chain of calls

What happens when a workspace, framework or module directory name — or a
directory above the workspace, or the directory the `mk/` files are installed in
— contains a character that make or the shell treats specially. Measured on
macOS (bmake 20260406, `/bin/sh`), 2026-11-07; the harness case
`116-path-characters` repeats the measurement on every platform the suite runs
on. Contract: `path-characters-contract-dec`, `path-characters-supported-req`,
`path-characters-refused-upfront-req`. Measurements:
`path-characters-measured-obs`.

## The result in one table

A tiny workspace (one framework, one module) built and cleaned with each
character in the module name, in the workspace name (with a parent directory
carrying it too), in every name at once, and with the `mk/` directory installed
under a name that carries it.

| Character | Outcome | Layer that fails |
|---|---|---|
| `[` `]` `%` `~` `@` `+` `^` `-` `é` `日本` | works everywhere | — |
| space, tab, `'` `"` `\` `` ` `` `$` `;` `&` `\|` `<` `>` `(` `)` | build stops | the shell (word splitting, quoting, operators, substitution) |
| `{` `}` | build stops (`{` `}` works in a workspace name) | order generator writes the name into a variable name |
| `#` | build stops | make: `#` ends an expression like `${X:U<path>}` |
| `:` `!` | build stops | make: the name lands in a dependency line |
| `,` | build stops at link | the linker flag `-Wl,-rpath,<path>` |
| `*` `?` `=` | **build says it succeeded and builds nothing** | make: the name lands in a dependency line |

Most characters that stop the build in a workspace or module name work in the
`mk/` directory name (`# ! : , = * ? { }`): the `mk/` path is quoted, or never
reaches a dependency line, in most places. Space, quotes, `$`, `;`, `&`, `|`,
`<`, `>`, `(`, `)`, `` ` `` and `\` fail there too.

The worst row is the last. A build that did nothing and reports
"workspace build complete" is worse than a failure: a user sees success, and a
CI run turns green with no binary.

## The chain of calls

A name travels through every layer below; each layer re-reads it with its own
rules. A character that is harmless in one layer breaks the next.

```
user's shell
  └ bmake  (-C dir, VAR=value arguments; MAKEFLAGS re-serialises them)
      └ makefile parse (dependency lines, assignments, ${..} expressions, # comments)
          └ recipe → sh -c   (the recipe becomes a temporary script)
              ├ $(...) / `...` capture (-V queries read back and re-split)
              ├ for _m in ${SUBDIR_MODULES}   (a whitespace-separated list)
              └ child bmake:  ${MAKE} -C ${_m} all VAR=value …
                  └ scripts (gen-mod-order.sh, gen-fw-order.sh): find, cd, read
                      ├ generated makefile (.gen-mod-order.mk: MODULE_DEPS.<name>=)
                      └ compiler / linker (-I -L -Wl,-rpath,<path>, -MF depfile)
```

| Layer | Rule that bites | Seen as |
|---|---|---|
| 1. `bmake -C dir` and `VAR=value` | bmake stores its arguments in `MAKEFLAGS` and re-reads them in the child; an `=` in the `-C` argument is read as an assignment | `bmake -C 'm=od.m' all` prints nothing and exits 0 |
| 2. makefile parse | a dependency line `${_OBJDIR}/x.o: ${.CURDIR}/src/x.c` is read after expansion: `=` makes it an assignment, `:` and `!` split the target, `*` `?` `[` are globbed, `#` starts a comment, `$` is expanded, `{` `}` unbalance an expression | silent no-op (`=`), "duplicate script for target" (`:` `!`), `Unclosed expression` (`#`) |
| 3. recipe in `sh -c` | an unquoted `${.CURDIR}` is split at spaces and tabs, globbed, and read for quotes, `$`, `` ` ``, `;` `&` `\|` `<` `>` `(` `)` | `cd: /…/a: No such file`, `syntax error near unexpected token`, `b-ws: command not found` |
| 4. word lists | `SUBDIR_MODULES`, `PREREQS` and the order files are whitespace-separated, so a name with whitespace is two names | module built as two directories |
| 5. child bmake | the sub-make is started with the same unquoted words, and its `-V` answer is re-split | as layers 1 and 3, one level down |
| 6. scripts and generated files | `gen-mod-order.sh` writes the name into a variable name of a generated makefile | `Invalid line "MODULE_DEPS.m{m.m="` |
| 7. compiler and linker | `-Wl,-rpath,<path>` is split at `,`; a path with whitespace needs a response file | `ld: file cannot be open() path=od.m/…` |

Of 374 path-bearing expansions in recipe lines of `mk/*.mk`, 56 (15 %) sit
inside quotes.

Two further observations:

- **`$` rewrites the name.** A directory `m$m.m` is read by make as `m` followed
  by the variable `$m`, which is empty: the module becomes `m.m`, a directory
  that does not exist.
- **A name is executed.** A directory named with a backquote or `$(…)` makes the
  shell run what is inside it when the unquoted path is used. Building an
  untrusted checkout already runs its makefiles, so this is no new trust
  boundary, but it makes the failure look like a command-not-found.

## What bmake offers, and what it cannot do

`${X:Q}` quotes a value for the shell and would fix layers 3 to 5 for space,
quotes, `$`, `;` `&` `|` `<` `>` `(` `)`. It does nothing for layers 1, 2, 6
and 7 (`= : ! # * ? { } ,`), which are make's own syntax or another program's, so
quoting everything cannot make every name work. The way out for those is to
refuse them.

## The contract (decided)

What is tested to work is valid, and must be supported and tested: **a
character that works on any platform works on every platform**. A mixed result
is fixed, not refused — `=` works under Debian's bmake and builds nothing under
macOS's and Alpine's, so the build is made to work there. **What works nowhere
is tested upfront and refused with an explanation**, before any build step.
There is one exception to refusing: characters evidently expected to work are
supported even though they fail today. Decided: **space, parentheses `( )`,
apostrophe `'`, ampersand `&` and hash `#`** (`C:\Program Files (x86)`,
`John's Documents`, `R&D`, `C# projects`). A comma is not in that set and is
refused. No outcome is ever a silent success.

A character is judged where it was measured, so the sets differ by place:

| Where | Works | Meant to work, not yet | Refused |
|---|---|---|---|
| workspace, framework, parent directory | `[ ] % ~ @ + ^ - = { }` (`%` stops the link under FreeBSD's make, `=` builds nothing under some bmakes: both are being fixed), non-ASCII | space `( ) ' &` `#` | tab, backslash, `"`, backquote, `$ ; \| < >`, `* ? ! : ,` |
| module (`*.m`, `*.tst`) name | `[ ] % ~ @ + ^ - =`, non-ASCII | space `( ) ' &` `#` | the above and `{ }` |
| the `mk/` directory's name | `[ ] % ~ @ + ^ - = # ! : , * ? { }`, non-ASCII | space `( ) ' &` | tab, backslash, `"`, backquote, `$ ; \| < >` |

"Not yet" is refused today with a message that says so, so that the failure is
a plain sentence and not a shell error, and the unquoted `rm -rf` of a path with
a space in it never runs. A space is not only a failure: `clean` removes
`${.CURDIR}/build/…` unquoted, so in `/home/me/my projects/ws` it would remove
`/home/me/my` and `projects/ws/build` relative to wherever it runs. The check
therefore runs for `clean` and `-V` queries too.

### Where the check is

- `mk.common.mk` (every role file reads it) runs `scripts/check-names.sh` first
  thing. It reads the directory from the shell (`pwd -P`) and the `mk/` directory
  from `BMK_MKDIR` in the environment — never `.CURDIR` or a command line: make
  expands a variable's value again each time it is used, so a `$` in a directory
  name is already gone when the makefile sees it.
- `gen-fw-order.sh` and `gen-mod-order.sh` check each framework and module
  directory they discover, before the first use of its name, so the message
  comes from the parent and not from a shell error in the middle of a recipe.
- `scripts/bmk-names.sh` holds the rules (what is refused, what is "not yet");
  nothing else knows them.

A refused name stops the build with one message, for example:

```
Bmake It cannot build in /work/ws/Fw/m od.m: the name 'm od.m' contains a space,
which Bmake It is meant to support and does not yet. Letters, digits and
. _ - + @ % ~ ^ [ ] = and non-ASCII letters work in a directory name; rename
the directory (docs/spec/85-names-and-paths.md).
```

One case cannot be caught: a `$` in the `mk/` directory's own name. Make
expands it in the `.include` that loads `mk.common.mk`, so bmake stops with
"Could not find" before any Bmake It file runs.

## Making the rest work (open)

Each of these is a change, not a refusal, and each removes a "not yet" or a
platform difference:

1. **`=` and `%` (and `: ! * ? #`, in the make layer): relative targets.** The rules are
   written with the absolute directory in the target (`${_OBJDIR}/x.o:
   ${.CURDIR}/src/x.c`). A build always runs in the module directory, so
   `build/<key>/obj/x.o: src/x.c` carries none of the path, and the characters
   that make reads as syntax never reach a dependency line. Only the module's
   own name remains, in `-C`, where bmake's `MAKEFLAGS` re-reads an `=`; `cd` and
   a plain `bmake` in the directory avoid it.
2. **Space, `( ) ' &`: quote the shell layer.** `${X:Q}` on the ~320 unquoted path
   expansions in recipes, and a word-list representation for `SUBDIR_MODULES`,
   `PREREQS` and the order files that does not split at a space.
3. **`#`: the `${X:U<path>}` expressions** in `mk.local.mk` and the other places
   a path is the default of a modifier.
4. **`{ }` in module names:** encode the name in the variable name that
   `.gen-mod-order.mk` writes (`MODULE_DEPS.<name>`).
5. **A linker option with a path** (`-Wl,-rpath,<path>`) needs `-Xlinker` form
   for a comma; a comma stays refused, so this only matters for 2.

Every one of them is done by moving a character from "not yet" to "works" in
`bmk-names.sh` and in the case's `MUST_FIX` list at the same time.

### Measured on the BSDs (2026-11-08)

The same case on FreeBSD 15.1 and NetBSD 10.2 (arm64 guests), run from the
cache copied to the network drive:

- **NetBSD 10.2**: the same table as macOS, including `=` silent and `%` working.
- **FreeBSD 15.1**: the same, except that **`%` stops the link** in the workspace,
  the module and every-name places (it works in the `mk/` name). The compile
  works and the link fails with "cannot open output file …/bin/x": the rule that
  creates `build/<key>/bin` has a target path containing `%`, which FreeBSD's make
  reads as a pattern. So `%`, which works on macOS, NetBSD and Linux, is a
  mixed-platform character like `=`, meant to work everywhere, and fixed by the
  same relative targets. Until then the case lists it with `=` and ends SKIP
  where it fails.

## The case

`tests/cases/116-path-characters`: for each of 36 characters, builds and cleans
a tree with the character in the module name, in the workspace name (and a
parent directory), in every name at once, and with the `mk/` files installed
under a name that carries it. The expectation per place is the table above.
A refusal must carry the message (`Bmake It cannot …`); any other failure
(`raw`), or a build that says it succeeded and built nothing (`SILENT`), fails
the case. The case ends SKIP while a meant-to-work character is still refused
as "not yet", or builds nothing under this platform's bmake (`=`); it fails on
any other deviation. A character the file system itself refuses (Windows:
`" * ? < > | : \`) is skipped for that character. Measured with the earlier
version of this case (no check yet): the same table on macOS, Linux glibc arm64
and musl amd64.
