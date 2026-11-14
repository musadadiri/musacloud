# Security design and threat model

MusaCloud protects three things: the files stored in Nextcloud, the credentials that run the system, and the backups in AWS S3. This document lists the threats I designed for, how each is handled, and the risk that remains.

## Threats and mitigations

| Threat | How MusaCloud handles it | Remaining risk |
| --- | --- | --- |
| Someone on the internet scans for the server and attacks it | Nextcloud listens only on `127.0.0.1:8080`. The only way in is Tailscale, so there are no public ports to find. | If my Tailscale login is compromised, an attacker could join my tailnet. That login should have two-factor authentication. |
| A Nextcloud password is stolen | Two-factor login (TOTP) is turned on for my account | Two-factor login isn't enforced for every account yet |
| Traffic is intercepted, for example on public Wi-Fi | All traffic is encrypted by Tailscale (WireGuard) and served over HTTPS with a Tailscale certificate | None identified |
| The VM is lost, broken or wiped | Nightly encrypted restic backups go to S3, and a full restore was tested and verified with SHA-256 | Backups only run while the VM is on, so a lab VM that is often off can fall more than a day behind |
| The AWS backup key leaks | The IAM policy limits the key to one bucket, and restic encrypts data before upload, so the key alone can't read files | A leaked key could still delete backups. S3 Versioning or Object Lock, plus regular key rotation, would reduce this. |
| An attacker who controls the server deletes the backups | Retention keeps 7 daily, 4 weekly and 6 monthly snapshots | The server holds a key that can delete objects. A separate append-only key or S3 Object Lock would close this gap. |
| Secrets end up on GitHub | `.env` is excluded by `.gitignore` and locked with `chmod 600` | Screenshots can still show secrets, so I review every image before publishing it |
| Known vulnerabilities in old software | Docker images and Ubuntu are updated monthly | Updates are manual, so they can be missed |

## Design principles

- **No public exposure.** Nothing listens on a public interface. Access requires being on my private network first.
- **Least privilege.** The backup key can reach one bucket. The admin account is separate from everyday use.
- **Encrypt before it leaves.** Backups are encrypted on the server, so the cloud provider stores only unreadable data.
- **Prove recovery.** A backup counts only after a restore has been tested and checked against the original files.

## Out of scope

- Physical or administrative access to the Azure hardware, and insider access at Microsoft or Amazon
- University administrators with access to the lab VM. This is why the lab build uses test data only.
- Compromise of the devices I use to log in

## Next improvements

1. Enforce two-factor login for every account.
2. Turn on S3 Versioning or Object Lock so backups can't be silently deleted.
3. Rotate the AWS access key and passwords on a regular schedule.
4. Send Nextcloud's login logs into a SIEM to alert on repeated failed logins.
