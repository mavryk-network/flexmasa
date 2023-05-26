#! /bin/sh

default_protocol=Mumbai
next_protocol_name=Nairobi
next_protocol=PtNairob
case "$(basename $0)" in
    "mumbaibox")
        default_protocol=Mumbai
        protocol_hash=PtMumbai
        binary_suffix=PtMumbai
        next_protocol_name=Nairobi
        next_protocol=PtNairob
        ;;
    "nairobibox")
        default_protocol=Nairobi
        protocol_hash=PtNairob
        binary_suffix=PtNairob
        next_protocol_name=Aplha
        next_protocol=alpha
        ;;
    "alphabox")
        default_protocol=Alpha
        protocol_hash=ProtoA
        binary_suffix=alpha
        next_protocol_name=Failure
        next_protocol=alpha
        ;;
    *) ;;
esac

all_commands="
* usage | help | --help | -h: Display this help message."
usage() {
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
export b0="$(flextesa key bootacc-0)"
all_commands="$all_commands
* start : Start a sandbox with the $default_protocol protocol."
root_path=/tmp/mini-box
start() {
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
* start_manual : Start a sandbox with the $default_protocol protocol and NO BAKING."
start_manual() {
    start --no-baking --timestamp-delay=-3600 "$@"
}

all_commands="$all_commands
* bake : Try to bake a block (to be used with 'start_manual' sandboxes)."
bake() {
    octez-client bake for baker0 --minimal-timestamp
}

vote_period=${blocks_per_voting_period:-16}
dummy_props=${extra_dummy_proposals_batch_size:-2}
dummy_levels=${extra_dummy_proposals_batch_levels:-3,5}

all_commands="$all_commands
* start_upgrade : Start a full-upgrade sandbox ($default_protocol -> $next_protocol_name)."
daemons_root=/tmp/daemons-upgrade-box
start_upgrade() {
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
* start_toru : Start a transactional rollup sandbox with the $default_protocol protocol."
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

## Smart rollup sandbox commands
all_commands="$all_commands
* start_custom_smart_rollup KIND TYPE PATH: Start a smart rollup sandbox with the $default_protocol protocol and a custom kernel.
* smart_rollup_info : Show the smart rollup node config file.
* start_tx_smart_rollup : Start the tx-kernel (transaction) smart rollup sandbox with the $default_protocol protocol.
* tx_client_show_config : Print tx-client config file. (Requires start_tx_smart_rollup).
* tx_client_init : Initialize the tx-client for interacting with the tx-smart-rollup kernel (Requires start_tx_smart_rollup)."
root_path="/tmp/mini-smart-rollup-box"
tx_client_dir="${root_path}/tx-client"
tx_client_config="${tx_client_dir}/config.json"

# Smart rollup with user provided kernel.
start_custom_smart_rollup() {
    kind="$1"
    type="$2"
    path="$3"

    flextesa mini-network \
        --root-path "$root_path" \
        --time-between-blocks "$time_bb" \
        --set-history-mode=N000:archive \
        --balance-of-bootstrap-accounts tez:100_000_000 \
        --number-of-boot 2 \
        --add-bootstrap-account="$alice@2_000_000_000_000" \
        --add-bootstrap-account="$bob@2_000_000_000_000" \
        --no-daemons-for=alice \
        --no-daemons-for=bob \
        --until-level 200_000_000 \
        --protocol-kind "$default_protocol" \
        --smart-rollup \
        --custom-kernel "$kind:$type:$path"

}

# Print the rollup node config.
smart_rollup_info() {
    config_file=$(find ${root_path}/smart-rollup -name '*-smart-rollup-operator-node-000' -type d -exec echo {}/data-dir/config.json \;)

    echo '{'
    echo "  \"smart_rollup_node_config\":  $(jq . ${config_file}),"
    echo '}'
}

# Smart rollup with tx-kernel (transaction rollup).
start_tx_smart_rollup() {
    flextesa mini-network \
        --root-path "$root_path" \
        --set-history-mode=N000:archive \
        --size 1 \
        --time-between-blocks "$time_bb" \
        --balance-of-bootstrap-accounts tez:100_000_000 \
        --number-of-boot 2 \
        --add-bootstrap-account="$alice@2_000_000_000_000" \
        --until-level 200_000_000 \
        --protocol-kind "$default_protocol" \
        --smart-rollup
}

# Print tx-client config file
tx_client_show_config() {
    if [ -f "$tx_client_config" ]; then
        echo '{'
        echo "\"config_file\": \"$tx_client_config\","
        echo "\"config\": $(jq . "$tx_client_config"),"
        echo '}'
    else
        echo "Error: Config file not found at $tx_client_config"
        return 1
    fi
}

# Initialize the tx-client for interacting with the tx-smart-rollup kernel
tx_client_init() {
    set -e

    mkdir -p "$tx_client_dir"
    base_dir="${root_path}/Client-base-C-N000"
    rollup_client_dir="${root_path}/smart-rollup/smart-rollup-client-${binary_suffix}"
    mkdir -p "$rollup_client_dir"

    # The tx-client config-init command takes as arguments the absolute paths to
    # the tezos binaries with no optional arguments. Thus, the follow scripts are created.
    # Create octez-client script with the correct endpoint
    echo '#! /bin/sh' >'/usr/bin/tz-client-for-tx-client.sh'
    echo 'octez-client -E http://localhost:20000 "$@"' >>'/usr/bin/tz-client-for-tx-client.sh'
    chmod +x '/usr/bin/tz-client-for-tx-client.sh'
    # Create octez-smart-rollup-client script
    echo '#! /bin/sh' >'/usr/bin/tz-rollup-client-for-tx-client.sh'
    echo "octez-smart-rollup-client-${binary_suffix} -E http://localhost:20002 -d \"${rollup_client_dir}\" \"\$@\"" >>'/usr/bin/tz-rollup-client-for-tx-client.sh'
    chmod +x '/usr/bin/tz-rollup-client-for-tx-client.sh'

    tx-client --config-file "$tx_client_config" config-init \
        --tz-client "/usr/bin/tz-client-for-tx-client.sh" \
        --tz-client-base-dir "$base_dir" \
        --tz-rollup-client "/usr/bin/tz-rollup-client-for-tx-client.sh" \
        --forwarding-account alice

    tx_client_show_config

}

all_commands="$all_commands
* info : Show accounts and information about the sandbox."
info() {
    cat >&2 <<EOF
Usable accounts:

- $(echo $alice | sed 's/,/\n  * /g')
- $(echo $bob | sed 's/,/\n  * /g')

Root path (logs, chain data, etc.): $root_path (inside container).
EOF
}

all_commands="$all_commands
* initclient : Setup the local octez-client."
initclient() {
    octez-client --endpoint http://localhost:20000 config update
    octez-client --protocol "$protocol_hash" import secret key alice "$(echo $alice | cut -d, -f 4)" --force
    octez-client --protocol "$protocol_hash" import secret key bob "$(echo $bob | cut -d, -f 4)" --force
    octez-client --protocol "$protocol_hash" import secret key baker0 "$(echo $b0 | cut -d, -f 4)" --force
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
