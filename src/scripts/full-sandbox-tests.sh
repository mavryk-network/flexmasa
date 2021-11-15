#! /usr/bin/env bash

# Those are tests that should succeed in a well configured environment:
# - flextesa command line app, and `tezos-*` binaries available in PATH
# - Alpha protocol is “similar enough” to the one pulled by the `Dockerfile`

set -e
set -o pipefail

say () { printf "[full-sandbox-tests:] $@\n" >&2 ; } 

runone () {
    name="$1"
    shift
    rootroot="/tmp/flextesa-full-sandbox-tests/$name/"
    root="$rootroot/root"
    log="$rootroot/log.txt"
    say "Running $name ($rootroot)"
    mkdir -p "$rootroot"
    "$@" --root "$root" 2>&1 | tee "$log" | sed 's/^/    ||/'
}

grana () {
    runone "mini-granada" flextesa mini --protocol-kind Granada --time-between-blocks 2 --until-level 4 --number-of-boot 1 --size 1
}
hangz () {
    runone "mini-hangz2" flextesa mini --protocol-kind Hangzhou --time-between-blocks 1 --minimal-block 1 --until-level 4 --number-of-boot 1 --size 1
}
alpha () {
    runone "mini-alpha" flextesa mini --protocol-kind Alpha --time-between-blocks 2 --minimal-block 2 --until-level 4 --number-of-boot 1 --size 1
}
all () {
    grana
    hangz
    alpha
}

{ if [ "$1" = "" ] ; then all ; else "$@" ; fi ; }
