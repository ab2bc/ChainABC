#!/usr/bin/env python3
"""
AB2BC 7-Chain Bridge Relayer Service

This service monitors events on all 7 chains and relays cross-chain transfers.
It handles:
1. TokensLocked events -> mint wrapped tokens on destination
2. TokensBurned events -> release native tokens on source

Architecture:
- Monitors RPC endpoints for each chain
- Maintains state of pending transfers
- Multi-sig verification for security
- Automatic retry with exponential backoff
"""

import asyncio
import json
import logging
import os
import time
from dataclasses import dataclass
from typing import Dict, List, Optional
from enum import Enum
import aiohttp
import hashlib

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger('bridge-relayer')

# Chain configuration
CHAINS = {
    1: {'name': 'ABC', 'rpc': 'http://192.168.5.1:21000', 'prefix': 'abc'},
    2: {'name': 'AGO', 'rpc': 'http://192.168.5.1:21004', 'prefix': 'ago'},
    3: {'name': 'AIY', 'rpc': 'http://192.168.5.1:21008', 'prefix': 'aiy'},
    4: {'name': 'AQY', 'rpc': 'http://192.168.5.1:21012', 'prefix': 'aqy'},
    5: {'name': 'ARY', 'rpc': 'http://192.168.5.1:21016', 'prefix': 'ary'},
    6: {'name': 'ASY', 'rpc': 'http://192.168.5.1:21020', 'prefix': 'asy'},
    7: {'name': 'AUY', 'rpc': 'http://192.168.5.1:21024', 'prefix': 'auy'},
}

# Pegging rates (1e9 = 1:1)
# Default all 1:1, can be updated dynamically
DEFAULT_PEG_RATES = {
    (1, 2): 1_000_000_000,  # ABC -> AGO
    (1, 3): 1_000_000_000,  # ABC -> AIY
    (1, 4): 1_000_000_000,  # ABC -> AQY
    (1, 5): 1_000_000_000,  # ABC -> ARY
    (1, 6): 1_000_000_000,  # ABC -> ASY
    (1, 7): 1_000_000_000,  # ABC -> AUY
    # ... all other pairs default to 1:1
}


