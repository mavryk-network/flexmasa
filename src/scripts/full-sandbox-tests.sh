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
        src/scripts/dummy_protocols/proto_012_Psithaca/lib_protocol/TEZOS_PROTOCOL \
	    --base-port 15_000 \
	    --extra-dummy-proposals-batch-size 2 \
	    --extra-dummy-proposals-batch-levels 3,5 \
	    --size 2 \
	    --number-of-b 2 \
	    --time-between-blocks 3 \
	    --blocks-per-vot 14 \
	    --with-timestamp \
	    --protocol-hash PtHangz2aRngywmSRGGvrcTyMbbdpWdpFKuS4uMWxg2RaH9i1qx \
	    --protocol-kind Hangzhou \
	    --tezos-client tezos-client \
	    --tezos-admin tezos-admin-client \
	    --tezos-node tezos-node \
	    --first-baker tezos-baker-011-PtHangz2 \
	    --first-endorser tezos-endorser-011-PtHangz2 \
	    --first-accuser tezos-accuser-011-PtHangz2 \
	    --second-baker tezos-baker-012-Psithaca \
	    --second-endorser tezos-baker-012-Psithaca \
	    --second-accuser tezos-accuser-012-Psithaca
}

daem-h2i-nay () {
    runone "dameons-upgrade-hanzhou-2-ithaca" flextesa daemons-upgrade \
        src/scripts/dummy_protocols/proto_012_Psithaca/lib_protocol/TEZOS_PROTOCOL \
        --base-port 15_000 \
	    --extra-dummy-proposals-batch-size 2 \
	    --extra-dummy-proposals-batch-levels 3,5 \
	    --size 2 \
	    --number-of-b 2 \
	    --time-between-blocks 3 \
	    --blocks-per-vot 14 \
	    --with-timestamp \
	    --protocol-hash PtHangz2aRngywmSRGGvrcTyMbbdpWdpFKuS4uMWxg2RaH9i1qx \
	    --protocol-kind Hangzhou \
	    --tezos-client tezos-client \
	    --tezos-admin tezos-admin-client \
	    --tezos-node tezos-node \
	    --first-baker tezos-baker-011-PtHangz2 \
	    --first-endorser tezos-endorser-011-PtHangz2 \
	    --first-accuser tezos-accuser-011-PtHangz2 \
	    --second-baker tezos-baker-012-Psithaca \
	    --second-endorser tezos-baker-012-Psithaca \
	    --second-accuser tezos-accuser-012-Psithaca \
        --test-variant nay-for-promotion
}

daem-i2a () {
    runone "dameons-upgrade-hanzhou-2-alpha" flextesa daemons-upgrade \
        src/scripts/dummy_protocols/proto_alpha/lib_protocol/TEZOS_PROTOCOL \
	    --base-port 16_000 \
	    --extra-dummy-proposals-batch-size 2 \
	    --extra-dummy-proposals-batch-levels 3,5 \
	    --size 2 \
	    --number-of-b 2 \
	    --time-betw 3 \
	    --blocks-per-vot 14 \
	    --with-timestamp \
	    --protocol-hash Psithaca2MLRFYargivpo7YvUr7wUDqyxrdhC5CQq78mRvimz6A \
	    --protocol-kind Ithaca \
	    --tezos-client tezos-client \
	    --tezos-admin tezos-admin-client \
	    --tezos-node tezos-node \
	    --first-baker tezos-baker-012-Psithaca \
	    --first-endorser tezos-baker-012-Psithaca \
	    --first-accuser tezos-accuser-012-Psithaca \
	    --second-baker tezos-baker-alpha \
	    --second-endorser tezos-baker-alpha \
	    --second-accuser tezos-accuser-alpha
}

daem-i2a-nay () {
    runone "dameons-upgrade-hanzhou-2-alpha" flextesa daemons-upgrade \
        src/scripts/dummy_protocols/proto_alpha/lib_protocol/TEZOS_PROTOCOL \
	    --base-port 16_000 \
	    --extra-dummy-proposals-batch-size 2 \
	    --extra-dummy-proposals-batch-levels 3,5 \
	    --size 2 \
	    --number-of-b 2 \
	    --time-betw 3 \
	    --blocks-per-vot 14 \
	    --with-timestamp \
	    --protocol-hash Psithaca2MLRFYargivpo7YvUr7wUDqyxrdhC5CQq78mRvimz6A \
	    --protocol-kind Ithaca \
	    --tezos-client tezos-client \
	    --tezos-admin tezos-admin-client \
	    --tezos-node tezos-node \
	    --first-baker tezos-baker-012-Psithaca \
	    --first-endorser tezos-baker-012-Psithaca \
	    --first-accuser tezos-accuser-012-Psithaca \
	    --second-baker tezos-baker-alpha \
	    --second-endorser tezos-baker-alpha \
	    --second-accuser tezos-accuser-alpha \
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
    daem-h2a
    daem-h2a-nay
}

{ if [ "$1" = "" ] ; then all ; else "$@" ; fi ; }
