#! /bin/sh

set -e

dest_dir="$1"
if ! [ -d "$dest_dir" ]; then
    echo "usage: $0 <destination-path>" >&2
    echo "       <destination-path> should be an existing directory." >&2
    exit 3
fi

# Use this scrpcipt to get the evm_kernel and the smart-rollup-client binary.
#
# - Go to https://gitlab.com/tezos/tezos/
# - Find a successful master-branch pipeline.
# - Get the job build_kerenls
# - Download the artifacts and put them in a more durable place.
# - Put those durable URLs down there, as `download_uri`:
#
# This time: https://gitlab.com/tezos/tezos/-/pipelines/1018329699
# (from 2023-09-27)
# corresponding to
# https://gitlab.com/tezos/tezos/-/commit/47bf956cf8b46d6606d00ce53f767478aa2251e6

download_uri="https://www.dropbox.com/scl/fi/bh2dptylfq7su1bu8wmm5/octez-kernel-build-20230927-47bf956c.zip?rlkey=ksglks74x22okpbglikghcpj5&raw=1"

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    rm -fr bins.zip
)
