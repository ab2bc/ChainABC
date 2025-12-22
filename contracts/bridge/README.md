# AB2BC 7-Chain Bridge

A cross-chain bridge enabling token transfers between all 7 AB2BC chains with configurable pegging rates.

## Chains

| ID | Chain | Token |
|----|-------|-------|
| 1 | ABC | ABC |
| 2 | AGO | AGO |
| 3 | AIY | AIY |
| 4 | AQY | AQY |
| 5 | ARY | ARY |
| 6 | ASY | ASY |
| 7 | AUY | AUY |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      AB2BC Bridge System                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐      │
│  │   ABC   │    │   AGO   │    │   AIY   │    │   ...   │      │
│  │  Chain  │    │  Chain  │    │  Chain  │    │ Chains  │      │
│  └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘      │
│       │              │              │              │            │
│       ▼              ▼              ▼              ▼            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Bridge Contracts                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │ bridge_token │  │   pegging    │  │    router    │   │   │
│  │  │ (lock/mint)  │  │  (rates)     │  │  (entry)     │   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Relayer Service                        │   │
│  │  • Monitors events on all 7 chains                      │   │
│  │  • Relays proofs for minting/releasing                  │   │
│  │  • Multi-sig verification                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Smart Contracts

### 1. bridge_token.move
Core bridging logic:
- **Lock & Mint**: Lock native tokens, mint wrapped on destination
- **Burn & Release**: Burn wrapped tokens, release native on source
- **Fee collection**: Configurable fee (default 0.3%)
- **Pause mechanism**: Emergency pause by admin

### 2. pegging.move
Exchange rate management:
- **Fixed Pegs**: 1:1 rate (default for all pairs)
- **Floating Pegs**: Market-driven rates with bounds
- **Algorithmic Pegs**: Auto-adjusted rates
- **Oracle Integration**: External price feeds

### 3. router.move
User-facing interface:
- **Slippage Protection**: Minimum output guarantee
- **Rate Freshness**: Validates oracle data age
- **Quoting**: Preview output amounts before bridging

## Pegging Modes

### Fixed (1:1)
All chains maintain 1:1 parity. Default for internal ecosystem.

```
1 ABC = 1 AGO = 1 AIY = 1 AQY = 1 ARY = 1 ASY = 1 AUY
```

### Floating (Market)
Rate determined by supply/demand with min/max bounds.

```
Rate bounds: 0.9 - 1.1 (±10%)
Oracle updates: Every 60 seconds
Deviation limit: 5% per update
```

### Algorithmic
Rate auto-adjusts based on bridge utilization.

```
High outflow → rate decreases (discourages exits)
High inflow → rate increases (encourages exits)
Target: 50% utilization on each side
```

## Usage

### Bridge ABC to AQY (Example)

```typescript
// 1. Connect to ABC chain
const client = new SuiClient({ url: 'http://192.168.5.1:21000' });

// 2. Quote the bridge
const quote = await client.devInspectTransactionBlock({
  transactionBlock: tx,
  sender: address,
});

// 3. Execute bridge
const tx = new Transaction();
tx.moveCall({
  target: 'bridge::router::bridge_with_peg',
  arguments: [
    tx.object(BRIDGE_CONFIG),
    tx.object(TREASURY),
    tx.object(PEG_REGISTRY),
    tx.object(CLOCK),
    tx.object(coinId),
    tx.pure.u8(4),  // dest_chain: AQY
    tx.pure.vector('u8', recipientBytes),
    tx.pure.u64(minAmountOut),
    tx.pure.u64(nonce),
  ],
});

const result = await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

## Relayer Setup

### Requirements
- Python 3.10+
- Access to all 7 chain RPC endpoints
- Relayer private key with gas on all chains

### Start Relayer
```bash
cd relayer
export RELAYER_PRIVATE_KEY="your_key_here"
python3 bridge_relayer.py
```

### Configuration
Edit `CHAINS` in `bridge_relayer.py` to match your RPC endpoints:
```python
CHAINS = {
    1: {'name': 'ABC', 'rpc': 'http://192.168.5.1:21000', 'prefix': 'abc'},
    2: {'name': 'AGO', 'rpc': 'http://192.168.5.1:21004', 'prefix': 'ago'},
    # ...
}
```

## Security Considerations

1. **Multi-sig Relayers**: Production should use N-of-M relayer threshold
2. **Rate Limits**: Max bridge amount per transaction/day
3. **Pause Mechanism**: Admin can pause bridge in emergency
4. **Replay Protection**: TX hashes tracked to prevent double-spend
5. **Rate Bounds**: Pegging rates constrained to prevent manipulation

## Fees

| Fee Type | Amount | Recipient |
|----------|--------|-----------|
| Bridge Fee | 0.3% | Fee Collector |
| Gas Fee | Variable | Network |

## Deployment

1. Deploy contracts to all 7 chains
2. Initialize bridge config with same admin
3. Initialize pegging registry with default rates
4. Register relayer addresses
5. Start relayer service

```bash
# Deploy to each chain
sui client publish --gas-budget 100000000

# Initialize on each chain
sui client call --package $BRIDGE_PKG \
  --module bridge_token \
  --function init_bridge \
  --args $CHAIN_ID $ADMIN [$RELAYERS] $THRESHOLD
```

## Monitoring

Bridge status available at: http://192.168.5.1:3004

The relayer logs metrics every 60 seconds:
- Pending transfers
- Completed transfers  
- Failed transfers
- Chain checkpoint status
