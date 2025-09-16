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
# - Go to https://gitlab.com/mavryk-network/mavryk-protocol/
# - Find a successful master-branch pipeline.
# - Get the job build_kernels
# - Download the artifacts and put them in a more durable place.
# - Put those durable URLs down there, as `download_uri`:
#
# This time: https://gitlab.com/mavryk-network/mavryk-protocol/-/pipelines/1606209115
# (from 2024-12-31)
# corresponding to:
# https://gitlab.com/mavryk-network/mavryk-protocol/-/commit/0dffc5348a478c7a7df7f7802dd4dd90c71a93f3

download_uri="https://www.dropbox.com/scl/fi/50f8fgokziat22uc3elgd/mavkit-kernel-build-20250301-0dffc534.zip?rlkey=p16byef4n2hjp7z0tnq3q709f&st=4e68x3qg&raw=1"

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    rm -fr bins.zip
)
