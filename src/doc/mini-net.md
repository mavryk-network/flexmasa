The mini-net Command
====================

Flextesa ships with the `flextesa` command-line application; this document deals
with the `./flextesa mini-net` sub-command (also available in the Tezos
[repository](https://tezos.gitlab.io/developer/flextesa.html) as `tezos-sandbox
mini-net`).

One can use `./flextesa mini-net --help` to see all the available options.

Accessing Tezos Software
------------------------

Flextesa needs to access `octez-node`, `octez-client`, and, depending on the
options, all the “baker deamons.”

An easy way to let flextesa find them is to add them to the `PATH`, for instance
if all the tezos utilities have been build at `/path/to/octez-repo/`:

    $ export PATH=/path/to/octez-repo/:$PATH
    $ flextesa mini  \
               --size 2 --time-between-blocks 10 --number-of-boot 2

If one does not want to, or cannot, use this method, all the executable paths
can be passed with command line options:

    $ flextesa mini  \
               --size 3 --time-between-blocks 8 --number-of-boot 2 \
               --octez-node /path/to/octez-repo/octez-node \
               --octez-client /path/to/octez-repo/octez-client \
               --octez-baker /path/to/octez-repo/octez-baker-alpha \
               --octez-endorser /path/to/octez-repo/octez-endorser-alpha \
               --octez-accuser /path/to/octez-repo/octez-accuser-alpha

The above command starts 3 nodes, activates the protocol `alpha` with a
block-time of 8 seconds (`alpha` is the development protocol of the `master`
branch; it *mimics* the `mainnet` one), and starts baking daemons for 2
bootstrap-baker accounts.

* If you are using the docker image, valid `octez-*` executables are already in
  the `$PATH`.
* The following sections assume you have these figured out (as additional
  arguments or in the `$PATH`).

A Note On Interactivity
-----------------------

Many sandbox setups in Flextesa, once the sandbox is ready, give the user an
interactive command prompt.

You can always type `help` (or `h`) to see available commands, and `quit` (or
`q`) to leave the prompt.

The improve user-experience on normal terminals (i.e. not Emacs …) it is
recommended to wrap the `flextesa` command in command-line edition tool like
`rlfe`, `rlwrap` or `ledit`.

More Examples
-------------

### “Manual” Sandbox and Shell Environment

A *manual* sandbox, as opposed to a *full* one, is a sandbox without baking
daemons, the client needs to manually bake blocks on demand (this is very useful
to make faster and more reproducible tests for instance).


    $ flextesa mini  \
               --size 1 --number-of-boot 1 --base-port 4000 \
               --octez-node /path/to/octez-repo/octez-node \
               --octez-client /path/to/octez-repo/octez-client \
               --no-baking

By typing `help` we see we can use the command `bake` to make new blocks:

```
  Available commands:
    * {q|quit}: Quit this prompt and continue.
...
    * {bake}: Manually bake a block (with C-N000).
...
```

One can also use `octez-client -E http://localhost:4000 bake for ...` from
outside the sandbox.

Luckily such a client has already been configured by Flextesa; type `help-env`
on the prompt:

```
Flextesa: Please enter command:
  help-env
Flextesa:
  Shell Environment
    * A loadable shell environment is available at
    `/tmp/mininet-test/shell.env`.
    * It contains 1 POSIX-shell aliases (compatible with `bash`, etc.).

    Example:

        . /tmp/mininet-test/shell.env
        c0 list known addresses
        c0 rpc get /chains/main/blocks/head/metadata
```

And indeed we can use such a client to bake a new block:

```
 $ c0 list known addresses
bootacc-0: tz1YPSCGWXwBdTncK2aCctSZAXWvGsGwVJqU (unencrypted sk known)
dictator-default: tz1aYQcaXmowUu59gAgMGdiX6ARR7gdmikZk (unencrypted sk known)

 $ c0 bake for bootacc-0
Feb 12 10:30:42 - alpha.baking.forge: found 0 valid operations (0 refused) for timestamp 2020-02-12T15:30:42-00:00 (fitness 01::0000000000000002)
Injected block BLehBRAoyFAB
```

When running “manual” sandboxes the option `--timestamp-delay` is also useful
(e.g. `--timestamp-delay=-3600`), it allows the user to bake faster than the
expected time between blocks.

### Running Another Protocol And History Modes

The
[`./src/scripts/tutorial-box.sh`](https://gitlab.com/tezos/flextesa/blob/master/src/scripts/tutorial-box.sh)
uses protocol-specific binaries (present in the default docker image) to run
non-interactive sandboxes with the “real” Babylon or Carthage protocols.

For instance:

    $ flextesa mini-net \
               --root /tmp/mini-box \
               --size 1 \
               --set-history-mode N000:archive
               --number-of-bootstrap-accounts 1 \
               --time-b 5 \
               --until-level 2_000_000 \
               --octez-baker octez-baker-005-PsBabyM1 \
               --octez-endor octez-endorser-005-PsBabyM1 \
               --octez-accus octez-accuser-005-PsBabyM1 \
               --protocol-kind Babylon \
               --protocol-hash PsBabyM1eUXZseaJdmXFApDSBqj8YBfwELoxZHHW77EMcAbbwAS

runs a 1-node sandbox with 1 bootstrap baker, running Babylon (the same as
mainnet) but with a time-between-blocks of 5 seconds.

Moreover, instead of becoming interactive, the sandbox will run for 2×10⁶ blocks
and the node will be an `archive` node (see documentation on [history
modes](https://tezos.gitlab.io/user/history_modes.html)).

### Adding Custom Bootstrap Accounts

**Note on Oxford** Bootstrap accounts in Oxford protocol will start out
automatically staking. This stake is frozen and will not show up in the account
balance until un-staked. The frozen balance is calculated by the protocol with a
minimum of 6,000 ꜩ.

The option `--add-bootstrap-account` adds arbitrary key-pairs as
bootstrap-accounts with a given amount of μꜩ; the option `--no-daemons-for`
prevents the sandbox from baking with a given bootstrap-account.

More over flextesa provides a command to generate **deterministic** key-pairs
from any string.

    $ alice=$(./flextesa key-of-name alice)
    $ flextesa mini  \
               --size 2 --time-between-blocks 10 --number-of-boot 2 \
               --add-bootstrap-account "$alice@2_000_000_000_000 \
               --no-daemons-for=alice

This sandbox has one more account with 2 million ꜩ, that account is not used for
baking. See the output of the key generation:

```
 $ flextesa key-of-name alice
alice,edpkvGfYw3LyB1UcCahKQk4rF2tvbMUk8GFiTuMjL75uGXrpvKXhjn,tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb,unencrypted:edsk3QoqBuvdamxouPhin7swCvkQNgq4jP5KZPbwWNnwdZpSpJiEbq
```

One can use simply `octez-client import secret key the-alice
unencrypted:edsk3QoqBuvdamxouPhin7swCvkQNgq4jP5KZPbwWNnwdZpSpJiEbq` to interact
with this account.

### Choosing a (Vanity) Chain-id

With the default values the chain id for the sandbox is `NetXKMbjQL2SBox` (cf.
RPC `/chains/main/chain_id`), but one may want to use a different one.

The chain-id is computed from the hash of the Genesis block, which can be forced
with the `--genesis-block-hash`; and one can brute-force a block-hash to
generate vanity chain-id with the `flextesa vanity-chain-id` command.

```
 $ flextesa vanity-chain-id Bob  \
            --attempts 1_000_000 --first --seed my-seed-string

Flextesa.vanity-chain-id:  Looking for "Bob"
Flextesa.vanity-chain-id:
  Results:
    * Seed: "my-seed-string140396"
      → block: "BMKZs8QDZ9NmVJqvTeVimXCtKmRiYoASzx4N3gMPv6yqGiuTw2q"
      → chain-id: "NetXLGHj52FuBob"
```

One can use it like this:

    $ flextesa mini  \
               --size 2 --time-between-blocks 10 --number-of-boot 2 \
               --genesis BMKZs8QDZ9NmVJqvTeVimXCtKmRiYoASzx4N3gMPv6yqGiuTw2q

And check interactively that `c0 rpc get /chains/main/chain_id` returns
`"NetXLGHj52FuBob"`.

### Root Path & Stopping/Restarting Sandboxes

All the sandboxes keep all their data within a “root path” which can be set with
the `--root-path` option.

By default the `mini-net` erases that directory at startup but one can try to
restart a sandbox from the state it was when it was shut down with the option
`--keep-root`.

Restarting sandboxes is *not an exact science* because it is not how a
blockchain is supposed to work, sometimes bakers and nodes fail while trying to
catch-up, it is better to use “small” networks:

    $ flextesa mini --root /tmp/longer-running-mini-net \
               --size 1 --time-between-blocks 2 --number-of-boot 1 \
               --keep-root

Stopping the sandbox with `quit`, and restarting with the same command some time
later usually works.

## Smart Optimistic Rollups

Flextesa automates several steps involved in originating a [smart optimistic
rollup](https://tezos.gitlab.io/alpha/smart_rollups.html). For a quick start,
the command `flextesa mini-network --smart-rollup` will start the mini-network
sandbox with a default transaction smart rollup using the
[tx-kernel](https://gitlab.com/tezos/kernel). A smart-rollup-node in
**operator** mode will begin progressing the rollup. This assumes the octez
binaries are in your `$PATH`. Otherwise, you'll need to pass the option
`--octez-smart-rollup-node-binary`.

You can use `/src/scripts/get-tx-client.sh` to get the tx-client binaries. The
tx-client can be used to interact with the tx-rollup. See its
[documentation](https://gitlab.com/emturner/tx-client).

In order to start a smart rollup sandbox with a custom kernel use the
`--custom-kernel` option.

```
$ flextesa mini-network \
            --protocol-kind Mumbai \
            --smart-rollup \
            --custom-kernel wasm_2_0_0:bytes:path/to/my-kernel.wasm
            --smart-contract path/to/l1_contract.tz
            --octez-smart-rollup-node /binaries/octez-smart-rollup-node-PtMumbai
```

The arguments passed to `--custom-kernel`, `wasm_2_0_0` and `bytes` are the
`KIND` and `TYPE` of the rollup. Use values appropriate for your kernel. The
final argument is the path to the .wasm file for your kernel.

Most kernels will be too large for an L1 operation. When this is the case,
Flextesa will use the
[smart-rollup-installer](https://crates.io/crates/tezos-smart-rollup-installer)
to create an installer kernel and originate the rollup.

The `--smart-contract PATH` option simply originates the layer one smart
contract at `PATH`.

There are two additional options that can be used with the smart rollup. With
`--smart-rollup-start-level LEVEL` Flextesa will wait until `LEVEL` to originate
the rollup. The default is level 5. `--smart-rollup-node-mode MODE` will set the
[mode](https://tezos.gitlab.io/alpha/smart_rollups.html#deploying-a-rollup-node)
of the smart-rollup-node initialized by Flextesa.

Once the rollup is originated, Flextesa will display the rollup address and
rpc_port for the rollup node. This information can also be found in the rollup
node's data directory at `.../data-dir/config.json`.

