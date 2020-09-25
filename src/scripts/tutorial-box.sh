#! /bin/sh

default_protocol=Carthage

all_commands="
* usage | help | --help | -h: Display this help message."
usage () {
    cat >&2 <<EOF
This script provides a Flextesa “mini-net” sandbox with predefined
parameters useful for tutorials and basic exploration with
wallet software like \`tezos-client\`. This one uses the $default_protocol
protocol (hash: $protocol_hash).

usage: $0 <command>

where <command> may be:
$all_commands
EOF
}

case "$default_protocol" in
    "Carthage" )
        daemon_suffix=006-PsCARTHA
        protocol_hash=PsCARTHAGazKbHtnKfLzQg3kms52kSRpgnDY982a9oYsSXRLQEb
        ;;
    "Delphi")
        daemon_suffix=007-PsDELPH1
        protocol_hash=PsDELPH1Kxsxt8f9eWbxQeRxkjfbxoqM52jvs5Y5fBxWWh4ifpo
        ;;
    * )
        echo "Cannot understand protocol kind: '$default_protocol'"
        usage ;;
esac

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
             --time-b "$time_bb" \
             --add-bootstrap-account="$alice@2_000_000_000_000" \
             --add-bootstrap-account="$bob@2_000_000_000_000" \
             --no-daemons-for=alice \
             --no-daemons-for=bob \
             --until-level 200_000_000 \
             --tezos-baker "tezos-baker-$daemon_suffix" \
             --tezos-endor "tezos-endorser-$daemon_suffix" \
             --tezos-accus "tezos-accuser-$daemon_suffix" \
             --protocol-kind "$default_protocol" \
             --protocol-hash "$protocol_hash"
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


if [ "$1" = "" ] || [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ] ; then
    usage
else
    "$@"
fi
