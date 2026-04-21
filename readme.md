# G8Chain — validator node

Fork of go-ethereum used as the G8Chain execution client, plus **genesis** files and **scripts** to run **mainnet** and **testnet** validators on Ubuntu from one repository.

## Layout

| Path | Purpose |
|------|---------|
| **`geth/`** | Client source — `make all` → `geth/build/bin/geth`. |
| **`config/networks/mainnet/genesis.json`** | Mainnet genesis. |
| **`config/networks/testnet/genesis.json`** | Testnet genesis (replace with your real testnet genesis if it differs). |
| **`config/networks/<net>/env.example`** | Template for **`.env.mainnet`** / **`.env.testnet`** at repo root. |
| **`scripts/setup-validator.sh`** | Install Go, build geth, create accounts, `geth init` for the chosen network. |
| **`scripts/start-validator.sh`** | Start validators in tmux for **one** network at a time. |
| **`scripts/reset-chaindata.sh`** | Wipe **`chaindata/<network>/node*`** after confirmation. |
| **`chaindata/mainnet/`**, **`chaindata/testnet/`** | Datadirs per network (`node1`, …). Not committed. |

Env files at the repo root:

- **`.env.mainnet`** — `CHAINID`, `BOOTNODE`, `IP` for mainnet.
- **`.env.testnet`** — same for testnet.

Setup copies the matching **`config/networks/<net>/env.example`** if **`.env.<net>`** is missing, then appends your public **IP**.

**Ports:** mainnet validators use **32669, 32670, …** Testnet uses **32769, 32770, …** so both networks can run on one machine without P2P port clashes.

### Bootnode

A **bootnode** is the first peer your node talks to so it can **discover the rest of the network** (via devp2p). You set it as **`BOOTNODE`** in **`.env.mainnet`** or **`.env.testnet`**.

Use an **ENR** (`enr:-…`) or **`enode://…`** URL from a node that is already running on that network (often another validator or a dedicated bootnode). Mainnet and testnet each need their **own** bootnode list; do not point testnet at mainnet peers.

Repo root includes **`.env.mainnet`** and **`.env.testnet`** (gitignored by default — copy from **`config/networks/*/env.example`** if you start fresh).

## Requirements

- **OS:** Ubuntu 20.04+ (64-bit)
- **RAM:** 8 GB minimum (32 GB recommended)
- **Disk:** SSD recommended
- **Firewall:** allow P2P ports you use (see above)

---

## Step-by-step: mainnet validator

Do these on the **Ubuntu server** that will run the validator (often as `root`).

