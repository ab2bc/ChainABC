/// AB2BC Bridge Pegging Module
/// Handles pegged exchange rates between the 7 chains
/// Supports both 1:1 pegging and dynamic rate pegging
module bridge::pegging {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use std::vector;

    // ============ Error Codes ============
    const E_NOT_AUTHORIZED: u64 = 100;
    const E_INVALID_CHAIN_PAIR: u64 = 101;
    const E_RATE_EXPIRED: u64 = 102;
    const E_RATE_DEVIATION_TOO_HIGH: u64 = 103;
    const E_ORACLE_NOT_SET: u64 = 104;

    // ============ Chain Identifiers ============
    const CHAIN_ABC: u8 = 1;
    const CHAIN_AGO: u8 = 2;
    const CHAIN_AIY: u8 = 3;
    const CHAIN_AQY: u8 = 4;
    const CHAIN_ARY: u8 = 5;
    const CHAIN_ASY: u8 = 6;
    const CHAIN_AUY: u8 = 7;

    // Pegging types
    const PEG_TYPE_FIXED: u8 = 0;      // 1:1 fixed rate
    const PEG_TYPE_FLOATING: u8 = 1;   // Market-driven rate
    const PEG_TYPE_ALGORITHMIC: u8 = 2; // Algorithm-adjusted rate

    // ============ Structs ============

    /// Peg rate between two chains
    /// Rate is expressed as: 1 source_token = rate / 1e9 dest_token
    public struct PegRate has store, copy, drop {
        source_chain: u8,
        dest_chain: u8,
        rate: u64,           // Rate with 9 decimal precision (1e9 = 1:1)
        peg_type: u8,
        last_updated: u64,   // Timestamp
        min_rate: u64,       // Floor rate (for algorithmic pegs)
        max_rate: u64,       // Ceiling rate
    }

    /// Oracle configuration for a chain pair
    public struct OracleConfig has store, drop {
        oracle_address: address,
        heartbeat_seconds: u64,     // Max time between updates
        deviation_threshold: u64,   // Max % change per update (basis points)
    }

    /// Main pegging registry
    public struct PeggingRegistry has key {
        id: UID,
        admin: address,
        /// Table of chain_pair_key -> PegRate
        /// Key: (source_chain * 10 + dest_chain)
        rates: Table<u64, PegRate>,
        /// Oracle configs per chain pair
        oracles: Table<u64, OracleConfig>,
        /// Default peg type for new pairs
        default_peg_type: u8,
    }

    /// Price oracle aggregator
    public struct PriceOracle has key {
        id: UID,
        admin: address,
        /// Authorized price feeders
        feeders: vector<address>,
        /// Required confirmations for price update
        required_confirmations: u64,
    }

    // ============ Events ============

    public struct RateUpdated has copy, drop {
        source_chain: u8,
        dest_chain: u8,
        old_rate: u64,
        new_rate: u64,
        peg_type: u8,
        timestamp: u64,
    }

    public struct PegCreated has copy, drop {
        source_chain: u8,
        dest_chain: u8,
        initial_rate: u64,
        peg_type: u8,
    }

    // ============ Initialization ============

    /// Initialize the pegging registry with default 1:1 rates
    public fun init_registry(admin: address, ctx: &mut TxContext) {
        let registry = PeggingRegistry {
            id: object::new(ctx),
            admin,
            rates: table::new(ctx),
            oracles: table::new(ctx),
            default_peg_type: PEG_TYPE_FIXED,
        };
        
        transfer::share_object(registry);
    }

    /// Initialize all 7x7 chain pair rates (42 pairs, excluding self)
    /// Initial pegging rates:
    /// - 1 ASY, AUY, AIY, ARY, ABC = 1,000 AQY (1K AQY)
    /// - 1 AGO = 1,000,000 AQY (1M AQY)
    /// 
    /// Rate precision: 9 decimals (1_000_000_000 = 1.0)
    /// When source->AQY: rate = how many AQY you get for 1 source token
    /// When AQY->dest: rate = how many dest tokens you get for 1 AQY
    public fun init_all_rates(
        registry: &mut PeggingRegistry,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_AUTHORIZED);
        
