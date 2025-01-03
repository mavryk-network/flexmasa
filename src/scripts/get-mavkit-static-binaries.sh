#! /bin/sh

set -e

dest_dir="$1"
if ! [ -d "$dest_dir" ]; then
    echo "usage: $0 <destination-path>" >&2
    echo "       <destination-path> should be an existing directory." >&2
    exit 3
fi

# - Go to https://gitlab.com/mavryk-network/mavryk-protocol/
# - Find a successful master-branch pipeline.
# - Get the 2 jobs making x86_64 and arm64 static binaries.
# - Download the artifacts and put them in a more durable place.
# - Put those durable URLs down there, as `download_uri`:
#
# This time: https://gitlab.com/mavryk-network/mavryk-protocol/-/pipelines/1608813286
# (from 2025-01-02)
# corresponding to:
# https://gitlab.com/mavryk-network/mavryk-protocol/-/commit/e072107c2d273332fd02a50d5c0eb7f88600efce

directory_name=
case $(uname -m) in
    x86_64)
        download_uri="https://www.dropbox.com/scl/fi/it3q7muv5ttdvaee5e6ie/mavkit-static-binaries-x86_64.zip?rlkey=0s9hrhu4zon56ehm8uf4cm6b8&st=bvwlrpfl&raw=1"
        directory_name=x86_64
        ;;
    aarch64)
        download_uri="https://www.dropbox.com/scl/fi/49fs95dxdq2xzrh4axivt/mavkit-static-binaries-arm64.zip?rlkey=9jjlqh90m4uibmotlzsqim61i&st=ffwjw2kb&raw=1"
        directory_name=arm64
        ;;
    *)
        echo "Unknown architecture: $(uname -a)" >&2
        exit 4
        ;;
esac

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip" --http1.1
    cd "$dest_dir"
    unzip bins.zip
    mv mavkit-binaries/$directory_name/* .
    rm -fr bins.zip mavkit-binaries/
    chmod a+rx mavkit-*
)
