The Daemons Upgrade Command
===========================

Flextesa ships with the `flextesa` command-line application. This document deals
with the `./flextesa daemons-upgrade` sub-command.

One can use `./flextesa daemons-upgrade --help` to see all the available options.

Accessing Tezos Software
-------------------------------------------------------------------------------

Flexstesa needs access to the Tezos software. In particular, the
`daemons-upgrade` command requires the baker daemons, (`octez-baker-PtKathma`,
`octez-baker-PtLimaPt`, `octez-baker-alpha`) depending on which protocol
upgrade is being tested.

An easy way to let Flextesa find them is to add them to the `PATH`. For instance,
if all the Tezos utilities have been build at `/path/to/octez-repo/`:

```
    $ export PATH=/path/to/octez-repo/:$PATH
    $ flextesa daemons-upgrade \
        --protocol-kind Kathmandu \
        --next-protocol-kind Lima \
        --second-baker octez-baker-PtLimaPt
```

Note: Flextesa will infer the executables needed based on the value passed to
`--protocol-kind`. However, the option `--second-baker` is required to provide
the baker executable for the next (upgrade) protocol.

As an alternative to adding the Tezos software to `PATH`, all  the executable
paths can be passed with command line options:

```
    $ flextesa daemons-upgrade  \
        --protocol-kind Kathmandu --next-protocol-kind Lima \
        --octez-node /path/to/octez-repo/octez-node \
        --octez-client /path/to/octez-repo/octez-client \
        --first-accuser /path/to/octez-repo/octez-accuser-PtKathma \
        --first-endorser /path/to/octez-repo/octez-endorser-PtKathma \
        --first-baker /path/to/octez-repo/octez-baker-PtKathma \
        --second-accuser /path/to/octez-repo/octez-accuser-PtKathma \
        --second-endorser /path/to/octez-repo/octez-endorser-PtKathma \
        --second-baker /path/to/octez-repo/octez-baker-PtLimaPt
```

Both examples above, activate the protocol `Kathmandu`, and propose the `Lima`
upgrade. The sandbox network will do a full voting round followed by a protocol
change. Finally, Flextesa will kill all processes once the daemon-upgrade test
is complete.

* If you are using the docker image, valid `octez-*` executables are already in
  the `$PATH`.

### Example:

```
    $ flextesa daemons-upgrade  \
        --protocol-kind Lima \
        --size 2 \
        --number-of-bootstrap-accounts 2 \
        --until-level 2_000_000 \
        --time-between-blocks 5 \
        --next-protocol-kind Alpha \
        --second-baker octez-baker-alpha \
        --blocks-per-voting-period 14 \
        --extra-dummy-proposals-batch-size 2 \
        --extra-dummy-proposals-batch-levels 3,5 \
        --with-timestamp
```

The above command activates the `Lima` protocol, starts 2 nodes and 2
bootstrap accounts. The sandbox will run for 2×10⁶ blocks with a blocktime of 5
seconds before killing all processes.

The test will propose the protocol `Alpha` upgrade. Each voting period (there
are five) will last 14 blocks. In addition, two batches of two dummy protocols
will be proposed at levels 3 and 5 within the proposal voting (the first)
period. Finally, a timestamp will be displayed with each message.

As of the `Lima` protocol, the `extra_dummy_proposals_batch_size` can't exceed
the `number_of_bootstrap_accounts` or the operations will fail with too many
`manager_operations_per_block`.

* The `daemons-upgrade` command shares many options with the `mini-network` command
(see it's [documentation](./src/doc/mini-net.md)).

Test Variants
-------------------------------------------------------------------------------

There are two variations of the test set with the `--test-variant` option:

- `--test-variant full-upgrade` will go through the voting phases and complete
  the protocol change (this is the default variant).
- `--test-variant nay-for-promotion` will complete all of the voting phases with
  "nay" votes winning the final phase.

Interactivity
-------------------------------------------------------------------------------

```
    $ flextesa daemons-upgrade \
        --protocol-kind Lima --next-protocol Alpha \
        --second-baker octez-baker-PtLimaPt \
        --interactive true
```

With the option `--interactive true`, Flextesa will pause twice during the test;
once on the `Lima` network and once after the upgrade to `Alpha`.  This
will allow you to interact with the network at different stages. Type `help`
(or `h`) to see available commands, and `quit` (or `q`) to unpause and continue
the upgrade.

Similarly, the option `--pause-at-end` will allow you to interact with the
network before Flextesa kills all processes and quits.

If one runs the `daemons-upgrade` interactively with the `--until-level` option,
Flextesa will do the second (or final) pause after reaching the level set by the
user.

For example:
```
    $ flextesa daemons-upgrade \
        --protocol-kind Lima --next-protocol Alpha \
        --second-baker octez-baker-aphla \
        --pause-at-end true \
        --until-level 200
```

The above command will start the `Lima` network, do the upgrade to `Alpha`
protocol, continue running until block 200, then pause once before finally
killing all processes.
