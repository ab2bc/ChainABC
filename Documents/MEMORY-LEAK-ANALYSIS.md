# Sui Validator Memory Leak Analysis

## Summary

Analysis of jemalloc heap profiles from a running Sui validator (AQY-G1) revealed **2.3 GB of memory growth** over approximately 8 hours of runtime.

## Key Findings

### Memory Growth by Function

| Function | Memory Growth | Percentage | Category |
|----------|---------------|------------|----------|
| `::commit_transaction_outputs` | **1010.5 MB** | 43.3% | Transaction storage |
| `::poll_next` | 912.4 MB | 39.1% | Async polling |
| `::insert_checkpoint_contents` | **552.7 MB** | 23.7% | Checkpoint storage |
| `::multi_insert_transaction_and_effects` | **447.7 MB** | 19.2% | Transaction/effects |
| `::allocate` | 293.2 MB | 12.6% | General allocation |
| `::get` (checkpoint) | 198.8 MB | 8.5% | Checkpoint retrieval |

### Root Causes

1. **Transaction Output Caching** (`commit_transaction_outputs`) - 43% of growth
   - Located in: `crates/sui-core/src/execution_cache/writeback_cache.rs:1044`
   - Caches transactions and effects in memory after DB commit
   - Uses bounded LRU cache but default size is 100,000 entries

2. **Checkpoint Content Storage** (`insert_checkpoint_contents`) - 24% of growth
   - Located in: `crates/sui-core/src/checkpoints/mod.rs:924`
   - Stores checkpoint contents
   - Pruning retains 5,000 full checkpoints (`NUM_SAVED_FULL_CHECKPOINT_CONTENTS`)

3. **Transaction/Effects Multi-Insert** (`multi_insert_transaction_and_effects`) - 19% of growth
   - Part of the writeback cache flush process
   - Accumulates transaction effects in memory

## Configuration Options

### Current Validator Config (`validator.yaml`)
```yaml
authority-store-pruning-config:
  num-latest-epoch-dbs-to-retain: 2
  epoch-db-pruning-period-secs: 3600
```

### Available Cache Size Limits

The `ExecutionCacheConfig::WritebackCache` supports these parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max-cache-size` | 100,000 | Maximum entries in most caches |
| `package-cache-size` | 1,000 | Package cache entries |
| `object-cache-size` | 100,000 | Object version cache |
| `marker-cache-size` | (object-cache-size) | Object markers |
| `transaction-cache-size` | 100,000 | Transaction cache |
| `effect-cache-size` | (transaction-cache-size) | Effects cache |
| `events-cache-size` | (transaction-cache-size) | Events cache |
| `backpressure-threshold` | N/A | Pause consensus handler |

### Environment Variable Overrides

These can override config file settings:
- `SUI_MAX_CACHE_SIZE` - Maximum cache size
- `SUI_PACKAGE_CACHE_SIZE` - Package cache size

## Recommendations

### 1. Reduce Cache Sizes

Add to `validator.yaml`:

```yaml
execution-cache:
  WritebackCache:
    max-cache-size: 50000       # Reduce from 100k to 50k
    transaction-cache-size: 30000
    effect-cache-size: 30000
    events-cache-size: 20000
    object-cache-size: 50000
```

### 2. More Aggressive Pruning

```yaml
authority-store-pruning-config:
  num-latest-epoch-dbs-to-retain: 1  # Reduce from 2 to 1
  epoch-db-pruning-period-secs: 1800 # Reduce from 3600 to 1800
```

### 3. Monitor Memory with Metrics

The validator exposes Prometheus metrics at the `metrics-address`:
- Cache sizes and hit rates
- Backpressure status
- DB sizes

### 4. Consider Heap Fragmentation

jemalloc may show "growth" that is actually fragmentation. Consider:
- `MALLOC_CONF="background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:1000"`

## Files Analyzed

- Heap profiles: `/home/apollo/deploy-aqy/nodes/AQY-G1/heap-profiles/`
- Comparison: `heap.2625202.100.i100.heap` → `heap.2625202.7900.i7900.heap`
- Analysis output: `/home/apollo/deploy-aqy/nodes/AQY-G1/heap-profiles/analysis/`

## Sui Source Code References

- **Writeback Cache**: `crates/sui-core/src/execution_cache/writeback_cache.rs`
- **Checkpoint Store**: `crates/sui-core/src/checkpoints/mod.rs`
- **Cache Config**: `crates/sui-config/src/node.rs` (lines 420-490)
- **Checkpoint Executor**: `crates/sui-core/src/checkpoints/checkpoint_executor/mod.rs`

## Next Steps

1. **Test reduced cache sizes** on a non-production validator
2. **Monitor memory** with reduced settings for 24-48 hours
3. **Compare heap profiles** before/after configuration changes
4. **Consider filing issue** with Sui Labs if memory growth persists with reduced caches

---

*Analysis performed: December 19, 2024*
*Sui version: AQY fork (based on mainnet)*
*Tools used: jemalloc heap profiling, jeprof*
