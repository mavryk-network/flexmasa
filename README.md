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

The current _released_ image is `oxheadalpha/flextesa:20221123` (also available
as `oxheadalpha/flextesa:latest`):

It is built top of the `flextesa` executable and Octez suite, for 2
architectures: `linux/amd64` and `linux/arm64/v8` (tested on Apple Silicon); it
also contains the `*box` scripts to quickly start networks with predefined
parameters. For instance:

```sh
image=oxheadalpha/flextesa:latest
script=kathmandubox
docker run --rm --name my-sandbox --detach -p 20000:20000 \
       -e block_time=3 \
       "$image" "$script" start
```

All the available scripts start single-node full-sandboxes (i.e. there is a
baker advancing the blockchain):

- `kathmandubox`: Kathmandu protocol.
- `limabox`: Lima protocol.
- `alphabox`: Alpha protocol, the development version of the `M` protocol at the
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

You can always stop the sandbox, and clean-up your resources with: `docker kill
my-sandbox`.

### User-Activated-Upgrades

The scripts inherit the [mini-net](./src/doc/mini-net.md)'s support for
user-activated-upgrades (a.k.a. “hard forks”). For instance, this command starts
a Kathmandu sandbox which switches to Lima at level 20:

```default
$ docker run --rm --name my-sandbox --detach -p 20000:20000 \
         -e block_time=2 \
         "$image" kathmandubox start --hard-fork 20:Lima:
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
"PtLimaPtLMwfNinJi9rCfDPWea8dFgTZ1MeJ9f1m2SRic6ayiwW"
```

Notes:

- The default cycle length in the sandboxes is 8 blocks and switching protocols
  before the end of the first cycle is not supported by Octez.
- The `limabox` script can also switch to `Alpha` (e.g. `--hard-fork
  16:Alpha:`).

### Full Governance Upgrade

The `start_upgrade` command is included with the docker image.

This implementation of `src/scripts/tutorial-box.sh` is a call to `flextesa
daemons-upgrade` (see its general
[daemons-upgrade](./src/doc/daemons-upgrade.md)).

``` default
$ docker run --rm --name my-sandbox -p 20000:20000 --detach \
         -e block_time=2 \
         "$image" kathmandubox start_upgrade
```

With `start_upgrade` the sandbox network will do a full voting round followed by
a protocol change. The `kathmandubox` script will start with the `Kathmandu`
protocol and upgrade to `Lima`; the `limabox` upgrades to to `Alpha`.

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
         "$image" kathmandubox start_upgrade
```

The above command will result in 5 total proposals and upgrade to the Alpha
proposal. As of the `Lima` protocol, the `extra_dummy_proposals_batch_size`
can't exceed the `number_of_bootstrap_accounts` or the operations will fail with
too many `manager_operations_per_block`.

The default values are:

- `blocks_per_voting_period` = 16
- `extra_dummy_proposals_batch_size` = 2
- `extra_dummy_proposals_batch_level` = 3,5
- `number_of_bootstrap_accounts` = 4

Note: As with the `start` command `start_upgrade` comes with the Alice and Bob
accounts by default.

### Transaction Optimistic Rollups

The `start_toru` command included in the scripts is and implementation of the
`flextesa mini-network` with the addition of the option ` --tx-rollup
10:torubox`.

``` default
$ docker run --rm --name my-sandbox --detach -p 20000:20000 \
       "$image" "$script" start_toru
