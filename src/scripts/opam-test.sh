#!/bin/sh

opam pin -n add secp256k1 local-vendor/tezos-master/vendors/ocaml-secp256k1/
opam pin -n add ocplib-resto-directory local-vendor/tezos-master/vendors/ocplib-resto/lib_resto-directory/
opam pin -n add ocplib-resto local-vendor/tezos-master/vendors/ocplib-resto/lib_resto/
opam pin -n add tezos-rpc local-vendor/tezos-master/src/lib_rpc/
opam pin -n add tezos-clic local-vendor/tezos-master/src/lib_clic/
opam pin -n add tezos-micheline local-vendor/tezos-master/src/lib_micheline/
opam pin -n add tezos-event-logging local-vendor/tezos-master/src/lib_event_logging/
opam pin -n add tezos-error-monad local-vendor/tezos-master/src/lib_error_monad/
opam pin -n add tezos-data-encoding local-vendor/tezos-master/src/lib_data_encoding/
opam pin -n add tezos-crypto local-vendor/tezos-master/src/lib_crypto/
opam pin -n add tezos-stdlib local-vendor/tezos-master/src/lib_stdlib/
opam pin -n add tezos-base local-vendor/tezos-master/src/lib_base/
opam pin -n add tezos-stdlib-unix local-vendor/tezos-master/src/lib_stdlib_unix/
opam pin -n add flextesa src/lib/
opam install --yes flextesa
