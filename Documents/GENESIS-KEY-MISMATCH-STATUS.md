# Genesis/Key Mismatch Status Report

**Date:** December 2, 2025  
**Status:** 🚨 CRITICAL - Deployment Blocked

## Issue Summary

The deployment ZIP (`deploy-192-168-12-100.zip`) contains a **genesis.blob that was built with different keys** than the validator key files and genesisAQY.YAML.

## Evidence

### G1 Network Key Comparison

| Source | Key (hex) |
|--------|-----------|
| ZIP private key (derived) | `01c43c558f9d6ccfd4d59611529122232835be44c213f0b24deabb8c4527fb83` |
| genesisAQY.YAML | `01c43c558f9d6ccfd4d59611529122232835be44c213f0b24deabb8c4527fb83` |
| genesis.blob (actual) | `4cb1a22d652eb6b85d9b01d796745c43689a029badc399226a1262176ba42b4e` |

**Result:** ZIP and YAML match ✅, but genesis.blob is different ❌

## Symptoms

When validators start:
- All 10 validators (G1-G5, P1-P5) start successfully
- Transport errors occur: `transport error { k#80fb539f.. } with 2000 stake`
- No checkpoint progress: `Received no new synced checkpoints for 5s`
- Fullnodes (F1-F5) crash with exit code 139 (SIGSEGV)

## Root Cause

The genesis.blob in the deployment ZIP was built from a **different set of keys** than what's in:
1. The individual node ZIP files (e.g., `AQY-G1.zip/network.key`)
2. The `genesisAQY.YAML` configuration file

This means validators authenticate with keys that don't match what's registered in the genesis block.

## Key Format Reference

All key formats have been verified correct:

| Key Type | Format | Length |
|----------|--------|--------|
| Protocol | BLS12-381 raw scalar | 32 bytes (base64: 44 chars) |
| Network | Ed25519 + 0x00 flag | 33 bytes (base64: 44 chars) |
| Worker | Ed25519 + 0x00 flag | 33 bytes (base64: 44 chars) |
| Account | Ed25519 + 0x00 flag | 33 bytes (base64: 44 chars) |

## Solution Required

**Option 1:** Regenerate genesis.blob from genesisAQY.YAML
```bash
sui genesis --from-config genesisAQY.YAML -o genesis.blob
```

**Option 2:** Regenerate everything together
- Generate new keys
- Build genesisAQY.YAML with those keys
- Build genesis.blob from the YAML
- Package into deployment ZIP

## Files Verified Working

The following template/code changes have been applied and are correct:

1. **`AManager/validator.yaml`** - Key paths point to `/opt/sui/config/*.key`
2. **`AManager/MainForm.cs`** - Writes `.key` files (not `.key.b64`)
3. **Deploy script** - Extracts keys correctly, mounts to containers

## Deployment Status

| Component | Status |
|-----------|--------|
| Docker images | ✅ Working (ghcr.io/ab2bc/aqy-node:dev) |
| Container startup | ✅ Validators start |
| Key file mounting | ✅ Keys mounted correctly |
| Genesis mounting | ✅ Genesis mounted at /genesis/genesis.blob |
| P2P connectivity | ❌ Transport errors (key mismatch) |
| Consensus | ❌ No checkpoints produced |
| Fullnodes | ❌ Crashing (exit 139) |

## Next Steps

1. User needs to regenerate genesis.blob using the same keys as in the ZIP
2. Repackage deployment ZIP with matching genesis.blob
3. Redeploy and verify consensus

## Verification Command

To verify keys match after regeneration:
```python
import base64
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

# Read private key from ZIP
with open('network.key', 'r') as f:
    key_b64 = f.read().strip()
key_bytes = base64.b64decode(key_b64)
private_key = Ed25519PrivateKey.from_private_bytes(key_bytes[1:])  # Skip 0x00 flag
pubkey = private_key.public_key().public_bytes_raw().hex()
print(f"Derived pubkey: {pubkey}")

# Compare with genesis - should match
```
