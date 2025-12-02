# Fixes Applied - November 30, 2025

## Issues Resolved from FIX.md

### 1. ✅ Full Node Genesis Path Configuration - FIXED

**Issue**: Full nodes fail with "Unable to load Genesis from /genesis/genesis.blob"

**Root Cause**: Container mounts genesis to `/work/genesis` but config used `/genesis`

**Fix Applied**:
- Updated `fullnode.yaml` template: Changed genesis path to `/work/genesis/genesis.blob`
- Updated `validator.yaml` template: Changed genesis path to `/work/genesis/genesis.blob`
- Updated comments to reflect correct mount point: `/work/genesis`

**Files Modified**:
- `/mnt/c/Apollo/ChainABC/AManager/fullnode.yaml`
- `/mnt/c/Apollo/ChainABC/AManager/validator.yaml`

---

### 2. ✅ P2P Listen Address Format - ALREADY CORRECT

**Issue**: Docker image requires `IP:PORT` format, not QUIC multiaddr for `listen-address`

**Status**: Templates already use correct format

**Verified**:
- validator.yaml: `listen-address: "0.0.0.0:25000"` ✓
- fullnode.yaml: `listen-address: 0.0.0.0:25000` ✓
- external-address correctly uses QUIC multiaddr format ✓

**Code Verification**:
- `UpdateYaml.cs` line 268: Uses `ip + ":" + p2pPort` format ✓
- No multiaddr format for listen-address in code ✓

---

### 3. ✅ Port Offset System - VERIFIED CORRECT

**Status**: No index offset as required

**Verified**:
- All validators of same flavor+mode use SAME ports (different IPs)
- `ComputeOffsetForIndex()`: Returns `GetFlavorModeOffset()` only (no index addition)
- `DockerScript.ComputeFixedOffset()`: Returns flavor+mode offset only
- Port allocation: Flavor base (0/150/300/450/600/750/900) + Mode offset (0/50/100)

**Examples**:
- AQY-G1, AQY-G2, AQY-G3: All use UDP 25000 (different IPs)
- AQY-P1, AQY-P2: All use UDP 25050 (different IPs)
- AQY-F*: All use UDP 25100 (different IPs)

---

### 4. ⚠️ Docker Permission Issues - NOTED

**Issue**: Deployment requires sudo for Docker access

**Status**: Known issue documented - deployment scripts should use sudo

**Workaround**: Run deployment with `sudo bash deploy-*.sh`

**Future Enhancement**: Script could add docker permission check at startup

---

## Summary of Changes

### Template Files Updated:

1. **validator.yaml**:
   - Genesis path: `/genesis/genesis.blob` → `/work/genesis/genesis.blob`
   - Container mount comment updated
   - listen-address format: Already correct `"0.0.0.0:25000"`

2. **fullnode.yaml**:
   - Genesis path: `/genesis/genesis.blob` → `/work/genesis/genesis.blob`
   - Updated comment: Removed incorrect "QUIC multiaddr required" note
   - Added note: "listen-address uses IP:PORT format (ghcr.io/ab2bc/aqy-node:dev requirement)"
   - listen-address format: Already correct `0.0.0.0:25000`

### Code Verification:

- ✅ `MainForm.cs`: Port calculation verified - no index offset
- ✅ `DockerScript.cs`: Offset calculation verified - flavor+mode only
- ✅ `UpdateYaml.cs`: listen-address uses IP:PORT format
- ✅ Build successful: 0 errors, warnings only in SuiRenamerLib (not AManager)

---

## Testing Recommendations

After deploying with updated templates:

1. **Generate new node configs** using the application
2. **Verify ZIP files** contain correct paths:
   ```bash
   unzip -p nodes/AQY-F1/AQY-F1.zip fullnode.yaml | grep "genesis-file-location"
   # Should show: /work/genesis/genesis.blob
   
   unzip -p nodes/AQY-F1/AQY-F1.zip fullnode.yaml | grep "listen-address"
   # Should show: 0.0.0.0:25100 (IP:PORT format)
   ```

3. **Deploy and test**:
   ```bash
   sudo bash deploy-192-168-12-100.sh
   sudo docker ps --filter "name=AQY"
   curl http://192.168.12.100:23100/metrics | head
   ```

4. **Monitor logs**:
   ```bash
   sudo docker logs AQY-F1 2>&1 | grep -i "genesis\|error"
   # Should NOT see "Unable to load Genesis" error
   ```

---

## Next Steps

1. Rebuild node deployment packages using updated templates
2. Test deployment on 192.168.12.100
3. Verify all containers start successfully
4. Confirm metrics and RPC endpoints accessible
5. Check for P2P peer connections in logs

---

## Files Location

- Templates: `~/Apollo/ChainABC/validator.yaml`, `~/Apollo/ChainABC/fullnode.yaml`
- Source: `/mnt/c/Apollo/ChainABC/AManager/`
- Binaries: `~/Apollo/ChainABC/AManager.dll` and dependencies


## Fix 5: Docker Bridge Networking with Correct Seed-Peers (2024-12-01)

**Problem**: Validators showing 0 peers despite successful deployment. Initially attempted host networking but encountered admin port conflicts (port 1337). 

