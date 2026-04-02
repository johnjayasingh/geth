# G8Chain — validator node

This repository contains the **G8Chain geth fork** (`node_src/`), the **genesis** used to join the network (`genesis.json`), and scripts to **build**, **initialize**, and **run validator nodes** on Ubuntu.

Nothing else is required to operate a validator: there is no explorer, migration tooling, or ancillary services in this tree.

## Requirements

- **OS:** Ubuntu 20.04 LTS or newer (64-bit)
- **RAM:** 8 GB minimum (32 GB recommended)
- **Disk:** SSD strongly recommended; chain data grows over time
- **Network:** open **TCP/UDP 32668–32700** (or the port range you configure) for P2P

## Quick start (new validator)

As `root` (paths assume clone at `/root/core-blockchain`):

```bash
apt update && apt upgrade -y
apt install -y git tar curl wget build-essential tree tmux
git clone <this-repo-url> /root/core-blockchain
cd /root/core-blockchain
./node-setup.sh --validator 1
```

Edit `.env`: set **`BOOTNODE`** (and **`CHAINID`** if your network differs). `node-setup.sh` creates `.env` from `.env.example` if needed and appends your public **`IP`**.

Start the validator:

```bash
./node-start.sh --validator
```

Attach to the console (example: first node):

```bash
tmux attach -t node1
```

Detach from tmux: `Ctrl+b`, then `d`.

## Building geth only

```bash
cd node_src && make all
```

Binary: `node_src/build/bin/geth`.

## Initialize data directory manually

```bash
./node_src/build/bin/geth --datadir /path/to/datadir init ./genesis.json
```

## Wipe local chain data (dangerous)

```bash
./format-package.sh
```

This prompts before deleting under `chaindata/` and `tmp/`.

## Wallet / keystore

After setup, account keys live under `chaindata/node<N>/keystore/`. Protect **`pass.txt`** and keystore files; never commit them. See `.gitignore`.

## License

See `LICENSE`.
