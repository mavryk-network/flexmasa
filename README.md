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

The current _released_ image is `tqtezos/flextesa:20211025`, on top of the
`flextesa` executable and Octez suite, it has the `*box` scripts to quickly
start networks:

For instance:

```sh
image=tqtezos/flextesa:20211025
docker run --rm --name my-sandbox --detach -p 20000:20000 \
       "$image" granabox start
```

of for Hangzhou:


```sh
docker run --rm --name my-sandbox --detach -p 20000:20000 \
       "$image" hangzbox start
```

See also the account available by default:

```sh
 $ docker exec my-sandbox granabox info
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

These scripts correspond to the tutorial at
<https://assets.tqtezos.com/docs/setup/2-sandbox/> (now deprecated but still
relevant).

Don't forget to clean-up your resources (`docker kill my-sandbox`).


## Build

You need, Tezos' libraries (with `proto_alpha`) opam-installed or locally
vendored:

    make vendors

Then:

    make

The above builds the `flextesa` library, the `flextesa` command line application
(see `./flextesa --help`) and the tests (in `src/test`).

One can easily create an opam-switch which should just work with the above:

    opam switch create . 4.12.0
    opam switch import src/tezos-master.opam-switch
    opam exec -- bash local-vendor/tezos-master/scripts/install_build_deps.rust.sh

(where `<name>` is preferably a fresh name).


## MacOSX Users

At runtime, sandboxes usually depend on a couple of linux utilities.

If you are on Mac OS X, you can do `brew install coreutils util-linux`. Then run
the tests with:

```
export PATH="/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/util-linux/bin:$PATH"
```

## Build Docker Image

See `docker/Dockerfile`, usually requires modifications with each new version of
Octez or new protocol (for now, it clones a specific branch of Flextesa):

```sh
image=tqtezos/flextesa:20211005
# Make the “build” image
docker build --target build_step -t flextesa-build .
docker tag flextesa-build "${image}-build"
docker push "${image}-build"
# Tag and push (optional, requires access rights):
docker build --target run_image -t flextesa-run .
docker tag flextesa-local "$image"
docker push "$image"
```

Do not forget to test it:
`docker run -it "$image" hangzbox start`

## More Documentation

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
[docker sandbox](https://assets.tqtezos.com/setup/2-sandbox)
(uses the docker images from this repository).
