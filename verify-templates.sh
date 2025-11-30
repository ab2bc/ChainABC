#!/bin/bash
# Template Verification Script
# Verifies that all critical fixes from FIX.md are applied

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Template Configuration Verification - ChainABC AManager       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

TEMPLATES_DIR=~/Apollo/ChainABC
PASS=0
FAIL=0

check() {
    local test_name="$1"
    local command="$2"
    local expected="$3"
    
    result=$(eval "$command" 2>/dev/null)
    
    if echo "$result" | grep -q "$expected"; then
        echo "✅ PASS: $test_name"
        ((PASS++))
        return 0
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected: $expected"
        echo "   Got: $result"
        ((FAIL++))
        return 1
    fi
}

echo "Testing validator.yaml template..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check "Validator genesis path" \
    "grep 'genesis-file-location' $TEMPLATES_DIR/validator.yaml" \
    "/work/genesis/genesis.blob"

check "Validator listen-address format (IP:PORT)" \
    "grep -A1 'p2p-config:' $TEMPLATES_DIR/validator.yaml | grep listen-address" \
    "0.0.0.0:25000"

check "Validator external-address format (QUIC multiaddr)" \
    "grep 'external-address' $TEMPLATES_DIR/validator.yaml" \
    "/ip4/.*/udp/.*/quic-v1"

echo ""
echo "Testing fullnode.yaml template..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check "Fullnode genesis path" \
    "grep 'genesis-file-location' $TEMPLATES_DIR/fullnode.yaml" \
    "/work/genesis/genesis.blob"

check "Fullnode listen-address format (IP:PORT)" \
    "awk '/^[^#]*listen-address:/ {print}' $TEMPLATES_DIR/fullnode.yaml | head -1" \
    "0.0.0.0:25"

check "Fullnode external-address format (QUIC multiaddr)" \
    "grep 'external-address' $TEMPLATES_DIR/fullnode.yaml" \
    "/ip4/.*/udp/.*/quic-v1"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Test Summary                                                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "  ✅ Passed: $PASS"
echo "  ❌ Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "🎉 All tests PASSED! Templates are correctly configured."
    echo ""
    echo "Critical fixes applied:"
    echo "  • Genesis path: /work/genesis/genesis.blob (matches Docker mount)"
    echo "  • listen-address: IP:PORT format (ghcr.io/ab2bc/aqy-node:dev compatible)"
    echo "  • external-address: QUIC multiaddr format (Sui P2P requirement)"
    echo ""
    echo "Next steps:"
    echo "  1. Launch AManager application"
    echo "  2. Generate node deployment packages"
    echo "  3. Verify generated ZIPs contain correct configurations"
    echo "  4. Deploy to target server with: sudo bash deploy-*.sh"
    exit 0
else
    echo "⚠️  Some tests FAILED. Please review the template files."
    exit 1
fi
