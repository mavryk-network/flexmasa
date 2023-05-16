#! /bin/sh

set -e

dest_dir="$1"
if ! [ -d "$dest_dir" ]; then
    echo "usage: $0 <destination-path>" >&2
    echo "       <destination-path> should be an existing directory." >&2
    exit 3
fi

# Install Rust
echo "Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Download and unzip the repository
echo "Downloading the tx-client repository..."
URL=https://gitlab.com/emturner/tx-client/-/archive/bb054499e40f347f564b883e5bc4cb8819c33c14/tx-client-bb054499e40f347f564b883e5bc4cb8819c33c14.tar.gz
curl -L "$URL" -o "$dest_dir/tx-client.tar.gz"
cd "$dest_dir"
echo "Unpacking tx-client..."
tar -xzf tx-client.tar.gz
rm tx-client.tar.gz

# Create tx-client.sh script
echo "#!/bin/sh" >tx-client.sh
echo "TX_CLIENT=\"cargo run -q -- --config-file ${dest_dir}/.tx-client.config\"" >>tx-client.sh
echo '$TX_CLIENT "$@"' >>tx-client.sh
chmod +x tx-client.sh
