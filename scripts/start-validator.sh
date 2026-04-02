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

usage() {
  echo -e "\nUsage: $0 --network <mainnet|testnet> --validator [OPTIONS]"
  echo "Options:"
  echo -e "\t-h, --help       This help"
  echo -e "\t-v, --verbose    Verbose"
  echo -e "\t--network        mainnet or testnet (required)"
  echo -e "\t--validator      Start all validator nodes for this network"
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

ENV_FILE="$REPO_ROOT/.env.$NETWORK"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — copy config/networks/$NETWORK/env.example to .env.$NETWORK and set CHAINID, BOOTNODE, IP." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$ENV_FILE"

welcome(){
  echo -e "\n\n\t${ORANGE}Network: $NETWORK"
  echo -e "\t${ORANGE}Validators: $totalValidator"
  echo -e "\t${ORANGE}Data directories: chaindata/$NETWORK/node*"
  echo -e "${GREEN}
  \t+------------------------------------------------+
  \t+   G8Chain validator
  \t+   OS: $(. /etc/os-release && printf '%s\n' "${PRETTY_NAME}")
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
  # testnet defaults +100 on port base so mainnet + testnet can run on one host without collision
  local off=0
  [ "$NETWORK" = testnet ] && off=100
  while [[ $i -le $totalValidator ]]; do
    local p=$((32668 + off + i))
    local sess="${NETWORK}-n${i}"
    if tmux has-session -t "$sess" > /dev/null 2>&1; then
      :
    else
      tmux new-session -d -s "$sess"
      tmux send-keys -t "$sess" "$GETH --datadir ./chaindata/$NETWORK/node$i --networkid $CHAINID --bootnodes $BOOTNODE --mine --port $p --nat extip:$IP --gpo.percentile 0 --gpo.maxprice 100 --gpo.ignoreprice 0 --unlock 0 --password ./chaindata/$NETWORK/node$i/pass.txt --syncmode=full console" Enter
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
