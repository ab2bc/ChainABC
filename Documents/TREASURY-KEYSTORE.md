# Treasury Keystore Configuration

## Overview

The treasury keystore contains the private keys for accounts that hold the initial token supply. This is used to fund validators and pay for staking transactions.

## Keystore Location

The canonical location for treasury keystores is:

```
~/ab2bc/{FLAVOR}/
```

For example:
- `~/ab2bc/AQY/aqy.keystore`
- `~/ab2bc/ABC/abc.keystore`

## Required Files

| File | Purpose |
|------|---------|
| `{flavor}.keystore` | JSON array of private keys |
| `client.yaml` | Sui client configuration |
| `{flavor}.aliases` | Key aliases (optional) |

## client.yaml Structure

```yaml
---
keystore:
  File: /home/apollo/ab2bc/AQY/aqy.keystore
external_keys: ~
envs:
  - alias: aqy-rpc
    rpc: "http://127.0.0.1:21868"
    ws: ~
    basic_auth: ~
    chain_id: ff61e47e
active_env: aqy-rpc
active_address: "0x8692249fcbd8ff235ea40c1b0e1a2de3c4c395293abcd6b3a650296e7babb6fb"
```

## Common Issues

### 1. Keystore Filename Mismatch

**Problem**: `client.yaml` references `sui.keystore` but actual file is `aqy.keystore`

**Solution**: Ensure consistency:
```yaml
keystore:
  File: /home/apollo/ab2bc/AQY/aqy.keystore  # Must match actual filename
```

### 2. Missing client.yaml

The deploy script creates `client.yaml` automatically if missing, but it needs:
- A running RPC endpoint to connect to
- The keystore file to already exist

### 3. Wrong Active Address

**Problem**: `active_address` doesn't match any key in keystore

**Solution**: 
```bash
# List addresses in keystore
export SUI_CONFIG_DIR=~/ab2bc/AQY
sui keytool list

# Switch to correct address
sui client switch --address 0x...
```

### 4. Empty Keystore in Deploy Directory

**Problem**: `$DEPLOY_ROOT/ab2bc/AQY/` exists but is empty

**Cause**: Script incorrectly creates directory but doesn't copy keys

**Solution**: The script should use `$HOME/ab2bc/$FLAVOR` not `$DEPLOY_ROOT/ab2bc/$FLAVOR`

## Creating Treasury Keystore

If keystore is missing, create it from genesis keys:

```bash
mkdir -p ~/ab2bc/AQY
cd ~/ab2bc/AQY
echo '[]' > aqy.keystore

# Import treasury private key (base64 format)
export SUI_CONFIG_DIR=~/ab2bc/AQY
sui keytool import suiprivkey1q... ed25519 --alias treasury

# Create client.yaml
cat > client.yaml << 'EOF'
---
keystore:
  File: /home/apollo/ab2bc/AQY/aqy.keystore
envs:
  - alias: aqy-rpc
    rpc: "http://127.0.0.1:21868"
    ws: ~
    basic_auth: ~
active_env: aqy-rpc
active_address: ~
EOF
```

## Using Treasury in Scripts

```bash
# Set config directory
export SUI_CONFIG_DIR=~/ab2bc/AQY

# Get treasury coin with sufficient balance
treasury_coin=$(sui client gas --json | jq -r '.[] | select(.mistBalance >= 100000000000000) | .gasCoinId' | head -1)

# Use in PTB transaction
sui client ptb \
  --gas-coin "@$treasury_coin" \
  --split-coins gas "[100000000000000]" \
  --assign coins \
  --transfer-objects "[coins]" @{RECIPIENT} \
  --gas-budget 50000000
```

## Security Considerations

1. **Never commit keystores to git** - Add to .gitignore
2. **Restrict file permissions** - `chmod 600 *.keystore`
3. **Don't copy to deployment directories** - Reference from home directory
4. **Backup securely** - Keystores are the only way to access funds

## Troubleshooting

### Check keystore contents
```bash
export SUI_CONFIG_DIR=~/ab2bc/AQY
sui keytool list
```

### Verify address has balance
```bash
sui client gas
```

### Check RPC connectivity
```bash
curl -s http://127.0.0.1:21868 -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"sui_getChainIdentifier","params":[]}' | jq
```