```

After starting up the mini-network, Flextesa will originate a transaction
optimistic rollup called `tourbox` at bock level `10` and start a transaction
rollup operator node. Like the scripts above, the Alice and Bob account will be
included by default.

Before you can interact with the transaction rollup, you will need to retrieve
some important information with the following command.

``` default
$ docker exec my-sandbox ${script} toru_info
{
  "data_dir": "/tmp/mini-box/tx-rollup-torubox/torubox-operator-node-000/data-dir",
  "rollup_id": "txr1arPn95HNJ2JPxFL1q51LGgk4KeR4v36p8",
  "rpc_port": "0.0.0.0:20002",
  "mode": "operator",
  "signers": {
    "operator": "tz1db9qaMMNoQPAATe2D3kafKzWWNuMhnmbT",
    "submit_batch": "tz1YVgxuvoqc2DxLjMcmgcpgnWXn6wiJNf5E",
    "finalize_commitment": "tz1WbzTV5WrHBbfbc8Bw55xaQWLjNvfcBKp4",
    "remove_commitment": "tz1ihyGvQHQu1F6TVMqKJdPtw2BHqMcDotsT",
    "rejection": "tz1gDMHL96KSohLp2H5RPFxAM7wATD7zffRV",
    "dispatch_withdrawals": "tz1LuLiAjZs2sFgivjsuLiuB8nJA48pVfcQc"
  },
  "allow_deposit": true
}
[
  {
    "name": "torubox-deposit-contract",
    "value": "KT1NjJEFRjAugzPwAkEccTAq3v2SYoScyGnL"
  }
]
```

For the next few examples we will record the `rollup_id`, `rpc_addr` and the
`KT1` address for the `torubox-deposit-contract`. (We continue with `tcli` alias
created above.)

``` default
$ rollup_id=txr1arPn95HNJ2JPxFL1q51LGgk4KeR4v36p8
$ rpc_port=20002
$ contract=KT1NjJEFRjAugzPwAkEccTAq3v2SYoScyGnL
```

Next create a `tz4` transaction rollup address and transfer tickets to that
address on the rollup via the `torubox-deposit-contract`:

``` default
$ tcli bls gen keys rollup_bob
$ tcli bls show address rollup_bob
Hash: tz4EimhLzauGZjt6ebLDzbD9Dfuk9vwj7HUz
Public Key: BLpk1x8Eu1D5DWnop7osZtDx8kkBgG83tFiNcyBKkFatUg1wKpVbmjY2QqJehfju1t7YydXidXhF

$ bobs_tz4=tz4EimhLzauGZjt6ebLDzbD9Dfuk9vwj7HUz

$ tcli transfer 0 from alice to "$contract" \
        --arg "(Pair \"my_tickts\" 100 \"${bobs_tz4}\" \"${rollup_id}\")" \
        --burn-cap 1
```

The above argument passed to the contract's default entrypoint will send `100`
tickets containing the string `"my_tickets"` to rollup_bob's address on the
TORU. A successful transfer will produces a long out put. For this example, we
are interested in the ticket.

e.g. `Ticket hash: exprtp67k3xjvBWX4jBV4skJFNDYVp4XKJKujG5vs7SvkF9h9FSxtP`

Use the ticket hash to check the balance of the roll_bob with the
tx-rollup-client. As with the octez-client, you can use the rollup-client
configured inside of the docker container. For example:

``` default
$ ticket_hash=exprtp67k3xjvBWX4jBV4skJFNDYVp4XKJKujG5vs7SvkF9h9FSxtP
$ alias torucli='docker exec my-sandbox tezos-tx-rollup-client-014-PtKathma -E http://localhost:${rpc_port}'

$ torucli get balance for rollup_bob of "$ticket_hash"
100
```

Note that the transaction rollup client should use the RPC address of the
transaction rollup node.

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

Do not forget to test it: `docker run -it "$image" limabox start`

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

When ready for the release, repeat the theses steps swapping the manifest "$tag" each time. Once sans "-rc" and again for "latest".

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

Some documentation, including many examples, is part of the `tezos/tezos`
repository: [Flexible Network
Sandboxes](https://tezos.gitlab.io/developer/flextesa.html) (it uses the
`tezos-sandbox` executable which is implemented there).

Blog posts:

- [2019-06-14](https://obsidian.systems/blog/introducing-flextesa-robust-testing-tools-for-tezos-and-its-applications)
- [2021-10-14](https://medium.com/the-aleph/new-flextesa-docker-image-and-some-development-news-f0d5360f01bd)
- [2021-11-29](https://medium.com/the-aleph/flextesa-new-image-user-activated-upgrades-tenderbake-cc7602781879)

TQ Tezos' [Digital Assets on Tezos](https://assets.tqtezos.com) documentation
shows how to quickly set up a [docker
sandbox](https://assets.tqtezos.com/setup/2-sandbox) (uses the docker images
from this repository).
