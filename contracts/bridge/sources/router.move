/// AB2BC Bridge Router Module  
/// Main entry point for cross-chain transfers with pegging support
/// Coordinates between bridge_token and pegging modules
module bridge::router {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::clock::Clock;
    use bridge::bridge_token::{Self, BridgeConfig, BridgeTreasury, ProcessedTxs};
    use bridge::pegging::{Self, PeggingRegistry};
    use std::vector;

    // ============ Error Codes ============
    const E_SLIPPAGE_EXCEEDED: u64 = 200;
    const E_ROUTE_NOT_FOUND: u64 = 201;
    const E_STALE_RATE: u64 = 202;

    // ============ Structs ============

    /// Route for multi-hop bridges (if needed)
    public struct BridgeRoute has store, copy, drop {
        hops: vector<u8>,  // Chain IDs in order
        rates: vector<u64>, // Rates at each hop
    }

    /// Bridge request with slippage protection
    public struct BridgeRequest has key, store {
        id: UID,
        sender: address,
        source_chain: u8,
        dest_chain: u8,
        amount_in: u64,
        min_amount_out: u64,
        recipient: vector<u8>,
        deadline: u64,
        nonce: u64,
    }

    // ============ Events ============

    public struct CrossChainSwap has copy, drop {
        sender: address,
        source_chain: u8,
        dest_chain: u8,
        amount_in: u64,
        amount_out: u64,
        rate_used: u64,
        fee: u64,
        nonce: u64,
    }

    // ============ Main Bridge Functions ============

    /// Bridge tokens to another chain with pegging and slippage protection
    public fun bridge_with_peg<T>(
        bridge_config: &BridgeConfig,
        treasury: &mut BridgeTreasury<T>,
        peg_registry: &PeggingRegistry,
        clock: &Clock,
        coin: Coin<T>,
        dest_chain: u8,
        recipient: vector<u8>,
        min_amount_out: u64,
        nonce: u64,
        ctx: &mut TxContext
    ) {
        let source_chain = bridge_token::get_this_chain(bridge_config);
        let amount_in = coin::value(&coin);
        
        // Check rate is fresh
        assert!(
            pegging::is_rate_fresh(peg_registry, source_chain, dest_chain, clock),
            E_STALE_RATE
        );
        
        // Calculate output with pegging rate
        let amount_out = pegging::calculate_output(
            peg_registry,
            source_chain,
            dest_chain,
            amount_in
        );
        
        // Slippage check
        assert!(amount_out >= min_amount_out, E_SLIPPAGE_EXCEEDED);
        
        // Get the rate for event
        let (rate, _, _) = pegging::get_rate(peg_registry, source_chain, dest_chain);
        
        // Execute bridge (locks tokens)
        bridge_token::bridge_out(
            bridge_config,
            treasury,
            coin,
            dest_chain,
            recipient,
            nonce,
            ctx
        );
        
        // Emit cross-chain swap event
        event::emit(CrossChainSwap {
            sender: tx_context::sender(ctx),
            source_chain,
            dest_chain,
            amount_in,
            amount_out,
            rate_used: rate,
            fee: bridge_token::get_fee_bps(bridge_config),
            nonce,
        });
    }

    /// Quote bridge output (view function for UI)
    public fun quote_bridge(
        bridge_config: &BridgeConfig,
        peg_registry: &PeggingRegistry,
        dest_chain: u8,
        amount_in: u64
    ): (u64, u64, u64) {  // Returns (amount_out, rate, fee)
        let source_chain = bridge_token::get_this_chain(bridge_config);
        let fee_bps = bridge_token::get_fee_bps(bridge_config);
        
        // Calculate fee
        let fee = (amount_in * fee_bps) / 10000;
        let amount_after_fee = amount_in - fee;
        
        // Get rate and calculate output
        let (rate, _, _) = pegging::get_rate(peg_registry, source_chain, dest_chain);
        let amount_out = ((amount_after_fee as u128) * (rate as u128) / 1_000_000_000 as u64);
        
        (amount_out, rate, fee)
    }

    /// Get all available routes from this chain
    public fun get_available_routes(
        peg_registry: &PeggingRegistry,
        source_chain: u8
    ): vector<u8> {
        // Returns list of destination chains with configured rates
        let routes = vector::empty<u8>();
        let all_rates = pegging::get_all_rates_for_chain(peg_registry, source_chain);
        
        let mut i = 0;
        let len = vector::length(&all_rates);
        while (i < len) {
            // Extract dest_chain from each rate
            // Note: In real implementation, we'd have a getter for this
            i = i + 1;
        };
        
        routes
    }

    // ============ Test Helper Functions ============

    /// Check slippage protection
    public fun check_slippage(
        config: &BridgeConfig,
        registry: &PeggingRegistry,
        dest_chain: u8,
        amount_in: u64,
        min_amount_out: u64,
        _clock: &Clock
    ) {
        let (amount_out, _, _) = quote_bridge(config, registry, dest_chain, amount_in);
        assert!(amount_out >= min_amount_out, E_SLIPPAGE_EXCEEDED);
    }

    /// Check rate freshness
    public fun check_rate_freshness(
        registry: &PeggingRegistry,
        source_chain: u8,
        dest_chain: u8,
        clock: &Clock
    ) {
        assert!(pegging::is_rate_fresh(registry, source_chain, dest_chain, clock), E_STALE_RATE);
    }

    /// Check if chain is designated for external trading (only AQY)
    public fun is_external_trading_chain(chain_id: u8): bool {
        chain_id == 4 // CHAIN_AQY
    }

    /// Check if swap is valid internal swap (between non-AQY chains)
    public fun is_valid_internal_swap(source: u8, dest: u8): bool {
        !is_external_trading_chain(source) && !is_external_trading_chain(dest)
    }

    /// Check if swap is valid for external trading (TO AQY)
    public fun is_valid_swap_to_external(source: u8, dest: u8): bool {
        !is_external_trading_chain(source) && is_external_trading_chain(dest)
    }

    /// Check if swap is valid from external (FROM AQY to internal)
    public fun is_valid_swap_from_external(source: u8, dest: u8): bool {
        is_external_trading_chain(source) && !is_external_trading_chain(dest)
    }
}