### 1. Prepare the server

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git tar curl wget build-essential tree tmux
```

Open inbound **TCP and UDP** for P2P (defaults: **32669** for the first mainnet validator, then 32670, … if you add more nodes on the same host).

### 2. Clone this repository

```bash
sudo -i
git clone <your-repo-url> /root/core-blockchain
cd /root/core-blockchain
chmod +x scripts/*.sh
```

Use your real clone URL and path; the rest of this guide assumes **`/root/core-blockchain`**.

### 3. Configure mainnet env (before or after setup)

Ensure **`.env.mainnet`** exists at the repo root. If it does not:

```bash
cp config/networks/mainnet/env.example .env.mainnet
```

Edit **`.env.mainnet`**:

| Variable | What to set |
|----------|-------------|
| **`CHAINID`** | Must match **`config/networks/mainnet/genesis.json`** (e.g. `17171`). |
| **`BOOTNODE`** | ENR (`enr:-…`) or `enode://…` of a peer **already on mainnet** (another validator or bootnode). |
| **`IP`** | This machine’s **public** IPv4 (used for `--nat extip`). You can set it manually or let **`setup-validator.sh`** append it when it runs. |

### 4. Run setup for mainnet

Creates Go toolchain (if needed), builds **geth**, creates **`chaindata/mainnet/node1`**, validator account, runs **`geth init`** with mainnet genesis, marks the node as a validator.

```bash
./scripts/setup-validator.sh --network mainnet --validator 1
```

Follow prompts (e.g. validator account password). **Back up** **`chaindata/mainnet/node1/keystore/`** and **`pass.txt`** securely.

If **`.env.mainnet`** was missing, setup copies **`config/networks/mainnet/env.example`** and may append **`IP`**. Re-open **`.env.mainnet`** and confirm **`BOOTNODE`** and **`CHAINID`**.

### 5. Start the mainnet validator

```bash
./scripts/start-validator.sh --network mainnet --validator
```

### 6. Attach to the console

```bash
tmux attach -t mainnet-n1
```

Detach without stopping the node: **Ctrl+b**, then **d**.

List tmux sessions: `tmux ls`.

---

## Step-by-step: testnet validator

Testnet uses **separate** genesis, env, chain data, and P2P ports (**32769+** on the same host so it does not clash with mainnet).

### 1. Same server prep as mainnet

If this is a **new** machine only for testnet, repeat **mainnet §1–2** (apt, clone, `chmod +x scripts/*.sh`).

### 2. Testnet genesis

If your testnet has its **own** genesis (different alloc / chain id), replace:

`config/networks/testnet/genesis.json`

with the file your team uses for testnet, and make **`CHAINID`** in **`.env.testnet`** match that genesis.

### 3. Configure testnet env

```bash
cp config/networks/testnet/env.example .env.testnet
```

Edit **`.env.testnet`**:

| Variable | What to set |
|----------|-------------|
| **`CHAINID`** | Must match **`config/networks/testnet/genesis.json`**. |
| **`BOOTNODE`** | See **two-node flow** below: empty for validator 1 only, then node 1’s enode for validator 2. |
| **`IP`** | Public IP for `--nat extip` (optional; scripts use `--nat any` if empty). |

### 4. Build geth and create validators (one or two nodes)

**Single testnet validator** (joins an existing testnet that already has peers):

```bash
./scripts/setup-validator.sh --network testnet --validator 1
# set BOOTNODE to your network’s boot ENR/enode in .env.testnet, then:
./scripts/start-validator.sh --network testnet --validator
```

**Two validators on a fresh testnet** (node 1 acts as the seed peer / “bootnode” for node 2):

1. **Build + two datadirs**

   ```bash
   ./scripts/setup-validator.sh --network testnet --validator 2
   ```

2. **Env — phase A** — In **`.env.testnet`**, set **`CHAINID`** to match testnet genesis. Leave **`BOOTNODE`** **empty** (or `""`) so validator **1** can start without an upstream bootnode.

3. **Start validator 1 only**

   ```bash
   ./scripts/start-validator.sh --network testnet --validator --max-nodes 1
   tmux attach -t testnet-n1
   ```

   Wait until it is running, then detach (**Ctrl+b**, **d**).

4. **Get node 1’s enode** (needs IPC while node 1 is up)

   ```bash
   ./scripts/print-enode.sh --network testnet --node 1
   ```

5. **Env — phase B** — Put that **`enode://...`** line into **`BOOTNODE=`** in **`.env.testnet`**. If the enode shows `127.0.0.1` and the second validator runs on **another machine**, replace the IP with validator 1’s **reachable** address and ensure P2P port **32769** (first testnet validator) is allowed through the firewall.

6. **Start validator 2** (session **`testnet-n2`**; node 1’s tmux session is left running)

   ```bash
   ./scripts/start-validator.sh --network testnet --validator --max-nodes 2
   tmux attach -t testnet-n2
   ```

`--max-nodes N` starts only **`node1`…`nodeN`**. Already-running tmux sessions are skipped, so you can run step 3, then step 6, without duplicating node 1.

Back up **`chaindata/testnet/node*/keystore/`** and **`pass.txt`** after setup.

---

## Same machine: mainnet + testnet

You can run **both** on one server: separate **`chaindata/mainnet`** and **`chaindata/testnet`**, separate **`.env.mainnet`** / **`.env.testnet`**, and non-overlapping ports (mainnet **32669+**, testnet **32769+**).

Start each when ready:

```bash
./scripts/start-validator.sh --network mainnet --validator
./scripts/start-validator.sh --network testnet --validator
```

Use **`tmux ls`** to see **`mainnet-n1`**, **`testnet-n1`**, etc.

---

## Build geth only

```bash
cd geth && make all
```

## Initialize a datadir manually

```bash
./geth/build/bin/geth --datadir /path/to/datadir init ./config/networks/mainnet/genesis.json
# or
./geth/build/bin/geth --datadir /path/to/datadir init ./config/networks/testnet/genesis.json
```

## Reset local chain data (one network)

```bash
./scripts/reset-chaindata.sh --network mainnet
# or
./scripts/reset-chaindata.sh --network testnet
```

## Keys

Keystores and **`pass.txt`** live under **`chaindata/<network>/node<N>/`**. Do not commit keys or **`.env.*`**. See **`.gitignore`**.

---

## Current testnet infrastructure

| Role | IP | Domain | Notes |
|------|----|--------|-------|
| **Validator 0** (bootnode) | 194.5.129.120 | — | Also serves RPC on port 80 |
| **Validator 1** | 194.5.129.118 | — | |
| **Validator 2** | 194.5.129.237 | — | |
| **RPC Node** | 194.5.129.128 | `https://testnet-rpc.g8chain.com` | HTTP :8545, WS :8546, nginx+SSL on :443 |
| **Block Explorer** | 194.5.129.88 | `https://testnet-explorer.g8chain.com` | Blockscout on :4000, nginx+SSL on :443 |

