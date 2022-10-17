FROM ocaml/opam:alpine-3.15-ocaml-4.12 as build_step
#ENV DEBIAN_FRONTEND=noninteractive
RUN sudo cp /usr/bin/opam-2.1 /usr/bin/opam
RUN sudo apk update
ADD  --chown=opam:opam . ./
RUN opam pin add -n tezai-base58-digest https://gitlab.com/oxheadalpha/tezai-base58-digest.git
RUN opam install --with-test --deps-only ./tezai-tz1-crypto.opam ./flextesa.opam
RUN opam exec -- dune build --profile=release src/app/main.exe
RUN sudo cp _build/default/src/app/main.exe /usr/bin/flextesa
RUN sudo sh src/scripts/get-octez-static-binaries.sh /usr/bin/
#WORKDIR /usr/bin
RUN sudo sh src/scripts/get-zcash-params.sh /usr/share/zcash-params
FROM alpine:3.15 as run_image
RUN apk update
RUN apk add curl libev libffi unzip gmp rlwrap
WORKDIR /usr/bin
COPY --from=0 /usr/bin/tezos-accuser-013-PtJakart .
COPY --from=0 /usr/bin/tezos-accuser-014-PtKathma .
COPY --from=0 /usr/bin/tezos-accuser-alpha .
COPY --from=0 /usr/bin/tezos-admin-client .
COPY --from=0 /usr/bin/tezos-baker-013-PtJakart .
COPY --from=0 /usr/bin/tezos-baker-014-PtKathma .
COPY --from=0 /usr/bin/tezos-baker-alpha .
COPY --from=0 /usr/bin/tezos-client .
COPY --from=0 /usr/bin/tezos-codec .
COPY --from=0 /usr/bin/tezos-embedded-protocol-packer .
#COPY --from=0 /usr/bin/tezos-init-sandboxed-client.sh .
COPY --from=0 /usr/bin/tezos-node .
#COPY --from=0 /usr/bin/tezos-sandboxed-node.sh .
#COPY --from=0 /usr/bin/tezos-signer .
COPY --from=0 /usr/bin/tezos-validator .
COPY --from=0 /usr/bin/flextesa .
COPY --from=0 /usr/share/zcash-params/* /usr/share/zcash-params/
COPY --from=0 /usr/bin/tezos-tx-rollup-client-013-PtJakart .
COPY --from=0 /usr/bin/tezos-tx-rollup-client-014-PtKathma .
COPY --from=0 /usr/bin/tezos-tx-rollup-client-alpha .
COPY --from=0 /usr/bin/tezos-tx-rollup-node-013-PtJakart .
COPY --from=0 /usr/bin/tezos-tx-rollup-node-014-PtKathma .
COPY --from=0 /usr/bin/tezos-tx-rollup-node-alpha .
RUN sh -c 'printf "#!/bin/sh\nsleep 1\nrlwrap flextesa \"\\\$@\"\n" > /usr/bin/flextesarl'
RUN chmod a+rx /usr/bin/flextesarl
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/jakartabox
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/kathmandubox
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/alphabox
RUN chmod a+rx /usr/bin/jakartabox
RUN chmod a+rx /usr/bin/kathmandubox
RUN chmod a+rx /usr/bin/alphabox
RUN /usr/bin/alphabox initclient
ENV TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=Y

