.PHONY: fmt all build vendors clean

all: build

build:
	dune build @check src/test/main.exe src/app/main.exe && \
             ln -sf _build/default/src/app/main.exe flextesa

test:
	dune runtest

clean:
	dune clean

fmt:
	find ./src/ \( ! -name ".#*" \) \( -name "*.mli" -o -name "*.ml" \) -exec ocamlformat --profile=compact -i {} \;
