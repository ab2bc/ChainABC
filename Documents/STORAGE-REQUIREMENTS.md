# Storage Requirements for AQY Network Nodes

## Overview

This document outlines storage requirements for running AQY blockchain nodes based on observed growth rates from a 15-node test deployment.

## Current Observations (Test Network)

| Metric | Value |
|--------|-------|
| Network started | Empty genesis |
| Checkpoints after 45 min | ~8,800 |
| Checkpoint rate | ~195/minute (~280,000/day) |
| Block height after 45 min | ~70,000 |

## Storage Breakdown Per Node Type

### Genesis Validator (G) - ~186 MB after 8,800 checkpoints

```
AQY-G1 (186 MB):
├── data/consensus/    99 MB  ← Mysticeti consensus WAL/logs
├── data/db/live/      89 MB
│   ├── store/         74 MB  ← RocksDB: transactions, objects, effects
│   ├── checkpoints/   16 MB  ← Certified checkpoint data
│   └── epochs/       128 KB  ← Epoch metadata
├── genesis/          452 KB  ← genesis.blob
└── config/            32 KB  ← validator.yaml, keys
```

### Post-Genesis Validator (P) - ~100 MB
- No consensus production (just syncing)
- Smaller consensus directory
- Same db structure as G

### Fullnode (F) - ~113 MB
- No consensus directory
- Only syncs checkpoints and objects
- Stores transaction effects

## Growth Rate Calculation

### Per Checkpoint Growth

| Node Type | Growth/Checkpoint |
|-----------|-------------------|
| G validator | ~27 KB |
| P validator | ~11 KB |
| F fullnode | ~13 KB |

### Daily Growth (Empty Blocks, No Transactions)

| Component | Daily Growth |
|-----------|-------------|
| 5× G validators | 5 × 7.5 GB = **37.5 GB/day** |
| 5× P validators | 5 × 3 GB = **15 GB/day** |
| 5× F fullnodes | 5 × 3.6 GB = **18 GB/day** |
| **15-Node Total** | **~70 GB/day** |

## Storage Recommendations

### By Deployment Duration

| Duration | 15-Node Storage | Recommendation |
|----------|-----------------|----------------|
| 1 day | ~70 GB | 256 GB SSD |
| 1 week | ~500 GB | 1 TB SSD |
| 1 month | ~2 TB | 4 TB SSD |
| 3 months | ~6 TB | 8 TB SSD |
| 1 year | ~25 TB | Enterprise NVMe array |

### By Deployment Type

| Scenario | Nodes | Daily Growth | 1-Month Minimum |
|----------|-------|--------------|-----------------|
| Minimal test | 5 G only | ~37 GB/day | 2 TB |
| With fullnode | 5 G + 1 F | ~41 GB/day | 2 TB |
| Full 15-node | 5 G + 5 P + 5 F | ~70 GB/day | 4 TB |
| Production (per node) | 1 validator | ~7.5 GB/day | 500 GB |

### Production Recommendations

1. **Validators (G)**
   - Minimum: 1 TB NVMe SSD
   - Recommended: 2 TB NVMe SSD
   - IOPS: 50,000+ read, 25,000+ write

2. **Fullnodes (F)**
   - Minimum: 500 GB NVMe SSD
   - Recommended: 1 TB NVMe SSD

3. **Multi-Node Server**
   - Separate drives per node recommended
   - Or: Fast NVMe array with 100,000+ IOPS
   - RAID-0 for performance, external backups

## What Consumes Storage

### Consensus Directory (`data/consensus/`)
- Mysticeti consensus protocol logs
- Vote certificates and leader schedules
- Write-Ahead Log (WAL) for crash recovery
- **Only on validators**, not fullnodes

### Store (`data/db/live/store/`)
- **Objects**: Sui Move objects and their versions
- **Transactions**: Transaction digests and effects
- **Events**: Emitted Move events
- **Markers**: Object ownership tracking

