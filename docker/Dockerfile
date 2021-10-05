FROM ocaml/opam:ubuntu-21.04-ocaml-4.12
RUN git clone https://gitlab.com/smondet/flextesa.git -b smondet-try-fix-docker
RUN sudo cp /usr/bin/opam-2.1 /usr/bin/opam
RUN opam update
WORKDIR flextesa
RUN make vendors
RUN opam exec -- sh src/scripts/opam-test.sh
RUN opam exec -- dune build src/app/main.exe
RUN sudo cp _build/default/src/app/main.exe /usr/bin/flextesa
FROM ubuntu:21.04
RUN apt update
RUN apt install --yes curl libev-dev libffi-dev
# Get link from https://gitlab.com/tezos/tezos/-/releases
RUN curl -L https://gitlab.com/tezos/tezos/-/jobs/1612155317/artifacts/download -o /usr/bin/bins.zip
RUN sh -c 'curl https://raw.githubusercontent.com/zcash/zcash/master/zcutil/fetch-params.sh | sh'
WORKDIR /usr/bin
RUN apt install --yes unzip
RUN unzip bins.zip
RUN cp tezos-binaries/* .
RUN chmod a+rx tezos-*
# https://gitlab.com/tezos/tezos/-/issues/634
RUN apt install --yes netbase
COPY --from=0 /usr/bin/flextesa /usr/bin/flextesa
RUN sh -c 'printf "#!/bin/sh\nsleep 1\nrlwrap flextesa \"\\\$@\"\n" > /usr/bin/flextesarl'
RUN chmod a+rx /usr/bin/flextesarl
COPY --from=0 /home/opam/flextesa/src/scripts/tutorial-box.sh /usr/bin/granabox
COPY --from=0 /home/opam/flextesa/src/scripts/tutorial-box.sh /usr/bin/hangzbox
RUN sed -i s/default_protocol=Granada/default_protocol=Hangzhou/ /usr/bin/hangzbox
RUN chmod a+rx /usr/bin/granabox
RUN chmod a+rx /usr/bin/hangzbox
