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
RUN apk add curl libev libffi unzip gmp rlwrap jq
WORKDIR /usr/bin
COPY --from=0 /usr/bin/octez-accuser-PtMumbai .
COPY --from=0 /usr/bin/octez-accuser-PtNairob .
COPY --from=0 /usr/bin/octez-accuser-alpha .
COPY --from=0 /usr/bin/octez-admin-client .
COPY --from=0 /usr/bin/octez-baker-PtMumbai .
COPY --from=0 /usr/bin/octez-baker-PtNairob .
COPY --from=0 /usr/bin/octez-baker-alpha .
COPY --from=0 /usr/bin/octez-client .
COPY --from=0 /usr/bin/octez-codec .
COPY --from=0 /usr/bin/octez-dac-node .
COPY --from=0 /usr/bin/octez-dal-node .
COPY --from=0 /usr/bin/octez-node .
COPY --from=0 /usr/bin/octez-proxy-server .
COPY --from=0 /usr/bin/octez-signer .
COPY --from=0 /usr/bin/octez-smart-rollup-client-PtMumbai .
COPY --from=0 /usr/bin/octez-smart-rollup-client-PtNairob .
COPY --from=0 /usr/bin/octez-smart-rollup-client-alpha .
COPY --from=0 /usr/bin/octez-smart-rollup-node-PtMumbai .
COPY --from=0 /usr/bin/octez-smart-rollup-node-PtNairob .
COPY --from=0 /usr/bin/octez-smart-rollup-node-alpha .
COPY --from=0 /usr/bin/octez-smart-rollup-wasm-debugger .
COPY --from=0 /usr/bin/flextesa .
COPY --from=0 /usr/share/zcash-params/* /usr/share/zcash-params/
RUN sh -c 'printf "#!/bin/sh\nsleep 1\nrlwrap flextesa \"\\\$@\"\n" > /usr/bin/flextesarl'
RUN chmod a+rx /usr/bin/flextesarl
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/limabox
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/mumbaibox
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/alphabox
RUN chmod a+rx /usr/bin/limabox
RUN chmod a+rx /usr/bin/mumbaibox
RUN chmod a+rx /usr/bin/alphabox
RUN /usr/bin/alphabox initclient
RUN ln -s /usr/bin/octez-client /usr/bin/tezos-client
ENV TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=Y
