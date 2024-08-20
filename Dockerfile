FROM ocaml/opam:alpine-3.16-ocaml-4.14 as build_step
#ENV DEBIAN_FRONTEND=noninteractive
RUN sudo cp /usr/bin/opam-2.1 /usr/bin/opam
RUN sudo apk update
ADD  --chown=opam:opam . ./
RUN opam pin add -n mavai-base58-digest https://gitlab.com/mavryk-network/mavai-base-58-digest.git
RUN opam update
RUN opam install --with-test --deps-only ./mavai-mv1-crypto.opam ./flexmasa.opam
RUN opam exec -- dune build --profile=release src/app/main.exe
RUN sudo cp _build/default/src/app/main.exe /usr/bin/flexmasa
RUN sudo sh src/scripts/get-mavkit-static-binaries.sh /usr/bin
RUN sudo sh src/scripts/get-zcash-params.sh /usr/share/zcash-params
RUN sudo sh src/scripts/get-mavkit-kernel-build.sh /usr/bin
RUN sudo sh src/scripts/get-tx-client.sh /usr/bin
FROM alpine:3.15 as run_image
RUN apk update
RUN apk add curl libev libffi unzip gmp rlwrap jq hidapi-dev libstdc++
WORKDIR /usr/bin
COPY --from=0 /usr/bin/mavkit-accuser-PtAtLas .
COPY --from=0 /usr/bin/mavkit-accuser-PtBoreas .
COPY --from=0 /usr/bin/mavkit-accuser-alpha .
COPY --from=0 /usr/bin/mavkit-admin-client .
COPY --from=0 /usr/bin/mavkit-baker-PtAtLas .
COPY --from=0 /usr/bin/mavkit-baker-PtBoreas .
COPY --from=0 /usr/bin/mavkit-baker-alpha .
COPY --from=0 /usr/bin/mavkit-client .
COPY --from=0 /usr/bin/mavkit-codec .
COPY --from=0 /usr/bin/mavkit-dac-client .
COPY --from=0 /usr/bin/mavkit-dac-node .
COPY --from=0 /usr/bin/mavkit-dal-node .
COPY --from=0 /usr/bin/mavkit-evm-node .
COPY --from=0 /usr/bin/mavkit-node .
COPY --from=0 /usr/bin/mavkit-proxy-server .
COPY --from=0 /usr/bin/mavkit-signer .
COPY --from=0 /usr/bin/mavkit-smart-rollup-node .
COPY --from=0 /usr/bin/mavkit-smart-rollup-wasm-debugger .
COPY --from=0 /usr/bin/flexmasa .
COPY --from=0 /usr/share/zcash-params/* /usr/share/zcash-params/
COPY --from=0 /usr/bin/smart-rollup-installer .
RUN sh -c 'printf "#!/bin/sh\nsleep 1\nrlwrap flexmasa \"\\\$@\"\n" > /usr/bin/flexmasarl'
RUN chmod a+rx /usr/bin/flexmasarl
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/atlasbox
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/boreasbox
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/alphabox
RUN chmod a+rx /usr/bin/atlasbox
RUN chmod a+rx /usr/bin/boreasbox
RUN chmod a+rx /usr/bin/alphabox
RUN /usr/bin/alphabox initclient
RUN ln -s /usr/bin/mavkit-client /usr/bin/mavryk-client
ENV MAVRYK_CLIENT_UNSAFE_DISABLE_DISCLAIMER=Y
COPY --from=0 /usr/bin/tx-client .
