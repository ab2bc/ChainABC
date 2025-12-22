/// AB2BC Bridge Token Module
/// Represents wrapped/pegged tokens from other chains in the 7-chain network
/// Chains: ABC, AGO, AIY, AQY, ARY, ASY, AUY
module bridge::bridge_token {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use std::string::{Self, String};
    use std::vector;

    // ============ Error Codes ============
    const E_NOT_AUTHORIZED: u64 = 0;
    const E_INVALID_CHAIN: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_BRIDGE_PAUSED: u64 = 3;
    const E_INVALID_PROOF: u64 = 4;
    const E_ALREADY_PROCESSED: u64 = 5;
    const E_AMOUNT_TOO_LOW: u64 = 6;

    // ============ Chain Identifiers ============
    const CHAIN_ABC: u8 = 1;
    const CHAIN_AGO: u8 = 2;
    const CHAIN_AIY: u8 = 3;
    const CHAIN_AQY: u8 = 4;
    const CHAIN_ARY: u8 = 5;
    const CHAIN_ASY: u8 = 6;
    const CHAIN_AUY: u8 = 7;

    // ============ Structs ============

    /// Witness for creating bridge tokens
    public struct BRIDGE_TOKEN has drop {}

    /// Wrapped token representing assets from another chain
    /// Each chain will have 6 of these (one for each other chain's native token)
    public struct WrappedToken<phantom T> has key, store {
        id: UID,
        /// The source chain this token originates from
        source_chain: u8,
        /// Symbol of the original token
        original_symbol: String,
        /// Decimals (matching source chain)
        decimals: u8,
    }

    /// Treasury capability for minting/burning wrapped tokens
    public struct BridgeTreasury<phantom T> has key, store {
        id: UID,
        cap: TreasuryCap<T>,
        /// Total locked on this chain (for native tokens being bridged out)
        total_locked: Balance<T>,
        /// Source chain ID
        source_chain: u8,
    }

    /// Bridge configuration and state
    public struct BridgeConfig has key {
        id: UID,
        /// This chain's identifier
        this_chain: u8,
        /// Admin address
        admin: address,
        /// Relayer addresses (multisig threshold)
        relayers: vector<address>,
        /// Required signatures for relay
        threshold: u64,
        /// Bridge paused state
        paused: bool,
        /// Minimum bridge amount
        min_bridge_amount: u64,
        /// Fee percentage (basis points, 100 = 1%)
        fee_bps: u64,
        /// Fee collector address
        fee_collector: address,
    }

    /// Processed transaction tracker to prevent replay
    public struct ProcessedTxs has key {
        id: UID,
        /// Mapping of source_chain -> tx_hash -> processed
        processed: vector<vector<u8>>,
    }

    // ============ Events ============

    /// Emitted when tokens are locked for bridging out
    public struct TokensLocked has copy, drop {
        sender: address,
        recipient: vector<u8>,  // Recipient address on destination chain
        source_chain: u8,
        dest_chain: u8,
        amount: u64,
        fee: u64,
        nonce: u64,
    }

    /// Emitted when wrapped tokens are minted (bridge in)
    public struct TokensMinted has copy, drop {
        recipient: address,
        source_chain: u8,
        source_tx_hash: vector<u8>,
        amount: u64,
    }

    /// Emitted when wrapped tokens are burned for redemption
    public struct TokensBurned has copy, drop {
        sender: address,
        recipient: vector<u8>,  // Recipient on source chain
        source_chain: u8,
        amount: u64,
        nonce: u64,
    }

    /// Emitted when native tokens are released (bridge back)
    public struct TokensReleased has copy, drop {
        recipient: address,
        source_chain: u8,
        source_tx_hash: vector<u8>,
        amount: u64,
    }

    // ============ Initialization ============

    /// Initialize the bridge for this chain
    public fun init_bridge(
        this_chain: u8,
        admin: address,
        relayers: vector<address>,
        threshold: u64,
        ctx: &mut TxContext
    ) {
        assert!(this_chain >= CHAIN_ABC && this_chain <= CHAIN_AUY, E_INVALID_CHAIN);
        
        let config = BridgeConfig {
            id: object::new(ctx),
            this_chain,
            admin,
            relayers,
            threshold,
            paused: false,
            min_bridge_amount: 1000000,  // 0.001 tokens (6 decimals)
            fee_bps: 30,  // 0.3% fee
            fee_collector: admin,
        };
        
        let processed = ProcessedTxs {
            id: object::new(ctx),
            processed: vector::empty(),
        };
        
        transfer::share_object(config);
        transfer::share_object(processed);
    }

    // ============ Bridge Out (Lock & Burn) ============

