Mavbox: Mavryk Sandboxes
==================================

This repository contains the Mavbox library used in
[mavryk-network/mavryk-protocol](https://gitlab.com/mavryk-network/mavryk-protocol) to build the `mavryk-sandbox`
[tests](https://protocol.mavryk.org/developer/mavbox.html), as well as some extra
testing utilities, such as the `mavbox` application, which may be useful to
the greater community (e.g. to test third party tools against fully functional
Mavryk sandboxes).


<!--TOC-->


## Run With Docker

The _dev_ image is `registry.gitlab.com/mavryk-network/mavbox:dev-run`

It is built top of the `mavbox` executable and Mavkit suite, for 2
architectures: `linux/amd64` and `linux/arm64/v8` (tested on Apple Silicon); it
also contains the `*box` scripts to quickly start networks with predefined
parameters. For instance:
  
```sh
image=mavrykdynamics/mavbox:latest
script=atlasbox
docker run --rm --name my-sandbox --detach -p 20000:20000 \
       -e block_time=3 \
       "$image" "$script" start
```

All the available scripts start single-node full-sandboxes (i.e. there is a
baker advancing the blockchain):

- `atlasbox`: Atlas protocol
- `boreasbox`: Boreas protocol
- `alphabox`: Alpha protocol, the development version of the `N` protocol at the
  time the docker-build was last updated.
    - See also `docker run "$image" mavkit-node --version`.

The default `block_time` is 5 seconds.

See also the accounts available by default:

```default
$ docker exec my-sandbox $script info
Usable accounts:

- alice
  * edpkvGfYw3LyB1UcCahKQk4rF2tvbMUk8GFiTuMjL75uGXrpvKXhjn
  * mv1Hox9jGJg3uSmsv9NTvuK7rMHh25cq44nv
  * unencrypted:edsk3QoqBuvdamxouPhin7swCvkQNgq4jP5KZPbwWNnwdZpSpJiEbq
- bob
  * edpkurPsQ8eUApnLUJ9ZPDvu98E8VNj4KtJa1aZr16Cr5ow5VHKnz4
  * mv1NpEEq8FLgc2Yi4wNpEZ3pvc1kUZrp2JWU
  * unencrypted:edsk3RFfvaFaxbHx8BMtEW1rKQcPtDML3LXjNqMNLCzC3wLC1bWbAt

Root path (logs, chain data, etc.): /tmp/mini-box (inside container).
```

The implementation for these scripts is `src/scripts/tutorial-box.sh`, they are
just calls to `mavbox mini-net` (see its general
[documentation](./src/doc/mini-net.md)).

The scripts run sandboxes with archive nodes for which the RPC port is `20 000`.
You can use any client, including the `mavkit-client` inside the docker
container, which happens to be already configured:

```default
$ alias mcli='docker exec my-sandbox mavkit-client'
$ mcli get balance for alice
2000000 ṁ
```

**Note on Atlas** Bootstrap accounts in `atlasbox` will start out
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

Example (using the `mcli` alias above):


```default
$ mcli get balance for alice
1800000 ṁ
$ mcli --wait none transfer 10 from alice to bob   # Option `--wait` is IMPORTANT!
...
$ mcli get balance for alice   # Alice's balance has not changed yet:
1800000 ṁ
$ docker exec my-sandbox "$script" bake
...
$ mcli get balance for alice   # The operation is now included:
1799989.999648 ṁ
$ mcli rpc get /chains/main/blocks/head/metadata | jq .level_info.level
2
$ docker exec my-sandbox "$script" bake
...
$ mcli rpc get /chains/main/blocks/head/metadata | jq .level_info.level
3
```

Notes:

- If you forget `--wait none`, `mavkit-client` waits for the operation to be
  included, so you will need to `bake` from another terminal.
- `"$script" bake` is equivalent to `mcli bake for baker0 --minimal-timestamp`.


### User-Activated-Upgrades

The scripts inherit the [mini-net](./src/doc/mini-net.md)'s support for
user-activated-upgrades (a.k.a. “hard forks”). For instance, this command starts
a Nairobi sandbox which switches to Atlas at level 20:


```default
$ docker run --rm --name my-sandbox --detach -p 20000:20000 \
         -e block_time=2 \
         "$image" atlasbox start --hard-fork 20:Atlas:
```

With `mcli` above and `jq` you can keep checking the following to observe the
protocol change:

```default
$ mcli rpc get /chains/main/blocks/head/metadata | jq .level_info,.protocol
{
  "level": 24,
  "level_position": 23,
  "cycle": 2,
  "cycle_position": 7,
  "expected_commitment": true
}
"PtAtLas..."
```

Notes:

- The default cycle length in the sandboxes is 8 blocks and switching protocols
  before the end of the first cycle is not supported by Mavkit.
- The `atlasbox` script can also switch to `Alpha` (e.g. `--hard-fork
  16:Alpha:`).

### Full Governance Upgrade

The `start_upgrade` command is included with the docker image.

This implementation of `src/scripts/tutorial-box.sh` is a call to `mavbox
daemons-upgrade` (see its general
[daemons-upgrade](./src/doc/daemons-upgrade.md)).

``` default
$ docker run --rm --name my-sandbox -p 20000:20000 --detach \
         -e block_time=2 \
         "$image" atlasbox start_upgrade
```

With `start_upgrade` the sandbox network will do a full voting round followed by
a protocol change. The `atlasbox` script will start with the `Nairobi` protocol and
upgrade to `Atlas`; the `atlasbox` upgrades to protocol `Alpha`.

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
adaptive issuance is immediately activated (requires at least the Atlas
protocol).

``` default
$ docker run --rm --name my-sandbox -p 20000:20000 --detach \
        "$image" atlasbox start_adaptive_issuance
```

Once adaptive issuance is activated, it will launch after five cycles. Any
changes in issuance will take effect a few cycles after the launch cycle. Using
the `mcli` command (as aliased earlier), you can check the launch cycle and view
the expected issuance for the next few cycles.

``` default
$ mcli rpc get /chains/main/blocks/head/context/adaptive_issuance_launch_cycle
5
$ mcli rpc get /chains/main/blocks/head/context/issuance/expected_issuance | jq .
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
`start_upgrade_with_adaptive_issuance` combined with the atlasbox script,
after upgrading to the Atlas protocol, the `adaptive_issuance_ema_threshold`
will be determined by the protocol.

You can verify its value using:

``` default
$ mcli rpc get /chains/main/blocks/head/context/constants | jq .adaptive_issuance_launch_ema_threshold
100000000
```

An EMA threshold of 100,000,000 signifies that, after upgrading to the Atlas
protocol, atlasbox will require more than an hour (with block times set to
one second) to activate adaptive issuance. For quicker activation, consider using
`atlasbox start_upgrade_with_adaptive_issuance`.

### Smart Optimistic Rollups

The released image [scripts](#run-with-docker) include two commands for starting
a [Smart Optimistic Rollup](https://protocol.mavryk.org/alpha/smart_rollups.html)
sandbox:

- [start_custom_smart_rollup](#staring-a-smart-rollup-sandbox-with-a-custom-kernel)
- [start_evm_rollup](#startgin-the-evm-smart-rollup)

Both are an implementation of the `mavbox mini-network` with the
`--smart-rollup` option.

#### Staring a Smart-Rollup Sandbox with a Custom Kernel
The following command will start a smart-rollup with the kernel you provide.

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

Mavbox has a few help options to use when testing your smart-rollup kernel.
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

If you have a kernel "set-up" file, Mavbox will pass it to the
`smart-rollup-installer` when preparing the kernel preimage with the option
`--kernel-setup-file=PATH`. The option `--smart-contract=PATH:TYPE` will
originate the smart contract of TYPE at PATH. Both the smart contract and set-up
files can added to the same directory as your kernel file which will be mounted
to the container.

The options `--smart-rollup-node-init-with=FLAG|OPTION=VALUE` and
`--smart-rollup-node-run-with=FLAG|OPTION=VALUE` will allow you to pass
additional options to the mavkit-smart-rollup-node binaries `init` and `run`
command. The example above is equivalent to:

``` default
$ mavkit-smart-rollup-node init --log-kernel-debug
$ mavkit-smart-rollup-node run --log-kernel-debug --log-kernel-debug-file=/tmp/my-debug.log 
```

You can confirm that the smart-rollup-node has been initialized and see relevant
rollup info from the node's config with the `smart_rollup_info` command.

``` default
$ docker exec my-sandbox "$script" smart_rollup_info
{
  "smart_rollup_node_config":  {
  "smart-rollup-address": "sr1KVTPm3NLuetrrPLGYnQrzMpoSmXFsNXwp",
  "smart-rollup-node-operator": {
    "publish": "mv1TjkB9jh2RXyDZgvdDgwC9f93WxCUzimyp",
    "add_messages": "mv1TjkB9jh2RXyDZgvdDgwC9f93WxCUzimyp",
    "cement": "mv1TjkB9jh2RXyDZgvdDgwC9f93WxCUzimyp",
    "refute": "mv1TjkB9jh2RXyDZgvdDgwC9f93WxCUzimyp"
  },
  "rpc-addr": "0.0.0.0",
  "rpc-port": 20002,
  "fee-parameters": {},
  "mode": "operator"
},
}
```

For convenience, the included script contains the function
`inticlient` to add smart contract and smart rollup addresses to the mavkit-client
data directory configured.

``` default
$ docker exec my-sandbox "$script" initclient
Mavryk address added: mv1Hox9jGJg3uSmsv9NTvuK7rMHh25cq44nv
Mavryk address added: mv1NpEEq8FLgc2Yi4wNpEZ3pvc1kUZrp2JWU
Mavryk address added: mv1LkuVrpuEYCjZqTM93ri8aKYNtqFoYeACk
Added contract my-contract: KT19Z5M5z9jBf1ikYABrbrCw3M2QLQLSV1KA
Added smart rollup custom: sr1KVTPm3NLuetrrPLGYnQrzMpoSmXFsNXwp
```
#### Start the EVM Smart-Rollup

Mavbox includes an implementation of the EVM Smart-Rollup (a.k.a. Etherlink) developed by Nomadic Labs. See its documentation [here](https://docs.etherlink.com/get-started/connect-your-wallet-to-etherlink). To start this sandbox Use the `star_evm_smart_rollup` command form the included scripts. 

``` default
$ docker run --rm --detach -p 20000:20000 -p 20002:20002 -p 20004:20004 --name my-sandbox \
        "$image" "$script" start_evm_smart_rollup 
```
The published ports `20000`, `20002`and `20004` are for the `mavkit-node`, `mavkit-smart-rollup-node` and `mavkit-evm-node`, respectively. You can use Ethereum's rpc [api](https://ethereum.org/en/developers/docs/apis/json-rpc/) to interact with the `mavkit-evm-node` at port `20004`. For example, this call returns the Ethereum chain_id:

``` sh
$ curl -s -H "Content-Type: application/json" -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"net_version\",\"params\":[]}" http://localhost:20004
{"jsonrpc":"2.0","result":"123123","id":null}
```

In addition to the EVM smart-rollup, this sandbox will originate two smart-contracts used for depositing tez to an account in the rollup. Use the 'initclient' function in the included scrips to setup the mavkit-client (included in the container). 

``` sh
$ docker exec my-sandbox "$script" initclient
Mavryk address added: mv1Hox9jGJg3uSmsv9NTvuK7rMHh25cq44nv
Mavryk address added: mv1NpEEq8FLgc2Yi4wNpEZ3pvc1kUZrp2JWU
Mavryk address added: mv1LkuVrpuEYCjZqTM93ri8aKYNtqFoYeACk
Added contract evm-bridge: KT1Vq3vBnCNuds6YwjjcJeqBTaeqgTh52oQy
Added contract exchanger: KT1D3VK3BQ2rbpufqwacJU97wgQst7NyuST3
Added smart rollup evm: sr1DRk5qfiziibipQBVYS7PPtt4Abk8k5bny

$ alias mcli='docker exec my-sandbox mavkit-client'

$ mcli list known contracts
exchanger: KT1Ty6UAYMwV4bteh8oEM6XdUvXzvsUuk3fX
evm-bridge: KT1GC5oTZMP6Wi3V4cJq4uia9dEmNyWsmd3U
baker0: mv1LkuVrpuEYCjZqTM93ri8aKYNtqFoYeACk
bob: mv1NpEEq8FLgc2Yi4wNpEZ3pvc1kUZrp2JWU
alice: mv1Hox9jGJg3uSmsv9NTvuK7rMHh25cq44nv

$ mcli list known smart rollups
evm: sr1DRk5qfiziibipQBVYS7PPtt4Abk8k5bny
```

Record the evm smart rollup address. You will use it to transfer tez onto the rollup. Tez can be transferred an Ethereum account address on the rollup via the evm-bridge contract. 

``` sh
$ sr_addr=sr1DRk5qfiziibipQBVYS7PPtt4Abk8k5bny
$ example_ethacc=0x798e0be76b06De09b88534c56EDF7AF339447e02

$ mcli transfer 10 from alice to evm-bridge --entrypoint "deposit" --arg "(Pair \"${sr_addr}\" ${example_ethacc})" --burn-cap 1
Node is bootstrapped.
Estimated gas: 6019.859 units (will add 100 for safety)
Estimated storage: 123 bytes added (will add 20 for safety)
Operation successfully injected in the node.
...
```

Now check the balance of the eth account.

``` sh
$ curl -s -H "Content-Type: application/json" -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$example_ethacc\", \"latest\"]}" http://localhost:20004
{"jsonrpc":"2.0","result":"0x8ac7230489e80000","id":null}

# Convert "result" to decimal. Remove the 'Ox' and uppercase. 
$ echo 'ibase=16; 8AC7230489E80000' | bc
10000000000000000000
```

The Ethereum rpc api uses units of "wei", which isn't very meaningful in this case. Removing 18 zeros will give you 10 tez.

From here you can connect an Ethereum client to the `mavkit-evm-node` at the localhost address and port `20004`. You'll also need the Ethereum chain_id or net_version which we fetch in the example above (123123).

## Build

With Opam ≥ 2.1:

```sh
opam switch create . --deps-only \
     --formula='"ocaml-base-compiler" {>= "4.13" & < "4.14"}'
eval $(opam env)
opam pin add -n mavryk-base58-digest https://gitlab.com/mavryk-network/mavryk-base-58-digest.git
opam install --deps-only --with-test --with-doc \
     ./mavryk-mv1-crypto.opam \
     ./mavbox.opam ./mavbox-cli.opam # Most of this should be already done.
opam install merlin ocamlformat.0.24.1    # For development.
```

Then:

    make

The above builds the `mavbox` library, the `mavbox` command line application
(see `./mavbox --help`) and the tests (in `src/test`).


## MacOSX Users

At runtime, sandboxes usually depend on a couple of linux utilities.

If you are on Mac OS X, you can do `brew install coreutils util-linux`. Then run
the tests with:

```
export PATH="/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/util-linux/bin:$PATH"
```

## Build Of The Docker Image

See `./Dockerfile`, it often requires modifications with each new version of
Mavkit or for new protocols, the version of the Mavkit static binaries (`x86_64`
and `arm64`) is set in `src/scripts/get-mavkit-static-binaries.sh`.

There are 2 images: `-build` (all dependencies) and `-run` (stripped down image
with only runtime requirements).

The `x86_64` images are built by the CI, see the job `docker:images:` in
`./.gitlab-ci.yml`.

To build locally:

```sh
docker build --target build_step -t mavbox-build .
docker build --target run_image -t mavbox-run .
```

Do not forget to test it: `docker run -it "$image" "$script" start`

### Multi-Architecture Image

To build the **released multi-architecture images**, we used to use
[buildx](https://docs.docker.com/buildx/working-with-buildx/) but this does not
work anymore (Qemu cannot handle the build on the foreign architecture). We use
the “manifest method” cf.
[docker.com](https://www.docker.com/blog/multi-arch-build-and-images-the-simple-way/).
We need one host for each architecture (AMD64 and ARM64).

#### On Each Architecture

Setting up Docker (example of AWS-like Ubuntu hosts):

```sh
sudo apt update
sudo apt install docker.io
sudo adduser ubuntu docker
```

(may have to `sudo su ubuntu` to really get _into the group_)

Build and push the image (you may need to `docker login`):

```sh
base=mavrykdynamics/mavbox
tag=20240228-rc
docker build --target run_image -t mavbox-run .
docker tag mavbox-run "$base:$tag-$(uname -p)"
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
newtag=20240228
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

The command `mavbox mini-net [...]` has a dedicated documentation page: [The
`mini-net` Command](./src/doc/mini-net.md).

Documentation regarding `mavbox daemons-upgrade [...]` can be found here: [The
`daemons-upgrade` Command](./src/doc/daemons-upgrade.md).

The API documentation of the Mavbox OCaml library starts here: [Mavbox:
API](https://protocol.mavryk.org/mavbox/lib-index.html).

Blog posts:

- [2019-06-14](https://obsidian.systems/blog/introducing-mavbox-robust-testing-tools-for-tezos-and-its-applications)
- [2021-10-14](https://medium.com/the-aleph/new-mavbox-docker-image-and-some-development-news-f0d5360f01bd)
- [2021-11-29](https://medium.com/the-aleph/mavbox-new-image-user-activated-upgrades-tenderbake-cc7602781879)
- [2022-03-22](https://medium.com/the-aleph/mavbox-protocol-upgrades-3fdf2fae11e1):
  Mavbox: Protocol Upgrades
- [2022-11-30](https://medium.com/the-aleph/mavbox-toru-sandbox-78d7b166e06):
  Mavbox TORU Sandbox




