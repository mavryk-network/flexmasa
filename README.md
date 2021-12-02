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

The current _released_ image is `tqtezos/flextesa:2021TODO`
(also available at `registry.gitlab.com/smondet/flextesa:70D070D0-run`):

It is built top of the `flextesa` executable and Octez suite; it also contains
the `*box` scripts to quickly start networks with predefined parameters. For
instance:

```sh
image=tqtezos/flextesa:2021..
image=registry.gitlab.com/smondet/flextesa:8bea4e08-run
script=granabox
docker run --rm --name my-sandbox --detach -p 20000:20000 \
       -e block_time=3 \
       "$image" "$script" start
```

All the available scripts start single-node full-sandboxes (i.e. there is a
baker advancing the blockchain):

- `granabox`: Granada protocol.
- `hangzbox`: Hangzhou protocol.
- `alphabox` (aliased to `tenderbox`): Alpha protocol, the development version
  of the `I` protocol at the time the docker-build was last updated.
    - See also `docker run "$image" tezos-node --version`.

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
You can use any client, including the `tezos-client` inside the docker
container, which happens to be already configured:

```default
$ alias tcli='docker exec my-sandbox tezos-client'
$ tcli get balance for alice
2000000 ꜩ
```

The scripts inherit the [mini-net](./src/doc/mini-net.md)'s support for
user-activated-upgrades (a.k.a. “hard forks”). For instance, this command starts
a Granada sandbox which switches to Hangzhou at level 20:

```default
$ docker run --rm --name my-sandbox --detach -p 20000:20000 \
         -e block_time=2 \
         "$image" granabox start --hard-fork 20:Hangzhou:
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
"PtHangz2aRngywmSRGGvrcTyMbbdpWdpFKuS4uMWxg2RaH9i1qx"
```

Notes:

- The default cycle length in the sandboxes is 8 blocks and switching protocols
  before the end of the first cycle is not supported by Octez.
- The `hangzbox` script can also switch to `Alpha` (e.g.
  `--hard-fork 16:Alpha:`).

These scripts correspond to the tutorial at
<https://assets.tqtezos.com/docs/setup/2-sandbox/> (which is now deprecated but
still relevant).

Don't forget to clean-up your resources when you are done:
`docker kill my-sandbox`.


## Build

With Opam ≥ 2.1:

```sh
opam switch create . --deps-only \
     --formula='"ocaml-base-compiler" {>= "4.13" & < "4.14"}'
eval $(opam env)
opam install --deps-only --with-test --with-doc \
     ./tezai-base58-digest.opam ./tezai-tz1-crypto.opam \
     ./flextesa.opam ./flextesa-cli.opam # Most of this should be already done.
opam install merlin ocamlformat.0.19.0    # For development.
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

## Build Docker Image

See `./Dockerfile`, usually requires modifications with each new version of
Octez or new protocols.

There are 2 images: `-build` (all dependencies) and `-run` (stripped down image
with only runtime requirements).

The images are built by the CI, see the job `docker:images:` in
`./.gitlab-ci.yml`.

To build locally:

```sh
docker build --target build_step -t flextesa-build .
docker build --target run_image -t flextesa-run .
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