    /// Lock native tokens to bridge to another chain
    /// Returns a receipt that relayers will use to mint on destination
    public fun bridge_out<T>(
        config: &BridgeConfig,
        treasury: &mut BridgeTreasury<T>,
        mut coin: Coin<T>,
        dest_chain: u8,
        recipient: vector<u8>,
        nonce: u64,
        ctx: &mut TxContext
    ) {
        assert!(!config.paused, E_BRIDGE_PAUSED);
        assert!(dest_chain >= CHAIN_ABC && dest_chain <= CHAIN_AUY, E_INVALID_CHAIN);
        assert!(dest_chain != config.this_chain, E_INVALID_CHAIN);
        
        let amount = coin::value(&coin);
        assert!(amount >= config.min_bridge_amount, E_AMOUNT_TOO_LOW);
        
        // Calculate and deduct fee
        let fee = (amount * config.fee_bps) / 10000;
        let bridge_amount = amount - fee;
        
        // Split fee and send to collector
        let fee_coin = coin::split(&mut coin, fee, ctx);
        transfer::public_transfer(fee_coin, config.fee_collector);
        
        // Lock the remaining tokens
        let locked_balance = coin::into_balance(coin);
        balance::join(&mut treasury.total_locked, locked_balance);
        
        // Emit event for relayers
        event::emit(TokensLocked {
            sender: tx_context::sender(ctx),
            recipient,
            source_chain: config.this_chain,
            dest_chain,
            amount: bridge_amount,
            fee,
            nonce,
        });
    }

    /// Burn wrapped tokens to redeem on source chain
    public fun bridge_back<T>(
        config: &BridgeConfig,
        treasury: &mut BridgeTreasury<T>,
        coin: Coin<T>,
        recipient: vector<u8>,
        nonce: u64,
        ctx: &mut TxContext
    ) {
        assert!(!config.paused, E_BRIDGE_PAUSED);
        
        let amount = coin::value(&coin);
        assert!(amount >= config.min_bridge_amount, E_AMOUNT_TOO_LOW);
        
        // Burn the wrapped tokens
        coin::burn(&mut treasury.cap, coin);
        
        // Emit event for relayers to release on source chain
        event::emit(TokensBurned {
            sender: tx_context::sender(ctx),
            recipient,
            source_chain: treasury.source_chain,
            amount,
            nonce,
        });
    }

    // ============ Bridge In (Mint & Release) ============

    /// Mint wrapped tokens after verifying relay proof
    /// Called by relayers with multi-sig threshold
    public fun mint_wrapped<T>(
        config: &BridgeConfig,
        treasury: &mut BridgeTreasury<T>,
        processed: &mut ProcessedTxs,
        recipient: address,
        amount: u64,
        source_chain: u8,
        source_tx_hash: vector<u8>,
        _signatures: vector<vector<u8>>,  // Relayer signatures
        ctx: &mut TxContext
    ) {
        assert!(!config.paused, E_BRIDGE_PAUSED);
        assert!(is_relayer(config, tx_context::sender(ctx)), E_NOT_AUTHORIZED);
        
        // Check not already processed
        assert!(!is_processed(processed, &source_tx_hash), E_ALREADY_PROCESSED);
        
        // TODO: Verify threshold signatures
        // For MVP, single relayer is trusted
        
        // Mark as processed
        vector::push_back(&mut processed.processed, source_tx_hash);
        
        // Mint wrapped tokens to recipient
        let minted = coin::mint(&mut treasury.cap, amount, ctx);
        transfer::public_transfer(minted, recipient);
        
        // Emit event
        event::emit(TokensMinted {
            recipient,
            source_chain,
            source_tx_hash: vector::empty(),  // Already stored
            amount,
        });
    }

    /// Release native tokens after verifying burn proof from another chain
    public fun release_native<T>(
        config: &BridgeConfig,
        treasury: &mut BridgeTreasury<T>,
        processed: &mut ProcessedTxs,
        recipient: address,
        amount: u64,
        source_chain: u8,
        source_tx_hash: vector<u8>,
        _signatures: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        assert!(!config.paused, E_BRIDGE_PAUSED);
        assert!(is_relayer(config, tx_context::sender(ctx)), E_NOT_AUTHORIZED);
        assert!(!is_processed(processed, &source_tx_hash), E_ALREADY_PROCESSED);
        
        // Verify sufficient locked balance
        assert!(balance::value(&treasury.total_locked) >= amount, E_INSUFFICIENT_BALANCE);
        
        // Mark as processed
        vector::push_back(&mut processed.processed, source_tx_hash);
        
        // Release tokens
        let released = coin::from_balance(
            balance::split(&mut treasury.total_locked, amount),
            ctx
        );
        transfer::public_transfer(released, recipient);
        
        event::emit(TokensReleased {
            recipient,
            source_chain,
            source_tx_hash: vector::empty(),
            amount,
        });
    }

