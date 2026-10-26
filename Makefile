EMACS ?= emacs

# Locate straight build directory for the current Emacs version
STRAIGHT_DIRS := $(wildcard $(HOME)/.config/emacs/.local/straight/build-30.2.50/*)
LOAD_PATH_FLAGS := $(foreach dir,$(STRAIGHT_DIRS),-L $(dir)) -L . -L tests

.PHONY: all compile test clean

all: compile test

compile:
	$(EMACS) -Q --batch \
		$(LOAD_PATH_FLAGS) \
		--eval "(setq byte-compile-error-on-warn t)" \
		-f batch-byte-compile llm-review.el

test:
	$(EMACS) -Q --batch \
		$(LOAD_PATH_FLAGS) \
		-l tests/llm-review-test.el \
		-f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc lisp/*.elc tests/*.elc
	rm -rf test-sandbox
