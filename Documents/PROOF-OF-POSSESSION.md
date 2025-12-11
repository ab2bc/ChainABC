# Proof of Possession (PoP) - Critical Knowledge

## What is Proof of Possession?

Proof of Possession (PoP) is a cryptographic signature that proves the validator owns the BLS protocol key. It's required when registering a validator to prevent key theft attacks.

## The Problem: Stale PoP

The `add_validator.yaml` file is generated during initial key generation, but the PoP can become invalid if:

1. The protocol key file is regenerated
2. The validator name changes
3. The file was generated with a different tool version

## Symptoms of Invalid PoP

When registering a validator with an invalid PoP:

```
Error: validate_metadata_bcs error code 0
```

Or the transaction fails silently.

## Solution: Regenerate PoP

Always use `sui validator make-validator-info` to generate a fresh PoP before registration:

```bash
cd /path/to/validator/keys

# Ensure these files exist:
# - protocol.key  (BLS private key)
# - network.key   (Ed25519 network key)
# - worker.key    (Ed25519 worker key)  
# - account.key   (Ed25519 account key)

sui validator make-validator-info \
  "VALIDATOR_NAME" \
  "Validator Description" \
  "https://example.com" \
  "https://example.com/logo.png" \
  "IP_OR_HOSTNAME" \
  1000  # gas price
```

This generates `validator.info` with:
- Correct public keys derived from private keys
- Fresh Proof of Possession
- Network addresses (which may need adjustment)

## Extract PoP from validator.info

```bash
grep "proof_of_possession:" validator.info | awk '{print $2}'
```

## Convert PoP Formats

The PoP in `validator.info` is base64. For PTB calls, convert to hex:

```bash
pop_base64="kJP/0Nto9Gqle3TnMeiKlfwsRu90nMncF1oeVthFuvjhGS/vpIbqXZKgkJC8B1CU"
pop_hex=$(echo "$pop_base64" | base64 -d | xxd -p | tr -d '\n')
echo "$pop_hex"
# Output: 9093ffd0db68f46aa57b74e731e88a95fc2c46ef749cc9dc175a1e56d845baf8e1192fefa486ea5d92a09090bc075094
```

## PoP in Different Contexts

| Context | Format | Length |
|---------|--------|--------|
| add_validator.yaml | Hex string | 96 chars |
| validator.info | Base64 | 64 chars |
| PTB vector | Hex bytes | 48 bytes |

## Validation

A valid PoP for a BLS12-381 key should:
- Be exactly 48 bytes (96 hex chars)
- When verified against the protocol public key and validator name, should pass

## Key Files Relationship

```
protocol.key (private) 
    ↓
    derives → protocol_public_key (96 bytes BLS pubkey)
    ↓
    signs → proof_of_possession (48 bytes signature)
```

The PoP is a BLS signature of a message containing the validator's account address, signed by the protocol private key.

## Best Practice

**Never use the PoP from add_validator.yaml directly.** Always regenerate before registration:

```bash
# In deploy script, before registration:
sui validator make-validator-info "$name" "$desc" "$url" "$logo" "$ip" "$gas_price"
pop=$(grep "proof_of_possession:" validator.info | awk '{print $2}')
pop_hex=$(echo "$pop" | base64 -d | xxd -p | tr -d '\n')
# Now use $pop_hex in PTB call
```
