FROM ocaml/opam:ubuntu-21.04-ocaml-4.12 as build_step
ENV DEBIAN_FRONTEND=noninteractive
RUN sudo cp /usr/bin/opam-2.1 /usr/bin/opam
#RUN opam update
ADD  --chown=opam:opam . ./
RUN opam install --with-test --deps-only ./tezai-base58-digest.opam ./tezai-tz1-crypto.opam ./flextesa.opam
RUN opam exec -- dune build --profile=release src/app/main.exe
RUN sudo cp _build/default/src/app/main.exe /usr/bin/flextesa
# Get link from the master pipeline, or from
# https://gitlab.com/tezos/tezos/-/releases
RUN sudo curl -L https://gitlab.com/tezos/tezos/-/jobs/1838794710/artifacts/download -o /usr/bin/bins.zip
WORKDIR /usr/bin
RUN sudo unzip bins.zip
RUN sudo mv tezos-binaries/* .
RUN sudo rm -fr bins.zip tezos-binaries
RUN sudo chmod a+rx tezos-*
ENV SAPLING_SPEND='sapling-spend.params'
ENV SAPLING_OUTPUT='sapling-output.params'
# ENV SAPLING_SPROUT_GROTH16_NAME='sprout-groth16.params'
ENV DOWNLOAD_URL="https://download.z.cash/downloads"
ENV LOCALLOC=/usr/share/zcash-params
RUN sudo mkdir -p $LOCALLOC
RUN sudo curl --output "$LOCALLOC/$SAPLING_OUTPUT" -L "$DOWNLOAD_URL/$SAPLING_OUTPUT"
RUN sudo curl --output "$LOCALLOC/$SAPLING_SPEND" -L "$DOWNLOAD_URL/$SAPLING_SPEND"
FROM ubuntu:21.04 as run_image
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update --yes
RUN apt-get install --yes curl libev4 libffi7 rlfe unzip netbase
WORKDIR /usr/bin
COPY --from=0 /usr/bin/tezos-accuser-010-PtGRANAD .
COPY --from=0 /usr/bin/tezos-accuser-011-PtHangz2 .
COPY --from=0 /usr/bin/tezos-accuser-alpha .
COPY --from=0 /usr/bin/tezos-admin-client .
COPY --from=0 /usr/bin/tezos-baker-010-PtGRANAD .
COPY --from=0 /usr/bin/tezos-baker-011-PtHangz2 .
COPY --from=0 /usr/bin/tezos-baker-alpha .
COPY --from=0 /usr/bin/tezos-client .
COPY --from=0 /usr/bin/tezos-codec .
COPY --from=0 /usr/bin/tezos-embedded-protocol-packer .
COPY --from=0 /usr/bin/tezos-endorser-010-PtGRANAD .
COPY --from=0 /usr/bin/tezos-endorser-011-PtHangz2 .
#COPY --from=0 /usr/bin/tezos-init-sandboxed-client.sh .
COPY --from=0 /usr/bin/tezos-node .
#COPY --from=0 /usr/bin/tezos-sandboxed-node.sh .
#COPY --from=0 /usr/bin/tezos-signer .
COPY --from=0 /usr/bin/tezos-validator .
COPY --from=0 /usr/bin/flextesa .
COPY --from=0 /usr/share/zcash-params/* /usr/share/zcash-params/
RUN sh -c 'printf "#!/bin/sh\nsleep 1\nrlfe flextesa \"\\\$@\"\n" > /usr/bin/flextesarl'
RUN chmod a+rx /usr/bin/flextesarl
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/granabox
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/hangzbox
RUN sed -i s/default_protocol=Granada/default_protocol=Hangzhou/ /usr/bin/hangzbox
COPY --from=0 /home/opam/src/scripts/tutorial-box.sh /usr/bin/alphabox
RUN sed -i s/default_protocol=Granada/default_protocol=Alpha/ /usr/bin/alphabox
RUN chmod a+rx /usr/bin/granabox
RUN chmod a+rx /usr/bin/hangzbox
RUN chmod a+rx /usr/bin/alphabox
RUN cp /usr/bin/alphabox /usr/bin/tenderbox
RUN /usr/bin/granabox initclient
ENV TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=Y

