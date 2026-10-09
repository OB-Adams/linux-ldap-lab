#!/usr/bin/env bash
# Remove a user and any group memberships that reference them.
# Usage: ldap-del-user.sh <username>
set -euo pipefail

LDAP_URI="${LDAP_URI:-ldap://ldap.lab.local}"
BASE_DN="${BASE_DN:-dc=lab,dc=local}"
ADMIN_DN="${ADMIN_DN:-cn=Directory Manager}"

[[ $# -eq 1 ]] || { echo "Usage: $0 <username>" >&2; exit 2; }
user=$1
[[ $user =~ ^[a-z][a-z0-9_-]{1,31}$ ]] || { echo "Invalid username: $user" >&2; exit 2; }

pwfile=$(mktemp); chmod 600 "$pwfile"; trap 'rm -f "$pwfile"' EXIT
read -r -s -p "Directory Manager password: " adminpw; echo
printf '%s' "$adminpw" > "$pwfile"; unset adminpw

ldap() { local tool=$1; shift; "$tool" -x -H "$LDAP_URI" -ZZ -D "$ADMIN_DN" -y "$pwfile" "$@"; }

dn="uid=$user,ou=People,$BASE_DN"
ldap ldapsearch -LLL -b "$dn" -s base dn | grep -q '^dn:' || { echo "No such user: $user" >&2; exit 1; }

read -r -p "Delete $user and remove from all groups? [y/N] " ans
[[ $ans == y || $ans == Y ]] || { echo "Aborted."; exit 1; }

# Remove memberUid references first, so no group points at a dead account.
while IFS= read -r gdn; do
  [[ -n $gdn ]] || continue
  ldap ldapmodify <<LDIF
dn: $gdn
changetype: modify
delete: memberUid
memberUid: $user
LDIF
done < <(ldap ldapsearch -LLL -b "ou=Groups,$BASE_DN" "(memberUid=$user)" dn | sed -n 's/^dn: //p')

ldap ldapdelete "$dn"
echo "Deleted $user. On clients, run: sudo sss_cache -E"
