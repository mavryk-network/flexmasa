.PHONY: fmt all build vendors clean

all: build

build:
	dune build @check src/test/main.exe src/app/main.exe && \
             ln -sf _build/default/src/app/main.exe mavbox

test:
	dune runtest

clean:
	dune clean

fmt:
	dune build mavbox.opam mavbox-cli.opam \
             mavryk-mv1-crypto.opam \
             @fmt --auto-promote
