#! /bin/sh

default_protocol=Nairobi
next_protocol_name=Oxford
next_protocol_hash=Proxford
case "$(basename $0)" in
    "nairobibox")
        default_protocol=Nairobi
        protocol_hash=PtNairob
        binary_suffix=PtNairob
        next_protocol_name=Oxford
        next_protocol_hash=Proxford
        ;;
    "oxfordbox")
        default_protocol=Oxford
        protocol_hash=Proxford
        binary_suffix=Proxford
        next_protocol_name=Alpha
        next_protocol_hash=alpha
        ;;
    "alphabox")
        default_protocol=Alpha
        protocol_hash=ProtoA
        binary_suffix=alpha
        next_protocol_name=Failure
        next_protocol_hash=alpha
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
root_path=/tmp/flextesa-mini-box

export alice="$(flextesa key alice)"
export bob="$(flextesa key bob)"
export b0="$(flextesa key bootacc-0)"
all_commands="$all_commands
* start : Start a sandbox with the $default_protocol protocol."
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
    octez-client --endpoint http://localhost:20000 bake for bootacc-0 --minimal-timestamp
}

vote_period=${blocks_per_voting_period:-16}
dummy_props=${extra_dummy_proposals_batch_size:-2}
dummy_levels=${extra_dummy_proposals_batch_levels:-3,5}

all_commands="$all_commands
* start_upgrade : Start a full-upgrade sandbox ($default_protocol -> $next_protocol_name)."
start_upgrade() {
    flextesa daemons-upgrade \
        --root-path "$root_path" "$@" \
        --next-protocol-kind "$next_protocol_name" \
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
        --second-baker octez-baker-"$next_protocol_hash" \
        --test-variant full-upgrade \
        --until-level 200_000_000
}

## Smart rollup sandbox commands
all_commands="$all_commands
* start_custom_smart_rollup KIND TYPE PATH : Start a smart rollup sandbox with the $default_protocol protocol and a custom kernel."
# Smart rollup with user provided kernel.
start_custom_smart_rollup() {
    kind="$1"
    type="$2"
    kernel_path="$3"
    shift 3

    # Check if the required arguments are provided
    if [ -z "$kind" ] || [ -z "$type" ] || [ -z "$kernel_path" ]; then
        echo "Error: Missing required arguments: KIND TYPE PATH"
        return 1
    fi

    start --start-smart-rollup "custom:$kind:$type:$kernel_path" "$@"

}

# Print the rollup node config.
all_commands="$all_commands
* smart_rollup_info : Show the smart rollup node config file. (and evm node config file if applicable)."
smart_rollup_info() {
    config_file=$(find "${root_path}/smart-rollup" -name '*-smart-rollup-operator-node-000' -type d -exec echo {}/data-dir/config.json \;)
    evm_node_conf="/tmp/flextesa-mini-box/smart-rollup/evm-node/data-dir/config.json"

    if [ ! -f "$config_file" ]; then
        echo "Smart-rollup-node config file not found."
        config_json="{}"
    else
        config_json=$(jq . "$config_file")
    fi

    if [ ! -f "$evm_node_conf" ]; then
        evm_conf_json="{}"
    else
        evm_conf_json=$(jq . "$evm_node_conf")
    fi

    echo '{'
    echo "  \"smart_rollup_node_config\":  ${config_json},"
    echo "  \"evm_node_config\":  ${evm_conf_json},"
    echo '}'
}

# Smart rollup with tx-kernel (transaction rollup).
all_commands="$all_commands
* start_tx_smart_rollup : Start the tx-kernel (transaction) smart rollup sandbox with the $default_protocol protocol."
start_tx_smart_rollup() {
    start --start-smart-rollup tx "$@"
}

# Print tx-client config file
all_commands="$all_commands
* tx_client_show_config : Print tx-client config file. (Requires start_tx_smart_rollup)."
tx_client_dir="${root_root}/tx-client"
tx_client_config="${tx_client_dir}/config.json"
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
all_commands="$all_commands
* tx_client_init : Initialize the tx-client for interacting with the tx-smart-rollup kernel (Requires start_tx_smart_rollup)."
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

# Start EVM Smart Rollup
all_commands="$all_commands
* start_evm_smart_rollup : Start the EVM smart rollup sandbox with the $default_protocol protocol."
start_evm_smart_rollup() {
    start --start-smart-rollup evm "$@"
}

all_commands="$all_commands
* start_adaptive_issuanced : Start a $default_protocol protocol sandbox with all bakers voting \"on\" for addative issuance."
start_adaptive_issuance() {
    start --issuance-vote "on" "$@"
}

all_commands="$all_commands
* start_upgrade_with_adaptive_issuanced : Start a $default_protocol protocol sandbox with all bakers voting \"on\" for addative issuance."
start_upgrade_with_adaptive_issuance() {
    flextesa daemons-upgrade \
        --root "$root_path" --size 1 "$@" \
        --number-of-b 2 \
        --balance-of-bootstrap-accounts tez:100_000_000 \
        --add-bootstrap-account="$alice@2_000_000_000_000" \
        --add-bootstrap-account="$bob@2_000_000_000_000" \
        --no-daemons-for=alice \
        --no-daemons-for=bob \
        --time-b "$time_bb" \
        --with-timestamp \
        --protocol-kind "$default_protocol" \
        --second-baker octez-baker-"$next_protocol_hash" \
        --test-variant full-upgrade \
        --until-level 200_000_000 \
        --adaptive-issuance-vote-first-baker "pass" --adaptive-issuance-vote-second-baker "on"
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
* client_remember_contracts : Add the contracts originated by flextesa to the octez-client data-dir."
client_remember_contracts() {
    contracts="${root_path}/Client-base-C-N000/contracts"

    if [ -f "$contracts" ]; then
        length=$(jq 'length' "$contracts")
        i=0

        while [ $i -lt $length ]; do
            contract_name=$(jq -r ".[$i].name" "$contracts")
            contract_value=$(jq -r ".[$i].value" "$contracts")

            octez-client remember contract "$contract_name" "$contract_value"
            echo "Added contract $contract_name: $contract_value"

            i=$((i + 1))
        done
    else
        echo "There were no smart contract addresses found at $contracts"
    fi
}

all_commands="$all_commands
* client_remember_rollups : Add smart-rollup address to the octez-client data-dir."
client_remember_rollups() {
    rollups="${root_path}/Client-base-C-N000/smart_rollups"

    if [ -f "$rollups" ]; then
        length=$(jq 'length' "$rollups")
        i=0

        while [ $i -lt $length ]; do
            rollup_name=$(jq -r ".[$i].name" "$rollups")
            rollup_value=$(jq -r ".[$i].value" "$rollups")

            octez-client remember smart rollup "$rollup_name" "$rollup_value"
            echo "Added smart rollup $rollup_name: $rollup_value"

            i=$((i + 1))
        done
    else
        echo "There were no smart rollup addresses found at $rollups"
    fi
}

all_commands="$all_commands
* initclient : Setup the local octez-client."
initclient() {
    octez-client --endpoint http://localhost:20000 config update
    octez-client --protocol "$protocol_hash" import secret key alice "$(echo $alice | cut -d, -f 4)" --force
    octez-client --protocol "$protocol_hash" import secret key bob "$(echo $bob | cut -d, -f 4)" --force
    octez-client --protocol "$protocol_hash" import secret key baker0 "$(echo $b0 | cut -d, -f 4)" --force
    client_remember_contracts
    client_remember_rollups
}

if [ "$1" = "" ] || [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
else
    "$@"
fi
