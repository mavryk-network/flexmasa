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

Let's use this version:

```
export flextesa_image=registry.gitlab.com/tezos/flextesa:7dd2d93a-run
```

in the container `flextesarl` is `flextesa` + `rlwrap` (while bypassing a docker
problem):

```
docker run -it --rm "$flextesa_image" flextesarl mini-net --size 2
```

that's it the sandbox with 2 nodes starts and drops you in the interactive
prompt: type `help` (or `h`) to list available commands, `al` to check the
current level, `m` to see the metadata of the head block, etc.

More Documentation
------------------

The API documentation of the Flextesa OCaml library starts here:
[Flextesa: API](https://tezos.gitlab.io/flextesa/lib-index.html).

Some documentation, including many examples, is part of the `tezos/tezos`
repository:
[Flexible Network Sandboxes](https://tezos.gitlab.io/developer/flextesa.html)
(it uses the `tezos-sandbox` executable which is implemented there).

TQ Tezos' [“assets documentation”](https://assets.tqtezos.com)
shows how to quickly set up a
[Babylon docker sandbox](https://assets.tqtezos.com/sandbox-quickstart)
(uses the docker images from this repository).

