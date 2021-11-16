FROM ocaml/opam:ubuntu-21.04-ocaml-4.12 as build_step
ENV DEBIAN_FRONTEND=noninteractive
RUN sudo cp /usr/bin/opam-2.1 /usr/bin/opam
#RUN opam update
ADD  --chown=opam:opam . ./
RUN opam install --with-test --deps-only ./tezai-base58-digest.opam ./tezai-tz1-crypto.opam ./flextesa.opam
RUN opam exec -- dune build --profile=release src/app/main.exe
RUN sudo cp _build/default/src/app/main.exe /usr/bin/flextesa
FROM ubuntu:21.04 as run_image
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update --yes
RUN apt-get install --yes curl libev4 libffi7 rlfe unzip netbase
# Get link from the master pipeline, or from
# https://gitlab.com/tezos/tezos/-/releases
RUN curl -L https://gitlab.com/tezos/tezos/-/jobs/1784112584/artifacts/download -o /usr/bin/bins.zip
WORKDIR /usr/bin
RUN unzip bins.zip
RUN cp tezos-binaries/* .
RUN chmod a+rx tezos-*
ENV SAPLING_SPEND='sapling-spend.params'
ENV SAPLING_OUTPUT='sapling-output.params'
# ENV SAPLING_SPROUT_GROTH16_NAME='sprout-groth16.params'
ENV DOWNLOAD_URL="https://download.z.cash/downloads"
ENV LOCALLOC=/usr/share/zcash-params
RUN mkdir -p $LOCALLOC
RUN curl --output "$LOCALLOC/$SAPLING_OUTPUT" -L "$DOWNLOAD_URL/$SAPLING_OUTPUT"
RUN curl --output "$LOCALLOC/$SAPLING_SPEND" -L "$DOWNLOAD_URL/$SAPLING_SPEND"
COPY --from=0 /usr/bin/flextesa /usr/bin/flextesa
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


