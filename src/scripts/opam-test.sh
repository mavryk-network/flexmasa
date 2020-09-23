#!/bin/sh

# Current version of tezos-crypto uses `conf-rust` just for show.
mkdir -p /tmp/bin
echo "#!/bin/sh" > /tmp/bin/cargo
echo "#!/bin/sh" > /tmp/bin/rustc
chmod a+x /tmp/bin/*
export PATH=/tmp/bin:$PATH

vendor=local-vendor/tezos-master

# We still need a more recent tezos-crypto (API change) and others (stdlib):
opam pin -n add tezos-stdlib "$vendor/src/lib_stdlib/"
opam pin -n add tezos-error-monad "$vendor/src/lib_error_monad/"
opam pin -n add tezos-lwt-result-stdlib "$vendor/src/lib_lwt_result_stdlib/"
opam pin -n add tezos-event-logging "$vendor/src/lib_event_logging/"
opam pin -n add tezos-stdlib-unix "$vendor/src/lib_stdlib_unix/"
opam pin -n add tezos-clic "$vendor/src/lib_clic/"
opam pin -n add tezos-crypto "$vendor/src/lib_crypto/"
opam pin -n add tezos-base "$vendor/src/lib_base/"
opam install --yes ringo hacl-star tezos-lwt-result-stdlib tezos-error-monad tezos-stdlib tezos-event-logging tezos-stdlib-unix tezos-clic tezos-crypto
# There is seems to be a dependency missing:
opam install --yes tezos-base

# Now the test:
opam pin -n add flextesa src/lib/
opam install --yes flextesa

