Flextesa: Flexible Tezos Sandboxes
==================================

This repository contains the Flextesa library used in
[tezos/tezos](https://gitlab.com/tezos/tezos) to build the `tezos-sandbox`
[tests](https://tezos.gitlab.io/developer/flextesa.html), as well as some extra
testing utilities, such as the `flextesa` application, which may be useful to
the greater community (e.g. to test third party tools against fully functional
Tezos sandboxes).


<!--TOC-->


## Run With Docker

The current _released_ image is `oxheadalpha/flextesa:20230915` (also available
as `oxheadalpha/flextesa:latest`):

It is built top of the `flextesa` executable and Octez suite, for 2
architectures: `linux/amd64` and `linux/arm64/v8` (tested on Apple Silicon); it
also contains the `*box` scripts to quickly start networks with predefined
parameters. For instance:
  
```sh
image=oxheadalpha/flextesa:latest
script=nairobibox
docker run --rm --name my-sandbox --detach -p 20000:20000 \
       -e block_time=3 \
       "$image" "$script" start
```

All the available scripts start single-node full-sandboxes (i.e. there is a
baker advancing the blockchain):

- `nairobibox`: Nairobi protocol
- `oxfordbox`: Oxford protocol
- `alphabox`: Alpha protocol, the development version of the `N` protocol at the
  time the docker-build was last updated.
    - See also `docker run "$image" octez-node --version`.

The default `block_time` is 5 seconds.

See also the accounts available by default:

```default
$ docker exec my-sandbox $script info
Usable accounts:

- alice
  * edpkvGfYw3LyB1UcCahKQk4rF2tvbMUk8GFiTuMjL75uGXrpvKXhjn
  * tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb
  * unencrypted:edsk3QoqBuvdamxouPhin7swCvkQNgq4jP5KZPbwWNnwdZpSpJiEbq
- bob
  * edpkurPsQ8eUApnLUJ9ZPDvu98E8VNj4KtJa1aZr16Cr5ow5VHKnz4
  * tz1aSkwEot3L2kmUvcoxzjMomb9mvBNuzFK6
  * unencrypted:edsk3RFfvaFaxbHx8BMtEW1rKQcPtDML3LXjNqMNLCzC3wLC1bWbAt

Root path (logs, chain data, etc.): /tmp/mini-box (inside container).
```

The implementation for these scripts is `src/scripts/tutorial-box.sh`, they are
just calls to `flextesa mini-net` (see its general
[documentation](./src/doc/mini-net.md)).

The scripts run sandboxes with archive nodes for which the RPC port is `20 000`.
You can use any client, including the `octez-client` inside the docker
container, which happens to be already configured:

```default
$ alias tcli='docker exec my-sandbox octez-client'
$ tcli get balance for alice
2000000 ꜩ
```

**Note on Oxford** Bootstrap accounts in `oxfordbox` will start out
automatically staking. This stake is frozen and will not show up in the account
balance until un-staked.

You can always stop the sandbox, and clean-up your resources with: `docker kill
my-sandbox`.


### Baking Manually

One can run so-called “manual” sandboxes, i.e. sandboxes with no baking, with
the `start_manual` command.

```default
$ docker run --rm --name my-sandbox --detach -p 20000:20000 \
         "$image" "$script" start_manual
```

Then every time one needs a block to be baked:

```default
$ docker exec my-sandbox "$script" bake
```

Example (using the `tcli` alias above):


```default
$ tcli get balance for alice
1800000 ꜩ
$ tcli --wait none transfer 10 from alice to bob   # Option `--wait` is IMPORTANT!
...
$ tcli get balance for alice   # Alice's balance has not changed yet:
1800000 ꜩ
$ docker exec my-sandbox "$script" bake
...
$ tcli get balance for alice   # The operation is now included:
1799989.999648 ꜩ
$ tcli rpc get /chains/main/blocks/head/metadata | jq .level_info.level
2
$ docker exec my-sandbox "$script" bake
...
$ tcli rpc get /chains/main/blocks/head/metadata | jq .level_info.level
3
```

Notes:

- If you forget `--wait none`, `octez-client` waits for the operation to be
  included, so you will need to `bake` from another terminal.
- `"$script" bake` is equivalent to `tcli bake for baker0 --minimal-timestamp`.


### User-Activated-Upgrades

The scripts inherit the [mini-net](./src/doc/mini-net.md)'s support for
user-activated-upgrades (a.k.a. “hard forks”). For instance, this command starts
a Nairobi sandbox which switches to Oxford at level 20:


```default
$ docker run --rm --name my-sandbox --detach -p 20000:20000 \
         -e block_time=2 \
         "$image" nairobibox start --hard-fork 20:Oxford:
```

With `tcli` above and `jq` you can keep checking the following to observe the
protocol change:

```default
$ tcli rpc get /chains/main/blocks/head/metadata | jq .level_info,.protocol
{
  "level": 24,
  "level_position": 23,
  "cycle": 2,
  "cycle_position": 7,
  "expected_commitment": true
}
"Proxford..."
```

Notes:

- The default cycle length in the sandboxes is 8 blocks and switching protocols
  before the end of the first cycle is not supported by Octez.
- The `oxfordbox` script can also switch to `Alpha` (e.g. `--hard-fork
  16:Alpha:`).

### Full Governance Upgrade

The `start_upgrade` command is included with the docker image.

This implementation of `src/scripts/tutorial-box.sh` is a call to `flextesa
daemons-upgrade` (see its general
[daemons-upgrade](./src/doc/daemons-upgrade.md)).

``` default
$ docker run --rm --name my-sandbox -p 20000:20000 --detach \
         -e block_time=2 \
         "$image" nairobibox start_upgrade
```

With `start_upgrade` the sandbox network will do a full voting round followed by
a protocol change. The `nairobibox` script will start with the `Nairobi` protocol and
upgrade to `Oxford`; the `oxfordbox` upgrades to protocol `Alpha`.

Voting occurs over five periods. You can adjust the length of the voting periods
with the variable `blocks_per_voting_period`. Batches of dummy proposals will be
inserted with `extra_dummy_proposals_batch_size`. These proposals can be
scheduled at specific block-levels within the first (Proposal) voting period,
using the variable `extra_dummy_proposals_batch_level`.

``` default
$ docker run --rm --name my-sandbox -p 20000:20000 --detach \
         -e blocks_per_voting_period=12 \
         -e extra_dummy_proposals_batch_size=2 \
         -e extra_dummy_proposals_batch_level=2,4 \
         -e number_of_bootstrap_accounts=2
         "$image" "$script" start_upgrade
```

The above command will result in 5 total proposals followed by a successful
upgrade. The `extra_dummy_proposals_batch_size`can't exceed the
`number_of_bootstrap_accounts` or the operations will fail with too many
`manager_operations_per_block`.

The default values are:

- `blocks_per_voting_period` = 16
- `extra_dummy_proposals_batch_size` = 2
- `extra_dummy_proposals_batch_level` = 3,5
- `number_of_bootstrap_accounts` = 4

Note: As with the `start` command `start_upgrade` comes with the Alice and Bob
accounts by default.

### Adaptive Issuance

The `start_adaptive_issuance` command initializes a sandbox environment where
adaptive issuance is immediately activated (requires at least the Oxford
protocol).

``` default
$ docker run --rm --name my-sandbox -p 20000:20000 --detach \
        "$image" oxfordbox start_adaptive_issuance
```

Once adaptive issuance is activated, it will launch after five cycles. Any
changes in issuance will take effect a few cycles after the launch cycle. Using
the `tcli` command (as aliased earlier), you can check the launch cycle and view
the expected issuance for the next few cycles.

``` default
$ tcli rpc get /chains/main/blocks/head/context/adaptive_issuance_launch_cycle
5
$ tcli rpc get /chains/main/blocks/head/context/issuance/expected_issuance | jq .
[
  {
    "cycle": 1,
    "baking_reward_fixed_portion": "333333",
    "baking_reward_bonus_per_slot": "1302",
    "attesting_reward_per_slot": "2604",
    "liquidity_baking_subsidy": "83333",
    "seed_nonce_revelation_tip": "260",
    "vdf_revelation_tip": "260"
  },
 ...
]
```

The command `start_upgrade_with_adaptive_issuance` starts a sandbox network
that undergoes a complete governance upgrade. Once the upgrade to the next
protocol is completed, all bakers will vote "on" for adaptive issuance.

``` default
$ docker run --rm --name my-sandbox -p 20000:20000 --detach \
          "$image" "$script" start_upgrade_with_adaptive_issuance
```

To expedite the activation of adaptive issuance, the protocol constant
`adaptive_issuance_ema_threshold` is set to 1. This facilitates immediate
activation in most tests, with a singular exception: it's not possible to adjust
protocol constants for a future protocol. Thus, when using the command
`start_upgrade_with_adaptive_issuance` combined with the nairobibox script,
after upgrading to the Oxford protocol, the `adaptive_issuance_ema_threshold`
will be determined by the protocol.

You can verify its value using:

``` default
$ tcli rpc get /chains/main/blocks/head/context/constants | jq .adaptive_issuance_launch_ema_threshold
100000000
```

An EMA threshold of 100,000,000 signifies that, after upgrading to the Oxford
protocol, nairobibox will require more than an hour (with block times set to
one second) to activate adaptive issuance. For quicker activation, consider using
`oxfordbox start_upgrade_with_adaptive_issuance`.

### Smart Optimistic Rollups

The released image [scripts](#run-with-docker) include two commands for starting
a [Smart Optimistic Rollup](https://tezos.gitlab.io/alpha/smart_rollups.html)
sandbox:

- [start_custom_smart_rollup](#staring-a-smart-rollup-sandbox-with-a-custom-kernel)
- [start_tx_smart_rollup](#-start-the-tx-smart-rollup)

Both are an implementation of the `flextesa mini-network` with the
`--smart-rollup` option.

#### Staring a Smart Rollup Sandbox with a Custom Kernel
The following command will start a smart rollup with the kernel you provide.

``` default
$ docker run --rm --detach -p 20000:20000 -p 20002:20002 --name my-sandbox \
        --volume /path/to/kernel/files:/rollup "$image" "$script" \
        start_custom_smart_rollup wasm_2_0_0 "Unit" /rollup/my-kernel.wasm \
```

Replace `/path/to/kernel/files` with the path to the directory containing the
.wasm file on the docker host. The `--volume` option will mount that directory
to the docker container. `wasm_2_0_0` and `Unit` should be the values (KIND and
TYPE) appropriate for your kernel. `/rollup/my-kernel.wasm` will be the location
of your kernel inside the container. The published (`-p`) ports **20000** and
**20002** will be the rpc_ports for the **tezos-node** and **smart-rollup-node**
respectively.

Flextesa has a few help options to use when testing your smart rollup kernel.
This example uses the same `start_custom_rollup` command from above.

``` default
$ docker run --rm --detach -p 20000:20000 -p 20002:20002 --name my-sandbox \
        --volume /path/to/kernel/files:/rollup "$image" "$script" \
        start_custom_smart_rollup wasm_2_0_0 "Unit" /rollup/kernel.wasm \
        --kernel-setup-file=/rollup/setup-file.yaml \
        --smart-contract=/rollup/my-contract.tz:"Unit" \
        --smart-rollup-node-init-with=log-kernel-debug \
        --smart-rollup-node-run-with="log-kernel-debug log-kernel-debug-file=/tmp/my-debug.log"
```

If you have a kernel "set-up" file, Flextesa will pass it to the
`smart-rollup-installer` when preparing the kernel preimage with the option
`--kernel-setup-file=PATH`. The option `--smart-contract=PATH:TYPE` will
originate the smart contract of TYPE at PATH. Both the smart contract and set-up
files can added to the same directory as your kernel file which will be mounted
to the container.

The options `--smart-rollup-node-init-with=FLAG|OPTION=VALUE` and
`--smart-rollup-node-run-with=FLAG|OPTION=VALUE` will allow you to pass
additional options to the octez-smart-rollup-node binaries `init` and `run`
command. The example above is equivalent to:

``` default
$ octez-smart-rollup-node init --log-kernel-debug
$ octez-smart-rollup-node run --log-kernel-debug --log-kernel-debug-file=/tmp/my-debug.log 
```

You can confirm that the smart-rollup-node has been initialized and see relevant
rollup info from the node's config with the `smart_rollup_info` command.

``` default
$ docker exec my-sandbox "$script" smart_rollup_info
{
  "smart_rollup_node_config":  {
  "smart-rollup-address": "sr1KVTPm3NLuetrrPLGYnQrzMpoSmXFsNXwp",
  "smart-rollup-node-operator": {
    "publish": "tz1SEQPRfF2JKz7XFF3rN2smFkmeAmws51nQ",
    "add_messages": "tz1SEQPRfF2JKz7XFF3rN2smFkmeAmws51nQ",
    "cement": "tz1SEQPRfF2JKz7XFF3rN2smFkmeAmws51nQ",
    "refute": "tz1SEQPRfF2JKz7XFF3rN2smFkmeAmws51nQ"
  },
  "rpc-addr": "0.0.0.0",
  "rpc-port": 20002,
  "fee-parameters": {},
  "mode": "operator"
},
}
```

You'll need the **rpc-port** for the smart rollup node entrypoint when making
calls with the smart-rollup-client. For exmaple:

``` default
$ alias srcli='docker exec my-sandbox octez-smart-rollup-client-PtNairobi -E http://localhost:20002'
```

For convenience, the included script contains the function
`client_remember_smart_contracts` to add contract addresses to the octez-client
data directory configured.

``` default
$ docker exec my-sandbox "$script" client_remember_contracts
Added contract my-contract: KT19Z5M5z9jBf1ikYABrbrCw3M2QLQLSV1KA

$ docker exec my-sandbox octez-client list known contracts
my-contract: KT19Z5M5z9jBf1ikYABrbrCw3M2QLQLSV1KA
```

```

#### Start the TX Smart Rollup
The command `start_tx_smart_rollup`, originates the transaction smart rollup
with the [tx-kernel](https://gitlab.com/tezos/kernel). This is the default kernel 
included with flextesa mini-network.

``` default
$ docker run --rm --name my-sandbox --detach -p 20000:20000 -p 20002:20002 \
        "$image" "$script" start_tx_smart_rollup 
```

The docker container includes the
[tx-client](https://gitlab.com/emturner/tx-client) which can be used to interact
with the tx-smart-rollup. Initialize it with the following command.

``` default
$ docker exec my-sandbox "$script" tx_client_init
$ docker exec my-sandbox "$script" tx_client_show_config
{
"config_file": "/tmp/mini-smart-rollup-box/tx-client/config.json",
"config": {
  "tz_client": "/usr/bin/tz-client-for-tx-client.sh",
  "tz_client_base_dir": "/tmp/mini-smart-rollup-box/Client-base-C-N000",
  "tz_rollup_client": "/usr/bin/tz-rollup-client-for-tx-client.sh",
  "forwarding_account": "alice",
  "depositor_address": "KT1EX3joap58iygupJsbxhgGmhwVTWzHM3ky",
  "rollup_address": "sr1KVTPm3NLuetrrPLGYnQrzMpoSmXFsNXwp",
  "known_accounts": [],
  "known_tickets": {}
},
}

```

Alias the tx-client to simplify interacting with the tx-smart-rollup (the
`--config-file` option is required). Then generate a new address and send ticks
to that address.

``` default
$ alias tx_cli='docker exec my-sandbox tx-client \
        --config-file /tmp/mini-smart-rollup-box/tx-client/config.json'
$ tx_cli gen-key alice_rollup_addr
$ tx_cli mint-and-deposit \
        --amount 10 \
        --contents "hello world" \
        --target alice_rollup_addr \
        --ticket-alias my_tickets
```

The tx-client command, `mint-and-deposit` is a layer one contract call which
mints ticket and deposits them to the target address. Below is a truncated
example of the calls output.

``` default
Node is bootstrapped.
Estimated gas: 4058.231 units (will add 100 for safety)
Estimated storage: 66 bytes added (will add 20 for safety)
Operation successfully injected in the node.
...
      Internal operations:
        Internal Transaction:
          Amount: ꜩ0
          From: KT1EX3joap58iygupJsbxhgGmhwVTWzHM3ky
          To: sr1KVTPm3NLuetrrPLGYnQrzMpoSmXFsNXwp
          Parameter: (Pair "5e87fcdd8c9bf5d80a58ec7c5e28c41bec64ae0a"
                           (Pair 0x01411c976a093fbd4964353e52a2470ed61d1148ef00 (Pair "hello world" 10)))
          This transaction was successfully applied
          Consumed gas: 1007.075
          Ticket updates:
            Ticketer: KT1EX3joap58iygupJsbxhgGmhwVTWzHM3ky
            Content type: string
            Content: "hello world"
            Account updates:
              sr1KVTPm3NLuetrrPLGYnQrzMpoSmXFsNXwp ... +10

...
```

For more information on the tx-client see it's [repository](https://gitlab.com/emturner/tx-client).

## Build

With Opam ≥ 2.1:

```sh
opam switch create . --deps-only \
     --formula='"ocaml-base-compiler" {>= "4.13" & < "4.14"}'
eval $(opam env)
opam pin add -n tezai-base58-digest https://gitlab.com/oxheadalpha/tezai-base58-digest.git
opam install --deps-only --with-test --with-doc \
     ./tezai-tz1-crypto.opam \
     ./flextesa.opam ./flextesa-cli.opam # Most of this should be already done.
opam install merlin ocamlformat.0.24.1    # For development.
```

Then:

    make

The above builds the `flextesa` library, the `flextesa` command line application
(see `./flextesa --help`) and the tests (in `src/test`).


## MacOSX Users

At runtime, sandboxes usually depend on a couple of linux utilities.

If you are on Mac OS X, you can do `brew install coreutils util-linux`. Then run
the tests with:

```
export PATH="/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/util-linux/bin:$PATH"
```

## Build Of The Docker Image

See `./Dockerfile`, it often requires modifications with each new version of
Octez or for new protocols, the version of the Octez static binaries (`x86_64`
and `arm64`) is set in `src/scripts/get-octez-static-binaries.sh`.

There are 2 images: `-build` (all dependencies) and `-run` (stripped down image
with only runtime requirements).

The `x86_64` images are built by the CI, see the job `docker:images:` in
`./.gitlab-ci.yml`.

To build locally:

```sh
docker build --target build_step -t flextesa-build .
docker build --target run_image -t flextesa-run .
```

Do not forget to test it: `docker run -it "$image" "$script" start`

### Multi-Architecture Image

To build the **released multi-architecture images**, we used to use
[buildx](https://docs.docker.com/buildx/working-with-buildx/) but this does not
work anymore (Qemu cannot handle the build on the foreign archtecture). We use
the “manifest method” cf.
[docker.com](https://www.docker.com/blog/multi-arch-build-and-images-the-simple-way/).
We need one host for each architecture (AMD64 and ARM64).

#### On Each Architechture

Setting up Docker (example of AWS-like Ubuntu hosts):

```sh
sudo apt update
sudo apt install docker.io
sudo adduser ubuntu docker
```

(may have to `sudo su ubuntu` to really get _into the group_)

Build and push the image (you may need to `docker login`):

```sh
base=oxheadalpha/flextesa
tag=20221024-rc
docker build --target run_image -t flextesa-run .
docker tag flextesa-run "$base:$tag-$(uname -p)"
docker push "$base:$tag-$(uname -p)"
```

#### Merging The Manifests

On any host:

```sh
docker manifest create $base:$tag \
      --amend $base:$tag-aarch64 \
      --amend $base:$tag-x86_64
docker manifest push $base:$tag
```

When ready for the release, repeat the theses steps swapping the manifest "$tag"
each time. Once sans "-rc" and again for "latest".

``` sh
newtag=20221024
docker manifest create $base:$newtag \
      --amend $base:$tag-aarch64 \
      --amend $base:$tag-x86_64
docker manifest push $base:$newtag
docker manifest create $base:latest \
      --amend $base:$tag-aarch64 \
      --amend $base:$tag-x86_64
docker manifest push $base:latest
```

## More Documentation

The command `flextesa mini-net [...]` has a dedicated documentation page: [The
`mini-net` Command](./src/doc/mini-net.md).

Documentation regarding `flextesa daemons-upgrade [...]` can be found here: [The
`daemons-upgrade` Command](./src/doc/daemons-upgrade.md).

The API documentation of the Flextesa OCaml library starts here: [Flextesa:
API](https://tezos.gitlab.io/flextesa/lib-index.html).

Blog posts:

- [2019-06-14](https://obsidian.systems/blog/introducing-flextesa-robust-testing-tools-for-tezos-and-its-applications)
- [2021-10-14](https://medium.com/the-aleph/new-flextesa-docker-image-and-some-development-news-f0d5360f01bd)
- [2021-11-29](https://medium.com/the-aleph/flextesa-new-image-user-activated-upgrades-tenderbake-cc7602781879)
- [2022-03-22](https://medium.com/the-aleph/flextesa-protocol-upgrades-3fdf2fae11e1):
  Flextesa: Protocol Upgrades
- [2022-11-30](https://medium.com/the-aleph/flextesa-toru-sandbox-78d7b166e06):
  Flextesa TORU Sandbox




