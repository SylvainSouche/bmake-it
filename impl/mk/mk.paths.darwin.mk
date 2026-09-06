# mk.paths.darwin.mk — where host tools live on macOS
# Xcode CLT ships in /usr/bin; MacPorts and both Homebrew layouts are
# common enough to search unconditionally.
_TOOL_PREFIXES = /usr/bin /opt/local/bin /opt/homebrew/bin /usr/local/bin
