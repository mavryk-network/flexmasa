.PHONY: fmt all build

all: build

build:
	dune build src/test/main.exe src/app/main.exe && \
             ln -sf _build/default/src/app/main.exe flextesa

fmt:
	find ./src/ \( ! -name ".#*" \) \( -name "*.mli" -o -name "*.ml" \) -exec ocamlformat -i {} \;
