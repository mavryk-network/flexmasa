#! /bin/sh

set -e

dest_dir="$1"
if ! [ -d "$dest_dir" ] ; then
    echo "usage: $0 <destination-path>" >&2
    exit 3
fi

# Get IDs from the master pipeline, or from
# https://gitlab.com/tezos/tezos/-/releases
# This time: https://gitlab.com/tezos/tezos/-/pipelines/479417578
job_id=none
case $(uname -m) in
    x86_64 ) job_id=2136984736 ;;
    aarch64 ) job_id=2136984737 ;;
    * ) echo "Unknown architecture: $(uname -a)" >&2 ; exit 4 ;;
esac

(
    curl -L "https://gitlab.com/tezos/tezos/-/jobs/$job_id/artifacts/download" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    mv tezos-binaries/$(uname -m)/* .
    rm -fr bins.zip tezos-binaries/
    chmod a+rx tezos-*
)
