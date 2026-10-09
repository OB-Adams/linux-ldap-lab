#!/usr/bin/env bash
# Health check for the LDAP service. Safe for cron or a systemd timer.
# Exit codes: 0 = OK, 1 = warning (certificate expiring), 2 = critical.
set -uo pipefail

HOST="${LDAP_HOST:-ldap.lab.local}"
WARN_DAYS="${WARN_DAYS:-30}"
status=0
note() { echo "$1"; }
fail() { echo "CRITICAL: $1"; status=2; }
warn() { echo "WARNING: $1"; [[ $status -lt 1 ]] && status=1; }

# 1. Ports reachable (3 s timeout each)
for port in 389 636; do
  if timeout 3 bash -c "exec 3<>/dev/tcp/$HOST/$port" 2>/dev/null; then
    note "OK: port $port reachable"
  else
    fail "port $port unreachable on $HOST"
  fi
done

# 2. StartTLS works and the server advertises the suffix
if out=$(ldapsearch -x -H "ldap://$HOST" -ZZ -LLL -s base -b "" namingContexts 2>&1); then
  note "OK: StartTLS query succeeded ($(echo "$out" | sed -n 's/^namingContexts: //p' | head -1))"
else
  fail "StartTLS rootDSE query failed: $(echo "$out" | head -1)"
fi

# 3. LDAPS certificate lifetime
cert=$(echo | openssl s_client -connect "$HOST:636" -servername "$HOST" 2>/dev/null \
       | openssl x509 2>/dev/null)
if [[ -z $cert ]]; then
  fail "could not read certificate from $HOST:636"
elif echo "$cert" | openssl x509 -noout -checkend 0 >/dev/null; then
  if echo "$cert" | openssl x509 -noout -checkend $((WARN_DAYS * 86400)) >/dev/null; then
    note "OK: certificate valid for more than $WARN_DAYS days"
  else
    warn "certificate expires within $WARN_DAYS days"
  fi
else
  fail "certificate has expired"
fi

exit $status
