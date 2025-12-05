# AQY Network Deployment Status

**Date**: December 5, 2025  
**Status**: ✅ **FULLY OPERATIONAL** - 15 nodes deployed, consensus active

## Network Overview

| Component | Count | Status |
|-----------|-------|--------|
| Genesis Validators | 5 (G1-G5) | ✅ Active in consensus |
| Post-Genesis Validators | 5 (P1-P5) | ✅ Running, healthy |
| Fullnodes | 5 (F1-F5) | ✅ Running, RPC available |
| **Total Containers** | **15** | ✅ All healthy |

## Consensus Status

- **Consensus Engine**: Mysticeti
- **Protocol Version**: v100
- **Epoch**: 0 (genesis)
- **Commit Rate**: ~51ms
- **Checkpoints**: Progressing normally

## Network Configuration

### Host Configuration
- **Host IP**: 192.168.12.100
- **Docker Network**: Bridge mode (172.17.0.x containers)
- **Docker Image**: `ghcr.io/ab2bc/aqy-node:dev` (192.9MB)

### Port Allocation Scheme

| Service | Port Range | Protocol |
|---------|------------|----------|
| JSON-RPC | 21xxx | TCP |
| Prometheus Metrics | 23xxx | TCP |
| P2P Network | 25xxx | UDP (5 ports per node) |
| Consensus | 26xxx | TCP (2 ports per node) |

## RPC Endpoints

Fullnodes provide JSON-RPC for transaction submission:

| Node | RPC Endpoint | Metrics |
|------|--------------|---------|
| F1 | http://192.168.12.100:21130 | :23130 |
| F2 | http://192.168.12.100:21866 | :23866 |
| F3 | http://192.168.12.100:21676 | :23676 |
| F4 | http://192.168.12.100:21900 | :23900 |
| F5 | http://192.168.12.100:21786 | :23786 |

**Note**: Validators (G1-G5, P1-P5) participate in consensus only and do not expose JSON-RPC.

## Genesis Configuration

- **Genesis File**: `genesis.blob` (447,010 bytes)
- **Genesis Validators**: 5 (equal voting power)
- **Validator Stake**: 20,000,000 AQY each
- **Total Stake**: 100,000,000 AQY

## Deployment Script

The deployment uses `deploy-192-168-12-100.sh` which:

1. **Phase 1**: Deploys genesis files to all nodes
2. **Phase 2**: Pulls/updates Docker images
3. **Phase 3**: Prepares node configurations with correct port mappings
4. **Phase 4**: Deploys all 15 containers with proper networking
5. **Phase 5**: Health monitoring and connectivity verification

### Running the Deployment

```bash
cd /home/apollo/Apollo/ab2bc/deploy-192-168-12-100
nohup ./deploy-192-168-12-100.sh > /tmp/deploy.log 2>&1 &
tail -f /tmp/deploy.log
```

### Checking Status

```bash
# Container count
docker ps --filter "name=AQY" --format "{{.Names}}" | wc -l

# Consensus status
docker logs AQY-G1 2>&1 | tail -5

# RPC test
curl -s http://127.0.0.1:21130 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"suix_getLatestSuiSystemState","params":[]}'
```

## Key Fixes Applied

1. **Genesis Mount Path**: Fixed mount from `/opt/sui/genesis` to `/genesis:ro`
2. **P2P Seed Peers**: Updated to use Docker bridge IPs (172.17.0.x) for container-to-container communication
3. **Port Extraction**: Correctly extracts ports from genesis.blob for each validator
4. **Progressive Mesh Updates**: Restarts containers with updated seed-peers as more validators join

## Transaction Readiness

The network is **ready for blockchain transactions**:

- ✅ Consensus achieving commits every ~50ms
- ✅ Checkpoints being created and certified
- ✅ JSON-RPC available on fullnodes
- ✅ All RPC methods available (transfer, stake, publish, etc.)

### Example RPC Calls

```bash
# Get system state
curl -s http://127.0.0.1:21130 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"suix_getLatestSuiSystemState","params":[]}'

# Get coin metadata
curl -s http://127.0.0.1:21130 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"suix_getCoinMetadata","params":["0x2::sui::SUI"]}'
```

---

*Last Updated: December 5, 2025*
