#! /usr/bin/env bash

# Those are tests that should succeed in a well configured environment:
# - flextesa command line app, and `octez-*` binaries available in PATH
# - Alpha protocol is “similar enough” to the one pulled by the `Dockerfile`

set -e
set -o pipefail

say () { printf "[full-sandbox-tests:] $@\n" >&2 ; } 

until_4="--until-level 4"
until_8="--until-level 8"
until_12="--until-level 12"
readline=""
if [ "$interactive" = "true" ] ; then
    until_4=""
    until_8=""
    until_12=""
    readline="rlwrap"
fi


runone () {
    name="$1"
    shift
    rootroot="/tmp/flextesa-full-sandbox-tests/$name/"
    root="$rootroot/root"
    log="$rootroot/log.txt"
    say "Running $name ($rootroot)"
    mkdir -p "$rootroot"
    $readline "$@" --root "$root" 2>&1 | tee "$log" | sed 's/^/  ||/'
}

current=Kathmandu
next=Lima
next_suffix=PtLimaPt
# Alpha is upgrading from Lima:
before_alpha=$next


quickmini () {
    proto="$1"
    runone "mini-$proto" flextesa mini --protocol-kind "$proto" \
           --time-between-blocks 1 $until_4 \
           --number-of-boot 1 --size 1
}

c2n () {
    runone "${current}2${next}" flextesa mini \
           --protocol-kind "$current" \
           --hard-fork 10:$next: \
           --time-between-blocks 1 --number-of-boot 1 --size 1 \
           $until_12
}
n2a () {
    runone "${before_alpha}2alpha" flextesa mini \
           --protocol-kind "$before_alpha" \
           --hard-fork 10:Alpha: \
           --time-between-blocks 2 --number-of-boot 2 --size 2 \
           $until_12
}

daem_c2n () {
    runone "dameons-upgrade-c2n" flextesa daemons-upgrade \
	   --protocol-kind "$current" \
           --next-protocol-kind "$next" \
	   --second-baker octez-baker-$next_suffix \
	   --extra-dummy-proposals-batch-size 2 \
	   --extra-dummy-proposals-batch-levels 3,5 \
	   --size 2 \
	   --number-of-b 2 \
	   --time-between-blocks 3 \
	   --blocks-per-vot 20 \
	   --with-timestamp \
           --test-variant full-upgrade
}

daem_c2n_nay () {
    runone "dameons-upgrade-c2n-nay" flextesa daemons-upgrade \
	   --protocol-kind "$current" \
           --next-protocol-kind "$current" \
	   --second-baker octez-baker-$next_suffix \
	   --extra-dummy-proposals-batch-size 2 \
	   --extra-dummy-proposals-batch-levels 3,5 \
	   --size 2 \
	   --number-of-b 2 \
	   --time-between-blocks 3 \
	   --with-timestamp \
           --test-variant nay-for-promotion
}

daem_n2a () {
    runone "dameons-upgrade-n2a" flextesa daemons-upgrade \
        --protocol-kind "$before_alpha" \
        --next-protocol-kind Alpha \
        --second-baker octez-baker-alpha \
        --extra-dummy-proposals-batch-size 2 \
        --extra-dummy-proposals-batch-levels 3,5 \
        --size 2 \
        --number-of-b 2 \
        --time-betw 3 \
        --with-timestamp \
        --test-variant full-upgrade
}

toru() {
    proto="$1"
    runone "mini-$proto" flextesa mini --protocol-kind "$proto" \
        --time-between-blocks 2 $until_8 \
        --number-of-boot 1 --size 1 \
        --tx-rollup 3:mini-tx-rollup
}

all() {
    quickmini "$current"
    quickmini "$next"
    quickmini Alpha
    c2n
    n2a
    daem_c2n
    daem_c2n_nay
    daem_n2a
}

{ if [ "$1" = "" ] ; then all ; else "$@" ; fi ; }
