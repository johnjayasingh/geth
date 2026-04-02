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
| **`BOOTNODE`** | ENR or `enode` from a peer **on testnet only** — not mainnet. |
| **`IP`** | Public IP of this host (same idea as mainnet). |

### 4. Run setup for testnet

```bash
./scripts/setup-validator.sh --network testnet --validator 1
```

Back up **`chaindata/testnet/node1/keystore/`** and **`pass.txt`**.

### 5. Start the testnet validator

```bash
./scripts/start-validator.sh --network testnet --validator
tmux attach -t testnet-n1
```

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

## License

See **`LICENSE`**.
