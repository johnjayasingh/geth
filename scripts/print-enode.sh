#!/bin/bash
# Print enode URL for a running validator (needs IPC from a running geth).
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORK=""
NODE_NUM=1
GETH="$REPO_ROOT/geth/build/bin/geth"

usage() {
  echo "Usage: $0 --network <mainnet|testnet> [--node <n>]"
  echo "  Requires geth running for that node (tmux session). Reads enode via IPC."
}

while [ $# -gt 0 ]; do
  case $1 in
  --network) NETWORK="${2:-}"; shift ;;
  --network=*) NETWORK="${1#*=}" ;;
  --node) NODE_NUM="${2:-}"; shift ;;
  --node=*) NODE_NUM="${1#*=}" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [ -z "$NETWORK" ] || { [ "$NETWORK" != mainnet ] && [ "$NETWORK" != testnet ]; }; then
  usage >&2
  exit 1
fi

IPC="$REPO_ROOT/chaindata/$NETWORK/node$NODE_NUM/geth.ipc"
if [ ! -S "$IPC" ] && [ ! -p "$IPC" ]; then
  echo "No IPC at $IPC — start the node first: ./scripts/start-validator.sh --network $NETWORK --validator --max-nodes $NODE_NUM" >&2
  exit 1
fi

exec "$GETH" attach "$IPC" --exec 'admin.nodeInfo.enode'
