# mk.paths.netbsd.mk — where host tools live on NetBSD
# Base system in /usr/bin; pkgsrc installs to /usr/pkg/bin by convention
# (confirmed empirically: pkgsrc clang-21.1.8 lands at /usr/pkg/bin/clang,
# not /usr/bin/clang -- this is exactly the case that motivated splitting
# these lists per OS instead of one shared guess).
_TOOL_PREFIXES = /usr/bin /usr/pkg/bin /usr/local/bin
