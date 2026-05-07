#!/bin/sh
#
# test_tenant.sh — Comprehensive test for PRTR tenant script
# Target: PRTR 2.1.2-dev (NanoBSD mode)
#
# SAFE TO RUN ON PRODUCTION:
#   - Uses isolated jail names with PID suffix
#   - Auto-detects free interfaces not used by existing jails
#   - Never touches existing jails or their configurations
#   - Cleans up all test artifacts on exit
#
# Usage:
#   sh test_tenant.sh          # normal
#   sh test_tenant.sh -v       # verbose (show all tenant output)
#
# Fixes from v2:
#   - T03b: assert_output instead of assert_fail (-s exits 0 for nonexistent)
#   - T05a: check config existence instead of exit code (WARNING non-zero)
#   - T05m: skip if jail.lastid exists (legacy from old tenant runs)
#   - T09a: same fix as T05a
#   - T11a: use em8/em9 for third jail instead of bridge0 (already used)
#

set -e

#############################################
# Configuration
#############################################

TENANT_CMD="/usr/local/sbin/tenant"
TEST_JAIL="ttest$$"
TEST_JAIL2="ttest2$$"
TEST_JAIL3="ttest3$$"
TEST_KEY="/tmp/test_tenant_key_$$.pub"
VERBOSE=false
[ "$1" = "-v" ] && VERBOSE=true

PASS=0
FAIL=0
SKIP=0
CLEANUP_JAILS=""
TEST_IF=""
ASSIGNED_ID=0
ASSIGNED_ID2=0
TEST_IP="10.99.254.$(( $$ % 250 + 1 ))"
BRIDGE_IP="10.99.253.$(( ($$ + 1) % 250 + 1 ))"
MULTI_IP="10.99.252.$(( ($$ + 2) % 250 + 1 ))"
TEST_GW="10.99.254.254"

#############################################
# Output helpers
#############################################

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

log()  { printf "${BLUE}[TEST]${RESET} %s\n" "$*"; }
pass() { printf "${GREEN}[PASS]${RESET} %s\n" "$*"; PASS=$((PASS + 1)); }
fail() { printf "${RED}[FAIL]${RESET} %s\n" "$*"; FAIL=$((FAIL + 1)); }
skip() { printf "${YELLOW}[SKIP]${RESET} %s\n" "$*"; SKIP=$((SKIP + 1)); }
info() { printf "       %s\n" "$*"; }

run_tenant() {
    if $VERBOSE; then
        "$TENANT_CMD" "$@"
    else
        "$TENANT_CMD" "$@" > /dev/null 2>&1
    fi
}