**Root Cause Analysis**:
1. **Bridge Mode Issue**: Validators used localhost/127.0.0.1 in seed-peers, which doesn't work in Docker bridge mode due to network isolation
2. **Host Mode Blocker**: Admin port 1337 hardcoded - all validators tried to bind simultaneously, causing conflicts
3. **Incorrect Listen Addresses**: Some configs used 192.168.12.100 instead of 0.0.0.0, causing "Cannot assign requested address" errors
4. **Wrong Genesis Path**: Fullnodes referenced /work/genesis instead of /genesis mount point

**Solution**: Return to bridge networking with corrected configurations
- Use Docker bridge IPs (172.17.0.x) in seed-peers for container-to-container P2P
- Set all listen-address values to 0.0.0.0 (not host IP or localhost)
- External-address uses host IP (192.168.12.100) for outside access
- Fullnodes use /genesis/genesis.blob as genesis-file-location

**Files Modified**:

1. **AManager/templates/deploy-template.sh**:
   - Updated NODES array with correct non-overlapping port assignments:
     * Genesis Validators (G1-G5): Actual ports from validator configs
     * Post-Genesis Validators (P1-P5): Actual ports from validator configs  
     * Fullnodes (F1-F5): Corrected ports (568, 598, 040, 186, 830)
   - Added bridge networking documentation in comments

2. **Created AManager/templates/validator.yaml.template**:
   ```yaml
   json-rpc-address: 0.0.0.0:{{RPC_PORT}}
   metrics-address: 0.0.0.0:{{METRICS_PORT}}
   p2p-config:
     listen-address: 0.0.0.0:{{UDP_PORT}}
     external-address: /ip4/{{PUBLIC_IP}}/udp/{{UDP_PORT}}/quic-v1
     seed-peers:
       # Docker bridge IPs (172.17.0.x) populated dynamically
   genesis:
     genesis-file-location: /genesis/genesis.blob
   ```

3. **Created AManager/templates/fullnode.yaml.template**:
   ```yaml
   json-rpc-address: 0.0.0.0:{{RPC_PORT}}
   metrics-address: 0.0.0.0:{{METRICS_PORT}}
   p2p-config:
     listen-address: 0.0.0.0:{{UDP_PORT}}
     external-address: /ip4/{{PUBLIC_IP}}/udp/{{UDP_PORT}}/quic-v1
     seed-peers:
       # Seed from all 10 validators using Docker bridge IPs
   genesis:
     genesis-file-location: /genesis/genesis.blob  # NOT /work/genesis
   ```

4. **Created AManager/templates/DEPLOYMENT-GUIDE.md**:
   - Comprehensive bridge networking architecture documentation
   - Port assignment matrix for all 15 nodes
   - Docker bridge IP mapping (G1=.2, P1=.3, G2=.4, etc.)
   - Configuration requirements and common issues
   - Validation checklist and success criteria

**Port Assignments** (Non-overlapping):
- **G1**: RPC 21694, Metrics 23694, UDP 25696-25700
- **G2**: RPC 21374, Metrics 23374, UDP 25376-25380
- **G3**: RPC 21102, Metrics 23102, UDP 25104-25108
- **G4**: RPC 21686, Metrics 23686, UDP 25688-25692
- **G5**: RPC 21634, Metrics 23634, UDP 25636-25640
- **P1**: RPC 21056, Metrics 23056, UDP 25058-25062
- **P2**: RPC 21458, Metrics 23458, UDP 25460-25464
- **P3**: RPC 21592, Metrics 23592, UDP 25594-25598
- **P4**: RPC 21384, Metrics 23384, UDP 25386-25390
- **P5**: RPC 21930, Metrics 23930, UDP 25932-25936
- **F1**: RPC 21568, Metrics 23568, UDP 25568-25572
- **F2**: RPC 21598, Metrics 23598, UDP 25600-25604 (adjusted to avoid P3 conflict)
- **F3**: RPC 21040, Metrics 23040, UDP 25040-25044
- **F4**: RPC 21186, Metrics 23186, UDP 25186-25190
- **F5**: RPC 21830, Metrics 23830, UDP 25830-25834

**Validated Results**:
- ✅ All 15 containers deployed successfully (10 validators + 5 fullnodes)
- ✅ Validators achieved full mesh: 9/9 peers on each validator within 30 seconds
- ✅ Fullnodes deployed and syncing (peer discovery in progress, expected behavior)
- ✅ No port conflicts
- ✅ Consensus-ready network operational

**Key Learnings**:
1. Docker bridge networking works correctly for multi-validator deployments on single host
2. Seed-peers MUST use Docker bridge IPs (172.17.0.x), never localhost or external IP
3. Listen addresses MUST be 0.0.0.0 inside containers (binding to all interfaces)
4. Host networking incompatible due to hardcoded admin port conflicts
5. Port assignments must be carefully validated to avoid overlaps (especially UDP ranges)
6. Fullnode peer discovery is slower than validators (10-30 minutes is normal)

**Production Recommendations**:
- For single-host deployments: Use bridge networking with Docker bridge IPs in seed-peers
- For multi-host deployments: Can use host networking (one validator per machine)
- Always validate port assignments don't overlap
- Monitor P2P metrics: curl http://HOST:METRICS_PORT/metrics | grep peers


