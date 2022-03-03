The Daemons Upgrade Command
===========================

Flextesa ships with the `flextesa` command-line application. This document deals
with the `./flextesa daemons-upgrade` sub-command.

One can use `./flextesa daemons-upgrade --help` to see all the available options.

Accessing Tezos Software
-------------------------------------------------------------------------------

Flexstesa needs access to the Tezos software. In particular, the
`daemons-upgrade` command requires the baker daemons, (`tezo-baker-011-PtHangz2`,
`tezos-baker-012-psithaca`, `tezos-baker-alpha`) depending on which protocol
upgrade is being tested.

An easy way to let Flextesa find them is to add them to the `PATH`. For instance,
if all the Tezos utilities have been build at `/path/to/tezos-repo/`:

```
    $ export PATH=/path/to/tezos-repo/:$PATH
    $ flextesa daemons-upgrade \
        --protocol-kind Hangzhou \
        --next-protocol-kind Ithaca \
        --second-baker tezos-baker-012-Psithaca
```

Note: Flextesa will infer the executables needed based on the value passed to
`--protocol-kind`. However, the option `--second-baker` is required to provide
the baker executable for the next (upgrade) protocol.

As an alternative to adding the Tezos software to `PATH`, all  the executable
paths can be passed with command line options:

```
    $ flextesa daemons-upgrade  \
        --protocol-kind Hangzhou --next-protocol-kind Ithaca \
        --tezos-node /path/to/tezos-repo/tezos-node \
        --tezos-client /path/to/tezos-repo/tezos-client \
        --first-accuser /path/to/tezos-repo/tezos-accuser-011-PtHangz2 \
        --first-endorser /path/to/tezos-repo/tezos-endorser-011-PtHangz2 \
        --first-baker /path/to/tezos-repo/tezos-baker-011-PtHangz2 \
        --second-accuser /path/to/tezos-repo/tezos-accuser-011-PtHangz2 \
        --second-endorser /path/to/tezos-repo/tezos-endorser-011-PtHangz2 \
        --second-baker /path/to/tezos-repo/tezos-baker-012-Psithaca
```

Both examples above, activate the protocol `Hangzhou`, and propose the `Ithaca`
upgrade. The sandbox network will do a full voting round followed by a protocol
change. Finally, Flexseta will kill all processes once the daemon-upgrade test
is complete.

* If you are using the docker image, valid `tezos-*` executables are already in
  the `$PATH`.

### Example:

```
    $ flextesa daemons-upgrade  \
        --protocol-kind Ithaca \
        --size 2 \
        --number-of-bootstrap-accounts 2 \
        --time-between-blocks 5 \
        --next-protocol-kind Alpha \
        --second-baker tezos-baker-alpha \
        --blocks-per-voting-period 14 \
        --extra-dummy-proposals-batch-size 2 \
        --extra-dummy-proposals-batch-levels 3,5 \
        --with-timestamp
```

The above command activates the `Ithaca` protocol, starts 2 nodes and 2
bootstrap accounts; with a blocktime of 5 seconds. The test will propose the
protocol `Alpha` upgrade. The voting periods are set to 14 blocks. In addition,
two dummy protocols will be proposed at levels 3 and 5 within the proposal
period. Finally, a timestamp will be displayed with each message.

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
        --protocol-kind Hangzhou --next-protocol Ithaca \
        --second-baker tezos-baker-012-Psithaca \
        --interactive true
```

With the option `--interactive true`, Flextesa will pause twice during the test;
once on the `Hangzhou` network and once after the upgrade to `Ithaca`.  This
will allow you to interact with the network at different stages. Type `help`
(or `h`) to see available commands, and `quit` (or `q`) to unpause and continue
the upgrade.

Similarly, the option `--pause-at-end` will allow you to interact with the
network before Flextesa kills all processes and quits.
