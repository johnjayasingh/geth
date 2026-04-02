#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GETH="$REPO_ROOT/geth/build/bin/geth"

GREEN='\033[0;32m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

NETWORK=""
totalValidator=0
totalNodes=0

genesis_path() {
  echo "$REPO_ROOT/config/networks/$NETWORK/genesis.json"
}

task1(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Setting up environment]${NC}\n"
  apt update && apt upgrade -y
  echo -e "\n${GREEN}[TASK 1 PASSED]${NC}\n"
}

task2(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Setting up environment]${NC}\n"
  apt -y install build-essential tree
  echo -e "\n${GREEN}[TASK 2 PASSED]${NC}\n"
}

task3(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Getting GO]${NC}\n"
  mkdir -p "$REPO_ROOT/tmp"
  cd "$REPO_ROOT/tmp" && wget "https://go.dev/dl/go1.17.3.linux-amd64.tar.gz"
  echo -e "\n${GREEN}[TASK 3 PASSED]${NC}\n"
}

task4(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Setting GO]${NC}\n"
  cd "$REPO_ROOT/tmp"
  rm -rf /usr/local/go && tar -C /usr/local -xzf go1.17.3.linux-amd64.tar.gz
  echo -e '\nPATH=$PATH:/usr/local/go/bin' >>/etc/profile

  echo -e "\ncd ${REPO_ROOT}" >>/etc/profile

  export PATH=$PATH:/usr/local/go/bin
  go env -w GO111MODULE=off
  echo -e "\n${GREEN}[TASK 4 PASSED]${NC}\n"
}

task5(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Setting up Permissions]${NC}\n"
  cd "$REPO_ROOT"
  chown -R root:root ./
  chmod a+x "$REPO_ROOT/scripts/setup-validator.sh" "$REPO_ROOT/scripts/start-validator.sh" "$REPO_ROOT/scripts/reset-chaindata.sh" "$REPO_ROOT/scripts/print-enode.sh"
  echo -e "\n${GREEN}[TASK 5 PASSED]${NC}\n"
}

task6(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Building geth]${NC}\n"
  cd "$REPO_ROOT/geth"
  make all
  echo -e "\n${GREEN}[TASK 6 PASSED]${NC}\n"
}

task7(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Creating data directories]${NC}\n"
  cd "$REPO_ROOT"
  mkdir -p "chaindata/$NETWORK"
  local i=1
  while [[ $i -le $totalNodes ]]; do
    mkdir -p "./chaindata/$NETWORK/node$i"
    ((i += 1))
  done
  tree "./chaindata/$NETWORK" || ls -la "./chaindata/$NETWORK"
  echo -e "\n${GREEN}[TASK 7 PASSED]${NC}\n"
}

task8(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Validator accounts]${NC}\n"
  echo -e "${ORANGE}Create a password for each validator account; back up the keystore and password securely.${NC}\n"
  local i=1
  while [[ $i -le $totalValidator ]]; do
    echo -e "\n${GREEN}+---------------------------------------------------------------------+\n"
    read -r -p "Enter password for validator $i:  " password
    echo "$password" >"./chaindata/$NETWORK/node$i/pass.txt"
    "$GETH" --datadir "./chaindata/$NETWORK/node$i" account new --password "./chaindata/$NETWORK/node$i/pass.txt"
    ((i += 1))
  done
  echo -e "\n${GREEN}[TASK 8 PASSED]${NC}\n"
}

labelValidators(){
  local i=1
  while [[ $i -le $totalValidator ]]; do
    touch "./chaindata/$NETWORK/node$i/.validator"
    ((i += 1))
  done
}

displayStatus(){
  echo -e "\n${ORANGE}STATUS: ${GREEN}Network ${ORANGE}${NETWORK}${GREEN}. Configure ${ORANGE}.env.${NETWORK}${GREEN} (CHAINID, BOOTNODE), then:${NC}"
  echo -e "  ${ORANGE}./scripts/start-validator.sh --network ${NETWORK} --validator${NC}\n"
}

displayWelcome(){
  echo -e "\n\n\t${ORANGE}Network: ${NETWORK}"
  echo -e "\t${ORANGE}Validators to create: $totalValidator"
  echo -e "${GREEN}
  \t+------------------------------------------------+
  \t+   G8Chain validator setup (Ubuntu 20.04+)
  \t+   OS: $(. /etc/os-release && printf '%s\n' "${PRETTY_NAME}")
  \t+------------------------------------------------+
  ${NC}\n"
}

doUpdate(){
  echo -e "${GREEN}Updating repository...${NC}"
  cd "$REPO_ROOT" && git pull
}

fetchNsetIP(){
  echo -e "\nIP=$(curl -sS http://checkip.amazonaws.com)" >> "$REPO_ROOT/.env.$NETWORK"
}

initGenesis(){
  local gen
  gen="$(genesis_path)"
  if [ ! -f "$gen" ]; then
    echo "Missing genesis: $gen" >&2
    exit 1
  fi
  local i=1
  while [[ $i -le $totalValidator ]]; do
    "$GETH" --datadir "./chaindata/$NETWORK/node$i" init "$gen"
    ((i += 1))
  done
}

finalize(){
  displayWelcome
  task1
  task2
  task3
  task4
  task5
  task6
  task7
  task8
  initGenesis
  labelValidators
  if [ ! -f "$REPO_ROOT/.env.$NETWORK" ] && [ -f "$REPO_ROOT/config/networks/$NETWORK/env.example" ]; then
    cp "$REPO_ROOT/config/networks/$NETWORK/env.example" "$REPO_ROOT/.env.$NETWORK"
  fi
  fetchNsetIP
  displayStatus
}

usage() {
  echo -e "\nUsage: $0 --network <mainnet|testnet> --validator <n> [OPTIONS]"
  echo "Options:"
  echo -e "\t-h, --help              This help"
  echo -e "\t-v, --verbose           Verbose"
  echo -e "\t--network <name>        mainnet or testnet (required)"
  echo -e "\t--validator <n>         Number of validator nodes to create (required)"
  echo -e "\t--update                git pull only, then exit"
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
    --network)
      NETWORK="${2:-}"
      shift
      ;;
    --network=*)
      NETWORK="${1#*=}"
      ;;
    --validator*)
      if [[ "$1" == *=* ]]; then
        totalValidator="${1#*=}"
      else
        totalValidator="${2:-}"
        shift
      fi
      if ! [[ "$totalValidator" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid --validator count" >&2
        exit 1
      fi
      totalNodes=$totalValidator
      ;;
    --update)
      doUpdate
      exit 0
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

if [ -z "$NETWORK" ] || { [ "$NETWORK" != mainnet ] && [ "$NETWORK" != testnet ]; }; then
  echo "--network mainnet|testnet is required" >&2
  usage
  exit 1
fi

if [ -z "$totalValidator" ] || [ "$totalValidator" -eq 0 ]; then
  usage
  exit 1
fi

finalize
