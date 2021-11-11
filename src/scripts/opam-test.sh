#!/bin/sh

vendor=local-vendor/tezos-master

# We still need a more recent tezos-crypto (API change) and others (stdlib):
opam pin -n add tezos-stdlib "$vendor/src/lib_stdlib/"
opam pin -n add tezos-error-monad "$vendor/src/lib_error_monad/"
opam pin -n add tezos-lwt-result-stdlib "$vendor/src/lib_lwt_result_stdlib/"
opam pin -n add tezos-event-logging "$vendor/src/lib_event_logging/"
opam pin -n add tezos-stdlib-unix "$vendor/src/lib_stdlib_unix/"
# opam pin -n add tezos-clic "$vendor/src/lib_clic/"
opam pin -n add bls12-381 "$vendor/vendors/ocaml-bls12-381/"
opam pin -n add uecc "$vendor/vendors/ocaml-uecc/"
opam pin -n add tezos-crypto "$vendor/src/lib_crypto/"
#opam pin -n add tezos-base "$vendor/src/lib_base/"
opam pin -n add tezos-hacl-glue "$vendor/src/lib_hacl_glue/virtual/"
opam pin -n add tezos-hacl-glue-unix "$vendor/src/lib_hacl_glue/unix/"
#opam pin -n add tezos-rpc-http-server "$vendor/src/lib_rpc_http/"
# opam install --yes ringo hacl-star tezos-lwt-result-stdlib tezos-error-monad tezos-stdlib tezos-event-logging tezos-stdlib-unix tezos-clic tezos-crypto tezos-hacl-glue-unix

# There is seems to be a dependency missing:
opam install --yes ppx_inline_test

# Now the test:
opam pin -n add flextesa src/lib/
opam install --yes flextesa

