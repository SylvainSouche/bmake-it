# Names and paths: special characters through the chain of calls

What happens when a workspace, framework or module directory name — or a
directory above the workspace, or the directory the `mk/` files are installed in
— contains a character that make or the shell treats specially. Measured on
macOS (bmake 20260406, `/bin/sh`), 2026-11-07; the harness case
`116-path-characters` repeats the measurement on every platform the suite runs
on. Contract: `path-characters-contract-dec`, `path-characters-supported-req`,
`path-characters-refused-upfront-req`; how the supported characters get through:
`path-characters-names-as-words-dec`. Measurements:
`path-characters-measured-obs`.

The first half of this page is the measurement that led to the contract; the
second half ("The contract", "How the supported characters get through") is what
Bmake It does now. **Now: a space, `( ) ' & #` and the others the first table
marks "works" are all supported in every place; what the table shows failing is
refused, or fixed, as the second half says.**

## The result in one table (before the fix)

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

`${X:Q}` quotes a value for the shell and fixes layers 3 to 5 for space,
apostrophe, `;` `&` `|` `<` `>` `(` `)` (and, in a recipe, `$` and quotes, which
are refused here for other reasons). It does nothing for layers 1, 2, 6
and 7 (`= : ! # * ? { } ,`), which are make's own syntax or another program's, so
quoting everything cannot make every name work. For `=`, `%`, `#`, space and
parentheses the way out is to keep the name out of the place make reads it
(relative paths, encoded words, a link); for the others it is to refuse them.

## The contract (decided)

What is tested to work is valid, and must be supported and tested: **a
character that works on any platform works on every platform**. A mixed result
is fixed, not refused — `=` works under Debian's bmake and builds nothing under
macOS's and Alpine's, so the build is made to work there. **What works nowhere
is tested upfront and refused with an explanation**, before any build step.
There is one exception to refusing: characters evidently expected to work are
supported even though they failed at first. Decided: **space, parentheses
`( )`, apostrophe `'`, ampersand `&` and hash `#`** (`C:\Program Files (x86)`,
`John's Documents`, `R&D`, `C# projects`). A comma is not in that set and is
refused. No outcome is ever a silent success.

All of them now work, in every place, on every platform the suite runs on.

A character is judged where it was measured, so the sets differ by place:

| Where | Works | Refused |
|---|---|---|
| workspace, framework, parent directory | space `( ) ' & #` `[ ] % ~ @ + ^ - = { }`, non-ASCII | tab, backslash, `"`, backquote, `$ ; \| < >`, `* ? ! : ,` |
| module (`*.m`, `*.tst`) name | space `( ) ' & #` `[ ] % ~ @ + ^ - = { }`, non-ASCII | the above |
| the `mk/` directory's name | space `( ) ' & #` `[ ] % ~ @ + ^ - = { } ! : , * ?`, non-ASCII | tab, backslash, `"`, backquote, `$ ; \| < >` |

### Where the check is

- `mk.common.mk` (every role file reads it) runs `scripts/check-names.sh` first
  thing. It reads the directory from the shell (`pwd -P`) and the `mk/` directory
  from `BMK_MKDIR` in the environment — never `.CURDIR` or a command line: make
  expands a variable's value again each time it is used, so a `$` in a directory
  name is already gone when the makefile sees it.
- `gen-fw-order.sh` and `gen-mod-order.sh` check each framework and module
  directory they discover, before the first use of its name, so the message
  comes from the parent and not from a shell error in the middle of a recipe.
- `scripts/bmk-names.sh` holds the rules (what is refused); nothing else knows
  them.

A refused name stops the build with one message, for example:

```
Bmake It cannot build in /work/ws/Fw/m|od.m: the name 'm|od.m' contains a vertical bar,
which the shell reads as syntax (no quoting carries it through every command Bmake It runs).
Letters, digits, spaces and . _ - + @ % ~ ^ [ ] = # ' & ( ) and non-ASCII letters work in
a directory name; rename the directory (docs/spec/85-names-and-paths.md).
```

One case cannot be caught: a `$` in the `mk/` directory's own name. Make
expands it in the `.include` that loads `mk.common.mk`, so bmake stops with
"Could not find" before any Bmake It file runs.

