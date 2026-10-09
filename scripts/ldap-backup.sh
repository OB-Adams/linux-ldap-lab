#!/usr/bin/env bash
# Back up the 389-ds instance (binary backup + LDIF export). Run as root on the server.
set -euo pipefail

INSTANCE="${INSTANCE:-lab}"
BACKEND="${BACKEND:-userroot}"
KEEP="${KEEP:-7}"
BAKDIR="/var/lib/dirsrv/slapd-$INSTANCE/bak"
LDIFDIR="/var/lib/dirsrv/slapd-$INSTANCE/ldif"

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 2; }
umask 077   # exports contain password hashes

dsconf "$INSTANCE" backup create
dsconf "$INSTANCE" backend export "$BACKEND"

# Retention: keep the newest $KEEP of each kind, delete the rest.
for dir in "$BAKDIR" "$LDIFDIR"; do
  [[ -d $dir ]] || continue
  ls -1dt "$dir"/* 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -rf
done
echo "Backup complete. Binary: $BAKDIR  LDIF: $LDIFDIR"