        let timestamp = clock::timestamp_ms(clock);
        
        // Rate constants (9 decimals precision)
        // 1 token = 1,000 AQY means rate of 1000_000_000_000 (1000 * 10^9)
        // 1 token = 1,000,000 AQY means rate of 1_000_000_000_000_000 (1M * 10^9)
        let rate_1k_aqy: u64 = 1_000_000_000_000;      // 1000.0 (for ABC, AIY, ARY, ASY, AUY -> AQY)
        let rate_1m_aqy: u64 = 1_000_000_000_000_000;  // 1000000.0 (for AGO -> AQY)
        let rate_aqy_to_1k: u64 = 1_000_000;           // 0.001 (for AQY -> ABC, AIY, ARY, ASY, AUY)
        let rate_aqy_to_ago: u64 = 1_000;              // 0.000001 (for AQY -> AGO)
        
        // Chains that are pegged at 1:1000 with AQY
        let chains_1k = vector[CHAIN_ABC, CHAIN_AIY, CHAIN_ARY, CHAIN_ASY, CHAIN_AUY];
        
        // Initialize rates FROM 1K-pegged chains TO AQY
        let mut i = 0;
        while (i < 5) {
            let source = *vector::borrow(&chains_1k, i);
            let key = get_pair_key(source, CHAIN_AQY);
            if (!table::contains(&registry.rates, key)) {
                let rate = PegRate {
                    source_chain: source,
                    dest_chain: CHAIN_AQY,
                    rate: rate_1k_aqy,  // 1 source = 1000 AQY
                    peg_type: PEG_TYPE_FIXED,
                    last_updated: timestamp,
                    min_rate: rate_1k_aqy * 9 / 10,   // 900 AQY floor
                    max_rate: rate_1k_aqy * 11 / 10, // 1100 AQY ceiling
                };
                table::add(&mut registry.rates, key, rate);
                event::emit(PegCreated {
                    source_chain: source,
                    dest_chain: CHAIN_AQY,
                    initial_rate: rate_1k_aqy,
                    peg_type: PEG_TYPE_FIXED,
                });
            };
            i = i + 1;
        };
        
        // Initialize rates FROM AQY TO 1K-pegged chains
        i = 0;
        while (i < 5) {
            let dest = *vector::borrow(&chains_1k, i);
            let key = get_pair_key(CHAIN_AQY, dest);
            if (!table::contains(&registry.rates, key)) {
                let rate = PegRate {
                    source_chain: CHAIN_AQY,
                    dest_chain: dest,
                    rate: rate_aqy_to_1k,  // 1000 AQY = 1 dest
                    peg_type: PEG_TYPE_FIXED,
                    last_updated: timestamp,
                    min_rate: rate_aqy_to_1k * 9 / 10,
                    max_rate: rate_aqy_to_1k * 11 / 10,
                };
                table::add(&mut registry.rates, key, rate);
                event::emit(PegCreated {
                    source_chain: CHAIN_AQY,
                    dest_chain: dest,
                    initial_rate: rate_aqy_to_1k,
                    peg_type: PEG_TYPE_FIXED,
                });
            };
            i = i + 1;
        };
        
        // Initialize AGO <-> AQY (1 AGO = 1M AQY)
        let key_ago_aqy = get_pair_key(CHAIN_AGO, CHAIN_AQY);
        if (!table::contains(&registry.rates, key_ago_aqy)) {
            let rate = PegRate {
                source_chain: CHAIN_AGO,
                dest_chain: CHAIN_AQY,
                rate: rate_1m_aqy,  // 1 AGO = 1M AQY
                peg_type: PEG_TYPE_FIXED,
                last_updated: timestamp,
                min_rate: rate_1m_aqy * 9 / 10,
                max_rate: rate_1m_aqy * 11 / 10,
            };
            table::add(&mut registry.rates, key_ago_aqy, rate);
            event::emit(PegCreated {
                source_chain: CHAIN_AGO,
                dest_chain: CHAIN_AQY,
                initial_rate: rate_1m_aqy,
                peg_type: PEG_TYPE_FIXED,
            });
        };
        