## How the supported characters get through

Three changes, one per layer that read a name.

**1. The shell: every path in a recipe is quoted.** Each expansion of a
directory (`${.CURDIR}`, `${BMK_MKDIR}`, `${_FWDIR}`, …) in a recipe or in a
`!=` command carries bmake's `:Q`, which writes it for the shell (`a\ b`,
`it\'s`, `R\&D`); one that stands inside double quotes is left as it was. Flags
that carry a directory (`-I`, `-L`, `-Wl,-rpath,`) are written the same way when
they are built, because `CFLAGS` and `LDFLAGS` are shell text. The link recipes
build their argument list with `set --` and `"$@"`, no longer a string split
again at its spaces.

**2. Word lists: a name is one encoded word.** Make splits a value at a space,
reads `#` as a comment, `'` as a quote, and a variable name cannot carry `=`. So
a name is written, in every word list (`SUBDIR_FRAMEWORKS`, `SUBDIR_MODULES`,
the module dependency lists, `PREREQS`, `PARENT_WS`, `_LOCAL_MK_DIRS`,
`_LIB_SEARCH_DIRS`) and in every variable name made from it
(`MODULE_DEPS.<m>`, `_PREREQ_BASE.<p>`), with those characters as `%XX`
(percent-encoding; `%` is `%25`):

| Character | Written | Character | Written |
|---|---|---|---|
| space | `%20` | `[` `]` | `%5B` `%5D` |
| `#` | `%23` | `~` | `%7E` |
| `'` | `%27` | `{` `}` | `%7B` `%7D` |
| `&` | `%26` | `=` | `%3D` |
| `(` `)` | `%28` `%29` | `%` | `%25` |