### Checkpoints (`data/db/live/checkpoints/`)
- Certified checkpoint summaries
- State commitments
- Checkpoint contents (transactions, effects)

### Epochs (`data/db/live/epochs/`)
- Epoch metadata (small, ~128 KB)
- Committee information
- Protocol config per epoch

## Pruning Options

To reduce storage, configure pruning in `validator.yaml` or `fullnode.yaml`:

```yaml
authority-store-pruning-config:
  # Keep only last N checkpoints
  num-latest-epoch-dbs-to-retain: 3
  epoch-db-pruning-period-secs: 3600
  
  # Object pruning
  num-epochs-to-retain: 2
  num-epochs-to-retain-for-checkpoints: 2
```

### Pruning Trade-offs

| Setting | Effect | Use Case |
|---------|--------|----------|
| Keep all | Full history | Archive nodes |
| Last 3 epochs | ~1 week history | Standard validators |
| Last 1 epoch | Minimal storage | Resource-constrained |

## Monitoring Commands

```bash
# Check total usage per node
du -sh nodes/AQY-*/

# Check breakdown for one node
du -sh nodes/AQY-G1/data/*/

# Watch growth over time
watch -n 60 'du -sh nodes/AQY-G1'

# Check available disk space
df -h /path/to/nodes
```

## Important Notes

1. **Empty blocks still grow**: Sui produces blocks continuously even with no transactions
2. **Transaction load matters**: Real usage can increase growth 2-5×
3. **Objects accumulate**: Each new object version is stored
4. **SSDs required**: HDDs cannot keep up with IOPS requirements
5. **Plan for pruning**: Configure before disk fills up

## Quick Reference

| Question | Answer |
|----------|--------|
| How long on 500 GB? | ~7 days (15 nodes) |
| How long on 1 TB? | ~14 days (15 nodes) |
| Minimum for 1 validator? | 256 GB (1 week test) |
| Production validator? | 2 TB NVMe minimum |
| Growth with transactions? | 2-5× higher than empty |

## Hardware Specifications

### Recommended Server for 15-Node Deployment

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 8 cores | 16+ cores (AMD EPYC / Intel Xeon) |
| **RAM** | 32 GB | 64+ GB |
| **Storage** | 2 TB NVMe | 4+ TB NVMe (or RAID-0 array) |
| **Network** | 1 Gbps | 10 Gbps |
| **OS** | Ubuntu 22.04 LTS | Ubuntu 22.04/24.04 LTS |

### Storage Configuration Options

| Configuration | Capacity | IOPS | Use Case |
|---------------|----------|------|----------|
| Single NVMe | 2-4 TB | 100K+ | Development/Testing |
| 2× NVMe RAID-0 | 4-8 TB | 200K+ | Small production |
| 4× NVMe RAID-0 | 8-16 TB | 400K+ | Full production |
| Enterprise SAN | 20+ TB | 500K+ | Long-term archive |

### Per-Node Resource Allocation (15 nodes on 1 server)

| Resource | Per Node | Total (15 nodes) |
|----------|----------|------------------|
| CPU cores | 0.5-1 | 8-16 cores |
| RAM | 2-4 GB | 32-64 GB |
| Disk IOPS | 3K-5K | 50K-75K |
| Network | 50 Mbps | 750 Mbps |

### Cloud Instance Equivalents

| Provider | Instance Type | Specs | Monthly Cost (approx) |
|----------|---------------|-------|----------------------|
| AWS | i3.2xlarge | 8 vCPU, 61 GB, 1.9 TB NVMe | ~$450 |
| GCP | n2-highmem-8 + SSD | 8 vCPU, 64 GB, 2 TB SSD | ~$500 |
| Azure | L8s_v3 | 8 vCPU, 64 GB, 1.9 TB NVMe | ~$480 |
| Hetzner | AX102 | 16 cores, 128 GB, 2× 1.92 TB NVMe | ~$150 |

