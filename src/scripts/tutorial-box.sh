#! /bin/sh

default_protocol=Kathmandu
next_protocol_name=Lima
next_protocol=PtLimaPt
case "$(basename $0)" in
    "kathmandubox" )
        default_protocol=Kathmandu
        next_protocol_name=Lima
        next_protocol=PtLimaPt ;;
    "limabox" )
        default_protocol=Lima
        next_protocol_name=Alpha
        next_protocol=alpha ;;
    "alphabox" )
        default_protocol=Alpha
        next_protocol_name=Failure
        next_protocol=alpha ;;
    * ) ;;
esac

all_commands="
* usage | help | --help | -h: Display this help message."
usage () {
    cat >&2 <<EOF
This script provides a Flextesa “mini-net” sandbox with predefined
parameters useful for tutorials and basic exploration with
wallet software like \`octez-client\`. This one uses the $default_protocol
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
* start : Start a sandbox with the $default_protocol protocol."
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

vote_period=${blocks_per_voting_period:-16}
dummy_props=${extra_dummy_proposals_batch_size:-2}
dummy_levels=${extra_dummy_proposals_batch_levels:-3,5}

all_commands="$all_commands
* start-upgrade : Start a full-upgrade sandbox ($default_protocol -> $next_protocol_name)."
daemons_root=/tmp/daemons-upgrade-box
start_upgrade () {
    flextesa daemons-upgrade \
        --next-protocol-kind "$next_protocol_name" \
        --root-path "$daemons_root" \
        --extra-dummy-proposals-batch-size "$dummy_props" \
        --extra-dummy-proposals-batch-levels "$dummy_levels" \
        --size 2 \
        --number-of-bootstrap-accounts 2 \
        --balance-of-bootstrap-accounts tez:100_000_000 \
        --add-bootstrap-account="$alice@2_000_000_000_000" \
        --add-bootstrap-account="$bob@2_000_000_000_000" \
        --no-daemons-for=alice \
        --no-daemons-for=bob \
        --time-between-blocks "$time_bb" \
        --blocks-per-voting-period "$vote_period" \
        --with-timestamp \
        --protocol-kind "$default_protocol" \
        --second-baker octez-baker-"$next_protocol" \
        --test-variant full-upgrade \
        --until-level 200_000_000
}

all_commands="$all_commands
* start : Start a transactional rollup sandbox with the $default_protocol protocol."
root_path=/tmp/mini-box
start_toru() {
    flextesa mini-net \
        --root "$root_path" --size 1 "$@" \
        --set-history-mode N000:archive \
        --number-of-b 2 \
        --balance-of-bootstrap-accounts tez:100_000_000 \
        --time-b "$time_bb" \
        --add-bootstrap-account="$alice@2_000_000_000_000" \
        --add-bootstrap-account="$bob@2_000_000_000_000" \
        --no-daemons-for=alice \
        --no-daemons-for=bob \
        --until-level 200_000_000 \
        --protocol-kind "$default_protocol" \
        --tx-rollup 10:torubox
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
* initclient : Setup the local octez-client."
initclient () {
    octez-client --endpoint http://localhost:20000 config update
    octez-client --protocol Psithaca2MLR import secret key alice "$(echo $alice | cut -d, -f 4)" --force
    octez-client --protocol Psithaca2MLR import secret key bob "$(echo $bob | cut -d, -f 4)" --force
}

all_commands="$all_commands
* toru_info : Show account and information about the trasanctional rollup sandbox."
toru_info() {
    echo '{'
    echo "  \"toru_node_config\":  $(jq . ${root_path}/tx-rollup-torubox/torubox-operator-node-000/data-dir/config.json),"
    echo "  \"turo_ticket_deposit_contract\":  $(jq .[0] ${root_path}/Client-base-C-N000/contracts)"
    echo '}'
}

if [ "$1" = "" ] || [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
else
    "$@"
fi