    // ============ Admin Functions ============

    /// Pause the bridge (emergency)
    public fun pause(config: &mut BridgeConfig, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        config.paused = true;
    }

    /// Unpause the bridge
    public fun unpause(config: &mut BridgeConfig, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        config.paused = false;
    }

    /// Update relayers
    public fun update_relayers(
        config: &mut BridgeConfig,
        new_relayers: vector<address>,
        new_threshold: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        config.relayers = new_relayers;
        config.threshold = new_threshold;
    }

    /// Update fee
    public fun update_fee(
        config: &mut BridgeConfig,
        new_fee_bps: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        assert!(new_fee_bps <= 1000, E_NOT_AUTHORIZED);  // Max 10%
        config.fee_bps = new_fee_bps;
    }

    // ============ View Functions ============

    public fun is_relayer(config: &BridgeConfig, addr: address): bool {
        let mut i = 0;
        let len = vector::length(&config.relayers);
        while (i < len) {
            if (*vector::borrow(&config.relayers, i) == addr) {
                return true
            };
            i = i + 1;
        };
        false
    }

    public fun is_processed(processed: &ProcessedTxs, tx_hash: &vector<u8>): bool {
        let mut i = 0;
        let len = vector::length(&processed.processed);
        while (i < len) {
            if (vector::borrow(&processed.processed, i) == tx_hash) {
                return true
            };
            i = i + 1;
        };
        false
    }

    public fun get_this_chain(config: &BridgeConfig): u8 {
        config.this_chain
    }

    public fun is_paused(config: &BridgeConfig): bool {
        config.paused
    }

    public fun get_fee_bps(config: &BridgeConfig): u64 {
        config.fee_bps
    }

    // ============ Test Helper Functions ============

    // Error codes for test helpers
    const E_NOT_RELAYER: u64 = 7;
    const E_INVALID_THRESHOLD: u64 = 8;
    const E_FEE_TOO_HIGH: u64 = 9;

    /// Initialize bridge configuration with custom parameters
    public fun init_bridge_custom(
        this_chain: u8,
        admin: address,
        relayers: vector<address>,
        threshold: u64,
        min_bridge_amount: u64,
        fee_bps: u64,
        fee_collector: address,
        ctx: &mut TxContext
    ) {
        assert!(threshold > 0 && threshold <= vector::length(&relayers), E_INVALID_THRESHOLD);
        assert!(fee_bps <= 1000, E_FEE_TOO_HIGH);
        
        let config = BridgeConfig {
            id: object::new(ctx),
            this_chain,
            admin,
            relayers,
            threshold,
            paused: false,
            min_bridge_amount,
            fee_bps,
            fee_collector,
        };
        
        let processed = ProcessedTxs {
            id: object::new(ctx),
            processed: vector::empty(),
        };
        
        transfer::share_object(config);
        transfer::share_object(processed);
    }

    /// Pause bridge (admin only)
    public fun pause_bridge(config: &mut BridgeConfig, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        config.paused = true;
    }

    /// Set fee (admin only)
    public fun set_fee(config: &mut BridgeConfig, new_fee_bps: u64, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        assert!(new_fee_bps <= 1000, E_FEE_TOO_HIGH);
        config.fee_bps = new_fee_bps;
    }

    /// Check if bridge is not paused
    public fun check_not_paused(config: &BridgeConfig) {
        assert!(!config.paused, E_BRIDGE_PAUSED);
    }

    /// Check minimum bridge amount
    public fun check_minimum_amount(config: &BridgeConfig, amount: u64) {
        assert!(amount >= config.min_bridge_amount, E_AMOUNT_TOO_LOW);
    }

    /// Validate chain ID
    public fun validate_chain(chain_id: u8) {
        assert!(chain_id >= CHAIN_ABC && chain_id <= CHAIN_AUY, E_INVALID_CHAIN);
    }

    /// Calculate fee for amount
    public fun calculate_fee(amount: u64, fee_bps: u64): u64 {
        (amount * fee_bps) / 10000
    }

    /// Get threshold
    public fun get_threshold(config: &BridgeConfig): u64 {
        config.threshold
    }

    /// Mark transaction as processed
    public fun mark_processed(processed: &mut ProcessedTxs, tx_hash: vector<u8>) {
        assert!(!is_processed(processed, &tx_hash), E_ALREADY_PROCESSED);
        vector::push_back(&mut processed.processed, tx_hash);
    }

    /// Check if address is a relayer
    public fun check_is_relayer(config: &BridgeConfig, addr: address) {
        assert!(is_relayer(config, addr), E_NOT_RELAYER);
    }
}
