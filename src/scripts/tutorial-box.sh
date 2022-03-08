#! /bin/sh

default_protocol=Hangzhou

all_commands="
* usage | help | --help | -h: Display this help message."
usage () {
    cat >&2 <<EOF
This script provides a Flextesa “mini-net” sandbox with predefined
parameters useful for tutorials and basic exploration with
wallet software like \`tezos-client\`. This one uses the $default_protocol
protocol.

usage: $0 <command>

where <command> may be:
$all_commands
EOF
}

time_bb=${block_time:-5}

export alice="$(flextesa key alice)"
export bob="$(flextesa key bob)"
all_commands="$all_commands
* start : Start the sandbox."
root_path=/tmp/mini-box
start () {
    flextesa mini-net \
             --root "$root_path" --size 1 "$@" \
             --set-history-mode N000:archive \
             --number-of-b 1 \
             --balance-of-bootstrap-accounts tez:100_000_000 \
             --time-b "$time_bb" \
             --add-bootstrap-account="$alice@2_000_000_000_000" \
             --add-bootstrap-account="$bob@2_000_000_000_000" \
             --no-daemons-for=alice \
             --no-daemons-for=bob \
             --until-level 200_000_000 \
             --protocol-kind "$default_protocol"
}

all_commands="$all_commands
* info : Show accounts and information about the sandbox."
info () {
    cat >&2 <<EOF
Usable accounts:

- $(echo $alice | sed 's/,/\n  * /g')
- $(echo $bob | sed 's/,/\n  * /g')

Root path (logs, chain data, etc.): $root_path (inside container).
EOF
}

all_commands="$all_commands
* initclient : Setup the local tezos-client."
initclient () {
    tezos-client --endpoint http://localhost:20000 config update
    tezos-client --protocol PtHangz2aRng import secret key alice "$(echo $alice | cut -d, -f 4)" --force
    tezos-client --protocol PtHangz2aRng import secret key bob "$(echo $bob | cut -d, -f 4)" --force
}

all_commands="$all_commands
* start-upgrade : Start the daemons upgrade sandbox."
daemons_root=/tmp/daemons-upgrade-box
next_protocol_name=Ithaca
next_protocol=012-Psithaca
vote_period=${blocks_per_voting_period:-16}

start_upgrade () {
    flextesa daemons-upgrade \
        --next-protocol-kind "$next_protocol_name" \
        --root-path "$daemons_root" \
        --extra-dummy-proposals-batch-size 2 \
        --extra-dummy-proposals-batch-levels 3,5 \
        --size 2 \
        --number-of-b 2 \
        --add-bootstrap-account="$alice@2_000_000_000_000" \
        --add-bootstrap-account="$bob@2_000_000_000_000" \
        --no-daemons-for=alice \
        --no-daemons-for=bob \
        --time-between-blocks "$time_bb" \
        --blocks-per-voting-period "$vote_period" \
        --with-timestamp \
        --protocol-kind "$default_protocol" \
        --second-baker tezos-baker-"$next_protocol" \
        --test-variant full-upgrade \
        --interactive false
}

if [ "$1" = "" ] || [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ] ; then
    usage
else
    "$@"
fi
