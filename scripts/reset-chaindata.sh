#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GREEN='\033[0;32m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

NETWORK=""
totalValidator=0
totalNodes=0

usage() {
  echo "Usage: $0 --network <mainnet|testnet>"
  echo "  Removes chaindata/<network>/node* and tmp/* after confirmation."
}

countNodes(){
  local base="$REPO_ROOT/chaindata/$NETWORK"
  [ -d "$base" ] || return
  totalNodes=$(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  local i=1
  while [[ $i -le $totalNodes ]]; do
    if [ -f "$base/node$i/.validator" ]; then
      ((totalValidator += 1)) || true
    fi
    ((i += 1))
  done
}

displayStatus(){
  echo -e "\n${GREEN}Removed chaindata/${NETWORK}/node* (and tmp/).${NC}"
}

task1(){
  echo -e "\n\n${ORANGE}TASK: ${RED}[Reset local chain data]${NC}\n"
  while true; do
    read -r -p "Delete chaindata/${NETWORK}/node* and tmp/? (y/N) " yn
    case $yn in
      [Yy]*)
        echo -e "${RED}Removing..."
        rm -rf "$REPO_ROOT/chaindata/$NETWORK"/node*
        rm -rf "$REPO_ROOT/tmp"/*
        displayStatus
        break
        ;;
      [Nn]*)
        exit 0
        ;;
      *)
        echo "Please answer yes or no."
        ;;
    esac
  done
  echo -e "\n${GREEN}[Done]${NC}\n"
}

displayWelcome(){
  countNodes
  echo -e "\n\n\t${ORANGE}Network: ${NETWORK}"
  echo -e "\t${ORANGE}Validator dirs: $totalValidator (of $totalNodes under chaindata/${NETWORK})"
  echo -e "\n${ORANGE}
  \t+------------------------------------------------------------------+
  \t|  This deletes data under chaindata/${NETWORK}/ and tmp/
  \t+------------------------------------------------------------------+
  ${NC}\n"
}

while [ $# -gt 0 ]; do
  case $1 in
  -h|--help)
    usage
    exit 0
    ;;
  --network)
    NETWORK="${2:-}"
    shift
    ;;
  --network=*)
    NETWORK="${1#*=}"
    ;;
  *)
    echo "Invalid option: $1" >&2
    usage
    exit 1
    ;;
  esac
  shift
done

if [ -z "$NETWORK" ] || { [ "$NETWORK" != mainnet ] && [ "$NETWORK" != testnet ]; }; then
  usage >&2
  exit 1
fi

displayWelcome
task1
