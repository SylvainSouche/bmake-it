# Names and paths: special characters through the chain of calls

What happens when a workspace, framework or module directory name — or a
directory above the workspace, or the directory the `mk/` files are installed in
— contains a character that make or the shell treats specially. Measured on
macOS (bmake 20260406, `/bin/sh`), 2026-11-07; the harness case
`116-path-characters` repeats the measurement on every platform the suite runs
on. Proposed contract: `path-characters-contract-cand` (open). Measurements:
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

## Proposed contract (`path-characters-contract-cand`)

1. **Supported** characters work in every name and in the install directory of
   `mk/`, on every platform: letters, digits and `. _ - + @ % ~ ^ [ ]` and
   non-ASCII letters.
2. **No silent success**: a build that built nothing never says it succeeded.
3. **Everything else is refused up front**, before any build step, with a
   message that names the offending character, the path and the rule — the
   project-wide rule that a wrong input ends in a readable error
   (`graceful-error-on-missing-variable-req`) — for a workspace, framework or
   module name, a directory above them, and the `mk/` directory.

Whether to also quote (layers 3 to 5) so that space and the shell characters
work is a separate decision: it is a change to about 320 expansions for
spaces in a path, which matters most on Windows (`C:\Users\First Last`) and
macOS (`~/Library/Mobile Documents`). The refusal in point 3 is cheap and
comes first.

## The case

`tests/cases/116-path-characters`: for each character, builds and cleans a tree
with the character in the module name, in the workspace name, in every name
at once, and with the `mk/` files installed under a name that carries it.
Contract 1 and 2 are checked. The case ends SKIP where a known gap
(`star question equals`, silent success) is open — whether it is depends on the
bmake version: `=` builds nothing under bmake 20260406 and works under Debian's —
and fails on any other violation. Contract 3 is not
checked yet: it needs the wording of the message. A character the file system
itself refuses (Windows: `" * ? < > | : \`) is skipped for that character.
