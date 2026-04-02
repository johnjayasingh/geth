#!/bin/bash
set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_ROOT"

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m'

totalValidator=0
totalNodes=0
isValidator=false

if [ ! -f ./.env ]; then
  echo "Missing .env — copy .env.example to .env and set CHAINID, BOOTNODE, and IP (or run node-setup.sh to append IP)." >&2
  exit 1
fi
# shellcheck disable=SC1091
source ./.env

welcome(){
  echo -e "\n\n\t${ORANGE}Validators: $totalValidator"
  echo -e "\t${ORANGE}Data directories (nodes): $totalNodes"
  echo -e "${GREEN}
  \t+------------------------------------------------+
  \t+   G8Chain validator node
  \t+   OS: $(. /etc/os-release && printf '%s\n' "${PRETTY_NAME}")
  \t+   ./node-start.sh --help
  \t+------------------------------------------------+
  ${NC}\n"
}

countNodes(){
  local i=1
  totalNodes=$(find ./chaindata -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if ! [[ "$totalNodes" =~ ^[0-9]+$ ]] || [ "$totalNodes" -eq 0 ]; then
    totalNodes=0
    totalValidator=0
    return
  fi
  while [[ $i -le $totalNodes ]]; do
    if [ -f "./chaindata/node$i/.validator" ]; then
      ((totalValidator += 1)) || true
    fi
    ((i += 1))
  done
}

startValidator(){
  local i=1
  local j=69
  while [[ $i -le $totalValidator ]]; do
    if tmux has-session -t "node$i" > /dev/null 2>&1; then
      :
    else
      tmux new-session -d -s "node$i"
      tmux send-keys -t "node$i" "./node_src/build/bin/geth --datadir ./chaindata/node$i --networkid $CHAINID --bootnodes $BOOTNODE --mine --port 326$j --nat extip:$IP --gpo.percentile 0 --gpo.maxprice 100 --gpo.ignoreprice 0 --unlock 0 --password ./chaindata/node$i/pass.txt --syncmode=full console" Enter
    fi
    ((i += 1))
    ((j += 1))
  done
}

finalize(){
  countNodes
  welcome

  if [ "$isValidator" = true ]; then
    if [ "$totalValidator" -eq 0 ]; then
      echo "No validator data under ./chaindata (expected .validator markers). Run node-setup.sh first." >&2
      exit 1
    fi
    echo -e "\n${GREEN}+------------------- Starting validators -------------------+${NC}"
    startValidator
  fi

  echo -e "\n${GREEN}+------------------ tmux sessions -------------------+${NC}"
  tmux ls || true
  echo -e "${NC}"
}

usage() {
  echo -e "\nUsage: $0 [OPTIONS]"
  echo "Options:"
  echo -e "\t-h, --help       This help"
  echo -e "\t-v, --verbose    Verbose"
  echo -e "\t--validator      Start all validator nodes"
}

verbose_mode=false

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

handle_options "$@"

if [ "$verbose_mode" = true ]; then
  set -x
fi

if [ "$isValidator" != true ]; then
  usage
  exit 1
fi

finalize
