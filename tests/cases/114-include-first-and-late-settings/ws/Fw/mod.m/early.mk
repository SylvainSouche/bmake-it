# a module that includes mk.common.mk first, to read TARGET in its top section
.include "mk.common.mk"
PROG=x
.if ${TARGET} == "win"
LDFLAGS+=-lpsapi
.endif
.include "mk.prog.mk"
