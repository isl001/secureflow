#!/usr/bin/env bash
# netcheck.sh — check a URL layer by layer: DNS -> TCP -> TLS -> HTTP
set -euo pipefail

usage() {
  echo "Usage: $0 https://host[:port]" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
url="$1"

# --- split the URL into parts ---
scheme="${url%%://*}"
rest="${url#*://}"
hostport="${rest%%/*}"
host="${hostport%%:*}"

if [[ "$hostport" == *:* ]]; then
  port="${hostport##*:}"
elif [[ "$scheme" == "https" ]]; then
  port=443
else
  port=80
fi

echo "== Checking $url (host=$host, port=$port)"

# --- helpers ---
ok()   { echo "[$1] $2 ✅"; }
fail() { echo "[$1] $2 ❌" >&2; exit 1; }

# --- layer 1: DNS ---
check_dns() {
  if [[ "$host" =~ ^[0-9.]+$ ]]; then
    ok "DNS " "$host is already an IP, no lookup needed"
    return
  fi
  local ip
  ip="$(dig +short "$host" A | grep -E '^[0-9.]+$' | head -n1 || true)"
  [[ -n "$ip" ]] || fail "DNS " "$host does not resolve (NXDOMAIN?)"
  ok "DNS " "$host -> $ip"
}

check_dns

# --- layer 2: TCP ---
if [[ "$(uname)" == "Darwin" ]]; then
  nc_timeout=(-G 5)
else
  nc_timeout=(-w 5)
fi

check_tcp() {
  local out
  if out="$(nc -vz "${nc_timeout[@]}" "$host" "$port" 2>&1)"; then
    ok "TCP " "port $port is open"
  elif grep -qi "refused" <<< "$out"; then
    fail "TCP " "port $port refused: host reached, but nothing listens there"
  else
    fail "TCP " "port $port timed out: no answer (firewall? wrong IP?)"
  fi
}

check_tcp

# --- layer 3: TLS ---
check_tls() {
  if [[ "$scheme" != "https" ]]; then
    ok "TLS " "skipped (plain http, no certificate)"
    return
  fi
  local cert end
  cert="$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null \
          | openssl x509 2>/dev/null || true)"
  [[ -n "$cert" ]] || fail "TLS " "could not get a certificate from $host:$port"
  end="$(openssl x509 -noout -enddate <<< "$cert")"
  end="${end#notAfter=}"
  if ! openssl x509 -noout -checkend 0 <<< "$cert" >/dev/null; then
    fail "TLS " "certificate EXPIRED on $end"
  elif ! openssl x509 -noout -checkend $((30*24*3600)) <<< "$cert" >/dev/null; then
    fail "TLS " "certificate expires soon: $end (less than 30 days)"
  fi
  ok "TLS " "certificate valid until $end"
}

check_tls

# --- layer 4: HTTP ---
check_http() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)"
  case "$code" in
    2??|3??) ok   "HTTP" "GET $url -> $code" ;;
    4??)     fail "HTTP" "GET $url -> $code (client side: wrong path or auth?)" ;;
    5??)     fail "HTTP" "GET $url -> $code (server side: the app has a problem)" ;;
    *)       fail "HTTP" "no HTTP answer (TLS name mismatch? app hung?)" ;;
  esac
}

check_http
echo "All checks passed ✅"