        let key_aqy_ago = get_pair_key(CHAIN_AQY, CHAIN_AGO);
        if (!table::contains(&registry.rates, key_aqy_ago)) {
            let rate = PegRate {
                source_chain: CHAIN_AQY,
                dest_chain: CHAIN_AGO,
                rate: rate_aqy_to_ago,  // 1M AQY = 1 AGO
                peg_type: PEG_TYPE_FIXED,
                last_updated: timestamp,
                min_rate: rate_aqy_to_ago * 9 / 10,
                max_rate: rate_aqy_to_ago * 11 / 10,
            };
            table::add(&mut registry.rates, key_aqy_ago, rate);
            event::emit(PegCreated {
                source_chain: CHAIN_AQY,
                dest_chain: CHAIN_AGO,
                initial_rate: rate_aqy_to_ago,
                peg_type: PEG_TYPE_FIXED,
            });
        };
        
        // Initialize cross-rates between non-AQY chains (via AQY peg)
        // ABC, AIY, ARY, ASY, AUY are all 1:1 with each other (same 1K AQY peg)
        i = 0;
        while (i < 5) {
            let mut j = 0;
            while (j < 5) {
                if (i != j) {
                    let source = *vector::borrow(&chains_1k, i);
                    let dest = *vector::borrow(&chains_1k, j);
                    let key = get_pair_key(source, dest);
                    if (!table::contains(&registry.rates, key)) {
                        let rate = PegRate {
                            source_chain: source,
                            dest_chain: dest,
                            rate: 1_000_000_000,  // 1:1 between same-tier chains
                            peg_type: PEG_TYPE_FIXED,
                            last_updated: timestamp,
                            min_rate: 900_000_000,
                            max_rate: 1_100_000_000,
                        };
                        table::add(&mut registry.rates, key, rate);
                        event::emit(PegCreated {
                            source_chain: source,
                            dest_chain: dest,
                            initial_rate: 1_000_000_000,
                            peg_type: PEG_TYPE_FIXED,
                        });
                    };
                };
                j = j + 1;
            };
            i = i + 1;
        };
        
