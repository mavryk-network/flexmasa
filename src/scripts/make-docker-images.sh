#! /bin/sh

set -e

usage () {
    cat >&2 <<EOF
usage: $0 {setup,build,run} <base-docker-image-tag> [<setup-image>]

Only \`build\` requires the setup-image.

Environment:

* \`just_show=true\`: does not build, just displays the Dockerfile.
EOF
}

shout () {
    YELLOW='\033[0;33m'
    NC='\033[0m'
    if [ "no_color" = "true" ]; then
        printf "$@"
    else
        printf "$YELLOW"; printf "$@" ; printf "$NC"
    fi
}

say () {
    shout "[Make-docker-images] " >&2
    printf "$@" >&2
    printf "\n" >&2
}

if ! [ -f src/scripts/ensure-vendors.sh ] ; then
    say "This script should run from the root of the flextesa tree."
    exit 1
fi

root_path="$PWD"

image_kind="$1"
docker_tag="$2"
setup_image="$3"
commit_ref_name="$4"

case "$commit_ref_name" in
    master | image* )
        setup_image=$docker_tag-setup
        ;;
    * )
        say "The setup image was likely not built"
        ;;
esac
say "Using setup-image: $setup_image"


tmppath=$(mktemp -d)

say "building $image_kind -> $docker_tag (in $tmppath from $root_path)"

cp -r Makefile dune-project src $tmppath/

cd $tmppath

# Use  docker run -it ocaml/opam2:alpine
# and opam depext -ln hidapi zarith lwt afl
# and also this: https://www.bakejar.com/2018/08/30/tezos-compilation-on-alpine.html
# because hidapi is not in the default
tezos_depexts="gmp-dev hidapi-dev@testing m4 perl pkgconfig libev-dev"
alpine_setup () {
    local sudo="$1"
    cat >> Dockerfile <<EOF
RUN $sudo sh -c "echo '@testing http://nl.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories"
RUN $sudo sh -c "echo '@testing http://nl.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories"
RUN $sudo apk update
RUN $sudo apk add $tezos_depexts curl net-tools rlwrap@testing
EOF
}

vendor=local-vendor/tezos-master
daemons () {
    local proto="$1"
    local proto_dir="$(echo $proto | tr -- - _)"
    cat <<EOF
$vendor/src/proto_$proto_dir/bin_baker/main_baker_$proto_dir.exe:tezos-baker-$proto
$vendor/src/proto_$proto_dir/bin_endorser/main_endorser_$proto_dir.exe:tezos-endorser-$proto
$vendor/src/proto_$proto_dir/bin_accuser/main_accuser_$proto_dir.exe:tezos-accuser-$proto
EOF
}
interesting_binaries="
src/app/main.exe:flextesa
$vendor/src/bin_node/main.exe:tezos-node
$vendor/src/bin_client/main_client.exe:tezos-client
$vendor/src/bin_client/main_admin.exe:tezos-admin-client
$vendor/src/bin_validation/main_validator.exe:tezos-validator
$vendor/src/bin_signer/main_signer.exe:tezos-signer
$vendor/src/bin_codec/codec.exe:tezos-codec
$vendor/src/lib_protocol_compiler/main_native.exe:tezos-protocol-compiler
$(daemons alpha)
$(daemons 005-PsBabyM1)
$(daemons 006-PsCARTHA)
"
build_interesting_binaries () {
    for ib in $interesting_binaries ; do
        echo "$ib" | sed 's/\([^:]*\):.*/RUN opam config exec -- dune build \1/'
    done
}
copy_interesting_binaries () {
    for ib in $interesting_binaries ; do
        echo "$ib" | sed 's@\([^:]*\):\(.*\)@COPY --from=0 /rebuild/_build/default/\1 /usr/bin/\2@'
    done
}

make_setup_dockerfile () {
    cat > Dockerfile <<EOF
FROM ocaml/opam2:alpine
WORKDIR /home/opam/opam-repository
RUN git pull
WORKDIR /
RUN opam update
EOF
    alpine_setup "sudo"
    cat >> Dockerfile <<EOF
RUN sudo mkdir -p /build
RUN sudo chown -R opam:opam /build
WORKDIR /build
ADD --chown=opam:opam . ./
RUN make vendors
RUN opam switch 4.07
RUN opam switch --switch 4.07 import src/tezos-master.opam-switch
EOF
#RUN opam config exec -- bash -c 'opam install \$(find local-vendor -name "*.opam" -print)'
}
make_build_dockerfile () {
    cat > Dockerfile <<EOF
FROM $setup_image
RUN sudo mkdir -p /rebuild
RUN sudo chown -R opam:opam /rebuild
WORKDIR /rebuild
ADD --chown=opam:opam . ./
RUN make vendors
RUN opam config exec -- make
EOF
    build_interesting_binaries >> Dockerfile
}
make_run_dockerfile () {
    cat > Dockerfile <<EOF
FROM $docker_tag-build
FROM alpine
EOF
    alpine_setup ""
    copy_interesting_binaries >> Dockerfile
    cat >> Dockerfile <<EOF
RUN sh -c 'printf "#!/bin/sh\nsleep 1\nrlwrap flextesa \"\\\$@\"\n" > /usr/bin/flextesarl'
RUN chmod a+rx /usr/bin/flextesarl
ADD ./src/scripts/mini-babylon.sh /usr/bin/babylonbox
RUN chmod a+rx /usr/bin/babylonbox
EOF
}

case "$image_kind" in
    "setup" )
        make_setup_dockerfile
        actual_tag="$docker_tag-setup"
        ;;
    "build" )
        make_build_dockerfile
        actual_tag="$docker_tag-build"
        ;;
    "run" )
        make_run_dockerfile
        actual_tag="$docker_tag-run"
        ;;
    * )
        say "Error unknown image-kind"
        usage
        exit 2
        ;;
esac
if [ "$just_show" = "true" ] ; then
    say "Dockerfile: "
    cat Dockerfile
else
    say "building $actual_tag"
    docker build -t "$actual_tag" .
fi