| Parameter | Value |
|-----------|-------|
| **Chain ID** | `18181` |
| **Network ID** | `18181` |
| **Consensus** | Congress (DPoS), 3 s blocks, epoch 100 |
| **Genesis** | `config/networks/testnet/genesis.json` |
| **Bootnode enode** | `enode://14b32b2c89b095aeaa75438e903c1150e90c10c1b13ca2fc3adead0e2fd3a3d0c13093d4e41268f16a08e2f4d29fdff3fc712ec79b8e1b125487284d9c014230@194.5.129.120:32669` |

### MetaMask / wallet config

| Field | Value |
|-------|-------|
| Network Name | G8Chain Testnet |
| RPC URL | `https://testnet-rpc.g8chain.com` |
| Chain ID | `18181` |
| Currency Symbol | G8C |
| Block Explorer | `https://testnet-explorer.g8chain.com` |

---

## Adding a new testnet validator

If the setup scripts don't fit your environment or you want full control, follow these manual steps on an **Ubuntu 20.04+** server.

### 1. Install dependencies

```bash
sudo apt update && sudo apt install -y build-essential git wget tmux
```

### 2. Install Go 1.17.3

```bash
cd /tmp && wget https://go.dev/dl/go1.17.3.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.17.3.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
go env -w GO111MODULE=off
```

### 3. Clone and build

```bash
git clone https://github.com/johnjayasingh/g8chain-geth.git ~/core-blockchain
cd ~/core-blockchain/geth && make geth
```

Binary lands at `geth/build/bin/geth`.

### 4. Create a validator account

```bash
cd ~/core-blockchain
mkdir -p chaindata/node1/keystore
./geth/build/bin/geth --datadir ./chaindata/node1 account new
```

Save the password in `chaindata/node1/pass.txt` and **back up the keystore directory**.

> **Important:** the new validator address must be added to the genesis `extraData` field and all nodes must re-init with the updated genesis for the validator to be authorized to seal blocks.

### 5. Initialize genesis

```bash
./geth/build/bin/geth --datadir ./chaindata/node1 init ./config/networks/testnet/genesis.json
```

### 6. Start the validator

Replace `<YOUR_IP>` with the server's public IP and `<BOOTNODE>` with the enode from the table above.

```bash
tmux new-session -d -s validator
tmux send-keys -t validator './geth/build/bin/geth \
  --datadir ./chaindata/node1 \
  --networkid 18181 \
  --port 32669 \
  --mine \
  --unlock 0 \
  --allow-insecure-unlock \
  --password ./chaindata/node1/pass.txt \
  --syncmode full \
  --gcmode archive \
  --bootnodes "<BOOTNODE>" \
  --nat extip:<YOUR_IP> \
  --verbosity 2' Enter
```

### 7. Verify

```bash
tmux attach -t validator
# Look for "Imported new chain segment" and increasing block numbers
# Detach: Ctrl+b, then d
```

### Adding the validator to the active set

A new validator address must appear in the genesis `extraData` to be allowed to seal. To add one:

1. Stop **all** nodes on the network.
2. Edit `config/networks/testnet/genesis.json` — in `extraData`, append the new 20-byte address (lowercase, no `0x`) between the 32-byte vanity prefix and the 65-byte signature suffix.
3. Delete `chaindata/node*/geth/` on every node.
4. Re-run `geth init` with the updated genesis on every node.
5. Restart all nodes.

The maximum active validator count is **21** (Congress consensus limit).

---

## Adding a testnet RPC node (non-mining)

Same as above but skip `--mine --unlock 0 --password ...` and add HTTP/WS flags:

```bash
tmux new-session -d -s rpc
tmux send-keys -t rpc 'sudo ./geth/build/bin/geth \
  --datadir ./chaindata/node1 \
  --networkid 18181 \
  --port 32669 \
  --syncmode full \
  --gcmode archive \
  --http --http.addr 0.0.0.0 --http.port 8545 \
  --http.api eth,net,web3,txpool,debug \
  --http.corsdomain "*" --http.vhosts "*" \
  --ws --ws.addr 0.0.0.0 --ws.port 8546 \
  --ws.api eth,net,web3,txpool --ws.origins "*" \
  --bootnodes "<BOOTNODE>" \
  --nat extip:<YOUR_IP> \
  --verbosity 2' Enter
```

Use `sudo` if binding to port 80/443, or put nginx in front (recommended).

---

## License

See **`LICENSE`**.
