#!/usr/bin/env bash
#
# Kaspa Node Setup Script for Ubuntu Linux
#
# Description
# Installs pre-reqs, golang, rust, git, net-tools, nano, tmux, btop, go, etc.
# on a fresh, clean Ubuntu server OS for getting a Kaspad and Miner setup and running.
#
# Usage 
# $ ./kaspad-miner-setup.sh [kaspa:..YOUR WALLET ADDRESS]
#
# Command line option(s)
# - WALLET ADDRESS is the KASPA_WALLET value for --mining-address for mining rewards
# otherwise it is donated to Kaspa development wallet
#
# Environment
# - Tested on Ubuntu Server minimum 22.04 running as a non-root user with sudo privileges
#
# general config
MINER_USER="kminer"
APT_PACKAGES="openssl curl wget snapd btop tmux git nano net-tools linux-kernel-headers build-essentials protobuf-compiler"

# common admin change for commands that filter .folders
shopt -s dotglob

KASPAD_DIR="/opt/kaspad"
KASPAD_REPO="https://github.com/kaspanet/kaspad"
KASPAD_REPO_NAME="kaspad"

KASPA_MINER_DIR="/opt/kaspa-miner"


################################################################

trap sigint INT

function sigint() {
    exit 1
}

# initial check for script arguments (fee address and IP options)
if [ -z "$1" ]; then
    echo "* requires kaspa wallet address, read the script notes and try again"
    exit 1
fi

KASPA_WALLET=$1

echo -e "KaspaD Node Setup\n"
echo -e "Note: this script automates most of the process.  Review logs for confirmation of DAC sync and Mining\n"
# add more detail on how to view logs
echo -e "* it coult take around 15 minutes to complete and several hours for sync *\n"

read -p "Press [Enter] to continiue"

# keep track of directory where we run the script
pushd $PWD &>/dev/null

echo -e "\nStep1: Install requirements and setup golang\n"

sudo apt-get update
sudo apt-get install -y $APT_PACKAGES
sudo snap install --classic go
echo "export PATH=$PATH:/snap/bin" >> ~/.bashrc

echo -e "\nstep 2: adding miner user, install rust

# add node account to run services
sudo useradd -m -s /bin/false -d /home/$MINER_USER $MINER_USER

#install rust
sudo -u $MINER_USER bash -c "cd \$HOME && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

echo -e "\nstep 3: setting up and run kaspad to start syncing data\n"

# kaspad setup
git clone $KASPAD_REPO
sleep 0.5
sudo mkdir -p $KASPAD_DIR
sudo mv $KASPAD_REPO_NAME/* $KASPAD_DIR
rm -rf $KASPAD_REPO_NAME
sudo chown -R $MINER_USER:$MINER_USER $KASPAD_DIR
cd $KASPAD_DIR
# add GOBIN here to change the install location. https://stackoverflow.com/questions/27192909/go-install-directory-outside-of-gopath
GOBIN="$KASPAD_DIR/build/bin
build all projects in ./cmd/
sudo -u $MINER_USER go install . ./cmd/...

# add kaspad to path to call from service w/o full path...or not

export PATH=$PATH:$GOBIN


#daemon configuration - should use json via kaspactl, but currently calling kaspad directly with switches
sudo tee /etc/systemd/system/kaspad.service > /dev/null <<EOT
[Unit]
Description=Kaspa (kaspad)
After=network.target
Wants=network.target

[Service]
User=$MINER_USER
Group=$MINER_USER
type=simple
Restart=always
RestartSec=5
ExecStart=$GOBIN/kaspad \
--utxoindex

[Install]
WantedBy=default.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable kaspad
sudo systemctl start kaspad
sudo systemctl status kaspad

echo -e "\nStep 4: setting up cpu miner\n"

# go back to start directory
popd

# kaspa-miner setup
# set Rust install location
CARGO_INSTALL_ROOT=$KASPA_MINER_DIR/.cargo/env
mkdir -p $CARGO_INSTALL_ROOT
sudo chown -R $MINER_USER:$MINER_USER $CARGO_INSTALL_ROOT
export PATH=$PATH:$CARGO_INSTALL_ROOT
cargo install kaspa-miner

#daemon configuration - miner
sudo tee /etc/systemd/system/kaspa-miner.service > /dev/null <<EOT
[Unit]
Description=Kaspa CPU Miner (kaspa-miner)
After=network.target
Wants=network.target

[Service]
User=$MINER_USER
Group=$MINER_USER
type=simple
Restart=always
RestartSec=5
ExecStart=$CARGO_INSTALL_ROOT/kaspa-miner \
--mining-address $KASPA_WALLET

[Install]
WantedBy=multi-user.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable kaspa-miner
sudo systemctl start kaspa-miner
sudo systemctl status kaspa-miner

echo -e "Now wait for a few hours for sync"
echo -e "Check logs with 'journalctl -u kaspad.service'"
echo -e "or 'journalctl -u kaspa-miner.service"