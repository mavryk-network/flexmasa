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
# This time: https://gitlab.com/tezos/tezos/-/pipelines/900218521
# (from 2023-06-14)
# corresponding to
# https://gitlab.com/tezos/tezos/-/commit/e937423b6127bee159ebf8ce21ca7adb832bcfc1

download_uri="https://www.dropbox.com/s/qvwp0eskex5stv7/octez-kernel-build-20230615-583bb51fb4.zip?raw=1"

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    rm -fr bins.zip
)