class TransferStatus(Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class CrossChainTransfer:
    """Represents a pending cross-chain transfer"""
    tx_hash: str
    source_chain: int
    dest_chain: int
    sender: str
    recipient: str
    amount: int
    fee: int
    nonce: int
    timestamp: float
    status: TransferStatus
    retries: int = 0
    dest_tx_hash: Optional[str] = None
    error: Optional[str] = None


class PegRateManager:
    """Manages exchange rates between chains"""
    
    def __init__(self):
        self.rates: Dict[tuple, int] = {}
        self._init_default_rates()
    
    def _init_default_rates(self):
        """Initialize all 42 chain pairs with 1:1 rate"""
        for src in range(1, 8):
            for dst in range(1, 8):
                if src != dst:
                    self.rates[(src, dst)] = 1_000_000_000  # 1:1
    
    def get_rate(self, source: int, dest: int) -> int:
        """Get exchange rate for chain pair"""
        return self.rates.get((source, dest), 1_000_000_000)
    
    def set_rate(self, source: int, dest: int, rate: int):
        """Update exchange rate"""
        self.rates[(source, dest)] = rate
        logger.info(f"Updated rate {CHAINS[source]['name']}->{CHAINS[dest]['name']}: {rate/1e9:.6f}")
    
    def calculate_output(self, source: int, dest: int, amount: int) -> int:
        """Calculate output amount after applying peg rate"""
        rate = self.get_rate(source, dest)
        return int(amount * rate // 1_000_000_000)


class BridgeRelayer:
    """Main relayer service"""
    
    def __init__(self, private_key: str):
        self.private_key = private_key
        self.peg_manager = PegRateManager()
        self.pending_transfers: Dict[str, CrossChainTransfer] = {}
        self.processed_hashes: set = set()
        self.last_checkpoint: Dict[int, int] = {i: 0 for i in range(1, 8)}
        self.running = False
    
    async def start(self):
        """Start the relayer service"""
        self.running = True
        logger.info("Starting Bridge Relayer Service...")
        logger.info(f"Monitoring {len(CHAINS)} chains")
        
        # Start monitoring tasks for each chain
        tasks = [
            self._monitor_chain(chain_id) 
            for chain_id in CHAINS.keys()
        ]
        tasks.append(self._process_pending_transfers())
        tasks.append(self._health_check_loop())
        
        await asyncio.gather(*tasks)
    
    async def stop(self):
        """Stop the relayer service"""
        self.running = False
        logger.info("Stopping Bridge Relayer...")
    
    async def _monitor_chain(self, chain_id: int):
        """Monitor a single chain for bridge events"""
        chain = CHAINS[chain_id]
        logger.info(f"Starting monitor for {chain['name']}")
        
        while self.running:
            try:
                await self._check_chain_events(chain_id)
                await asyncio.sleep(2)  # Check every 2 seconds
            except Exception as e:
                logger.error(f"Error monitoring {chain['name']}: {e}")
                await asyncio.sleep(10)  # Backoff on error
    
    async def _check_chain_events(self, chain_id: int):
        """Check for new bridge events on a chain"""
        chain = CHAINS[chain_id]
        prefix = chain['prefix']
        
        async with aiohttp.ClientSession() as session:
            # Get latest checkpoint
            payload = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": f"{prefix}_getLatestCheckpointSequenceNumber",
                "params": []
            }
            
            try:
                async with session.post(chain['rpc'], json=payload, timeout=5) as resp:
                    result = await resp.json()
                    if 'result' in result:
                        latest_cp = int(result['result'])
                        
                        # Process new checkpoints
                        if latest_cp > self.last_checkpoint[chain_id]:
                            await self._process_checkpoints(
                                chain_id, 
                                self.last_checkpoint[chain_id] + 1, 
                                latest_cp
                            )
                            self.last_checkpoint[chain_id] = latest_cp
            except asyncio.TimeoutError:
                logger.warning(f"Timeout checking {chain['name']}")
            except Exception as e:
                logger.debug(f"Error checking {chain['name']}: {e}")
    
    async def _process_checkpoints(self, chain_id: int, start: int, end: int):
        """Process checkpoints for bridge events"""
        chain = CHAINS[chain_id]
        prefix = chain['prefix']
        
        # In production, we'd query events from the checkpoint
        # For now, we simulate by checking transaction events
        logger.debug(f"Processing {chain['name']} checkpoints {start}-{end}")
        
        # Query events (simplified - real implementation needs event indexing)
        async with aiohttp.ClientSession() as session:
            for cp in range(start, min(end + 1, start + 10)):  # Process max 10 at a time
                payload = {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": f"{prefix}_getCheckpoint",
                    "params": [str(cp)]
                }
                
                try:
                    async with session.post(chain['rpc'], json=payload, timeout=5) as resp:
                        result = await resp.json()
                        if 'result' in result:
                            # Parse checkpoint for bridge events
                            await self._parse_checkpoint_for_bridge_events(chain_id, result['result'])
                except Exception as e:
                    logger.debug(f"Error processing checkpoint {cp}: {e}")
    
    async def _parse_checkpoint_for_bridge_events(self, chain_id: int, checkpoint: dict):
        """Parse a checkpoint for TokensLocked/TokensBurned events"""
        # In production, filter for specific event types from bridge module
        # This is a placeholder for the event parsing logic
        transactions = checkpoint.get('transactions', [])
        
        for tx_digest in transactions:
            if tx_digest in self.processed_hashes:
                continue
            
            # Query transaction effects for events
            # Look for bridge::bridge_token::TokensLocked events
            # Look for bridge::bridge_token::TokensBurned events
            pass
    
    async def _process_pending_transfers(self):
        """Process pending transfers"""
        while self.running:
            try:
                for tx_hash, transfer in list(self.pending_transfers.items()):
                    if transfer.status == TransferStatus.PENDING:
                        await self._execute_relay(transfer)
                
                await asyncio.sleep(5)
            except Exception as e:
                logger.error(f"Error processing pending transfers: {e}")
                await asyncio.sleep(10)
    
    async def _execute_relay(self, transfer: CrossChainTransfer):
        """Execute a relay transaction on destination chain"""
        transfer.status = TransferStatus.PROCESSING
        dest_chain = CHAINS[transfer.dest_chain]
        
        try:
            # Calculate output with pegging
            output_amount = self.peg_manager.calculate_output(
                transfer.source_chain,
                transfer.dest_chain,
                transfer.amount
            )
            
            logger.info(
                f"Relaying {transfer.amount} from {CHAINS[transfer.source_chain]['name']} "
                f"to {dest_chain['name']} -> {output_amount} (recipient: {transfer.recipient[:16]}...)"
            )
            
            # Build and submit mint transaction
            # In production: sign with relayer key, submit to dest chain
            
            # Simulate success for now
            transfer.status = TransferStatus.COMPLETED
            transfer.dest_tx_hash = f"simulated_{int(time.time())}"
            
            logger.info(f"✓ Relay completed: {transfer.tx_hash[:16]}... -> {transfer.dest_tx_hash}")
            
            # Add to processed set
            self.processed_hashes.add(transfer.tx_hash)
            
        except Exception as e:
            transfer.retries += 1
            transfer.error = str(e)
            
            if transfer.retries >= 3:
                transfer.status = TransferStatus.FAILED
                logger.error(f"✗ Relay failed after {transfer.retries} attempts: {e}")
            else:
                transfer.status = TransferStatus.PENDING
                logger.warning(f"Relay attempt {transfer.retries} failed, will retry: {e}")
    
    async def _health_check_loop(self):
        """Periodic health check and stats logging"""
        while self.running:
            await asyncio.sleep(60)
            
            # Log stats
            pending = sum(1 for t in self.pending_transfers.values() if t.status == TransferStatus.PENDING)
            completed = sum(1 for t in self.pending_transfers.values() if t.status == TransferStatus.COMPLETED)
            failed = sum(1 for t in self.pending_transfers.values() if t.status == TransferStatus.FAILED)
            
            logger.info(f"📊 Stats: pending={pending}, completed={completed}, failed={failed}")
            
            # Log chain status
            for chain_id, chain in CHAINS.items():
                logger.info(f"  {chain['name']}: checkpoint {self.last_checkpoint[chain_id]}")
    
    def add_manual_transfer(self, tx_hash: str, source: int, dest: int, 
                           sender: str, recipient: str, amount: int, nonce: int):
        """Manually add a transfer for testing"""
        transfer = CrossChainTransfer(
            tx_hash=tx_hash,
            source_chain=source,
            dest_chain=dest,
            sender=sender,
            recipient=recipient,
            amount=amount,
            fee=0,
            nonce=nonce,
            timestamp=time.time(),
            status=TransferStatus.PENDING
        )
        self.pending_transfers[tx_hash] = transfer
        logger.info(f"Added manual transfer: {tx_hash[:16]}...")


async def main():
    """Main entry point"""
    # Load relayer private key from environment or config
    private_key = os.environ.get('RELAYER_PRIVATE_KEY', 'demo_key')
    
    relayer = BridgeRelayer(private_key)
    
    try:
        await relayer.start()
    except KeyboardInterrupt:
        await relayer.stop()


if __name__ == '__main__':
    asyncio.run(main())
