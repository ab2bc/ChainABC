# Fire Drill Bug - Validator Registration Failure

## Problem Summary

When running `sui validator become-candidate` or `sui validator join-committee`, the command fails with:

```
Validator doesn't have enough Sui coins to cover transaction fees.
```

This happens even when the validator account has sufficient coins.

## Root Cause

The bug is in `crates/sui/src/fire_drill.rs` around line 110:

```rust
async fn get_gas_obj_ref(
    address: SuiAddress,
    sui_client: &SuiClient,
    minimal_gas_balance: u64,
) -> anyhow::Result<ObjectRef> {
    let coins = sui_client
        .coin_read_api()
        .get_coins(address, Some("0x2::sui::SUI".into()), None, None)
        .await?
        .data;
    // ...
}
```

The problem is that the renamer replaces `SUI` with the chain flavor (e.g., `AQY`), resulting in:

```rust
.get_coins(address, Some("0x2::sui::AQY".into()), None, None)
```

However, the RPC endpoint `suix_getCoins` expects the **original framework coin type** `0x2::sui::SUI` - it does NOT get renamed at the RPC level. The coin type in the framework is always `0x2::sui::SUI` internally.

## Why This Happens

The renamer pattern `SUI -> AQY` is too aggressive and replaces the string in contexts where it shouldn't:

1. The framework coin module is `0x2::sui` (lowercase)
2. The coin type struct is `SUI` (uppercase)
3. When querying coins, the RPC uses the original type path `0x2::sui::SUI`
4. The renamer incorrectly changes this to `0x2::sui::AQY`

## Verification

Check the compiled binary:
```bash
strings ~/Apollo/AQY/target/release/sui | grep "0x2::sui::" | head -5
```

If you see `0x2::sui::AQY` instead of `0x2::sui::SUI`, the bug is present.

## Workaround

Use `sui client ptb` with explicit `--gas-coin` parameter to bypass the broken gas lookup:

```bash
# Instead of:
sui validator become-candidate validator.info --gas-budget 500000000

# Use:
gas_coin=$(sui client gas --json | jq -r '.[0].gasCoinId')
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

## Permanent Fix

Add an exclusion pattern in the renamer to NOT rename `0x2::sui::SUI` in string literals:

### Option 1: Exclude in fire_drill.rs
Before renaming, add `fire_drill.rs` to exclusion list, or use a more specific pattern.

### Option 2: Fix the source code
Change `fire_drill.rs` to use a constant or config value instead of hardcoded string:

```rust
// In fire_drill.rs - use the native coin type constant
use sui_types::gas_coin::GAS;

// Then use GAS.type_tag().to_string() instead of hardcoded "0x2::sui::SUI"
```

### Option 3: Add negative pattern to renamer
In the renamer patterns file, add exclusion for this specific case:

```
# Exclusions - do not rename these
-"0x2::sui::SUI"
```

## Affected Commands

- `sui validator become-candidate`
- `sui validator join-committee`  
- `sui validator leave-committee`
- `sui validator update-metadata`
- Any command in `fire_drill.rs` that uses `get_gas_obj_ref()`

## Related Files

- `crates/sui/src/fire_drill.rs` - Contains the bug
- `crates/sui/src/validator_commands.rs` - Calls fire_drill functions
- Renamer patterns in `ChainABC/SuiRenamer/patterns-*.txt`

## Status

**Current Status**: Workaround implemented in `deploy-concurrent.sh` using PTB with explicit gas-coin.

**Permanent Fix Needed**: Update renamer to exclude `0x2::sui::SUI` string literal from replacement.
