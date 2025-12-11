# Post-Genesis Validator Staking Process

## Overview

This document describes the complete process for adding validators to the network after genesis has been created and the network is running.

## Prerequisites

1. Genesis network is running with genesis validators (G nodes)
2. Post-genesis validator nodes (P nodes) are deployed and synced
3. Treasury account has sufficient tokens for staking
4. Validator keys are generated and stored

## Key Locations

| Item | Location |
|------|----------|
| Treasury keystore | `~/ab2bc/{FLAVOR}/` |
| Genesis YAML | `~/Apollo/ab2bc/genesis{FLAVOR}.YAML` |
| Validator keys | `~/deploy-aqy/nodes/{NODE}/config/` |
| Deploy script | `~/deploy-aqy/deploy-concurrent.sh` |

## Step-by-Step Process

### Step 1: Fund the Validator Account

The validator needs gas to submit transactions:

```bash
# Using treasury keystore
export SUI_CONFIG_DIR=~/ab2bc/AQY

# Get treasury coin
treasury_coin=$(sui client gas --json | jq -r '.[] | select(.mistBalance > 1000000000) | .gasCoinId' | head -1)

# Send 1 AQY for gas
sui client ptb \
  --gas-coin "@$treasury_coin" \
  --split-coins gas "[1000000000]" \
  --assign coins \
  --transfer-objects "[coins]" @{VALIDATOR_ADDRESS} \
  --gas-budget 50000000
```

### Step 2: Generate Correct Proof of Possession

**CRITICAL**: The PoP in `add_validator.yaml` may be stale. Always regenerate:

```bash
cd /path/to/validator/keys
sui validator make-validator-info \
  "NODE_NAME" \
  "Description" \
  "https://website.com" \
  "https://website.com/logo.png" \
  "IP_ADDRESS" \
  1000  # gas price
```

This reads the key files (`protocol.key`, `network.key`, `worker.key`, `account.key`) from the current directory and generates `validator.info` with the correct PoP.

### Step 3: Register as Validator Candidate

Due to the fire_drill.rs bug, use PTB with explicit gas-coin:

```bash
export SUI_CONFIG_DIR=/path/to/validator/keystore

# Get validator's gas coin
gas_coin=$(sui client gas --json | jq -r '.[0].gasCoinId')

# Convert keys to vector format for PTB
# (see deploy-concurrent.sh hex_to_vector function)

sui client ptb \
  --gas-coin "@$gas_coin" \
  --gas-budget 100000000 \
  --move-call "0x3::sui_system::request_add_validator_candidate" \
  "@0x5" \
  "$protocol_vec" \
  "$network_vec" \
  "$worker_vec" \
  "$pop_vec" \
  "$name_vec" \
  "$desc_vec" \
  "$image_vec" \
  "$project_vec" \
  "$net_addr_vec" \
  "$p2p_addr_vec" \
  "$primary_addr_vec" \
  "$worker_addr_vec" \
  "$gas_price" \
  "$commission_rate"
```

### Step 4: Stake Tokens to the Validator

From the treasury, stake the required amount (100K minimum):

```bash
export SUI_CONFIG_DIR=~/ab2bc/AQY

treasury_coin=$(sui client gas --json | jq -r '.[] | select(.mistBalance >= 100000000000000) | .gasCoinId' | head -1)

sui client ptb \
  --gas-coin "@$treasury_coin" \
  --split-coins gas "[100000000000000]" \
  --assign stake_coin \
  --move-call "0x3::sui_system::request_add_stake" "@0x5" "stake_coin" "@{VALIDATOR_ADDRESS}" \
  --gas-budget 50000000
```

### Step 5: Request to Join Committee

The validator requests to join the active committee:

```bash
export SUI_CONFIG_DIR=/path/to/validator/keystore

# Get validator's gas coin
gas_coin=$(sui client gas --json | jq -r '.[0].gasCoinId')

# Note: request_add_validator only takes the system state object
# The validator is identified by the transaction sender (ctx)
sui client ptb \
  --gas-coin "@$gas_coin" \
  --gas-budget 50000000 \
  --move-call "0x3::sui_system::request_add_validator" "@0x5"
```

**Note**: The `request_add_validator` function signature is:
```move
public entry fun request_add_validator(wrapper: &mut SuiSystemState, ctx: &mut TxContext)
```

The validator is identified by the sender address in the transaction context, not by passing the `ValidatorOperationCap`.

### Step 6: Wait for Epoch Change

The validator will become active at the next epoch boundary. Check status:

```bash
curl -s http://127.0.0.1:21868 -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"suix_getLatestSuiSystemState","params":[]}' | \
  jq '{epoch: .result.epoch, activeValidators: [.result.activeValidators[].name], pendingCount: .result.pendingActiveValidatorsSize}'
```

## Validator Status Detection

### Check if Active
```bash
curl -s $RPC_URL -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"suix_getLatestSuiSystemState","params":[]}' | \
  jq -r --arg addr "$VALIDATOR_ADDRESS" '.result.activeValidators[] | select(.suiAddress == $addr) | .name'
```

### Check if Candidate/Pending
```bash
# Check for ValidatorOperationCap ownership (indicates registered candidate)
sui client objects $VALIDATOR_ADDRESS --json | jq '.[] | select(.objectType | contains("ValidatorOperationCap"))'
```

## Network Addresses Format

For PTB registration, addresses must be in multiaddr format:

| Address Type | Format | Example |
|--------------|--------|---------|
| network_address | `/dns/{IP}/tcp/{PORT}/http` | `/dns/192.168.12.185/tcp/25246/http` |
| p2p_address | `/dns/{IP}/udp/{PORT}` | `/dns/192.168.12.185/udp/25244` |
| narwhal_primary_address | `/dns/{IP}/udp/{PORT}` | `/dns/192.168.12.185/udp/25344` |
| narwhal_worker_address | `/dns/{IP}/udp/{PORT}` | `/dns/192.168.12.185/udp/25444` |

## Common Issues

### 1. "Validator doesn't have enough Sui coins"
**Cause**: fire_drill.rs bug - uses wrong coin type  
**Solution**: Use PTB with explicit `--gas-coin`

### 2. "validate_metadata_bcs error code 0"
**Cause**: Incorrect Proof of Possession  
**Solution**: Regenerate with `sui validator make-validator-info`

### 3. "keystore file not found"
**Cause**: client.yaml references wrong keystore path  
**Solution**: Ensure keystore filename matches (e.g., `aqy.keystore` not `sui.keystore`)

### 4. Validator external-address pointing to wrong IP
**Cause**: Template used wrong IP during deployment  
**Solution**: Fix validator.yaml `p2p-config.external-address` to use correct server IP

## Automation

The `deploy-concurrent.sh` script automates all these steps:

```bash
# Stake all P nodes
./deploy-concurrent.sh --stake

# Or for specific node
./deploy-concurrent.sh --stake --nodes AQY-P4
```

The script:
1. Checks if validator is already active/pending
2. Funds validator if needed
3. Regenerates PoP using make-validator-info
4. Registers as candidate via PTB
5. Stakes from treasury
6. Requests to join committee

## Key Files

- `add_validator.yaml` - Static validator metadata (may have stale PoP)
- `validator.yaml` - Runtime validator configuration
- `validator.info` - Generated file with correct PoP
- `account.key` - Validator's account private key (base64)
- `protocol.key` - BLS key for consensus
- `network.key` - Network/P2P key
- `worker.key` - Narwhal worker key
