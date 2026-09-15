# mk.paths.darwin.mk — where host tools live on macOS
# Unlike every other mk.paths.<os>.mk, the base system (/usr/bin, Apple's
# Xcode CLT clang) is NOT the intended default here -- CON-cross-platform-
# targets scopes macOS to a third-party package-manager toolchain.
#
# Tiered per macos-toolchain-tiers-req: tier 1 (MacPorts, Homebrew, pkgsrc/
# pkgin -- fully supported) searched before tier 2 (Nix -- still searched,
# lower priority). Homebrew needs both prefixes since Apple Silicon and
# Intel default differently. Apple's own /usr/bin is last regardless of
# tier -- still found (fail-loud detection beats no detection at all), but
# never preferred over a real third-party toolchain.
# @impl 0f87-6aa9-3a6f-6f56
_TOOL_PREFIXES = /opt/local/bin /opt/homebrew/bin /usr/local/bin /opt/pkg/bin \
                 ${HOME}/.nix-profile/bin /run/current-system/sw/bin \
                 /usr/bin
