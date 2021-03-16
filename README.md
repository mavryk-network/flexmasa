Flextesa: Flexible Tezos Sandboxes
==================================

This repository contains the Flextesa library used in
[tezos/tezos](https://gitlab.com/tezos/tezos) to build the `tezos-sandbox`
[tests](https://tezos.gitlab.io/developer/flextesa.html), as well as some extra
testing utilities, such as the `flextesa` application, which may be useful to
the greater community (e.g. to test third party tools against fully functional
Tezos sandboxes).


<!--TOC-->


Build
-----

You need, Tezos' libraries (with `proto_alpha`) opam-installed or locally
vendored:

    make vendors

Then:

    make

The above builds the `flextesa` and `michokit` libraries, the `flextesa` command
line application (see `./flextesa --help`) and the tests (in `src/test`).

One can easily create an opam-switch which should just work with the above:

    export OPAM_SWITCH="flextesa-switch"
    opam switch import src/tezos-master.opam-switch
    opam exec -- bash local-vendor/tezos-master/scripts/install_build_deps.rust.sh

(where `<name>` is preferably a fresh name).


MacOSX Users
------------

At runtime, sandboxes usually depend on a couple of linux utilities.

If you are on Mac OS X, you can do `brew install coreutils util-linux`. Then run
the tests with:

```
export PATH="/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/util-linux/bin:$PATH"
```

With Docker
-----------

See <https://assets.tqtezos.com/docs/setup/2-sandbox/>

More Documentation
------------------

The command `flextesa mini-net [...]` has a dedicated documentation
page: [The `mini-net` Command](./src/doc/mini-net.md).

The API documentation of the Flextesa OCaml library starts here:
[Flextesa: API](https://tezos.gitlab.io/flextesa/lib-index.html).

Some documentation, including many examples, is part of the `tezos/tezos`
repository:
[Flexible Network Sandboxes](https://tezos.gitlab.io/developer/flextesa.html)
(it uses the `tezos-sandbox` executable which is implemented there).

TQ Tezos' [Digital Assets on Tezos](https://assets.tqtezos.com)
documentation shows how to quickly set up a
[Babylon docker sandbox](https://assets.tqtezos.com/setup/2-sandbox)
(uses the docker images from this repository).
