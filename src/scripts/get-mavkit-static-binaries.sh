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
# This time: https://gitlab.com/mavryk-network/mavryk-protocol/-/pipelines/1416146798
# (from 2024-08-16)
# corresponding to:
# https://gitlab.com/mavryk-network/mavryk-protocol/-/commit/e072107c2d273332fd02a50d5c0eb7f88600efce

directory_name=
case $(uname -m) in
    x86_64)
        download_uri="https://www.dropbox.com/scl/fi/wc14p5x3zfd0epkerf3oc/mavkit-static-binaries-x86_64.zip?rlkey=y3z1y1o5l8erku394mwooqoyr&raw=1"
        directory_name=x86_64
        ;;
    aarch64)
        download_uri="https://www.dropbox.com/scl/fi/r5z9t4zkyudtv14rafe8b/mavkit-static-binaries-arm64.zip?rlkey=9634ixtqm55bsarnnphg7svbg&raw=1"
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
