# Setup guide

How to build MusaCloud from this repo. Tested on an Ubuntu 22.04 VM in Microsoft Azure, reached through remote desktop.

## Requirements

- Ubuntu 22.04 VM with `sudo` access and outbound internet
- At least 2 GB of RAM and 20 GB of free disk (check with `free -h` and `df -h /`)
- A free Tailscale account
- An AWS account, for backups

## 1. Install Docker

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo reboot
```

The `docker` group only takes effect after you log in again, which is why the reboot is needed. Afterward, confirm Docker works:

```bash
docker run hello-world
docker compose version
```

## 2. Join the VM to Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=musacloud
```

Open the login link it prints. Then, in the Tailscale admin console under DNS, turn on **MagicDNS** and **HTTPS Certificates**. Your server's address is `musacloud.<your-tailnet>.ts.net`.

## 3. Clone and configure

```bash
git clone https://github.com/YOUR-USERNAME/musacloud.git
cd musacloud
cp .env.example .env
openssl rand -hex 24
nano .env
chmod 600 .env
```

Run `openssl rand -hex 24` once for each password. Fill in `POSTGRES_PASSWORD`, `NEXTCLOUD_ADMIN_USER` (anything except "admin"), `NEXTCLOUD_ADMIN_PASSWORD` and `TAILSCALE_HOSTNAME`. The backup settings come in step 6.

> Uploading files from macOS through GitHub's website can rename dot-files to `_.env.example` and `_.gitignore`. Check with `ls -a`, and rename them with `mv` if needed.

## 4. Start MusaCloud

```bash
docker compose up -d
docker compose ps
docker compose logs -f app
```

All four containers (app, cron, db and redis) should show as Up. Wait for the log to say Nextcloud was successfully installed, then press Ctrl+C to stop watching it.

## 5. Turn on private HTTPS and harden login

```bash
sudo tailscale serve --bg 8080
```

From a device on your tailnet, open `https://musacloud.<your-tailnet>.ts.net` and log in. Never use `tailscale funnel`, which would put the server on the public internet.

Then:

1. Enable the **Two-Factor TOTP Provider** app and set up TOTP under Personal settings, then Security.
2. Create a separate non-admin account for everyday use.
3. Review Administration settings, then Overview. These commands fix the most common warnings on a new install:

```bash
docker compose exec -u www-data app php occ db:add-missing-indices
docker compose exec -u www-data app php occ maintenance:repair --include-expensive
docker compose exec -u www-data app php occ config:system:set maintenance_window_start --type=integer --value=1
```

## 6. Set up encrypted backups to S3

1. Create a private S3 bucket and leave **Block all public access** on. If you choose the account-regional namespace, AWS names the bucket `<prefix>-<account-id>-<region>-an`.
2. Create an IAM policy from `iam-policy.json`, putting your bucket name in both ARNs. Create an IAM user with only that policy, then create an access key for it.
3. Fill in the backup section of `.env`. The region must be the plain region code, such as `us-east-2`. The `-an` suffix belongs only in the bucket name.

```
RESTIC_REPOSITORY=s3:s3.<region>.amazonaws.com/<full-bucket-name>
RESTIC_PASSWORD=<generated password>
AWS_ACCESS_KEY_ID=<key id>
AWS_SECRET_ACCESS_KEY=<secret key>
AWS_DEFAULT_REGION=<region>
```

4. Create the repository and run the first backup:

```bash
sudo apt install -y restic
chmod +x backup.sh
sudo ./backup.sh init
sudo ./backup.sh
```

Store `RESTIC_PASSWORD` in a password manager. Without it, the backups can't be decrypted.

## 7. Schedule nightly backups

```bash
sudo timedatectl set-timezone Asia/Tokyo
sudo crontab -e
```

Use your own time zone. Add this line, with your own username in the path:

```
0 21 * * * /home/<user>/musacloud/backup.sh >> /var/log/musacloud-backup.log 2>&1
```

Cron only runs while the VM is on, so pick an hour when it normally is.

## 8. Verify a restore

```bash
sudo ./backup.sh snapshots
sudo ./backup.sh test-restore
sudo sha256sum /tmp/musacloud-restore-test/nextcloud/data/<user>/files/<file> ~/musacloud/nextcloud/data/<user>/files/<file>
```

The two hashes must match exactly. A backup isn't proven until this passes.

## Maintenance

| Task | Command |
| --- | --- |
| Check status | `docker compose ps` |
| Update Nextcloud (monthly) | `docker compose pull && docker compose up -d` |
| Update Ubuntu (monthly) | `sudo apt update && sudo apt upgrade -y` |
| Back up now | `sudo ./backup.sh` |
| Read the backup log | `sudo cat /var/log/musacloud-backup.log` |

Nextcloud can only upgrade one major version at a time, so update regularly.

For errors I hit during the build and how I fixed them, see the [build log](build-log.md).