A name without any of them is unchanged, so nothing else looks different.
`mk.common.mk` has the make side (`_BMK_ENC`, `_BMK_ENCW`, `_BMK_DEC`), and
`scripts/bmk-names.sh` the shell side (`bmk_enc`, `bmk_dec`); they are two
implementations of one scheme, and case 117 checks that they agree on every name
of a list. Two details of make's modifiers are why the make side is written as
it is: a modifier works on each word of a value, so `${.CURDIR:T}` is the last
piece of *each word* of a path with a space in it (`p Fw` for `/tmp/p p/Fw`; the
directory's name is `${.CURDIR:tW:T}` here, one word), and every modifier after
a space is in a value splits it again and joins the pieces with **one** space, so
decoding puts the space back last, as one word, or a name with two adjacent
spaces would lose one.

Writing a name in `PREREQS=` or `PARENT_WS=`: a backslash before a space, an
apostrophe and a hash sign, because make reads those. Nothing else needs one.

```make
PREREQS = My\ Framework John\'s R\&D C\#
PARENT_WS = /home/me/My\ Projects/core
```

`make add-prereq FW=<name>` and `add-parent WS=<path>` write that form.

**3. Dependency lines: no path in one carries a space or a parenthesis.**
Make cannot name a file with a space in its path in a dependency line (a quote or
a backslash is read as part of the word), and reads `d(1)/x.h` as the member `1`
of an archive `d`. So the paths a rule or a compiler's dependency file names are
relative to the module directory — bmake always runs there — and no part of the
workspace's path is in them: `-I../include`, `-Iinclude`, `../build/<key>/lib`.
A prerequisite framework (named in `PREREQS=`) is the one thing outside the
module that a header or a library comes from; one whose name or place has a space
or a parenthesis in it is reached through a link in the module's own build
directory, `build/<key>/prereqs/<encoded name>`, made when the module is built.
Ampersand, apostrophe and hash can be written in a dependency line, and are.

Two more places where bmake gets in the way, found by the case:

- **`-m` with a space.** bmake writes `-m <dir>` into `MAKEFLAGS` without quoting,
  so the sub-makes read a directory with a space in it as two words. The `mk/`
  directory is passed with `MAKESYSPATH=` — a colon-separated list, which is why a
  colon in the directory's name goes by `-m` instead. The README names
  `MAKESYSPATH`; the case does each as it must.
- **`bmake -V NAME`** prints the value as written, not expanded; a query that
  needs the expansion is `-V '${NAME}'`.

### What the cases cover

Case 116: a build, `clean` and `install`, with a program, a shared library the
program links, and two frameworks one of which lists the other, for every
character. Case 118, in a directory named `sp dir (1) & co's #x`: a prerequisite
framework in a `PARENT_WS` workspace (the parent written with backslashes);
`IMPORT=` resolved by `<NAME>_PREFIX`; `IMPORT=fetch:` with a patch and a
`file://` URL written percent-encoded; `FETCH_BUILD=cmake` (in a directory
without the `#`, see below); `add-prereq` and `add-parent`; `bmake run`;
`bmake test` with a compiled ATF test; `bmake docs`; and the HTML dashboards of
`REPORT=yes`. Running the whole suite with its work directory under such a path
(`TMPDIR="/tmp/sp dir (1) & co's #x" sh tests/harness/run-tests.sh`) found the
bugs fixed with this page; the cases that still fail there write a path, without
escaping it, into a file whose format needs it (see below), or run a shell-script
test.

### Limits that belong to other tools

- **`FETCH_URL=` is a list of URLs**, so a path with a space in a `file://` URL is
  written `%20`, an apostrophe `%27`, a hash `%23`, and so on (the same encoding
  as names); the fetch decodes it. Case 118 does so; a case that writes
  `file://$PWD/...` raw does not work in such a directory.
- **pkg-config cannot carry a space or an apostrophe in a package's prefix**: it
  prints `-I/a b/include` unquoted and then cannot read it back ("Text ended
  before matching quote"). An `IMPORT=pkg:` of a library installed under such a
  prefix fails there, whatever Bmake It does; `<NAME>_PREFIX=` does not use it. A
  `#` in the prefix is a comment in a `.pc` file.
- **CMake's makefiles cannot have a `#` in the path** (make reads it as a comment):
  `FETCH_BUILD=cmake` does not build in a workspace whose path has one.
- **Kyua** names its results file after the directory; the tests are run with an
  explicit results file (`-r`) so that a space or an apostrophe in the path does not
  stop `report-junit` from finding it.

### Not covered by a case

- The cross-test runner's shipping of library directories to a remote host
  (`mk.crosstest.mk`) quotes them; no case runs it with such a path.
- Windows (Cygwin, MSVC, mingw): runs in CI, not by hand.

### Refused, for a reason that is not Bmake It's

`bmake test` runs a compiled ATF test (`TESTS_C`, `TESTS_CXX`, `TEST_PROG`) in a
workspace whose path has a space in it, and says so, before running anything,
for a shell-script test (`testcases/*.sh`, `TESTS_SH`): ATF's own shell library
(`libatf-sh.subr`, the version MacPorts ships) tests its test directory unquoted
and stops with "too many arguments", which Kyua reports as `broken: Test program
did not exit cleanly`. Parentheses, apostrophes, ampersands and hash signs are
fine. The message names the cause and the two ways out (a workspace path
without a space, or a test in C or C++). Found by running the tests of case 91's
tree under `/tmp/bmk dev2/w (1) & co`.

## Measured on the BSDs (2026-11-08, before the fix)

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
under a name that carries it. Where the build is meant to work the tree is the
fuller one — a shared library in one framework, a program in a second framework
that lists the first in `PREREQS=` and links the library, then `install` into a
directory that carries the character too, then `clean`; where it is refused,
the small one (one program). The expectation per place is the table above.
A refusal must carry the message (`Bmake It cannot …`); any other failure
(`raw`), or a build that says it succeeded and built nothing (`SILENT`), fails
the case. It fails on any deviation. A character the file system itself refuses
(Windows: `" * ? < > | : \`) is skipped for that character. The `mk/` directory
goes by `-m` when its name has a colon and by `MAKESYSPATH` otherwise (see
above). `BMK_CASE_CHARS="space hash"` runs only those characters.

`tests/cases/117-name-encoding`: the make and the shell implementation of the
encoding agree on a list of names (space, two spaces, `#`, a leading `#`, `'`,
`&`, `( )`, `=`, `%` and `%20` as names, `[ ]`, `~`, `{ }`, non-ASCII), one by
one and as a list.
