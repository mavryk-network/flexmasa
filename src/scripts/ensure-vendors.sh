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

tezos_commit=c059d66e6f908228024344a830829b8a1c12ddaf

say "Vendoring tezos @ %10s" "$tezos_commit"

if [ -f "local-vendor/tezos-master/README.md" ] ; then
    say "Tezos already cloned"
else
    mkdir -p local-vendor/
    git clone --depth 100 https://gitlab.com/tezos/tezos.git -b master local-vendor/tezos-master
fi

(
    cd local-vendor/tezos-master/
    git pull
    git checkout "$tezos_commit"
    echo "(data_only_dirs flextesa-lib) ;; Unvendored flextesa" > vendors/dune
)
