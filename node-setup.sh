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
  mkdir -p "$SCRIPT_ROOT/tmp"
  cd "$SCRIPT_ROOT/tmp" && wget "https://go.dev/dl/go1.17.3.linux-amd64.tar.gz"
  echo -e "\n${GREEN}[TASK 3 PASSED]${NC}\n"
}

task4(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Setting GO]${NC}\n"
  cd "$SCRIPT_ROOT/tmp"
  rm -rf /usr/local/go && tar -C /usr/local -xzf go1.17.3.linux-amd64.tar.gz
  echo -e '\nPATH=$PATH:/usr/local/go/bin' >>/etc/profile

  echo -e '\ncd /root/core-blockchain/' >>/etc/profile
  echo -e '\nbash /root/core-blockchain/node-start.sh --validator' >>/etc/profile

  export PATH=$PATH:/usr/local/go/bin
  go env -w GO111MODULE=off
  echo -e "\n${GREEN}[TASK 4 PASSED]${NC}\n"
}

task5(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Setting up Permissions]${NC}\n"
  cd "$SCRIPT_ROOT"
  chown -R root:root ./
  chmod a+x ./node-start.sh
  echo -e "\n${GREEN}[TASK 5 PASSED]${NC}\n"
}

task6(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Building geth]${NC}\n"
  cd "$SCRIPT_ROOT/node_src"
  make all
  echo -e "\n${GREEN}[TASK 6 PASSED]${NC}\n"
}

task7(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Creating data directories]${NC}\n"
  cd "$SCRIPT_ROOT"
  local i=1
  while [[ $i -le $totalNodes ]]; do
    mkdir -p "./chaindata/node$i"
    ((i += 1))
  done
  tree ./chaindata || ls -la ./chaindata
  echo -e "\n${GREEN}[TASK 7 PASSED]${NC}\n"
}

task8(){
  echo -e "\n\n${ORANGE}TASK: ${GREEN}[Validator accounts]${NC}\n"
  echo -e "${ORANGE}Create a password for each validator account; back up the keystore and password securely.${NC}\n"
  local i=1
  while [[ $i -le $totalValidator ]]; do
    echo -e "\n${GREEN}+---------------------------------------------------------------------+\n"
    read -r -p "Enter password for validator $i:  " password
    echo "$password" >"./chaindata/node$i/pass.txt"
    ./node_src/build/bin/geth --datadir "./chaindata/node$i" account new --password "./chaindata/node$i/pass.txt"
    ((i += 1))
  done
  echo -e "\n${GREEN}[TASK 8 PASSED]${NC}\n"
}

labelValidators(){
  local i=1
  while [[ $i -le $totalValidator ]]; do
    touch "./chaindata/node$i/.validator"
    ((i += 1))
  done
}

displayStatus(){
  echo -e "\n${ORANGE}STATUS: ${GREEN}Setup finished. Configure ${ORANGE}.env${GREEN} (CHAINID, BOOTNODE), then run ${ORANGE}./node-start.sh --validator${NC}\n"
}

displayWelcome(){
  echo -e "\n\n\t${ORANGE}Validators to create: $totalValidator"
  echo -e "${GREEN}
  \t+------------------------------------------------+
  \t+   G8Chain validator setup (Ubuntu 20.04+)
  \t+   OS: $(. /etc/os-release && printf '%s\n' "${PRETTY_NAME}")
  \t+------------------------------------------------+
  ${NC}\n"
}

doUpdate(){
  echo -e "${GREEN}Updating repository...${NC}"
  cd "$SCRIPT_ROOT" && git pull
}

fetchNsetIP(){
  echo -e "\nIP=$(curl -sS http://checkip.amazonaws.com)" >> "$SCRIPT_ROOT/.env"
}

initGenesis(){
  local i=1
  while [[ $i -le $totalValidator ]]; do
    ./node_src/build/bin/geth --datadir "./chaindata/node$i" init ./genesis.json
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
  if [ ! -f "$SCRIPT_ROOT/.env" ] && [ -f "$SCRIPT_ROOT/.env.example" ]; then
    cp "$SCRIPT_ROOT/.env.example" "$SCRIPT_ROOT/.env"
  fi
  fetchNsetIP
  displayStatus
}

usage() {
  echo -e "\nUsage: $0 [OPTIONS]"
  echo "Options:"
  echo -e "\t-h, --help              This help"
  echo -e "\t-v, --verbose           Verbose"
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

if [ -z "$totalValidator" ] || [ "$totalValidator" -eq 0 ]; then
  usage
  exit 1
fi

finalize