**Note**: For production, consider running validators on separate physical machines for fault tolerance.

## Adding Post-Genesis Validators (P Nodes) to Committee

Post-genesis validators (P nodes) start as non-committee nodes that sync checkpoints but don't participate in consensus. To become active committee members, they must be staked.

### Prerequisites

1. P node is running and synced (shows checkpoints in status)
2. Validator info is registered on-chain
3. Sufficient AQY tokens for staking (minimum stake threshold)

### Method 1: Self-Staking via CLI

```bash
# Get the validator's operation cap object ID
sui client objects --json | jq '.[] | select(.type | contains("ValidatorOperationCap"))'

# Request to join the committee (requires operation cap)
sui client call \
  --package 0x3 \
  --module sui_system \
  --function request_add_validator \
  --args <system_state_id> <validator_cap_id> \
  --gas-budget 100000000

# Stake tokens to the validator
sui client call \
  --package 0x3 \
  --module sui_system \
  --function request_add_stake \
  --args <system_state_id> <coin_id> <validator_address> \
  --gas-budget 100000000
```

### Method 2: Using the AManager UI

1. Open AManager application
2. Navigate to **Validators** → **Post-Genesis**
3. Select the P node (e.g., AQY-P1)
4. Click **"Request Join Committee"**
5. Enter stake amount (minimum: 30,000,000 MIST = 0.03 AQY for testnet)
6. Confirm transaction

### Method 3: Programmatic Staking Script

```bash
#!/bin/bash
# stake-validator.sh - Stake a P node to join committee

VALIDATOR_ADDRESS="$1"
STAKE_AMOUNT="$2"  # In MIST (1 AQY = 1,000,000,000 MIST)

# Get system state
SYSTEM_STATE=$(sui client object 0x5 --json | jq -r '.objectId')

# Find a coin with sufficient balance
COIN=$(sui client gas --json | jq -r ".[0].gasCoinId")

# Request stake
sui client call \
  --package 0x3 \
  --module sui_system \
  --function request_add_stake \
  --args "$SYSTEM_STATE" "$COIN" "$VALIDATOR_ADDRESS" \
  --gas-budget 100000000
```

### Staking Timeline

| Event | When |
|-------|------|
| Stake transaction submitted | Immediate |
| Stake becomes "pending" | Next transaction |
| Validator joins committee | **Next epoch** |
| Validator starts producing blocks | After epoch change |

### Epoch Duration

- **Testnet**: Epochs are typically 1 hour
- **Mainnet**: Epochs are 24 hours
- Validator joins committee at the **start of the next epoch** after staking

### Minimum Stake Requirements

| Network | Minimum Stake |
|---------|---------------|
| Local testnet | 1 MIST (configurable) |
| Public testnet | 30,000 AQY |
| Mainnet | 30,000,000 AQY |

### Checking Validator Status

```bash
# Check if validator is in pending list
sui client call \
  --package 0x3 \
  --module sui_system \
  --function get_pending_validators \
  --args 0x5 \
  --gas-budget 10000000

# Check active validators
sui client call \
  --package 0x3 \
  --module sui_system \
  --function get_active_validators \
  --args 0x5 \
  --gas-budget 10000000
```

### After Joining Committee

Once the P node joins the committee:
- **Committee column**: Changes from `-` to `yes`
- **Height column**: Shows block height (starts producing blocks)
- **Peers**: Should increase as other validators connect
- **Storage growth**: Increases to match G validators (~7.5 GB/day)

### Quick Reference: P Node → Committee Member

```
1. Deploy P node           → Status: running, Committee: -
2. Register validator      → On-chain validator info created
3. Stake tokens            → Stake becomes pending
4. Wait for epoch change   → ~1 hour (testnet) / ~24 hours (mainnet)
5. P node in committee     → Committee: yes, Height: <number>
```
