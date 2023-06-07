#! /bin/sh

set -e

dest_dir="$1"
if ! [ -d "$dest_dir" ]; then
    echo "usage: $0 <destination-path>" >&2
    echo "       <destination-path> should be an existing directory." >&2
    exit 3
fi

# - Go to https://gitlab.com/tezos/tezos/
# - Find a successful master-branch pipeline.
# - Get the job build_kerenls
# - Download the artifacts and put them in a more durable place.
# - Put those durable URLs down there, as `download_uri`:
#
# This time:https://gitlab.com/tezos/tezos/-/pipelines/837598628
# (from 2023-04-14)
# corresponding to
# https://gitlab.com/tezos/tezos/-/commit/ad473c9195b10b82968d10c96aa72b080e4dd846

download_uri="https://www.dropbox.com/s/7j2wscs0qvv3ixw/octez-kernel-build-20230414-ac4a09f720.zip?raw=1"

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    rm -fr bins.zip
)
