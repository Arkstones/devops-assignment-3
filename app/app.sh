#!/usr/bin/env bash
# app.sh - small Linux/network diagnostic tool, checked by the CI pipeline.
#
# Usage: app.sh <command> [arguments]
#
# Exit codes:
#   0  success
#   1  runtime failure (host does not resolve, port is closed)
#   2  invalid command or input

set -u

PROG="app.sh"

# ---------- helpers ----------

# print an error and exit with code 2 (invalid input)
invalid() {
    echo "Error: $1" >&2
    echo "Run '$PROG help' to see the available commands." >&2
    exit 2
}

# print one "label: value" line with the labels lined up
show() {
    printf '%-20s %s\n' "$1:" "$2"
}

# letters, numbers, dots, hyphens (hostnames/IPv4) and colons (IPv6) only,
# max 253 characters. This keeps things like spaces, ; and $( ) out.
valid_host() {
    local host="$1"
    [[ -n "$host" ]] || return 1
    (( ${#host} <= 253 )) || return 1
    [[ "$host" =~ ^[A-Za-z0-9.:-]+$ ]] || return 1
    [[ "$host" != -* ]] || return 1
    return 0
}

# a port is a whole number from 1 to 65535
valid_port() {
    local port="$1"
    # at most 5 digits, so a huge number can't overflow bash's maths
    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    # 10# reads the number as base 10 so "0080" works
    (( 10#$port >= 1 && 10#$port <= 65535 )) || return 1
    return 0
}

# print the IP addresses for a host, one per line (nothing if it does not resolve)
resolve_host() {
    local host="$1"
    local result=""

    # an IPv4 address does not need resolving
    if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$host"
        return
    fi

    if command -v getent >/dev/null 2>&1; then
        result=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u)
        if [[ -z "$result" ]]; then
            result=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | sort -u)
        fi
    fi
    if [[ -z "$result" ]] && command -v nslookup >/dev/null 2>&1; then
        result=$(nslookup "$host" 2>/dev/null | awk '/^Address/ && NR > 2 {print $NF}' | sort -u)
    fi
    # nslookup only asks DNS, so also check /etc/hosts (for names like localhost)
    if [[ -z "$result" && -r /etc/hosts ]]; then
        result=$(awk -v h="$host" '$1 !~ /^#/ { for (i = 2; i <= NF; i++) if ($i == h) print $1 }' /etc/hosts | sort -u)
    fi
    echo "$result"
}

# ---------- commands ----------

cmd_help() {
    cat <<EOF
Usage: $PROG <command> [arguments]

Commands:
  system-info                Show system information
  check-host <host>          Resolve a host and show its IP addresses
  check-port <host> <port>   Check if a TCP port is open (port 1-65535)
  help                       Show this help message

Exit codes:
  0  success
  1  runtime failure (host does not resolve, port closed)
  2  invalid command or input

Examples:
  $PROG system-info
  $PROG check-host github.com
  $PROG check-port github.com 443
EOF
}

cmd_system_info() {
    local os="unknown"
    if [[ -r /etc/os-release ]]; then
        # subshell so the os-release variables don't leak into the script
        # shellcheck disable=SC1091  # file only exists at runtime
        os=$( . /etc/os-release; echo "${PRETTY_NAME:-${NAME:-unknown}}" )
    fi

    local seconds
    seconds=$(cut -d. -f1 /proc/uptime)

    echo "=============================="
    echo "      System Information"
    echo "=============================="
    show "Hostname"         "$(hostname)"
    show "Current user"     "$(id -un 2>/dev/null || id -u)"
    show "Date/time"        "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    show "Operating system" "$os"
    show "Kernel version"   "$(uname -r)"
    show "Architecture"     "$(uname -m)"
    show "Uptime"           "$((seconds / 86400)) days, $((seconds % 86400 / 3600)) hours, $((seconds % 3600 / 60)) minutes"
    show "CPU cores"        "$(nproc)"
    show "Memory"           "$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
                                    END {printf "%.1f GiB total, %.1f GiB available", t/1048576, a/1048576}' /proc/meminfo)"
    echo "=============================="
}

cmd_check_host() {
    local host="$1"
    local addresses
    addresses=$(resolve_host "$host")

    if [[ -z "$addresses" ]]; then
        echo "FAIL: could not resolve '$host'"
        return 1
    fi

    echo "OK: $host resolves to:"
    echo "$addresses" | sed 's/^/  /'
}

cmd_check_port() {
    local host="$1"
    local port=$((10#$2))

    # bash can open TCP connections through /dev/tcp, no extra tools needed.
    # timeout stops it from hanging on hosts that drop the packets.
    # $1/$2 are in single quotes on purpose: host and port are passed as arguments
    # to the inner bash instead of being pasted into the command string.
    # shellcheck disable=SC2016
    if timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
        echo "OK: port $port on $host is open"
        return 0
    fi

    echo "FAIL: port $port on $host is closed or not reachable"
    return 1
}

# ---------- main ----------

if [[ $# -lt 1 ]]; then
    cmd_help >&2
    echo >&2
    invalid "no command given"
fi

command="$1"
shift

case "$command" in
    help|-h|--help)
        cmd_help
        ;;
    system-info)
        [[ $# -eq 0 ]] || invalid "'system-info' does not take any arguments"
        cmd_system_info
        ;;
    check-host)
        [[ $# -ge 1 ]] || invalid "'check-host' needs a host, e.g. '$PROG check-host github.com'"
        [[ $# -eq 1 ]] || invalid "'check-host' takes exactly one argument: <host>"
        valid_host "$1" || invalid "'$1' is not a valid hostname or IP address"
        cmd_check_host "$1"
        ;;
    check-port)
        [[ $# -ge 1 ]] || invalid "'check-port' needs a host and a port, e.g. '$PROG check-port github.com 443'"
        [[ $# -ge 2 ]] || invalid "'check-port' needs a port number after the host"
        [[ $# -eq 2 ]] || invalid "'check-port' takes exactly two arguments: <host> <port>"
        valid_host "$1" || invalid "'$1' is not a valid hostname or IP address"
        valid_port "$2" || invalid "port must be a number from 1 to 65535, got '$2'"
        cmd_check_port "$1" "$2"
        ;;
    *)
        invalid "unknown command '$command'"
        ;;
esac

# exit with the status of the command that just ran (0 = ok, 1 = runtime failure)
exit $?
