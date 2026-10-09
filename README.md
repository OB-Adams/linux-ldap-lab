# linux-ldap-lab: centralized authentication with 389 Directory Server

A hands-on Linux administration lab: an LDAP directory on **Rocky Linux 10** (389 Directory Server) providing centralized login to a **CentOS Stream 10** client through **SSSD**, secured with TLS from a private CA.

## Architecture

```
  ┌─────────────────────────┐   StartTLS (389) / LDAPS (636)   ┌──────────────────────────┐
  │ ldap.lab.local          │ ◄──────────────────────────────  │ client.lab.local         │
  │ Rocky Linux 10.2        │                                  │ CentOS Stream 10         │
  │ 389-ds instance "lab"   │   1. SSSD binds as sssd-bind     │ SSSD + authselect        │
  │ suffix dc=lab,dc=local  │      (read-only) for lookups     │ oddjob-mkhomedir         │
  │ private CA (Lab Root CA)│   2. PAM binds as the user to    │ sshd -> PAM -> SSSD      │
  └─────────────────────────┘      verify the password         └──────────────────────────┘
```

## What this demonstrates

- Installing and instantiating 389-ds from an INF file (`dscreate`), SELinux enforcing, firewalld
- Directory design: OUs, `posixAccount` users, `posixGroup` groups, UID/GID ranges that avoid local collisions
- A private PKI: root CA, server certificate with a SAN, StartTLS and LDAPS, verified with `openssl s_client`
- Least privilege: a read-only service account via ACIs that cannot read `userPassword`; anonymous access limited to the rootDSE; password binds require TLS
- Client integration: SSSD, `authselect` with `with-mkhomedir`, CA trust via `update-ca-trust`
- Authorization separate from authentication (`access_provider = simple`)
- Operations: backup and restore drill, user lifecycle and health-check scripts, systemd timer

## Repository layout

```
configs/   lab.inf.example, sssd.conf.example, san.ext, backup systemd units
ldif/      structure.ldif, service.ldif.example, aci.ldif
scripts/   ldap-add-user.sh, ldap-del-user.sh, ldap-healthcheck.sh, ldap-backup.sh
docs/      troubleshooting.md
```

Secrets (`lab.inf`, `sssd.conf`, any `*.key`, the `ca/` directory) are git-ignored. Only `*.example` files with placeholders are committed.

## Build order

1. **Prep:** hostnames, static IPs, `/etc/hosts` (or DNS), chrony, firewalld, SELinux enforcing
2. **Server:** `dnf install 389-ds-base`, `dscreate from-file lab.inf`, open `ldap` and `ldaps` in firewalld
3. **Directory:** if the backend is missing, `dsconf lab backend create ... --create-suffix`; load `ldif/structure.ldif` with `ldapadd`
4. **TLS:** create the CA and server certificate (`configs/san.ext`), then `dsctl lab tls import-ca` and `import-server-key-cert`
5. **Access control:** create the `sssd-bind` account (`ldif/service.ldif.example`), set passwords with `ldappasswd -ZZ`, apply `ldif/aci.ldif`, then `nsslapd-allow-anonymous-access=rootdse` and `nsslapd-require-secure-binds=on`
6. **Client:** trust the CA, install `sssd sssd-ldap oddjob-mkhomedir`, deploy `sssd.conf`, `authselect select sssd with-mkhomedir`
7. **Authorization and recovery:** `simple_allow_groups`, run `scripts/ldap-backup.sh` and a restore drill

## Verification

```bash
getent passwd kofi            # identity via NSS
id kofi                       # primary and supplementary groups
ssh kofi@client.lab.local     # authentication via PAM, home directory auto-created
sudo scripts/ldap-healthcheck.sh   # exit 0/1/2 for ports, StartTLS, certificate expiry
```

## Security notes

- The CA private key lives on the server in this lab. In production it would be kept offline.
- `sssd.conf` holds the service-account password in plaintext (file mode 0600). That is why the account is read-only and cannot see password hashes.
- Backups and LDIF exports contain password hashes and are written with `umask 077`.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).
