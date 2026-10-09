#!/usr/bin/env bash
# Add a POSIX user to the lab directory and set an initial password.
# Usage: ldap-add-user.sh <username> <given-name> <surname>
# Run from any host with openldap-clients and the lab CA trusted.
set -euo pipefail

LDAP_URI="${LDAP_URI:-ldap://ldap.lab.local}"
BASE_DN="${BASE_DN:-dc=lab,dc=local}"
ADMIN_DN="${ADMIN_DN:-cn=Directory Manager}"
DEFAULT_GID="${DEFAULT_GID:-10000}"   # ldapusers
UID_FLOOR="${UID_FLOOR:-10000}"

usage() { echo "Usage: $0 <username> <given-name> <surname>" >&2; exit 2; }
[[ $# -eq 3 ]] || usage
user=$1 given=$2 sn=$3
[[ $user =~ ^[a-z][a-z0-9_-]{1,31}$ ]] || { echo "Invalid username: $user" >&2; exit 2; }

# Keep the admin password in a 0600 temp file, not on the command line
# (command-line arguments are visible to other users via ps).
pwfile=$(mktemp); chmod 600 "$pwfile"; trap 'rm -f "$pwfile"' EXIT
read -r -s -p "Directory Manager password: " adminpw; echo
printf '%s' "$adminpw" > "$pwfile"; unset adminpw

ldap() { # usage: ldap <tool> [args...]
  local tool=$1; shift
  "$tool" -x -H "$LDAP_URI" -ZZ -D "$ADMIN_DN" -y "$pwfile" "$@"
}

if ldap ldapsearch -LLL -b "ou=People,$BASE_DN" "(uid=$user)" dn | grep -q '^dn:'; then
  echo "User '$user' already exists." >&2; exit 1
fi

# Next free uidNumber: highest existing + 1 (never below the floor).
max=$(ldap ldapsearch -LLL -b "ou=People,$BASE_DN" "(uidNumber=*)" uidNumber \
      | awk '/^uidNumber:/{print $2}' | sort -n | tail -1)
next=$(( ${max:-$UID_FLOOR} + 1 ))

ldap ldapadd <<LDIF
dn: uid=$user,ou=People,$BASE_DN
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
uid: $user
cn: $given $sn
sn: $sn
givenName: $given
uidNumber: $next
gidNumber: $DEFAULT_GID
homeDirectory: /home/$user
loginShell: /bin/bash
LDIF

echo "Created $user with uidNumber $next. Set the user's password:"
ldap ldappasswd -S "uid=$user,ou=People,$BASE_DN"
