# Chain Reset & Admin Fee Routing Runbook

Last-ran: 2026-04-21 on testnet (chainId `18181`). Mainnet untouched.

This runbook covers (a) how admin fee-routing mode works, (b) how to wipe and
re-bootstrap a network using it, and (c) how *not* to break mainnet if you
later apply the same change there.

---

## 1. Mental model

**Admin fee-routing mode** is an opt-in `CongressConfig` flag. When
`congress.feeReceiver` is set in genesis:

- 100 % of every block's tx fees go directly to that address.
- **No system contracts** (`0xF000` Validators, `0xF001` Punish, `0xF002`
  Proposal, `0xF007` RewardPool) are initialised or upgraded.
- `redCoastBlock` / `sophonBlock` / `rewardPoolBlock` are ignored.
- Validator set is **fixed at genesis** via `extraData`. No vote-in/out, no
  slashing, no staking split.

Admin can spend the fees any time — burn by sending to `0x0`, withdraw by
sending to any address. They hold the EOA keystore.

When `feeReceiver` is **not** set (mainnet today), every existing code path
behaves as before.

---

## 2. Code changes (already merged)

| Commit | What it does |
|---|---|
| `6906175` | Adds `CongressConfig.FeeReceiver`; gates `initializeSystemContracts`, `tryPunishValidator`, `doSomethingAtEpoch`, `distributeBlockReward`, and `ApplySystemContractUpgrade` on it. Simplifies testnet `genesis.json`. |
| `117f63a` | Falls back to `snap.validators()` at epoch checkpoints when the contract at `0xF000` doesn't exist. |
| `cba6224` | Historical: repaired corrupted `0xF000` bytecode in testnet genesis. Not relevant post-reset; kept for audit. |

Mainnet `MainnetChainConfig` and `config/networks/mainnet/genesis.json` were
**not** touched. Validators/Punish/Proposal/RewardPool still run there.

---

## 3. Repeat the testnet reset

### 3.1 Prerequisites

Local:
- macOS / Linux workstation
- `git`, `ssh`, `scp`, `jq`, `python3`
- SSH key at `~/.ssh/g8chain` with access to all 4 testnet hosts

Each geth host (V1 `194.5.129.118`, V2 `194.5.129.237`, RPC `194.5.129.128`):
- `/usr/local/go` ≥ 1.18 (we use 1.21.5)
- Repo cloned at `/home/ubuntu/core-blockchain`
- `/data/geth/password.txt` exists and is non-empty
- Sudo available for `ubuntu`
- Ports 30303 (tcp/udp), 8545, 8546 open to peers / clients

Explorer host `194.5.129.88`:
- BlockScout 5.2.2-beta at `/home/blockscout-5.2.2-beta`
- Elixir 1.13, Erlang 24 at `/usr/local/lib/{elixir-1.13,erlang-24}`
- PostgreSQL with role `g8cadmin` (password `g8er342`) and database `blockscout`
- `systemd` unit `/etc/systemd/system/blockscout.service` (User=root)

### 3.2 Pick / generate the admin wallet

On the RPC node:

```bash
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.128 \
  "/home/ubuntu/core-blockchain/geth/build/bin/geth \
     --datadir /tmp/admin-key account new \
     --password <(echo 'CHOOSE_A_STRONG_PASSWORD')"
```

Note the printed address. **Download the keystore to a safe place** —
this is the only copy:

```bash
scp -i ~/.ssh/g8chain "ubuntu@194.5.129.128:/tmp/admin-key/keystore/UTC--*" ./admin-testnet-keystore.json
# After verifying the download:
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.128 "rm -rf /tmp/admin-key"
```

### 3.3 Generate validator keys (only if starting over)

Testnet currently uses:
- V1 signer `0x8E980df650e31Baa803de434df3Dc6A4fA23Bb66` (keystore on `194.5.129.118:/data/geth/keystore/`)
- V2 signer `0x705152DD5aE2A66583af1611Bdb6a399c08cEf0C` (keystore on `194.5.129.237:/data/geth/keystore/`)

To rotate, run `geth account new --password /data/geth/password.txt` on each
validator host, delete the old keystore, note the two new addresses.

### 3.4 Rewrite `config/networks/testnet/genesis.json`

The file is in git, so edit and push. Template:

