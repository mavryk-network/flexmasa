#! /usr/bin/env bash

# Those are tests that should succeed in a well configured environment:
# - flextesa command line app, and `tezos-*` binaries available in PATH
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
    $readline "$@" --root "$root" 2>&1 | tee "$log" | sed 's/^/    ||/'
}


hangz () {
    runone "mini-hangz2" flextesa mini --protocol-kind Hangzhou \
           --time-between-blocks 1 $until_4 \
           --number-of-boot 1 --size 1
}
itha () {
    runone "mini-ithaca" flextesa mini --protocol-kind Ithaca \
           --time-between-blocks 2 $until_4 --number-of-boot 1 --size 1
}
alpha () {
    runone "mini-alpha" flextesa mini --protocol-kind Alpha \
           --time-between-blocks 2 $until_4 \
           --number-of-boot 1 --size 1
}

h2i () {
    runone "hangzhou-2-ithaca" flextesa mini \
           --protocol-kind Hangzhou \
           --hard-fork 10:Ithaca: \
           --time-between-blocks 1 --number-of-boot 1 --size 1 \
           $until_12
}
i2a () {
    runone "ithaca2-2-alpha" flextesa mini \
           --protocol-kind Itha \
           --hard-fork 10:Alpha: \
           --time-between-blocks 2 --number-of-boot 2 --size 2 \
           $until_12
}

daem-h2i () {
    runone "dameons-upgrade-hanzhou-2-ithaca" flextesa daemons-upgrade \
        --next-protocol-kind Ithaca \
	    --extra-dummy-proposals-batch-size 2 \
	    --extra-dummy-proposals-batch-levels 3,5 \
	    --size 2 \
	    --number-of-b 2 \
	    --time-between-blocks 3 \
	    --blocks-per-vot 14 \
	    --with-timestamp \
	    --protocol-kind Hangzhou \
	    --second-baker tezos-baker-012-Psithaca \
        --test-variant full-upgrade
}

daem-h2i-nay () {
    runone "dameons-upgrade-hanzhou-2-ithaca" flextesa daemons-upgrade \
        --next-protocol-kind Ithaca \
	    --extra-dummy-proposals-batch-size 2 \
	    --extra-dummy-proposals-batch-levels 3,5 \
	    --size 2 \
	    --number-of-b 2 \
	    --time-between-blocks 3 \
	    --with-timestamp \
	    --protocol-kind Hangzhou \
	    --second-baker tezos-baker-012-Psithaca \
        --test-variant nay-for-promotion
}

daem-i2a () {
    runone "dameons-upgrade-hanzhou-2-alpha" flextesa daemons-upgrade \
        --next-protocol-kind Alpha \
	    --extra-dummy-proposals-batch-size 2 \
	    --extra-dummy-proposals-batch-levels 3,5 \
	    --size 2 \
	    --number-of-b 2 \
	    --time-betw 3 \
	    --with-timestamp \
	    --protocol-kind Ithaca \
	    --second-baker tezos-baker-alpha \
        --test-variant full-upgrade
}

daem-i2a-nay () {
    runone "dameons-upgrade-hanzhou-2-alpha" flextesa daemons-upgrade \
        --next-protocol-kind Alpha \
	    --extra-dummy-proposals-batch-size 2 \
	    --extra-dummy-proposals-batch-levels 3,5 \
	    --size 2 \
	    --number-of-b 2 \
	    --time-betw 3 \
	    --with-timestamp \
	    --protocol-kind Ithaca \
	    --second-baker tezos-baker-alpha \
        --test-variant nay-for-promotion
}

all () {
    hangz
    itha
    alpha
    h2i
    i2a
    daem-h2i
    daem-h2i-nay
    daem-i2a
    daem-i2a-nay
}

{ if [ "$1" = "" ] ; then all ; else "$@" ; fi ; }
