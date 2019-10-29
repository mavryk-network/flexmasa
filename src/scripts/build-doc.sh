#! /bin/sh

set -e

usage () {
    cat >&2 <<EOF
usage: $0 <output-path>

EOF
}

shout () {
    YELLOW='\033[0;33m'
    NC='\033[0m'
    if [ "no_color" = "true" ]; then
        printf "$@"
    else
        printf "$YELLOW"; printf "$@" ; printf "$NC"
    fi
}

say () {
    shout "[Make-doc] " >&2
    printf "$@" >&2
    printf "\n" >&2
}

if ! [ -f src/scripts/build-doc.sh ] ; then
    say "This script should run from the root of the flextesa tree."
    exit 1
fi

output_path="$1"

mkdir -p "$output_path/api"

opam config exec -- dune build @doc

opam config exec -- opam install --yes odig

cp -r _build/default/_doc/_html/* "$output_path/"

cp -r $(odig odoc-theme path odig.solarized.dark)/* "$output_path/"

index_fragment=$(mktemp "/tmp/index-XXXX.html")
odoc html-frag src/doc/index.mld \
     -I _build/default/src/lib/.flextesa.objs/byte/ -o "$index_fragment"

index="$output_path/index.html"
cat > "$index" <<'EOF'
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <title>Flextesa: Home</title>
    <link rel="stylesheet" href="./odoc.css"/>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  </head>
  <body>
    <main class="content">
EOF
cat $index_fragment >> $index 
cat >> "$index" <<'EOF'
    </main>
  </body>
</html>
EOF
#cat $index 

say "done: file://$PWD/$output_path/index.html"
say "done: file://$PWD/$output_path/flextesa/Flextesa/index.html"