```json
{
  "config": {
    "chainId": 18181,
    "homesteadBlock": 0, "eip150Block": 0,
    "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "eip155Block": 0, "eip158Block": 0,
    "byzantiumBlock": 0, "constantinopleBlock": 0, "petersburgBlock": 0,
    "istanbulBlock": 0, "muirGlacierBlock": 0,
    "berlinBlock": 0, "londonBlock": 0,
    "congress": {
      "period": 3,
      "epoch": 100,
      "feeReceiver": "0x<ADMIN_ADDRESS>"
    }
  },
  "nonce": "0x0FF9",
  "timestamp": "0x<HEX_UNIX_TIMESTAMP>",
  "extraData": "0x<VANITY><VAL1><VAL2>...<SIG>",
  "gasLimit": "0x174876E800",
  "difficulty": "0x1",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "number": "0x0",
  "gasUsed": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {
    "<admin-lowercase-no-0x>": {"balance": "0x33b2e3c9fd0803ce8000000"},
    "<v1-lowercase-no-0x>": {"balance": "0x52b7d2dcc80cd2e4000000"},
    "<v2-lowercase-no-0x>": {"balance": "0x52b7d2dcc80cd2e4000000"}
  }
}
```

**`extraData` format:**

```
0x
  0000...0000                         (32-byte vanity = 64 zeros)
  <validator1><validator2>...         (20 bytes each, ASCENDING hex order)
  0000...0000                         (65-byte seal = 130 zeros)
```

Generator snippet:

```python
import json
ADMIN, V1, V2 = "0x...", "0x...", "0x..."
vals = sorted([V1, V2], key=lambda a: a.lower())
extra = "0x" + "0"*64 + "".join(a[2:].lower() for a in vals) + "0"*130
# …then write genesis.json as above…
```

**Do not** include `redCoastBlock`, `sophonBlock`, `rewardPoolBlock`. Do not
put `0xF000` / `0xF001` / `0xF002` / `0xF007` in `alloc`. Admin fee mode
does not use them.

### 3.5 Commit, push, build on every node

```bash
git add config/networks/testnet/genesis.json
git commit -m "Reset testnet genesis for admin fee routing"
git push origin main
```

On each geth host in parallel:

```bash
for ip in 194.5.129.118 194.5.129.237 194.5.129.128; do
  (ssh -i ~/.ssh/g8chain ubuntu@$ip "
     cd /home/ubuntu/core-blockchain &&
     git fetch origin &&
     git reset --hard origin/main &&
     PATH=/usr/local/go/bin:\$PATH make -C geth geth") &
done
wait
```

### 3.6 Wipe chaindata and re-init

For each geth host (replace `<addr>` with the signer address on that host):

```bash
ssh -i ~/.ssh/g8chain ubuntu@<host> "
  sudo systemctl stop geth 2>/dev/null || true
  sudo pkill -9 geth 2>/dev/null || true
  sleep 2
  sudo rm -rf /data/geth/geth /data/geth/static-nodes.json
  sudo chown -R ubuntu:ubuntu /data/geth
"
scp -i ~/.ssh/g8chain config/networks/testnet/genesis.json ubuntu@<host>:/tmp/genesis.json
ssh -i ~/.ssh/g8chain ubuntu@<host> "
  /home/ubuntu/core-blockchain/geth/build/bin/geth --datadir /data/geth init /tmp/genesis.json
"
```

> **Critical:** geth stores its DB under `/data/geth/geth/`, not
> `/data/geth/`. Remove the nested directory, not just the parent.

### 3.7 Write the systemd unit

