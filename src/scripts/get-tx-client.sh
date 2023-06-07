#! /bin/sh

set -e

dest_dir="$(echo $1 | sed 's:/*$::')"
if ! [ -d "$dest_dir" ]; then
    echo "usage: $0 <destination-path>" >&2
    echo "       <destination-path> should be an existing directory." >&2
    exit 3
fi
tmp_dir=tx-client-tmp-dir

# Install Rust
echo "Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Url of the tx-client repository based on the current working commit.
URL=https://gitlab.com/emturner/tx-client/-/archive/bb054499e40f347f564b883e5bc4cb8819c33c14/tx-client-bb054499e40f347f564b883e5bc4cb8819c33c14.tar.gz

# Download and unzip the repository
echo "Downloading the tx-client repository..."
curl -L "$URL" -o "$dest_dir/tx-client.tar.gz"
cd "$dest_dir"
echo "Unpacking tx-client..."
tar -xzf tx-client.tar.gz
rm tx-client.tar.gz
# Rename the directory to something more sensible
mv tx-client-* ${tmp_dir}

# Build the tx-client binary
cd ${tmp_dir}
echo "Building tx-client..."
~/.cargo/bin/cargo build --release

# Move the binary to the destination directory and clean up the temporary directory.
cd ..
mv "${tmp_dir}/target/release/tx_kernel_client" tx-client
rm -rf ${tmp_dir}
