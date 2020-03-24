Changelog
=========

## WIP

* Add a *changelog:* `CHANGES.md`.

## `flextesa-20200324`

At `f24ebaf47e14678493736fa0969dfcbdf7e4a505`:

* Improve *Carthage* support: 
    * Binaries in and `carthagebox` script in docker image.
* Add/improve interactive commands:
    * `mp` for a mempool description.
    * `l` for a more readable summary of the current level metadata.
* Improve network start-up: wait for all nodes to reach level 1 (`bootstrapped`
  not enough any more, nodes seem to take longer to propagate the activation
  bloc).
* Switch to OCaml 4.09.1 by default (following the Tezos mothership).
* Improve the `<protocol>box` scripts (incl. “time-between-blocks”
  configurability).
* Make chain-id of the mini-net sandboxes configurable.
    * Use `NetXKMbjQL2SBox` as default chain-id.
    * Add the `--genesis-block-hash` option.
    * Add the `vanity-chain-id` sub-command (with `--machine-readable` option).
* Make `--keep-root` work for the mini-net (“restartable” sandboxes).
* Improve documentation.


## `flextesa-20200102`

First versioned release.
