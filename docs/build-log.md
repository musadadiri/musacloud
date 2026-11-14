# Build log

## Nov 14, 2026: Full build (Steps 1–13)

**Environment:** Ubuntu 22.04 VM in an Azure lab provided through Syracuse University, reached by remote desktop from my MacBook Air. Test files only.

**Result:** MusaCloud is running with private HTTPS access, encrypted nightly backups to AWS S3 and a verified restore.

### What I did

1. Updated the VM and checked its memory and disk space (`free -h`, `df -h /`).
2. Put the project files on GitHub and cloned them into the VM with `git clone`.
3. Installed Docker and confirmed it worked with `docker run hello-world`.
4. Installed Tailscale and joined the VM, my MacBook and my iPhone to one private network.
5. Created `.env` with generated passwords (`openssl rand -hex 24`) and locked it down with `chmod 600 .env`.
6. Started Nextcloud, PostgreSQL, Redis and the cron container with `docker compose up -d`.
7. Turned on private HTTPS with `sudo tailscale serve --bg 8080` and logged in from my laptop.
8. Reviewed Nextcloud's security and setup warnings (normal for a fresh install), turned on two-factor login, and uploaded two photos from the Nextcloud iPhone app.
9. Created an S3 bucket in us-east-2, a least-privilege IAM policy and a backup-only IAM user.
10. Created an encrypted restic repository and ran the first backup.
11. Set the VM's time zone and scheduled a nightly backup with cron.
12. Restored the backup to a test folder and verified it with SHA-256 hashes.

### Problems and fixes

#### 1. The setup steps assumed VirtualBox, but my VM is in Azure

- **Symptom:** The SSH and VirtualBox port-forwarding steps didn't apply to my setup.
- **Cause:** My VM is an Azure lab VM that I reach through remote desktop, not a VM running on my laptop.
- **Fix:** Skipped SSH and used the VM's own terminal (paste is Ctrl+Shift+V in Linux). After adding myself to the docker group, I ran `sudo reboot` instead of logging out over SSH.
- **Lesson:** Adapt instructions to the real environment. Lab VMs also shut down when idle, so Tailscale shows the server as "Not Connected" until the VM is started again. That's expected.

#### 2. A file "didn't exist" even though I uploaded it

- **Symptom:** `cp: cannot stat '.env.example': No such file or directory`
- **Cause:** `ls -a` showed `_.env.example` and `_.gitignore`. Files starting with a dot were renamed with an underscore when I uploaded them from my Mac.
- **Fix:**
  ```bash
  mv _.env.example .env.example
  mv _.gitignore .gitignore
  ```
- **Lesson:** When a file seems missing, run `ls -a` to see hidden files. A `.gitignore` with the wrong name silently does nothing, which could let secrets reach GitHub.

#### 3. The backup schedule wouldn't save

- **Symptom:** `crontab: ... :2: bad hour` and `errors in crontab file, can't install.`
- **Cause:** The hour field (the second item on the line) wasn't a plain number from 0 to 23.
- **Fix:** Replaced the line and confirmed it with `sudo crontab -l`:
  ```
  0 21 * * * /home/localadmin/musacloud/backup.sh >> /var/log/musacloud-backup.log 2>&1
  ```
- **Lesson:** A cron line has five time fields: minute, hour, day of month, month and day of week. I also found an `@reboot` entry from SU's lab system and left it alone.

#### 4. Backups couldn't reach the S3 bucket

- **First symptom:** `Fatal: unable to open config file: Stat: 400 Bad Request`
- **Cause:** The S3 console created my bucket in **us-east-2** with an account-regional name (`musacloud-backups-<account-id>-us-east-2-an`), but `.env` still had a placeholder bucket name and **us-east-1**.
- **Fix:** Copied the exact bucket name with Copy ARN, then updated `RESTIC_REPOSITORY` in `.env` and both bucket ARNs in the IAM policy.
- **Second symptom:** `301 response missing Location header`, with a request going to a `us-east-1` address.
- **Diagnosis:** `curl -I https://s3.us-east-2.amazonaws.com` returned `405` from AmazonS3, which proved the network could reach S3. Then `grep AWS_DEFAULT_REGION .env` showed `us-east-2-an`. The `-an` belongs only to the bucket name, so restic didn't recognize the region and fell back to us-east-1.
- **Fix:**
  ```bash
  sed -i 's/^AWS_DEFAULT_REGION=.*/AWS_DEFAULT_REGION=us-east-2/' .env
  ```
- **Lesson:** The region and bucket name must match everywhere: the bucket itself, the endpoint, the region setting and the IAM policy. Reading the address inside the error message showed exactly which region was wrong.

#### 5. Interrupted commands

- **Symptom:** `signal interrupt received, cleaning up`, and the restore folder didn't exist afterward.
- **Cause:** I pressed Ctrl+C on commands that looked stuck, so they never finished. (The earlier ones were also failing because of problem 4.)
- **Fix:** Let each command run to completion once the S3 settings were fixed.
- **Lesson:** The backup script's cleanup step (a `trap` in Bash) turned Nextcloud's maintenance mode back off even when a backup was interrupted, so the service stayed available.

#### 6. Verifying the restore

- **Symptom:** `sha256sum: /nextcloud/data/.../Library.jpg: No such file or directory`
- **Cause:** restic restored the files using shorter paths (`/tmp/musacloud-restore-test/nextcloud/...`), so my shortcut for finding the original file pointed to the wrong place.
- **Fix:** Compared the two files using their full paths:
  ```bash
  sudo sha256sum /tmp/musacloud-restore-test/nextcloud/data/musacloud/files/Photos/Library.jpg ~/musacloud/nextcloud/data/musacloud/files/Photos/Library.jpg
  ```
- **Result:** Both files had the same SHA-256 hash (`e57dd165...946f5a`), so the restored copy is identical to the original.

### Results

| Check | Result |
| --- | --- |
| First encrypted backup | Snapshot created Nov 14, 2026, 16:09 JST |
| Restore test | 27,619 files restored |
| Integrity check | SHA-256 hashes match |
| Nightly schedule | Cron job set for 21:00 |

### Next session

- [ ] Fix the file names on GitHub and add screenshots
- [ ] Enforce two-factor login and resolve the remaining Nextcloud warnings
- [ ] Add the HSTS header
- [ ] Check that the nightly backup ran: `sudo cat /var/log/musacloud-backup.log`
- [ ] Export the setup guide to `docs/setup-guide.md`