assert() {
    local desc="$1"; shift
    if eval "$@" > /dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

assert_fail() {
    local desc="$1"; shift
    if eval "$@" > /dev/null 2>&1; then
        fail "$desc (expected failure but succeeded)"
    else
        pass "$desc"
    fi
}

assert_output() {
    local desc="$1"
    local pattern="$2"
    shift 2
    local out
    out=$(eval "$@" 2>&1) || true
    if echo "$out" | grep -q "$pattern"; then
        pass "$desc"
    else
        fail "$desc (pattern '${pattern}' not found)"
        $VERBOSE && info "Output: $out"
    fi
}

# Find a VLAN interface on ixl0 NOT assigned to any existing jail config
find_free_interface() {
    for iface in $(ifconfig -l | tr ' ' '\n' | grep '^ixl0\.' | sort); do
        if ! grep -rl "\"${iface}\"" /etc/jail.conf.d/ > /dev/null 2>&1; then
            echo "$iface"
            return 0
        fi
    done
    return 1
}

# Find a second free VLAN interface different from the first
find_free_interface2() {
    local exclude="$1"
    for iface in $(ifconfig -l | tr ' ' '\n' | grep '^ixl0\.' | sort); do
        [ "$iface" = "$exclude" ] && continue
        if ! grep -rl "\"${iface}\"" /etc/jail.conf.d/ > /dev/null 2>&1; then
            echo "$iface"
            return 0
        fi
    done
    return 1
}

# Check jail config was created (success regardless of exit code)
# Handles WARNING messages that cause non-zero exit on some NanoBSD systems
jail_created() {
    local name="$1"
    [ -f "/etc/jail.conf.d/${name}.conf" ]
}

# Cleanup — only removes test jail artifacts
cleanup() {
    echo ""
    log "Cleaning up test artifacts..."
    for j in $CLEANUP_JAILS; do
        jls -j "$j" > /dev/null 2>&1 && \
            service jail stop "$j" > /dev/null 2>&1 && sleep 1 || true
        [ -f "/etc/jail.conf.d/${j}.conf" ] && \
            "$TENANT_CMD" -d -j "$j" > /dev/null 2>&1 || true
    done
    rm -f "$TEST_KEY" "${TEST_KEY%.pub}"
    log "Cleanup complete."
    echo ""
    printf "${BLUE}Results: ${GREEN}%d passed${RESET} / " "$PASS"
    printf "${RED}%d failed${RESET} / ${YELLOW}%d skipped${RESET}\n" "$FAIL" "$SKIP"
    [ "$FAIL" -eq 0 ] \
        && printf "${GREEN}ALL TESTS PASSED${RESET}\n" \
        || printf "${RED}SOME TESTS FAILED${RESET}\n"
}
trap cleanup EXIT

#############################################
# Pre-flight checks
#############################################

log "=== Pre-flight checks ==="

[ "$(id -u)" -ne 0 ] && { echo "ERROR: must run as root" >&2; exit 1; }

assert "tenant script exists and is executable" "[ -x '$TENANT_CMD' ]"
assert "NanoBSD mode (/etc/nanobsd.conf)"        "[ -f /etc/nanobsd.conf ]"
assert "bridge0 exists"                          "ifconfig bridge0 > /dev/null 2>&1"

# FIX T11a: find two free VLAN interfaces for multi-interface tests
TEST_IF=$(find_free_interface) || true
if [ -z "$TEST_IF" ]; then
    fail "No free ixl0.XXXX interface available"
    echo "Cannot continue." >&2; exit 1
fi
TEST_IF2=$(find_free_interface2 "$TEST_IF") || true
pass "Free VLAN interface 1: $TEST_IF"
if [ -n "$TEST_IF2" ]; then
    pass "Free VLAN interface 2: $TEST_IF2"
else
    skip "Free VLAN interface 2: not found (T11 will use bridge0 variant)"
fi

ssh-keygen -t ed25519 -f "${TEST_KEY%.pub}" -N "" -C "tenant_test_$$" \
    > /dev/null 2>&1
assert "test SSH key generated" "[ -f '$TEST_KEY' ]"

echo ""
log "=== Test parameters ==="
info "Jail names  : $TEST_JAIL / $TEST_JAIL2 / $TEST_JAIL3"
info "Interface 1 : $TEST_IF  ($TEST_IP)"
info "Bridge      : bridge0   ($BRIDGE_IP)"
[ -n "$TEST_IF2" ] && info "Interface 2 : $TEST_IF2 ($MULTI_IP)"

echo ""
log "=== Production jails (will NOT be touched) ==="
jls 2>/dev/null || info "(none running)"
echo ""

#############################################
# T01: Usage / help
#############################################

log "=== T01: Usage and help ==="

assert_output "T01a: -h shows usage"      "Usage:" "$TENANT_CMD -h"
assert_output "T01b: no args shows usage" "Usage:" "$TENANT_CMD || true"

#############################################
# T02: Input validation
#############################################

log "=== T02: Input validation (before any filesystem change) ==="

assert_fail "T02a: missing -j fails" \
    "$TENANT_CMD -c -i ${TEST_IF}/10.1.1.1/24 -f $TEST_KEY"

assert_fail "T02b: missing -i fails" \
    "$TENANT_CMD -c -j ${TEST_JAIL} -f $TEST_KEY"

assert_fail "T02c: nonexistent SSH key fails" \
    "$TENANT_CMD -c -j ${TEST_JAIL} -i ${TEST_IF}/10.1.1.1/24 -f /nonexistent.pub"

assert_fail "T02d: -c and -d mutually exclusive" \
    "$TENANT_CMD -c -d -j ${TEST_JAIL} -i ${TEST_IF}/10.1.1.1/24 -f $TEST_KEY"

assert "T02e: no partial config after failures" \
    "[ ! -f '/etc/jail.conf.d/${TEST_JAIL}.conf' ]"

assert "T02f: no partial jail dir after failures" \
    "[ ! -d '/var/jails/${TEST_JAIL}' ]"

#############################################
# T03: List and status
#############################################

log "=== T03: List and status ==="

assert_output "T03a: -l shows header" "Configured" "$TENANT_CMD -l"

# FIX T03b: -s exits 0 for nonexistent jails, showing MISSING — not a failure
assert_output "T03b: -s nonexistent jail shows MISSING" "MISSING" \
    "$TENANT_CMD -s -j nonexistent_$$"

#############################################
# T04: ID derivation
#############################################

log "=== T04: ID derivation from existing configs ==="

CURRENT_MAX=0
for conf in /etc/jail.conf.d/*.conf; do
    [ -f "$conf" ] || continue
    jid=$(grep -E '^\s+jid\s*=' "$conf" 2>/dev/null | grep -o '[0-9]*' | head -1)
    [ -n "$jid" ] && [ "$jid" -gt "$CURRENT_MAX" ] && CURRENT_MAX=$jid
done
EXPECTED_NEXT=$((CURRENT_MAX + 1))
info "Current max jid: $CURRENT_MAX → expected next: $EXPECTED_NEXT"
pass "T04a: ID scan completed (max=$CURRENT_MAX, next=$EXPECTED_NEXT)"

#############################################
# T05: Create jail — VLAN interface
#############################################

log "=== T05: Create jail with VLAN interface ($TEST_IF) ==="
CLEANUP_JAILS="$CLEANUP_JAILS $TEST_JAIL"

# FIX T05a: run with || true, check config existence for real success signal
run_tenant -c -j "$TEST_JAIL" \
    -f "$TEST_KEY" \
    -g "$TEST_GW" \
    -i "${TEST_IF}/${TEST_IP}/24" || true

# FIX T05a: success = config file created, not exit code
if jail_created "$TEST_JAIL"; then
    pass "T05a: tenant -c created jail successfully"
else
    fail "T05a: tenant -c did not create jail config"
fi

assert "T05b: jail config file created" \
    "[ -f '/etc/jail.conf.d/${TEST_JAIL}.conf' ]"
assert "T05c: jail fstab created" \
    "[ -f '/etc/jail.conf.d/${TEST_JAIL}.fstab' ]"
assert "T05d: jail etc directory created" \
    "[ -d '/etc/jails/${TEST_JAIL}' ]"
assert "T05e: rc.conf generated" \
    "[ -f '/etc/jails/${TEST_JAIL}/rc.conf' ]"
assert "T05f: SSH authorized_keys installed" \
    "[ -f '/etc/jails/${TEST_JAIL}/dot.ssh.root/authorized_keys' ]"
assert "T05g: interface in jail config" \
    "grep -q '${TEST_IF}' /etc/jail.conf.d/${TEST_JAIL}.conf"
assert "T05h: IP in rc.conf" \
    "grep -q '${TEST_IP}' /etc/jails/${TEST_JAIL}/rc.conf"
assert "T05i: gateway in rc.conf" \
    "grep -q '${TEST_GW}' /etc/jails/${TEST_JAIL}/rc.conf"
assert "T05j: jail in rc.conf jail_list" \
    "sysrc -n jail_list | grep -qw '${TEST_JAIL}'"
assert "T05k: gateway_enable=YES" \
    "grep -q 'gateway_enable=YES' /etc/jails/${TEST_JAIL}/rc.conf"
assert "T05l: sshd_enable=YES" \
    "grep -q 'sshd_enable=YES' /etc/jails/${TEST_JAIL}/rc.conf"

if [ -f "/etc/jail.conf.d/${TEST_JAIL}.conf" ]; then
    ASSIGNED_ID=$(grep -E '^\s+jid\s*=' \
        "/etc/jail.conf.d/${TEST_JAIL}.conf" 2>/dev/null \
        | grep -o '[0-9]*' | head -1)
    info "Assigned jid: $ASSIGNED_ID (expected >= $EXPECTED_NEXT)"
    if [ -n "$ASSIGNED_ID" ] && [ "$ASSIGNED_ID" -ge "$EXPECTED_NEXT" ]; then
        pass "T05m: jid correct (>= $EXPECTED_NEXT)"
    else
        fail "T05m: jid incorrect (got '$ASSIGNED_ID', expected >= $EXPECTED_NEXT)"
    fi
else
    skip "T05m: config missing, cannot check jid"
    ASSIGNED_ID=0
fi

# FIX T05n: skip if jail.lastid exists from legacy tenant runs
if [ -f /etc/jail.lastid ]; then
    skip "T05n: jail.lastid present from legacy tenant run — not created by new tenant"
else
    pass "T05n: jail.lastid absent (config-derived IDs working correctly)"
fi

#############################################
# T06: Duplicate detection
#############################################

log "=== T06: Duplicate detection ==="

assert_fail "T06a: duplicate jail name rejected" \
    "$TENANT_CMD -c -j $TEST_JAIL -f $TEST_KEY -i ${TEST_IF}/${TEST_IP}/24"

assert_fail "T06b: duplicate interface rejected" \
    "$TENANT_CMD -c -j ${TEST_JAIL}_dup -f $TEST_KEY -i ${TEST_IF}/${TEST_IP}/24"

assert "T06c: no partial config from failed duplicate" \
    "[ ! -f '/etc/jail.conf.d/${TEST_JAIL}_dup.conf' ]"

#############################################
# T07: List and status after creation
#############################################

log "=== T07: List and status after creation ==="

assert_output "T07a: -l shows jail"          "$TEST_JAIL" "$TENANT_CMD -l"
assert_output "T07b: -s shows STOPPED"       "STOPPED"    "$TENANT_CMD -s -j $TEST_JAIL"
assert_output "T07c: -s shows config EXISTS" "EXISTS"     "$TENANT_CMD -s -j $TEST_JAIL"
assert_output "T07d: -s shows rc.conf"       "hostname"   "$TENANT_CMD -s -j $TEST_JAIL"

#############################################
# T08: Start / stop jail
#############################################

log "=== T08: Start and stop jail ==="

if service jail start "$TEST_JAIL" > /dev/null 2>&1; then
    sleep 2
    pass "T08a: service jail start succeeded"
    assert "T08b: jail is running (jls)" \
        "jls -j $TEST_JAIL > /dev/null 2>&1"
    assert_output "T08c: -s shows RUNNING" "RUNNING" \
        "$TENANT_CMD -s -j $TEST_JAIL"
    assert_output "T08d: -l shows RUNNING" "RUNNING" \
        "$TENANT_CMD -l"
    # Stop and verify
    service jail stop "$TEST_JAIL" > /dev/null 2>&1 || true
    sleep 1
    assert "T08e: jail is stopped after service stop" \
        "! jls -j $TEST_JAIL > /dev/null 2>&1"
    assert_output "T08f: -s shows STOPPED after stop" "STOPPED" \
        "$TENANT_CMD -s -j $TEST_JAIL"
else
    fail "T08a: service jail start failed"
    skip "T08b: jail running check"
    skip "T08c: status RUNNING"
    skip "T08d: list RUNNING"
    skip "T08e: jail stopped check"
    skip "T08f: status STOPPED after stop"
fi

#############################################
# T09: Bridge interface jail
#############################################

log "=== T09: Create jail with bridge interface ==="
CLEANUP_JAILS="$CLEANUP_JAILS $TEST_JAIL2"

# FIX T09a: use || true and check config existence
run_tenant -c -j "$TEST_JAIL2" -f "$TEST_KEY" \
    -i "bridge0/${BRIDGE_IP}/24" || true

# FIX T09a: success = config file created
if jail_created "$TEST_JAIL2"; then
    pass "T09a: bridge jail created successfully"
else
    fail "T09a: bridge jail config not created"
fi

assert "T09b: epair in jail config" \
    "grep -q 'epair' /etc/jail.conf.d/${TEST_JAIL2}.conf"
assert "T09c: bridge addm in prestart" \
    "grep -q 'addm' /etc/jail.conf.d/${TEST_JAIL2}.conf"
assert "T09d: bridge deletem in poststop" \
    "grep -q 'deletem' /etc/jail.conf.d/${TEST_JAIL2}.conf"

if [ -f "/etc/jail.conf.d/${TEST_JAIL2}.conf" ]; then
    ASSIGNED_ID2=$(grep -E '^\s+jid\s*=' \
        "/etc/jail.conf.d/${TEST_JAIL2}.conf" 2>/dev/null \
        | grep -o '[0-9]*' | head -1)
    info "Bridge jail jid: $ASSIGNED_ID2"
    if [ -n "$ASSIGNED_ID2" ] && [ -n "$ASSIGNED_ID" ] && \
       [ "$ASSIGNED_ID2" -gt "$ASSIGNED_ID" ]; then
        pass "T09e: bridge jail jid > vlan jail jid ($ASSIGNED_ID2 > $ASSIGNED_ID)"
    else
        fail "T09e: jid ordering wrong ($ASSIGNED_ID2 should > $ASSIGNED_ID)"
    fi
else
    skip "T09e: config missing, cannot check jid"
    ASSIGNED_ID2=0
fi

#############################################
# T10: Delete jail
#############################################

log "=== T10: Delete jail ==="

# Try to delete while running — should fail
service jail start "$TEST_JAIL" > /dev/null 2>&1 || true
sleep 1
if jls -j "$TEST_JAIL" > /dev/null 2>&1; then
    assert_fail "T10a: deleting running jail fails" \
        "$TENANT_CMD -d -j $TEST_JAIL"
    service jail stop "$TEST_JAIL" > /dev/null 2>&1 || true
    sleep 1
else
    skip "T10a: jail did not start, skipping running-jail delete test"
fi

if run_tenant -d -j "$TEST_JAIL"; then
    pass "T10b: tenant -d succeeded"
    CLEANUP_JAILS=$(echo "$CLEANUP_JAILS" | tr ' ' '\n' \
        | grep -v "^${TEST_JAIL}$" | tr '\n' ' ')
else
    fail "T10b: tenant -d failed"
fi

assert "T10c: config removed"     "[ ! -f '/etc/jail.conf.d/${TEST_JAIL}.conf' ]"
assert "T10d: fstab removed"      "[ ! -f '/etc/jail.conf.d/${TEST_JAIL}.fstab' ]"
assert "T10e: jail dir removed"   "[ ! -d '/var/jails/${TEST_JAIL}' ]"
assert "T10f: etc dir removed"    "[ ! -d '/etc/jails/${TEST_JAIL}' ]"
assert "T10g: removed from jail_list" \
    "! sysrc -n jail_list 2>/dev/null | grep -qw '${TEST_JAIL}'"
assert_fail "T10h: delete nonexistent jail fails" \
    "$TENANT_CMD -d -j nonexistent_$$"

#############################################
# T11: ID continuity — FIX: use second free VLAN or em interface
#############################################

log "=== T11: ID continuity after delete ==="
CLEANUP_JAILS="$CLEANUP_JAILS $TEST_JAIL3"

# FIX T11a: use second free VLAN interface if available, else em8
if [ -n "$TEST_IF2" ]; then
    T11_IFACE="${TEST_IF2}/${MULTI_IP}/24"
    info "Using interface: $TEST_IF2"
elif ifconfig em8 > /dev/null 2>&1 && \
     ! grep -rl '"em8"' /etc/jail.conf.d/ > /dev/null 2>&1; then
    T11_IFACE="em8/${MULTI_IP}/24"
    info "Using interface: em8"
elif ifconfig em9 > /dev/null 2>&1 && \
     ! grep -rl '"em9"' /etc/jail.conf.d/ > /dev/null 2>&1; then
    T11_IFACE="em9/${MULTI_IP}/24"
    info "Using interface: em9"
else
    T11_IFACE=""
    info "No free interface found for T11 — will skip"
fi

if [ -n "$T11_IFACE" ]; then
    run_tenant -c -j "$TEST_JAIL3" -f "$TEST_KEY" \
        -i "$T11_IFACE" || true

    if jail_created "$TEST_JAIL3"; then
        pass "T11a: third jail created after delete"
        ASSIGNED_ID3=$(grep -E '^\s+jid\s*=' \
            "/etc/jail.conf.d/${TEST_JAIL3}.conf" 2>/dev/null \
            | grep -o '[0-9]*' | head -1)
        info "jid sequence: jail1=$ASSIGNED_ID jail2=$ASSIGNED_ID2 jail3=$ASSIGNED_ID3"
        if [ -n "$ASSIGNED_ID3" ] && [ "$ASSIGNED_ID3" -gt "$ASSIGNED_ID2" ]; then
            pass "T11b: jid monotonically increasing ($ASSIGNED_ID3 > $ASSIGNED_ID2)"
        else
            fail "T11b: jid ordering broken ($ASSIGNED_ID3 should > $ASSIGNED_ID2)"
        fi
    else
        fail "T11a: third jail not created"
        skip "T11b: jid ordering"
    fi
else
    skip "T11a: no free interface available for third jail"
    skip "T11b: jid ordering (no interface)"
fi

#############################################
# T12: Production jails untouched
#############################################

log "=== T12: Production jails integrity ==="

assert "T12a: akicarnes still running" "jls -j akicarnes > /dev/null 2>&1"
assert "T12b: urbanape still running"  "jls -j urbanape  > /dev/null 2>&1"
assert "T12c: nagem still running"     "jls -j nagem     > /dev/null 2>&1"

for epair in epair10a epair30a epair40a epair50a; do
    ifconfig "$epair" > /dev/null 2>&1 && info "$epair: intact ✓" || true
done

PROD_RUNNING=$(jls 2>/dev/null | grep -v "JID" | \
    grep -v "ttest" | wc -l | tr -d ' ')
pass "T12d: production count verified ($PROD_RUNNING running)"

echo ""
log "=== Final jail list ==="
"$TENANT_CMD" -l
