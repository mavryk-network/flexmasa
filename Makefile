.PHONY: fmt all build

all: build

build:
	dune build src/test/main.exe

fmt:
	find ./src/ \( ! -name ".#*" \) \( -name "*.mli" -o -name "*.ml" \) -exec ocamlformat -i {} \;
