# System Performance Analysis

**Date:** December 12, 2025  
**Host:** apollo-NucBox-K10  
**Analysis Type:** Multi-Chain Blockchain Deployment Resource Analysis

---

## System Hardware Specifications

| Component | Specification |
|-----------|---------------|
| **CPU** | 13th Gen Intel Core i9-13900HK |
| **Cores** | 14 cores (20 threads) |
| **RAM** | 61 GiB total |
| **Disk** | 478 GB LVM volume |
| **OS** | Ubuntu 25.04 (Linux 6.14.0-37-generic) |

---

## Current Resource Utilization

### Memory Usage

| Category | Usage | Available |
|----------|-------|-----------|
| **Total RAM** | 32 GiB used | 28 GiB available |
| **Swap** | 512 KiB used | 4.0 GiB available |
| **Memory %** | 52% utilized | 46% free |

### Disk Usage

| Mount | Size | Used | Available | Use% |
|-------|------|------|-----------|------|
| `/` (root) | 478 GB | 308 GB | 146 GB | 68% |

---

## Blockchain Container Resources

### Per-Chain Summary (4 nodes each: G1, G2, G3, F1)

| Chain | CPU % | Memory | Checkpoint | Status |
|-------|-------|--------|------------|--------|
| **AIY** | 89.5% | 2.53 GiB | 7,776 | ✅ Active |
| **ABC** | 83.9% | 2.51 GiB | 7,873 | ✅ Active |
| **ASY** | 76.2% | 2.52 GiB | 7,700 | ✅ Active |
| **AGO** | 75.9% | 2.52 GiB | 7,818 | ✅ Active |
| **ARY** | 72.8% | 2.53 GiB | 7,804 | ✅ Active |
| **AQY** | 72.0% | 2.53 GiB | 7,666 | ✅ Active |
| **AUY** | 61.5% | 2.52 GiB | 7,735 | ✅ Active |

**Totals (28 blockchain containers):**
- **Total CPU:** ~532% (across 20 threads = 26.6% avg per thread)
- **Total Memory:** ~17.6 GiB
- **All chains producing checkpoints at ~5/second**

### Per-Container Breakdown

| Container Type | CPU % Range | Memory Range | Network I/O |
|----------------|-------------|--------------|-------------|
| Validators (G1-G3) | 19-35% | 640-655 MiB | 85-115 MB in/out |
| Fullnodes (F1) | 5-9% | 570-585 MiB | ~27 MB in / ~19 MB out |

---

## Service Container Resources

| Service | CPU % | Memory | Purpose |
|---------|-------|--------|---------|
| **m2c-backend** | 0.0% | 42 MiB | M2C API backend |
| **ab2bc-admin** | 0.0% | 31 MiB | Admin console |
| **m2c-db** | 0.0% | 18 MiB | PostgreSQL database |
| **m2c-redis** | 0.6% | 3.5 MiB | Redis cache |

**Total Service Memory:** ~95 MiB (negligible)

---

## VMware Workstation Usage

| Metric | Value |
|--------|-------|
| **CPU** | 71.3% |
| **Memory** | 4.2 GiB (6.8% of system) |
| **VM** | Ubuntu 64-bit (192.168.5.129) |
| **Purpose** | Remote G4 validator nodes |

---

## Blockchain Data Storage

| Chain | Disk Usage |
|-------|------------|
| ARY | 757 MB |
| AIY | 756 MB |
| ASY | 756 MB |
| AUY | 756 MB |
| ABC | 754 MB |
| AGO | 754 MB |
| AQY | 570 MB |

**Total Blockchain Data:** ~5.1 GB

---

## Network Ports Summary

### Blockchain RPC Ports (per chain)
| Chain | G1 Port | G2 Port | G3 Port | F1 Port |
|-------|---------|---------|---------|---------|
| AQY | 21676 | ... | ... | 21668 |
| ASY | 21698 | ... | ... | ... |
| AUY | 21726 | ... | ... | ... |
| AIY | 21758 | ... | ... | ... |
| ARY | 21734 | ... | ... | ... |
| AGO | ... | ... | ... | ... |
| ABC | ... | ... | ... | ... |

### Service Ports
| Service | Port | Status |
|---------|------|--------|
| SSH | 22 | ✅ Listening |
| M2C Backend | 3000 | ✅ Listening |
| Attack UI | 3001 | ✅ Listening |
| Explorer | 3005 | ✅ Listening |
| Admin | 3101 | ✅ Listening |
| User Site | 3102 | ✅ Listening |
| Genesis Frontend | 3103 | ✅ Listening |
| Genesis API | 3104 | ✅ Listening |
| Attack Backend | 4000 | ✅ Listening |
| PostgreSQL | 5432 | ✅ Listening |
| Redis | 6379 | ✅ Listening |
| Red Envelope | 8081 | ✅ Listening |

---

## I/O Performance

| Metric | Value |
|--------|-------|
| **CPU User** | 14.73% |
| **CPU System** | 3.40% |
| **CPU Idle** | 81.78% |
| **I/O Wait** | 0.09% |
| **Disk Write Rate** | ~11.5 MB/s |
| **Disk Utilization** | 1.8-2.4% |

---

## Resource Analysis Summary

### Current Load
- **CPU:** Moderate (26.6% average across threads)
- **Memory:** Moderate (52% utilized)
- **Disk:** Low I/O, moderate storage (68% used)
- **Network:** Active blockchain P2P traffic

### Capacity for Additional Workloads
| Resource | Headroom | Notes |
|----------|----------|-------|
| **CPU** | ~73% available | Can add more chains/validators |
| **Memory** | ~28 GiB free | Room for ~11 more chains |
| **Disk** | 146 GB free | Sufficient for months of chain data |

### Recommendations
1. **Memory:** Consider limiting per-container memory if adding more chains
2. **CPU:** AIY chain using most CPU (89.5%) - monitor for bottlenecks
3. **Storage:** Implement log rotation for blockchain data directories
4. **VMware:** VM using 71% CPU - adequate for G4 validators

---

## Container Deployment Summary

### Local Host (192.168.5.1)
- **28 blockchain containers** (7 chains × 4 nodes)
- **4 service containers** (backend, db, redis, admin)
- **Total: 32 containers**

### Remote VM (192.168.5.129)
- **7 blockchain containers** (7 chains × 1 G4 validator each)
- **Total: 7 containers**

### Grand Total
- **35 blockchain validators + 4 service containers = 39 containers**

---

## Health Status

| Component | Status | Details |
|-----------|--------|---------|
| All 7 Chains | ✅ Healthy | Producing checkpoints |
| All 12 Services | ✅ Running | All ports responding |
| Disk I/O | ✅ Normal | Low utilization |
| Memory | ✅ Adequate | 46% available |
| CPU | ✅ Adequate | 73% headroom |

**Last Updated:** December 12, 2025 20:33 UTC
