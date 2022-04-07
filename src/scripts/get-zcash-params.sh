#! /bin/sh

set -e

SAPLING_SPEND='sapling-spend.params'
SAPLING_OUTPUT='sapling-output.params'
# ENV SAPLING_SPROUT_GROTH16_NAME='sprout-groth16.params'

DOWNLOAD_URL="https://download.z.cash/downloads"

destination=${1}

mkdir -p "$destination"
curl --output "$destination/$SAPLING_OUTPUT" -L "$DOWNLOAD_URL/$SAPLING_OUTPUT"
curl --output "$destination/$SAPLING_SPEND" -L "$DOWNLOAD_URL/$SAPLING_SPEND"
