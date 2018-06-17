.POSIX:
.SUFFIXES: .el .elc
EMACS = emacs

compile: latch.elc

clean:
	rm -f latch.elc

.el.elc:
	$(EMACS) -Q -batch -f batch-byte-compile $<