        // Initialize AGO <-> 1K chains (1 AGO = 1000 of the 1K-pegged chains)
        i = 0;
        while (i < 5) {
            let chain = *vector::borrow(&chains_1k, i);
            
            // AGO -> chain (1 AGO = 1000 chain tokens)
            let key_ago_chain = get_pair_key(CHAIN_AGO, chain);
            if (!table::contains(&registry.rates, key_ago_chain)) {
                let rate = PegRate {
                    source_chain: CHAIN_AGO,
                    dest_chain: chain,
                    rate: 1_000_000_000_000,  // 1 AGO = 1000 tokens
                    peg_type: PEG_TYPE_FIXED,
                    last_updated: timestamp,
                    min_rate: 900_000_000_000,
                    max_rate: 1_100_000_000_000,
                };
                table::add(&mut registry.rates, key_ago_chain, rate);
                event::emit(PegCreated {
                    source_chain: CHAIN_AGO,
                    dest_chain: chain,
                    initial_rate: 1_000_000_000_000,
                    peg_type: PEG_TYPE_FIXED,
                });
            };
            
            // chain -> AGO (1000 tokens = 1 AGO)
            let key_chain_ago = get_pair_key(chain, CHAIN_AGO);
            if (!table::contains(&registry.rates, key_chain_ago)) {
                let rate = PegRate {
                    source_chain: chain,
                    dest_chain: CHAIN_AGO,
                    rate: 1_000_000,  // 0.001 (1/1000)
                    peg_type: PEG_TYPE_FIXED,
                    last_updated: timestamp,
                    min_rate: 900_000,
                    max_rate: 1_100_000,
                };
                table::add(&mut registry.rates, key_chain_ago, rate);
                event::emit(PegCreated {
                    source_chain: chain,
                    dest_chain: CHAIN_AGO,
                    initial_rate: 1_000_000,
                    peg_type: PEG_TYPE_FIXED,
                });
            };
            
            i = i + 1;
        };
    }

    // ============ Rate Management ============

    /// Get the exchange rate for a chain pair
    public fun get_rate(
        registry: &PeggingRegistry,
        source_chain: u8,
        dest_chain: u8
    ): (u64, u8, u64) {  // Returns (rate, peg_type, last_updated)
        let key = get_pair_key(source_chain, dest_chain);
        assert!(table::contains(&registry.rates, key), E_INVALID_CHAIN_PAIR);
        
        let rate = table::borrow(&registry.rates, key);
        (rate.rate, rate.peg_type, rate.last_updated)
    }

    /// Calculate output amount for a given input
    public fun calculate_output(
        registry: &PeggingRegistry,
        source_chain: u8,
        dest_chain: u8,
        input_amount: u64
    ): u64 {
        let (rate, _, _) = get_rate(registry, source_chain, dest_chain);
        // output = input * rate / 1e9
        ((input_amount as u128) * (rate as u128) / 1_000_000_000 as u64)
    }

    /// Update rate (admin or oracle only)
    public fun update_rate(
        registry: &mut PeggingRegistry,
        source_chain: u8,
        dest_chain: u8,
        new_rate: u64,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let key = get_pair_key(source_chain, dest_chain);
        
        // Check authorization
        let is_admin = sender == registry.admin;
        let is_oracle = if (table::contains(&registry.oracles, key)) {
            let oracle_config = table::borrow(&registry.oracles, key);
            sender == oracle_config.oracle_address
        } else {
            false
        };
        
        assert!(is_admin || is_oracle, E_NOT_AUTHORIZED);
        assert!(table::contains(&registry.rates, key), E_INVALID_CHAIN_PAIR);
        
        let rate = table::borrow_mut(&mut registry.rates, key);
        let old_rate = rate.rate;
        let timestamp = clock::timestamp_ms(clock);
        
        // Validate rate is within bounds
        assert!(new_rate >= rate.min_rate && new_rate <= rate.max_rate, E_RATE_DEVIATION_TOO_HIGH);
        
        // Check deviation threshold for oracles
        if (!is_admin && table::contains(&registry.oracles, key)) {
            let oracle_config = table::borrow(&registry.oracles, key);
            let deviation = if (new_rate > old_rate) {
                ((new_rate - old_rate) * 10000) / old_rate
            } else {
                ((old_rate - new_rate) * 10000) / old_rate
            };
            assert!(deviation <= oracle_config.deviation_threshold, E_RATE_DEVIATION_TOO_HIGH);
        };
        
        rate.rate = new_rate;
        rate.last_updated = timestamp;
        
        event::emit(RateUpdated {
            source_chain,
            dest_chain,
            old_rate,
            new_rate,
            peg_type: rate.peg_type,
            timestamp,
        });
    }

    /// Set peg type for a pair
    public fun set_peg_type(
        registry: &mut PeggingRegistry,
        source_chain: u8,
        dest_chain: u8,
        peg_type: u8,
        min_rate: u64,
        max_rate: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_AUTHORIZED);
        let key = get_pair_key(source_chain, dest_chain);
        assert!(table::contains(&registry.rates, key), E_INVALID_CHAIN_PAIR);
        
        let rate = table::borrow_mut(&mut registry.rates, key);
        rate.peg_type = peg_type;
        rate.min_rate = min_rate;
        rate.max_rate = max_rate;
    }

    /// Configure oracle for a chain pair
    public fun set_oracle(
        registry: &mut PeggingRegistry,
        source_chain: u8,
        dest_chain: u8,
        oracle_address: address,
        heartbeat_seconds: u64,
        deviation_threshold: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_AUTHORIZED);
        let key = get_pair_key(source_chain, dest_chain);
        
        let config = OracleConfig {
            oracle_address,
            heartbeat_seconds,
            deviation_threshold,
        };
        
        if (table::contains(&registry.oracles, key)) {
            let _ = table::remove(&mut registry.oracles, key);
        };
        table::add(&mut registry.oracles, key, config);
    }

    // ============ View Functions ============

    /// Check if a rate is fresh (not expired)
    public fun is_rate_fresh(
        registry: &PeggingRegistry,
        source_chain: u8,
        dest_chain: u8,
        clock: &Clock
    ): bool {
        let key = get_pair_key(source_chain, dest_chain);
        if (!table::contains(&registry.rates, key)) {
            return false
        };
        
        let rate = table::borrow(&registry.rates, key);
        
        // Fixed pegs are always fresh
        if (rate.peg_type == PEG_TYPE_FIXED) {
            return true
        };
        
        // Check oracle heartbeat
        if (table::contains(&registry.oracles, key)) {
            let oracle = table::borrow(&registry.oracles, key);
            let now = clock::timestamp_ms(clock);
            let age = now - rate.last_updated;
            return age <= (oracle.heartbeat_seconds * 1000)
        };
        
        true  // No oracle configured, assume fresh
    }

    /// Get all rates for display
    public fun get_all_rates_for_chain(
        registry: &PeggingRegistry,
        source_chain: u8
    ): vector<PegRate> {
        let mut result = vector::empty<PegRate>();
        let chains = vector[CHAIN_ABC, CHAIN_AGO, CHAIN_AIY, CHAIN_AQY, CHAIN_ARY, CHAIN_ASY, CHAIN_AUY];
        
        let mut i = 0;
        while (i < 7) {
            let dest = *vector::borrow(&chains, i);
            if (dest != source_chain) {
                let key = get_pair_key(source_chain, dest);
                if (table::contains(&registry.rates, key)) {
                    vector::push_back(&mut result, *table::borrow(&registry.rates, key));
                };
            };
            i = i + 1;
        };
        
        result
    }

    // ============ Helper Functions ============

    /// Generate unique key for chain pair
    fun get_pair_key(source: u8, dest: u8): u64 {
        ((source as u64) * 10 + (dest as u64))
    }

    /// Get chain name from ID
    public fun get_chain_name(chain_id: u8): vector<u8> {
        if (chain_id == CHAIN_ABC) { b"ABC" }
        else if (chain_id == CHAIN_AGO) { b"AGO" }
        else if (chain_id == CHAIN_AIY) { b"AIY" }
        else if (chain_id == CHAIN_AQY) { b"AQY" }
        else if (chain_id == CHAIN_ARY) { b"ARY" }
        else if (chain_id == CHAIN_ASY) { b"ASY" }
        else if (chain_id == CHAIN_AUY) { b"AUY" }
        else { b"UNKNOWN" }
    }

    // ============ Test Helper Functions ============

    // Error code for rate out of bounds
    const E_RATE_OUT_OF_BOUNDS: u64 = 105;

    /// Validate chain pair (source != dest)
    public fun validate_chain_pair(source: u8, dest: u8) {
        assert!(source != dest, E_INVALID_CHAIN_PAIR);
        assert!(source >= CHAIN_ABC && source <= CHAIN_AUY, E_INVALID_CHAIN_PAIR);
        assert!(dest >= CHAIN_ABC && dest <= CHAIN_AUY, E_INVALID_CHAIN_PAIR);
    }

    /// Update rate with deviation check
    public fun update_rate_with_deviation_check(
        registry: &mut PeggingRegistry,
        source_chain: u8,
        dest_chain: u8,
        new_rate: u64,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_AUTHORIZED);
        validate_chain_pair(source_chain, dest_chain);
        
        let key = get_pair_key(source_chain, dest_chain);
        
        if (table::contains(&registry.rates, key)) {
            let old_rate = table::borrow(&registry.rates, key);
            
            // Check deviation limit (5% = 500 basis points)
            let deviation = if (new_rate > old_rate.rate) {
                ((new_rate - old_rate.rate) * 10000) / old_rate.rate
            } else {
                ((old_rate.rate - new_rate) * 10000) / old_rate.rate
            };
            
            assert!(deviation <= 500, E_RATE_DEVIATION_TOO_HIGH);
            
            // Update rate
            let rate_mut = table::borrow_mut(&mut registry.rates, key);
            rate_mut.rate = new_rate;
            rate_mut.last_updated = clock::timestamp_ms(clock);
        };
    }
}
