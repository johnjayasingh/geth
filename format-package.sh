#!/bin/bash
set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_ROOT"

GREEN='\033[0;32m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

totalValidator=0
totalNodes=0

countNodes(){
  totalNodes=$(find ./chaindata -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  local i=1
  while [[ $i -le $totalNodes ]]; do
    if [ -f "./chaindata/node$i/.validator" ]; then
      ((totalValidator += 1)) || true
    fi
    ((i += 1))
  done
}

displayStatus(){
  echo -e "\n${GREEN}Existing validator data under ./chaindata has been removed.${NC}"
}

task1(){
  echo -e "\n\n${ORANGE}TASK: ${RED}[Formatting installation]${NC}\n"
  while true; do
    read -r -p "Delete all node data under chaindata/ and tmp/? (y/N) " yn
    case $yn in
      [Yy]*)
        echo -e "${RED}Formatting..."
        rm -rf ./chaindata/node*
        rm -rf ./tmp/*
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
  echo -e "\n\n\t${ORANGE}Validator dirs found: $totalValidator (of $totalNodes under chaindata)"
  echo -e "\n${ORANGE}
  \t+------------------------------------------------------------------+
  \t|  This will delete validator/RPC data under ./chaindata and ./tmp
  \t|  Back up anything you need before continuing.
  \t+------------------------------------------------------------------+
  ${NC}\n"
}

finalize(){
  displayWelcome
  task1
}

finalize