Validators (fill `<addr>` with that host's signer):

```ini
[Unit]
Description=G8Chain Testnet Validator Node
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/home/ubuntu/core-blockchain/geth/build/bin/geth \
  --datadir /data/geth \
  --networkid 18181 \
  --port 30303 \
  --mine \
  --miner.etherbase <addr> \
  --unlock <addr> \
  --password /data/geth/password.txt \
  --allow-insecure-unlock \
  --http --http.addr 0.0.0.0 --http.port 8545 \
  --http.api eth,net,web3,personal,congress \
  --http.corsdomain "*" \
  --ws --ws.addr 0.0.0.0 --ws.port 8546 \
  --ws.api eth,net,web3,personal,congress \
  --ws.origins "*" \
  --maxpeers 50 --syncmode full --gcmode archive
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

RPC (no `--mine`, wider API, bigger cache):

```ini
ExecStart=/home/ubuntu/core-blockchain/geth/build/bin/geth \
  --datadir /data/geth --networkid 18181 --port 30303 \
  --http --http.addr 0.0.0.0 --http.port 8545 \
  --http.api eth,net,web3,txpool,congress \
  --http.corsdomain "*" --http.vhosts "*" \
  --ws --ws.addr 0.0.0.0 --ws.port 8546 \
  --ws.api eth,net,web3,txpool,congress --ws.origins "*" \
  --maxpeers 100 --syncmode full --gcmode archive \
  --cache 4096 --txpool.globalslots 20000 --txpool.accountslots 128
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now geth
```

### 3.8 Connect peers

After each fresh start or restart, peers don't auto-rediscover. Either:

**One-shot (disappears on restart):**

```bash
V1_ENODE=$(ssh -i ~/.ssh/g8chain ubuntu@194.5.129.118 \
  '/home/ubuntu/core-blockchain/geth/build/bin/geth attach /data/geth/geth.ipc --exec "admin.nodeInfo.enode"' \
  | tr -d '"' | sed "s/127.0.0.1/194.5.129.118/")
V2_ENODE=$(ssh -i ~/.ssh/g8chain ubuntu@194.5.129.237 \
  '/home/ubuntu/core-blockchain/geth/build/bin/geth attach /data/geth/geth.ipc --exec "admin.nodeInfo.enode"' \
  | tr -d '"' | sed "s/127.0.0.1/194.5.129.237/")

for ip in 194.5.129.237 194.5.129.128; do
  ssh -i ~/.ssh/g8chain ubuntu@$ip \
    "/home/ubuntu/core-blockchain/geth/build/bin/geth attach /data/geth/geth.ipc --exec 'admin.addPeer(\"$V1_ENODE\")'"
done
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.128 \
  "/home/ubuntu/core-blockchain/geth/build/bin/geth attach /data/geth/geth.ipc --exec 'admin.addPeer(\"$V2_ENODE\")'"
```

**Persistent (survives restart):** write `/data/geth/geth/static-nodes.json`
on each host with the peer enodes *before* starting geth:

```json
[
  "enode://<v1-id>@194.5.129.118:30303",
  "enode://<v2-id>@194.5.129.237:30303"
]
```

### 3.9 Verify

```bash
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.128 \
  '/home/ubuntu/core-blockchain/geth/build/bin/geth attach /data/geth/geth.ipc --exec \
   "JSON.stringify({block: eth.blockNumber, chainId: eth.chainId(), peers: net.peerCount})"'
```

Expected after ~10 s: `{"block":>0,"chainId":"0x4705","peers":2}`. Check
again 30 s later and confirm the block number increased.

Fee routing smoke test:

```bash
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.118 \
  '/home/ubuntu/core-blockchain/geth/build/bin/geth attach /data/geth/geth.ipc --exec "
     var admin = \"0x<ADMIN_ADDRESS>\";
     var pre = eth.getBalance(admin);
     eth.sendTransaction({from: eth.accounts[0], to: \"0x000000000000000000000000000000000000dEaD\",
                          value: web3.toWei(1, \"ether\"), gasPrice: web3.toWei(1, \"gwei\")});
     JSON.stringify({pre: pre.toString()})"'
# wait ~6 s, check admin balance — it should grow by gasUsed * gasPrice
```

### 3.10 Reset the explorer

```bash
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.88 "sudo systemctl stop blockscout"

# Drop + recreate DB; grant the public schema to g8cadmin (PG15+ default
# revokes public-schema CREATE from other roles).
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.88 "sudo -u postgres psql <<SQL
DROP DATABASE IF EXISTS blockscout;
CREATE DATABASE blockscout;
\c blockscout
CREATE EXTENSION IF NOT EXISTS citext;
ALTER DATABASE blockscout OWNER TO g8cadmin;
ALTER SCHEMA public OWNER TO g8cadmin;
GRANT ALL ON SCHEMA public TO g8cadmin;
GRANT ALL ON DATABASE blockscout TO g8cadmin;
SQL"

# Update CHAIN_ID in the systemd unit if it's wrong
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.88 \
  "sudo sed -i 's/CHAIN_ID=[0-9]*/CHAIN_ID=18181/' /etc/systemd/system/blockscout.service && sudo systemctl daemon-reload"

# Compile + migrate (as root, with full elixir env)
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.88 'sudo bash -c "
  set -e
  cd /home/blockscout-5.2.2-beta
  export PATH=/usr/local/lib/elixir-1.13/bin:/usr/local/lib/erlang-24/bin:\$PATH
  export ROOTDIR=/usr/local/lib/erlang-24
  export MIX_ENV=prod
  export DATABASE_URL=postgresql://g8cadmin:g8er342@localhost:5432/blockscout
  export ECTO_USE_SSL=false
  mix local.hex --force --if-missing
  mix local.rebar --force --if-missing
  mix deps.get
  mix deps.compile
  mix ecto.migrate
"'

ssh -i ~/.ssh/g8chain ubuntu@194.5.129.88 "sudo systemctl start blockscout"
```

Verify: `curl -I http://194.5.129.88:4000/` should return 200; indexer
catches up in a few seconds. Tail `logs/prod/indexer.log` for errors.

---

## 4. Applying to mainnet — **read before doing**

Mainnet has live state. A genesis rewrite **destroys all balances, contracts
and history**. Do not run the testnet reset procedure against mainnet.

If you genuinely want mainnet to adopt admin fee-routing, the choices are:

1. **Fresh mainnet fork (nuclear):** pick a block height `N` from
   mainnet; export the `alloc` at that block; paste into a new mainnet
   genesis that also sets `congress.feeReceiver` and drops the fork
   blocks; coordinate all three mainnet validators to stop, re-init with
   the new genesis, and restart. All post-`N` history is discarded.
   Everyone holding EGC is credited their balance at `N`. Requires
   announcement + downtime.

2. **Activate at a future block without reset:** would require a new
   code path that toggles `feeReceiver` at a specified block number
   (not what commit `6906175` does). This is a code change plus a
   coordinated hard fork. Scope it as its own project — do not improvise
   it during an operational window.

3. **Leave mainnet as-is** (current state). Recommended unless you have
   a business reason to change it.

Under no circumstances should you:

- `rm -rf` mainnet `/data/geth/geth`. You lose all balances.
- Push commit `6906175`-style changes to mainnet `ChainConfig` without
  also rewriting mainnet genesis — the `FeeReceiver` field is read from
  the *stored* genesis, so changing only `params/config.go` does nothing
  at runtime.

---

## 5. Admin operations

The admin wallet is an ordinary EOA.

**Withdraw:**

```bash
ssh -i ~/.ssh/g8chain ubuntu@194.5.129.128 \
  '/home/ubuntu/core-blockchain/geth/build/bin/geth attach /data/geth/geth.ipc --exec "
     personal.unlockAccount(\"0x<ADMIN_ADDR>\", \"<PASSWORD>\", 300);
     eth.sendTransaction({from: \"0x<ADMIN_ADDR>\", to: \"0x<RECIPIENT>\", value: web3.toWei(<N>, \"ether\")})"'
```

(The admin keystore must be present on whichever geth node you attach to.
We left it on the RPC node after generation. Move or copy it wherever
you prefer.)

**Burn:** same call with `to: "0x0000000000000000000000000000000000000000"`.

**Balance:** `eth.getBalance("0x<ADMIN_ADDR>")`.

---

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Fatal: database contains incompatible genesis` on init | Old chaindata not fully wiped | `sudo rm -rf /data/geth/geth` (nested `geth/`, not just parent) |
| `unsupported fork ordering` on init | redCoast/sophon/rewardPool present without proper sequencing | Admin-fee mode should not set any of them — remove from genesis |
| `invalid opcode: opcode 0xde` in `FinalizeAndAssemble` | Corrupted system-contract bytecode in alloc | Remove system contracts from alloc for admin-fee mode |
| `abi: length larger than int64: …` upgrade error at block = `redCoastBlock` | F000 doesn't match the V0 ABI the V1 upgrade expects | Admin-fee mode gates this; make sure `feeReceiver` is set in the genesis the node booted from |
| Chain halts at the block before an epoch boundary with `Failed to prepare header for mining err="abi: attempting to unmarshall an empty string"` | `Prepare()` called `getTopValidators` on a non-existent F000 | Ensure node is on commit ≥ `117f63a` |
| `peers: 0` after restart | No static peer list | Write `/data/geth/geth/static-nodes.json` or run the `admin.addPeer` one-shot |
| BlockScout `permission denied for schema public` during migrate | PG15+ default schema perms | `ALTER SCHEMA public OWNER TO g8cadmin; GRANT ALL ON SCHEMA public TO g8cadmin;` |
| BlockScout indexer frozen, UI shows stale blocks | Chain was actually halted (check `eth.blockNumber` on RPC); indexer catches up once chain advances | Resolve the chain halt; indexer has no issue |

---

## 7. Files & commits to reference

- [config/networks/testnet/genesis.json](../config/networks/testnet/genesis.json) — canonical testnet genesis
- [geth/params/config.go](../geth/params/config.go) — `CongressConfig.FeeReceiver` + testnet `ChainID`
- [geth/consensus/congress/congress.go](../geth/consensus/congress/congress.go) — gated paths (search `adminFeeMode`, `FeeReceiver`)
- `scripts/reset-testnet.sh` — **not in git** (the `scripts/` folder is gitignored). If you want it version-controlled, edit `.gitignore` to unblock it or move it under `docs/` or similar.

---

## 8. What's deliberately **not** covered

- Multi-sig admin contracts — current admin is a plain EOA. Upgrade to a
  contract if the private-key-loss blast radius becomes unacceptable.
- Slashing — there is none in admin-fee mode. A misbehaving validator
  just wastes its turn; consensus tolerates one out of two offline
  briefly but halts if both are down.
- Validator rotation — to swap a signer, regenerate genesis with the new
  `extraData` and redo the reset procedure. Running-chain rotation
  requires the validators contract, which this mode deliberately omits.
