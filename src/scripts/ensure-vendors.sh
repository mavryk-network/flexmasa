#! /bin/sh

set -e

usage () {
    cat >&2 <<EOF
usage: $0


EOF
}

say () {
    printf "[Ensure_vendors] " >&2
    printf "$@" >&2
    printf "\n" >&2
}

if ! [ -f src/scripts/ensure-vendors.sh ] ; then
    say "This script should run from the root of the flextesa tree."
    exit 1
fi

tezos_branch=sm@flextesa-ci
tezos_remote=https://gitlab.com/smondet/tezos.git

say "Vendoring tezos @ %10s" "$tezos_commit"

if [ -f "local-vendor/tezos-master/README.md" ] ; then
    say "Tezos already cloned"
else
    mkdir -p local-vendor/
    git clone --depth 10 "$tezos_remote" -b "$tezos_branch" \
        local-vendor/tezos-master
fi

(
    cd local-vendor/tezos-master/
    git checkout "$tezos_branch"
    git pull
    git log --oneline -n 5
    echo "(data_only_dirs flextesa-lib) ;; Unvendored flextesa" > vendors/dune
)
