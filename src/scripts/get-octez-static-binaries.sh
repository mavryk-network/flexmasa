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
# - Get the 2 jobs making x86_64 and arm64 static binaries.
# - Download the artifacts and put them in a more durable place.
# - Put those durable URLs down there, as `download_uri`:
#
# This time: https://gitlab.com/tezos/tezos/-/pipelines/801391070
# (from 2023-03-09)
# corresponding to
# https://gitlab.com/tezos/tezos/-/commit/3e9dad7af444515d6dbfb266854c3f400d6a045b

directory_name=
case $(uname -m) in
    x86_64)
        download_uri="https://www.dropbox.com/s/6n97tvjelrhx2au/octez-static-binaries-x86_64-20230309-3e9dad7af4.zip?raw=1"
        directory_name=x86_64
        ;;
    aarch64)
        download_uri="https://www.dropbox.com/s/ykgamh6ogjow76k/octez-static-arm64-20230201-739cc356c9.zip?raw=1"
        directory_name=arm64
        ;;
    *)
        echo "Unknown architecture: $(uname -a)" >&2
        exit 4
        ;;
esac

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    mv octez-binaries/$directory_name/* .
    rm -fr bins.zip octez-binaries/
    chmod a+rx octez-*
)
