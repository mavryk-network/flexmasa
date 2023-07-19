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
# This time: https://gitlab.com/tezos/tezos/-/pipelines/900218521
# (from 2023-07-06)
# corresponding to
# https://gitlab.com/tezos/tezos/-/commit/559c00e5a59c046a2cb2a37a2592b1845fc5265a

download_uri="https://www.dropbox.com/s/p72rt4peldo0h1o/octez-kernel-build-20230706-559c00e5.zip?raw=1"

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    rm -fr bins.zip
)
