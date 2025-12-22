# 7-Chain Bridge Contracts - Security Summary

## Overview

Three Move smart contracts implement the 7-chain bridge system for AB2BC:

1. **bridge_token.move** - Core bridge logic for token locking, minting, burning, and release
2. **pegging.move** - Exchange rate management and oracle integration  
3. **router.move** - User-facing bridge routing with slippage protection

## Chain Configuration

| Chain ID | Name | Trading Mode |
|----------|------|--------------|
| 1 | ABC | Internal Only |
| 2 | AGO | Internal Only |
| 3 | AIY | Internal Only |
| 4 | AQY | External Trading ⚠️ |
| 5 | ARY | Internal Only |
| 6 | ASY | Internal Only |
| 7 | AUY | Internal Only |

**Important:** AQY is designated for external trading. All other chains are for internal network swaps only.

## Security Features

### bridge_token.move

- **Multi-signature relayer consensus** - Configurable threshold for transaction validation
- **Replay attack prevention** - Processed transaction tracking with hash-based deduplication  
- **Pause mechanism** - Admin-only ability to halt bridge operations
- **Fee collection** - Configurable fee in basis points (default 0.3%)
- **Minimum bridge amounts** - Prevents dust attacks
- **Chain validation** - Only allows bridging between valid chains

### pegging.move

- **Rate staleness protection** - Timestamp tracking for rate freshness
- **Deviation limits** - Prevents oracle manipulation via max rate change per update
- **Admin-controlled rate updates** - Only authorized updaters can modify rates
- **Multiple peg types** - Fixed, floating, and algorithmic rate support
- **Oracle configuration** - Per-pair oracle settings with heartbeat monitoring

### router.move

- **Slippage protection** - User-specified minimum output amounts
- **Quote functionality** - Pre-transaction rate and fee estimation
- **Atomic cross-chain swaps** - Combined bridge and peg operations
- **Deadline enforcement** - Transaction expiration support

## Compilation Status

All three modules compile successfully with Sui Move 2024.beta edition:

```
BUILDING bridge
bridge_token.mv ✓
pegging.mv ✓  
router.mv ✓
```

## Admin Console Integration

Bridge contracts are integrated into the AB2BC Admin Console:

1. **SmartContractManagement.jsx** - Added 3 bridge templates:
   - 7-Chain Bridge Token
   - Pegging Module
   - Router

2. **ChainOracle.jsx** - Added 7-Chain Bridge Contract Management section:
   - Visual chain grid with trading mode indicators
   - AQY highlighted as external trading chain
   - Deploy/pause/update controls per chain

## Deployment Considerations

1. **Deploy Order:**
   - bridge_token first (core infrastructure)
   - pegging second (depends on bridge_token types)
   - router last (depends on both)

2. **Initialization:**
   - Set up relayer addresses with appropriate threshold
   - Initialize peg rates for all chain pairs (42 pairs for 7 chains)
   - Configure oracle addresses if using external price feeds

3. **Testing Requirements:**
   - Test with small amounts first
   - Verify relayer consensus works correctly
   - Test pause/unpause functionality
   - Validate rate updates and slippage protection

## Security Audit Recommendations

Before mainnet deployment:

1. Formal verification of math operations (overflow checks)
2. Audit of access control patterns
3. Review of event emission for monitoring
4. Stress testing with concurrent transactions
5. Third-party security audit

## File Locations

- Sources: `/contracts/bridge/sources/`
- Build output: `/contracts/bridge/build/bridge/bytecode_modules/`
- Admin Console: `/home/apollo/RE/admin-site/src/pages/`
