Flextesa: Flexible Tezos Sandboxes
==================================

Build
-----

You need, Tezos' libraries (with `proto_alpha`) opam-installed or locally
vendored:

    make vendors

Then:

    make

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


