#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GETH="$REPO_ROOT/geth/build/bin/geth"

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m'

NETWORK=""
totalValidator=0
totalNodes=0
isValidator=false
MAX_NODES=""  # empty = all

usage() {
  echo -e "\nUsage: $0 --network <mainnet|testnet> --validator [OPTIONS]"
  echo "Options:"
  echo -e "\t-h, --help          This help"
  echo -e "\t-v, --verbose       Verbose"
  echo -e "\t--network           mainnet or testnet (required)"
  echo -e "\t--validator         Start validator node(s) for this network"
  echo -e "\t--max-nodes <n>     Only start node1..nodeN (default: all). Use 1 first on fresh testnet, then set BOOTNODE and use 2."
}

handle_options() {
  while [ $# -gt 0 ]; do
    case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    -v | --verbose)
      verbose_mode=true
      ;;
    --network)
      NETWORK="${2:-}"
      shift
      ;;
    --network=*)
      NETWORK="${1#*=}"
      ;;
    --max-nodes)
      MAX_NODES="${2:-}"
      shift
      ;;
    --max-nodes=*)
      MAX_NODES="${1#*=}"
      ;;
    --validator)
      isValidator=true
      ;;
    *)
      echo "Invalid option: $1" >&2
      usage
      exit 1
      ;;
    esac
    shift
  done
}

verbose_mode=false
handle_options "$@"

if [ "$verbose_mode" = true ]; then
  set -x
fi

if [ -z "$NETWORK" ] || { [ "$NETWORK" != mainnet ] && [ "$NETWORK" != testnet ]; }; then
  echo "--network mainnet|testnet is required" >&2
  usage
  exit 1
fi

if [ -n "$MAX_NODES" ] && ! [[ "$MAX_NODES" =~ ^[1-9][0-9]*$ ]]; then
  echo "--max-nodes must be a positive integer" >&2
  exit 1
fi

ENV_FILE="$REPO_ROOT/.env.$NETWORK"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — copy config/networks/$NETWORK/env.example to .env.$NETWORK and set CHAINID, BOOTNODE, IP." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$ENV_FILE"

bootnode_placeholder() {
  [ -z "$BOOTNODE" ] && return 0
  [[ "$BOOTNODE" == *"REPLACE"* ]] && return 0
  [[ "$BOOTNODE" == *"<"* && "$BOOTNODE" == *">"* ]] && return 0
  return 1
}

nat_string() {
  if [ -n "$IP" ]; then
    echo "--nat extip:$IP"
  else
    echo "--nat any"
  fi
}

welcome(){
  local osname
  osname="$(. /etc/os-release 2>/dev/null && printf '%s\n' "${PRETTY_NAME}")" || osname="unknown"
  echo -e "\n\n\t${ORANGE}Network: $NETWORK"
  echo -e "\t${ORANGE}Validators: $totalValidator"
  echo -e "\t${ORANGE}Data directories: chaindata/$NETWORK/node*"
  echo -e "${GREEN}
  \t+------------------------------------------------+
  \t+   G8Chain validator
  \t+   OS: $osname
  \t+   scripts/start-validator.sh --help
  \t+------------------------------------------------+
  ${NC}\n"
}

countNodes(){
  local base="$REPO_ROOT/chaindata/$NETWORK"
  if [ ! -d "$base" ]; then
    totalNodes=0
    totalValidator=0
    return
  fi
  local i=1
  totalNodes=$(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if ! [[ "$totalNodes" =~ ^[0-9]+$ ]] || [ "$totalNodes" -eq 0 ]; then
    totalNodes=0
    totalValidator=0
    return
  fi
  while [[ $i -le $totalNodes ]]; do
    if [ -f "$base/node$i/.validator" ]; then
      ((totalValidator += 1)) || true
    fi
    ((i += 1))
  done
}

startValidator(){
  local i=1
  local off=0
  [ "$NETWORK" = testnet ] && off=100
  local limit=$totalValidator
  if [ -n "$MAX_NODES" ]; then
    if [ "$MAX_NODES" -lt "$totalValidator" ]; then
      limit=$MAX_NODES
    fi
  fi

  local natstr
  natstr=$(nat_string)

  while [[ $i -le $limit ]]; do
    local p=$((32668 + off + i))
    local sess="${NETWORK}-n${i}"

    local bootflag=""
    if [ "$i" -ge 2 ]; then
      if bootnode_placeholder; then
        echo "Validator $i requires BOOTNODE in .env.$NETWORK (enode from node 1: ./scripts/print-enode.sh --network $NETWORK --node 1)." >&2
        exit 1
      fi
      bootflag="--bootnodes $BOOTNODE"
    else
      if ! bootnode_placeholder; then
        bootflag="--bootnodes $BOOTNODE"
      fi
    fi

    if tmux has-session -t "$sess" > /dev/null 2>&1; then
      :
    else
      tmux new-session -d -s "$sess"
      tmux send-keys -t "$sess" "$GETH --datadir ./chaindata/$NETWORK/node$i --networkid $CHAINID $bootflag --mine --port $p $natstr --gpo.percentile 0 --gpo.maxprice 100 --gpo.ignoreprice 0 --unlock 0 --password ./chaindata/$NETWORK/node$i/pass.txt --syncmode=full console" Enter
    fi
    ((i += 1))
  done
}

finalize(){
  countNodes
  welcome

  if [ "$isValidator" = true ]; then
    if [ "$totalValidator" -eq 0 ]; then
      echo "No validator data under chaindata/$NETWORK/ (expected .validator markers). Run scripts/setup-validator.sh --network $NETWORK --validator <n> first." >&2
      exit 1
    fi
    echo -e "\n${GREEN}+------------------- Starting validators ($NETWORK) -------------------+${NC}"
    startValidator
  fi

  echo -e "\n${GREEN}+------------------ tmux sessions -------------------+${NC}"
  tmux ls || true
  echo -e "${NC}"
}

if [ "$isValidator" != true ]; then
  usage
  exit 1
fi

finalize
