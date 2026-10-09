# Troubleshooting log

Real failures hit while building this lab, with the diagnosis path for each.

| Symptom | Diagnosis | Cause / fix |
|---|---|---|
| `ldapsearch` on the base DN returns `result: 32 No such object` | rootDSE query (`-b "" -s base namingContexts`) showed no `namingContexts`; `dsconf lab backend suffix list` printed `No backends` | The instance had no backend, so the server was not responsible for any suffix. Fixed with `dsconf lab backend create --suffix dc=lab,dc=local --be-name userroot --create-suffix`. Make sure `[backend-userroot]` is uncommented in `lab.inf` (TODO: confirm the exact cause in your own INF and edit this line). |
| Anonymous search for a user returns `result: 0` but no entries | Same search as Directory Manager returned the entry | The data existed. Anonymous binds had no ACI granting read access to the user entries. Solved by a dedicated read-only service account, not by opening anonymous access. |
| `Server is unwilling to perform (53)` / `Unauthenticated binds are not allowed` | `-D` given without `-W` | A bind with a DN and an empty password is an "unauthenticated bind"; the server correctly refuses it. Supply the password. (A wrong password gives 49, not 53.) |
| `Can't contact LDAP server (-1)` | `openssl s_client` showed the real reason: `Verify return code: 19` (CA not trusted) and `64` (IP address mismatch) | The client library hides TLS detail behind -1. The certificate SAN only lists `ldap.lab.local`, so connect by hostname and trust the lab CA. |
| `getent passwd kofi` works but SSH says wrong password | `ldapwhoami -ZZ -D uid=kofi,...` isolates the bind; the server's access log shows the result code for the user bind | TODO: record the actual cause here (e.g. password never set for the user, or a config issue). |
| Fix applied but SSSD still shows the old result | n/a | SSSD caches positive and negative results. Run `sudo sss_cache -E` after changing the directory or `sssd.conf`. |

## Diagnostic toolbox

- Server: `sudo tail -f /var/log/dirsrv/slapd-lab/access` (bind and search result codes)
- TLS: `openssl s_client -connect ldap.lab.local:636 -CAfile ca.crt -verify_hostname ldap.lab.local`
- Client: `sudo sssctl domain-status lab.local`, `sudo sssctl user-checks <user> -a auth -s sshd`
- Logs: `/var/log/sssd/`, `journalctl -u sssd`, `/var/log/secure`
