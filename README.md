# MusaCloud

A private, self-hosted replacement for iCloud storage. Files and photos live on my own server, only my own devices can reach it, and encrypted backups go to Amazon S3 every night.

## How it works

```
iPhone / laptop ──(Tailscale private network, HTTPS)──► Ubuntu server
                                                          ├─ Nextcloud   (files + photos)
                                                          ├─ PostgreSQL  (database)
                                                          ├─ Redis       (speed)
                                                          └─ backup.sh ──(encrypted)──► Amazon S3
```

**Security design**

- **Not on the public internet.** The app only listens on `127.0.0.1`. Tailscale is the only way in.
- **HTTPS everywhere**, using Tailscale's automatic certificates.
- **Two-factor login** on Nextcloud.
- **Encrypted backups.** restic encrypts everything before it leaves the server, and the AWS key can only touch one bucket (least privilege).
- **No secrets in code.** Passwords and keys live in `.env`, which is never committed.

**Skills shown:** Docker, Linux, cloud storage (AWS S3, IAM), network security, backup and recovery, Bash scripting.

## What you need

- An Ubuntu Server 24.04 VM: 2 CPUs, 4 GB RAM, 50 GB+ disk, default NAT network
- A free Tailscale account
- An AWS account (storage costs very little while you're only backing up test files)
- Your phone, with the Tailscale and Nextcloud apps

## Setup

### Step 1: Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Log out and back in, then check that it works: `docker compose version`

### Step 2: Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=musacloud
```

Open the link it prints and log in. In the Tailscale admin console, go to the DNS page and make sure **MagicDNS** and **HTTPS certificates** are both on. Your server's full name (like `musacloud.your-tailnet.ts.net`) is shown on the Machines page.

### Step 3: Fill in your settings

Copy this project folder onto the VM, then:

```bash
cd musacloud
cp .env.example .env
nano .env
```

Fill in every value. Make each password with `openssl rand -hex 24`.

> Save `RESTIC_PASSWORD` in a password manager. Without it, your backups can never be opened.

### Step 4: Start the server

```bash
docker compose up -d
docker compose logs -f app
```

The first start takes a few minutes. When the log stops scrolling, press `Ctrl+C`.

### Step 5: Turn on private HTTPS access

```bash
sudo tailscale serve --bg 8080
```

It prints your URL. Open it on another device that's connected to Tailscale and log in with the admin account from `.env`. If it prints a link instead, open the link to enable HTTPS for your tailnet, then run the command again.

> Never use `tailscale funnel`. That would put your server on the public internet.

### Step 6: Lock it down

1. **Turn on two-factor login:** go to Apps, enable **Two-Factor TOTP Provider**, then go to Personal settings → Security and set it up with an authenticator app.
2. **Use a normal account day to day:** create a regular user for yourself and keep the admin account for admin tasks only.
3. **Fix warnings:** go to Administration settings → Overview and fix anything it lists.
4. **Prove it's private:** turn off Tailscale on your phone and try the URL. It should fail. Screenshot this for your portfolio.

### Step 7: Connect your iPhone

1. Install **Tailscale** and **Nextcloud** from the App Store.
2. Log in to Tailscale.
3. Open Nextcloud and enter your server's URL.
4. Turn on **Auto Upload** for photos.

Tailscale needs to be on for your phone to sync.

### Step 8: Set up AWS backups

1. **Secure your AWS account first:** turn on MFA for the root account, and don't use root for daily work.
2. **Create the bucket:** in S3, create a bucket (for example `musacloud-backups-` plus some random letters). Leave **Block all public access** on.
3. **Create the policy:** go to IAM → Policies → Create policy → JSON. Paste in `iam-policy.json`, replacing `YOUR-BUCKET-NAME` in both places.
4. **Create the backup user:** go to IAM → Users and create a user called `musacloud-backup`. Attach the policy, then create an access key (choose "Application running outside AWS"). Put both keys in `.env`.
5. **Run the first backup:**

   ```bash
   sudo apt install -y restic
   chmod +x backup.sh
   sudo ./backup.sh init
   sudo ./backup.sh
   ```

6. **Schedule it nightly at 3 a.m.:** run `sudo crontab -e` and add this line, changing the path to where your folder is:

   ```
   0 3 * * * /home/YOUR-USER/musacloud/backup.sh >> /var/log/musacloud-backup.log 2>&1
   ```

### Step 9: Test a restore (don't skip this)

```bash
sudo ./backup.sh snapshots
sudo ./backup.sh test-restore
```

Look inside `/tmp/musacloud-restore-test` and open a few photos and documents. A backup you've never restored isn't a backup yet.

> Keep iCloud running until this step works.

## Keeping it updated

```bash
docker compose pull && docker compose up -d
```

Do this about once a month. Nextcloud can only upgrade one major version at a time, so don't let it fall far behind.

## Next steps

- **Monitor it:** send Nextcloud's log (`nextcloud/data/nextcloud.log`) into the Splunk SIEM project to detect failed logins.
- **Make it always-on:** move from the VM to an old PC or mini PC with a big drive, and turn on disk encryption when installing Ubuntu.
- **Photos only?** Immich is a photo-focused alternative to Nextcloud.

## Files

| File | What it does |
|---|---|
| `docker-compose.yml` | Runs Nextcloud, the database, Redis and background jobs |
| `.env.example` | Template for passwords and keys (copy it to `.env`) |
| `backup.sh` | Encrypted backups to S3, plus restore testing |
| `iam-policy.json` | AWS permissions limited to the backup bucket |
| `.gitignore` | Keeps secrets and personal files off GitHub |
