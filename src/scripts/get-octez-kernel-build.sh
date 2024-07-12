#! /bin/sh

set -e

dest_dir="$1"
if ! [ -d "$dest_dir" ]; then
    echo "usage: $0 <destination-path>" >&2
    echo "       <destination-path> should be an existing directory." >&2
    exit 3
fi

# Use this scrpcipt to get the smart-rollup-installer and octez smart-rollup kernel binaries.
#
# - Go to https://gitlab.com/tezos/tezos/
# - Find a successful master-branch pipeline.
# - Get the job build_kerenls
# - Download the artifacts and put them in a more durable place.
# - Put those durable URLs down there, as `download_uri`:
#
# This time: https://gitlab.com/tezos/tezos/-/pipelines/1114693893
# (from 2023-09-27)
# corresponding to:
# https://gitlab.com/tezos/tezos/-/commit/50ce0bb6453cfa56cd62a417eba3454dd05d863e

download_uri="https://www.dropbox.com/scl/fi/qj8cjro7nipn47rxrw5sa/octez-kernel-build-20231220-50ce0bb6.zip?rlkey=nez38t9bdtw2xnl1c1iwo4q8q&dl&raw=1"

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    rm -fr bins.zip
)
