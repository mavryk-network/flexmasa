
.PHONY: fmt

fmt:
	find ./src/ \( ! -name ".#*" \) \( -name "*.mli" -o -name "*.ml" \) -exec ocamlformat -i {} \;
