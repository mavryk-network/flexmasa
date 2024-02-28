#! /usr/bin/env bash

# Those are tests that should succeed in a well configured environment:
# - flextesa command line app, and `octez-*` binaries available in PATH
# - Alpha protocol is “similar enough” to the one pulled by the `Dockerfile`

set -e
set -o pipefail

say() { printf "[full-sandbox-tests:] $@\n" >&2; }

until_4="--until-level 4"
until_8="--until-level 8"
until_12="--until-level 12"
readline=""
if [ "$interactive" = "true" ]; then
    until_4=""
    until_8=""
    until_12=""
    readline="rlwrap"
fi

runone() {
    name="$1"
    shift
    rootroot="/tmp/flextesa-full-sandbox-tests/$name"
    root="$rootroot/root"
    log="$rootroot/log.txt"
    say "Running $name ($rootroot)"
    mkdir -p "$rootroot"
    $readline "$@" --root "$root" 2>&1 | tee "$log" | sed 's/^/  ||/'
}

current=Atlas
next=Alpha
next_suffix=alpha
before_alpha=$next

quickmini() {
    proto="$1"
    runone "mini-$proto" flextesa mini --protocol-kind "$proto" \
        --time-between-blocks 1 $until_4 \
        --number-of-boot 1 --size 1
}

c2n() {
    runone "${current}2${next}" flextesa mini \
        --protocol-kind "$current" \
        --hard-fork 10:$next: \
        --time-between-blocks 1,3 --number-of-boot 2 --size 2 \
        $until_12
}
n2a() {
    runone "${before_alpha}2alpha" flextesa mini \
        --protocol-kind "$before_alpha" \
        --hard-fork 10:Alpha: \
        --time-between-blocks 1,3 --number-of-boot 2 --size 2 \
        $until_12
}

daem_c2n() {
    runone "dameons-upgrade-c2n" flextesa daemons-upgrade \
        --protocol-kind "$current" \
        --next-protocol-kind "$next" \
        --second-baker octez-baker-$next_suffix \
        --extra-dummy-proposals-batch-size 2 \
        --extra-dummy-proposals-batch-levels 3,5 \
        --size 2 --number-of-b 2 \
        --time-between-blocks 3,4 \
        --blocks-per-vot 16 \
        --with-timestamp \
        --test-variant full-upgrade \
        --waiting-attempts 30 $until_12

}

daem_c2n_nay() {
    runone "dameons-upgrade-c2n-nay" flextesa daemons-upgrade \
        --protocol-kind "$current" \
        --next-protocol-kind "$next" \
        --second-baker octez-baker-$next_suffix \
        --extra-dummy-proposals-batch-size 2 \
        --extra-dummy-proposals-batch-levels 3,5 \
        --size 2 \
        --number-of-b 2 \
        --time-between-blocks 3,4 \
        --blocks-per-vot 16 \
        --with-timestamp \
        --test-variant nay-for-promotion \
        --waiting-attempts 30 $until_12
}

daem_n2a() {
    runone "dameons-upgrade-n2a" flextesa daemons-upgrade \
        --protocol-kind "$before_alpha" \
        --next-protocol-kind Alpha \
        --second-baker octez-baker-alpha \
        --extra-dummy-proposals-batch-size 2 \
        --extra-dummy-proposals-batch-levels 3,5 \
        --size 2 \
        --number-of-b 2 \
        --time-between-blocks 3,5 \
        --blocks-per-vot 16 \
        --with-timestamp \
        --test-variant full-upgrade \
        --waiting-attempts 30 $until_12
}

evm_smart_rollup () {
    proto="$1"
    runone "evm-smart-rollup" flextesa mini --protocol-kind "$proto" \
           --time-between-blocks 1 $until_8 \
           --number-of-boot 1 --size 1 \
           --start-smart-rollup evm
}

ai() {
    proto="$1"
    runone "adaptive-issuance-$proto" flextesa mini --protocol-kind "$proto" \
        --time-between-blocks 1 --number-of-boot 1 --size 1 \
        --adaptive-issuance-vote "on" --until-level 48

}

daem_ai() {
    proto="$1"
    runone "daemon-upgrage-adaptive-issuance-$proto" flextesa daemons-upgrade --protocol-kind "$proto" \
        --time-between-blocks 1 --number-of-boot 1 --size 1 \
        --test-variant full-upgrade --next-protocol-kind "$next" --second-baker octez-baker-"$next_suffix" \
        --adaptive-issuance-vote-first-baker "pass" --adaptive-issuance-vote-second-baker "on" \
        --waiting-attempts 30 $until_12

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
    tx_smart_rollup
    evm_smart_rollup
    ai "$current"
    ai "$next"
    daem_ai "$current"
    daem_ai "$next"

}

mini() {
    quickmini "$current"
    quickmini "$next"
    quickmini Alpha

}

gov() {
    c2n
    n2a
    daem_c2n
    daem_c2n_nay
    daem_n2a

}

rollup() {
    evm_smart_rollup "$current"
    evm_smart_rollup "$next"

}

adissu() {
    ai "$current"
    ai "$next"
    daem_ai "$current"
    daem_ai "$next"

}

{ if [ "$1" = "" ]; then all; else "$@"; fi; }
