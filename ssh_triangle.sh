#!/usr/bin/env bash
# ssh_triangle.sh — helper for SSH jump-host access ("SSH triangle").
#
# What it does:
#   1. Check host reachability (TCP port, no login required).
#   2. Measure latency directly vs via the jump host (comparison).
#   3. Generate a ready-to-use `ssh -J` command and a ~/.ssh/config block.
#
# Usage:
#   ./ssh_triangle.sh check  <hostA> <hostB> [port]        # reachability of both hosts
#   ./ssh_triangle.sh compare <jump> <target> [port]       # latency direct vs via jump
#   ./ssh_triangle.sh gen    <jump> <target> [alias]       # ssh -J command + config block
#
# Examples:
#   ./ssh_triangle.sh check  vps1.example.com vps2.example.com 22
#   ./ssh_triangle.sh compare vps1.example.com vps2.example.com
#   ./ssh_triangle.sh gen    vps1.example.com vps2.example.com target-via-jump

set -euo pipefail

PROG="$(basename "$0")"
PORT_DEFAULT=22
CONNECT_TIMEOUT=5
PING_COUNT=5

usage() {
    grep '^#' "$0" | sed 's/^# \{0,1\}//' | tail -n +2
    exit "${1:-0}"
}

die() { echo "Error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "utility not found: $1"; }

# --- 1. TCP port reachability -------------------------------------------------
tcp_check() { # $1 host, $2 port -> 0 if the port answers
    local host="$1" port="$2"
    if command -v nc >/dev/null 2>&1; then
        nc -z -G "$CONNECT_TIMEOUT" "$host" "$port" >/dev/null 2>&1 \
            || nc -z -w "$CONNECT_TIMEOUT" "$host" "$port" >/dev/null 2>&1
    else
        (exec 3<>"/dev/tcp/$host/$port") >/dev/null 2>&1
    fi
}

cmd_check() {
    local port="${3:-$PORT_DEFAULT}" host ok=0 total=0
    echo "TCP port check (timeout ${CONNECT_TIMEOUT}s):"
    for host in "$1" "$2"; do
        total=$((total + 1))
        if tcp_check "$host" "$port"; then
            echo "  [OK]   $host:$port"
            ok=$((ok + 1))
        else
            echo "  [FAIL] $host:$port"
        fi
    done
    echo "Total: $ok/$total available"
    [ "$ok" -eq "$total" ]
}

# --- 2. Latency: direct vs via jump -------------------------------------------
avg_latency() { # stdin: ping output -> average in ms
    awk -F'[:=]' '/time=/ { split($3, a, " "); sum += a[1]; n++ }
                  END { if (n > 0) printf "%.1f", sum/n; else print "—" }'
}

ping_host() { # $1 host -> average latency (ms)
    ping -c "$PING_COUNT" -t "$PING_COUNT" "$1" 2>/dev/null | avg_latency \
        || ping -c "$PING_COUNT" -W "$PING_COUNT" "$1" 2>/dev/null | avg_latency
}

ping_via_jump() { # $1 jump, $2 target -> average latency of target from the jump host
    ssh -o ConnectTimeout="$CONNECT_TIMEOUT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "$1" "ping -c $PING_COUNT -W $PING_COUNT '$2' 2>/dev/null" | avg_latency
}

cmd_compare() {
    local jump="$1" target="$2" port="${3:-$PORT_DEFAULT}" direct via
    need ssh
    need ping
    tcp_check "$jump" "$port" || die "jump $jump:$port unreachable"

    echo "Latency measurement (${PING_COUNT} icmp packets):"
    direct="$(ping_host "$target")"
    echo "  direct to $target              : ${direct} ms"
    via="$(ping_via_jump "$jump" "$target")"
    echo "  from jump host ($jump) to $target: ${via} ms"

    if [ "$direct" != "—" ] && [ "$via" != "—" ]; then
        awk -v d="$direct" -v v="$via" 'BEGIN {
            diff = d - v; sign = (diff >= 0) ? "+" : "";
            printf "  difference (direct - via jump) : %s%.1f ms\n", sign, diff;
        }'
    fi
    echo
    echo "Ready-to-use route:"
    echo "  ssh -J $jump $target"
}

# --- 3. Command and config block generation -----------------------------------
cmd_gen() {
    local jump="$1" target="$2" alias="${3:-target-via-jump}" port="${4:-$PORT_DEFAULT}"
    cat <<EOF
One-liner:

  ssh -J $jump $target

Block for ~/.ssh/config:

Host $alias
    HostName $target
    Port $port
    User <user>
    ProxyJump <user>@$jump:$port
    # Handy options for flaky connections:
    ServerAliveInterval 30
    ServerAliveCountMax 4

After adding the block:  ssh $alias

Note: if the jump host uses a non-standard port, in a one-liner it is written as
$jump:$port, and in the config it goes into ProxyJump.
EOF
}

main() {
    [ $# -ge 1 ] || usage 1
    local cmd="$1"; shift
    case "$cmd" in
        check)   [ $# -ge 2 ] || usage 1; cmd_check "$@" ;;
        compare) [ $# -ge 2 ] || usage 1; cmd_compare "$@" ;;
        gen)     [ $# -ge 2 ] || usage 1; cmd_gen "$@" ;;
        -h|--help|help) usage 0 ;;
        *) die "unknown command: $cmd (see $PROG help)" ;;
    esac
}

main "$@"
