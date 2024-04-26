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
# This time: https://gitlab.com/tezos/tezos/-/pipelines/1114692838
# (from 2023-08-21)
# corresponding to:
# https://gitlab.com/tezos/tezos/-/commit/3e6ec4792f706670615cd565014228641aafd0f5

directory_name=
case $(uname -m) in
    x86_64)
        download_uri="https://www.dropbox.com/scl/fi/th2ngpexjpxtafvhvbzi9/mavkit-static-binaries-x86_64.zip?rlkey=890142kcvza84m4o27avrkrdf&raw=1"
        directory_name=x86_64
        ;;
    aarch64)
        download_uri="https://www.dropbox.com/scl/fi/vh0gcwj3bygwkt0ccc2fe/mavkit-static-binaries-arm64.zip?rlkey=tyevb69px2aun8pm3tu4x3ukm&dl=0&raw=1"
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
