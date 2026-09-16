# Bmake It — 90: Qt Development

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.
Not yet implemented — this chapter specs the mechanism; `mk/mk.qt.mk`
does not exist yet.

## Scope and stance

Qt application development is supported **without depending on Qt's own
build-system plumbing** — no `qmake`, no CMake's Qt integration modules
(`AUTOMOC`/`AUTOUIC`/`AUTORCC`). Only the real toolchain tools are
invoked directly: `moc`, `uic`, `rcc`, and the C++ compiler/linker
Bmake It already drives. Qt is a C++ *toolkit*, not a new language, so
this sits inside the existing C/C++ scope (`REQ-supported-languages`),
not an expansion of it (`REQ-qt-development-without-plumbing-req`).

**Original implementation, not adapted from prior art.** Real BSD-make
precedent was checked before designing this (FreeBSD ports'
`Mk/Uses/qt.mk`) and found to be dependency/path plumbing that still
hands off to `qmake` for the actual build — not a moc/uic/rcc mechanism
to adapt. A couple of small community example Makefiles were also
checked, purely to confirm moc/uic's documented behavior (moc operates
on a *header*, not a source file; uic on a `.ui` file). `mk.qt.mk` is
written from Qt's own public, documented tool contracts, not copied from
either — no text or code from any third-party project, regardless of
that project's own license (`qt-mechanism-original-implementation`).

## Declaring Qt usage

```
QT_MODULES = Core Widgets Gui
```

`QT_MODULES=<name> [<name> ...]` — Qt module names **without** the
`Qt5`/`Qt6` prefix (`Core`, `Widgets`, `Gui`, `Network`, ...). Resolved
via `pkg-config Qt${QT_VERSION}<name> --cflags --libs` — the same
pkg-config-based discovery already used for `atf-c++`/`atf-c`
(`mk.test.mk`), not `qmake -query`. `QT_VERSION ?= 6`, overridable to
`5` for a Qt5-only environment. Empty (unset) `QT_MODULES=` means the
mechanism is inactive for that module, mirroring how `TESTS_CXX=` gates
`mk.test.mk` (`REQ-qt-mk-mechanism-req`).

Tool locations (`MOC`, `UIC`, `RCC`) default to the versioned tools
pkg-config's own Qt `.pc` files expose (`pkg-config --variable=host_bins
Qt${QT_VERSION}Core` names the directory containing the *right* Qt
version's `moc`/`uic`/`rcc`, since a host can have Qt5 and Qt6
installed side by side) with a bare-PATH-lookup fallback, matching the
existing `MOC ?=`-style override pattern already used for `YACC`/`LEX`.

## Discovery: three different triggers for three different tools

| Input | Trigger | Matches yacc/lex how |
|---|---|---|
| `.ui` files | file extension, auto-discovered from `src/` | Identical: same auto-discovery loop as `.y`/`.l` |
| `.qrc` files | file extension, auto-discovered from `src/` | Identical |
| MOC input | **file content** — any `include/*.h` containing `Q_OBJECT`, `Q_GADGET`, or `Q_NAMESPACE` | New: no `.y`/`.l` precedent is content-triggered. No declared macro (`MOC_HEADERS=` or similar) — auto-discovered by scanning, matching this project's general preference for auto-discovery over explicit listing (`REQ-modules-and-frameworks-auto-discovered-req`) |

MOC's content-based trigger is the one genuinely new discovery mechanism
here — everything else reuses the extension-based `SRCS` auto-discovery
loop already in place.

## Generated-file destinations — closely mirroring yacc/lex

Every generated Qt artifact follows the **existing** rule for generated
files exactly: private by default in the module's own
`build/<KEY>/include/`, explicitly promoted to the framework's shared
`build/<KEY>/include/` only via `INCL=` (`REQ-generated-headers-in-build-tree-req`).

| Qt input | Generated | Staged | Compiled? | `INCL=`-promotable? |
|---|---|---|---|---|
| `src/foo.ui` | `ui_foo.h` | `build/<KEY>/obj/`, then copied to `build/<KEY>/include/` — identical two-step to `.y`'s generated header | No — `#include`d by a hand-written `.cpp` | Yes, same mechanism as a `.y`'s `-d` header |
| `include/foo.h` (contains `Q_OBJECT`/etc.) | `moc_foo.cpp` | `build/<KEY>/obj/` only | Yes → `.o`, linked | N/A — not a header, same as `.y`'s generated `.c` half |
| `src/foo.qrc` | `qrc_foo.cpp` | `build/<KEY>/obj/` only | Yes → `.o`, linked | N/A |

No new destination convention is introduced — a `.ui` header is treated
exactly like a yacc header, and `moc_*.cpp`/`qrc_*.cpp` are treated
exactly like a yacc `.c` file: compiled in place, never promoted.

## Progressive test harness

Verifying this mechanism needs real Qt applications, not just unit
tests of the `.mk` logic — and every level must be runnable headlessly
(no real display server), so it works in the same CI context as the
rest of the test harness. Four levels, each adding exactly one new
piece of the mechanism (`REQ-qt-progressive-test-harness-req`):

| Level | App | Proves | Headless via |
|---|---|---|---|
| 0 | `QCoreApplication` console app (`QString`, `qDebug()`) | `QT_MODULES=Core` linking/include resolution only — zero code generation | Naturally headless (no GUI module at all) |
| 1 | Adds a `QObject`-derived class with a signal connected to a slot, run inside a `QCoreApplication` event loop | MOC discovery, generation, compile, link | Still `QtCore`-only, naturally headless |
| 2 | A `QWidget` driven by a `.ui` file (`QT_MODULES=Core Widgets Gui`) | UIC | `QT_QPA_PLATFORM=offscreen` — Qt's own supported headless platform plugin, not a workaround |
| 3 | Level 2 plus an embedded icon via `.qrc` | RCC | Same `offscreen` platform |

QML/Qt Quick is explicitly out of scope for this initial harness — a
further level if ever needed, not designed here.

## Not yet decided

- Where these four test apps live relative to `examples/`/`tests/` —
  likely alongside the existing `examples/myworkspace` pattern, not
  designed here.
- Qt5-vs-Qt6 API differences in the test apps themselves (module names
  changed between major versions for a few modules) — deferred to
  implementation time.
- Whether a `QT_MODULES=` module's own `LIBS=`/`PREREQS=` interaction
  needs anything special — not yet checked against the existing
  `_LIB_SEARCH_DIRS`/prereq-resolution logic.
