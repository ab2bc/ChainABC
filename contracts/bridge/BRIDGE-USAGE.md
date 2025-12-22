# Bridge Contract Usage Guide

## Overview

The ChainABC Bridge enables secure cross-chain token transfers between the AQY ecosystem chains:
- **AQY** (Main Chain)
- **ASY**, **AUI**, **AIY**, **ARY**, **ABC** (1:1000 ratio with AQY)
- **AGO** (1:1000000 ratio with AQY)

## Architecture

The bridge consists of three core modules:

### 1. bridge_token.move - Core Bridge Logic
Handles the actual token locking, minting, burning, and releasing.

### 2. pegging.move - Exchange Rate Management
Manages conversion rates between chains using the `ab2bc_chains.rate_denominator` values.

### 3. router.move - User Interface
Entry point for users with slippage protection and fee handling.

---

## Pegging Ratios

| Source Chain | Destination | Rate | Example |
|-------------|-------------|------|---------|
| AQY → ASY | 1:1000 | 1 AQY = 1000 ASY |
| AQY → AUI | 1:1000 | 1 AQY = 1000 AUI |
| AQY → AIY | 1:1000 | 1 AQY = 1000 AIY |
| AQY → ARY | 1:1000 | 1 AQY = 1000 ARY |
| AQY → ABC | 1:1000 | 1 AQY = 1000 ABC |
| AQY → AGO | 1:1000000 | 1 AQY = 1,000,000 AGO |
| ASY → AQY | 1000:1 | 1000 ASY = 1 AQY |
| AGO → AQY | 1000000:1 | 1,000,000 AGO = 1 AQY |

---

## Contract Functions

### bridge_token Module

#### `init_bridge<T>(admin_cap, ctx)`
Initialize bridge with default 0.1% fee.

#### `init_bridge_custom<T>(admin_cap, fee_bps, ctx)`
Initialize bridge with custom fee (in basis points, e.g., 100 = 1%).

#### `bridge_out<T>(bridge, coins, dest_chain, dest_address, ctx)`
Lock tokens to bridge out to another chain.
- **bridge**: Bridge capability object
- **coins**: Coins to lock
- **dest_chain**: Destination chain ID
- **dest_address**: Recipient address on destination chain

#### `complete_bridge<T>(bridge, admin_cap, treasury, amount, recipient, source_chain, nonce, ctx)`
Complete incoming bridge (mint tokens to recipient).
- Only callable by admin/oracle

#### `release_tokens<T>(bridge, admin_cap, amount, recipient, ctx)`
Release locked tokens (for failed/reversed bridges).

#### `pause<T>(bridge, admin_cap)` / `unpause<T>(bridge, admin_cap)`
Emergency controls to pause/resume bridge operations.

#### `collect_fees<T>(bridge, admin_cap, ctx)`
Withdraw accumulated bridge fees.

---

### pegging Module

#### `create_rate_manager(ctx)`
Create a rate manager capability.

#### `init_all_rates(rate_manager, ctx)`
Initialize all chain pair exchange rates based on:
- AQY chain ID: 1
- ASY, AUI, AIY, ARY, ABC: denominator 1000
- AGO: denominator 1000000

#### `get_rate(registry, source_chain, dest_chain)`
Get exchange rate for a chain pair.

#### `calculate_output(registry, source_chain, dest_chain, input_amount)`
Calculate output amount for a bridge transfer.

#### `update_rate(registry, admin_cap, source_chain, dest_chain, rate, rate_decimals)`
Update a specific exchange rate (admin only).

---

### router Module

#### `bridge_with_peg<T>(bridge, rate_registry, coins, dest_chain, dest_address, min_output, ctx)`
Bridge tokens with automatic rate conversion and slippage protection.
- **min_output**: Minimum acceptable output (slippage protection)

#### `quote_bridge(rate_registry, source_chain, dest_chain, amount)`
Get a quote for a bridge transfer without executing.

---

## Admin Console Integration

### Chain Oracle & Pegging Management
Access via: `http://localhost:3100` → Chain Oracle

Features:
- View all pegging ratios from database
- Monitor bridge contract status
- Security test controls
- Deploy/update contracts

### Smart Contract Management
Access via: Smart Contract Management → Bridge Contracts

Templates available:
- Bridge Token (bridge_token.move)
- Pegging Module (pegging.move)
- Router Module (router.move)

---

## Database Configuration

Pegging ratios are stored in `ab2bc_chains` table:

```sql
SELECT symbol, rate_denominator FROM ab2bc_chains;
```

| symbol | rate_denominator |
|--------|-----------------|
| AQY    | 1               |
| ASY    | 1000            |
| AUI    | 1000            |
| AIY    | 1000            |
| ARY    | 1000            |
| ABC    | 1000            |
| AGO    | 1000000         |

The admin API (`/api/oracle/data`) loads these values automatically.

---

## Deployment Steps

### 1. Build Contracts
```bash
cd /path/to/ChainABC/contracts/bridge
sui move build
```

### 2. Deploy to Network
```bash
sui client publish --gas-budget 100000000
```

### 3. Initialize Bridge
After deployment, call:
1. `bridge_token::init_bridge<COIN_TYPE>(admin_cap, ctx)`
2. `pegging::create_rate_manager(ctx)`
3. `pegging::init_all_rates(rate_manager, ctx)`

### 4. Configure Admin Console
Update the contract addresses in the Admin Console database.

---

## Security Features

1. **Replay Protection**: Nonce tracking prevents double-spending
2. **Rate Bounds**: Configurable min/max exchange rates
3. **Slippage Protection**: User-specified minimum output
4. **Multi-sig Verification**: Admin operations require capability
5. **Pause Mechanism**: Emergency stop for bridge operations
6. **Fee Collection**: Configurable bridge fees (default 0.1%)

---

## Troubleshooting

### "Bridge is paused"
- Check if bridge was paused by admin
- Call `unpause()` with admin capability

### "Insufficient balance"
- Verify token balance before bridging
- Check if fees are accounted for

### "Invalid nonce"
- Transaction may be a replay attempt
- Wait for previous transaction to confirm

### "Slippage exceeded"
- Market rate changed beyond tolerance
- Increase `min_output` tolerance or retry

---

## API Endpoints

### GET /api/oracle/data
Returns pegging configuration and chain data.

Response includes:
- `peggingConfig`: Array of chain pegging ratios
- `configSource`: "database" or "default"
- `chains`: Array of chain status information

### GET /api/health
Health check endpoint for monitoring.

---

## Example Bridge Flow

### AQY → ASY Transfer (1000 tokens)

1. User initiates bridge with 1 AQY
2. Router calculates: 1 AQY × 1000 = 1000 ASY
3. Bridge locks 1 AQY on source chain
4. Oracle observes lock event
5. Oracle calls `complete_bridge` on ASY chain
6. User receives 1000 ASY (minus fees)

### ASY → AQY Transfer (1000 tokens)

1. User initiates bridge with 1000 ASY
2. Router calculates: 1000 ASY ÷ 1000 = 1 AQY
3. Bridge locks 1000 ASY on ASY chain
4. Oracle observes lock event
5. Oracle calls `complete_bridge` on AQY chain
6. User receives 1 AQY (minus fees)

---

## Version History

- **v1.0.0** - Initial release with bridge_token, pegging, router modules
- Supports all 7 AQY ecosystem chains
- Database-driven pegging configuration
- Admin Console integration
