# Technical Guide: Exposing a Local Linux Environment via Cloudflare (CGNAT/Hotspot Friendly)

This document outlines the end-to-end process of securely exposing local web applications and a Telegram bot listener to the internet from behind a Carrier-Grade NAT (CGNAT) or mobile hotspot.

It utilizes a zero-cost stack: a `.qzz.io` domain (offered by `https://nic.us.kg/`), Cloudflare Tunnels, and Cloudflare Zero Trust. A static landing page is served directly from the Linux box via nginx, routed through the tunnel to the root domain.

---

## Phase 1: Clean House Essentials (Local Hardening)

Before connecting your machine to the Cloudflare edge, secure the local host. These steps should be done before the box is reachable from the internet.

**1. Update System Packages**

```bash
sudo apt update && sudo apt upgrade -y
# Enable automatic security updates (Debian/Ubuntu)
sudo apt install unattended-upgrades -y

# Verify the periodic job is actually enabled (installing the package alone does not prove it)
systemctl status unattended-upgrades --no-pager
apt-config dump APT::Periodic::Unattended-Upgrade   # should be "1"
```

**2. Enable Ubuntu Pro (Free Extended Security)**

Ubuntu offers a free "Pro" tier for personal use (up to 5 machines) that provides Expanded Security Maintenance (ESM) for additional packages.

- Go to [ubuntu.com/pro](https://ubuntu.com/pro) and sign in or create a free account.
- Navigate to your dashboard to find your **Pro token**.
- Attach your machine to your Pro account:

```bash
sudo pro attach <YOUR_TOKEN>
```

_(This automatically enables ESM infrastructure and application updates.)_

**3. Secure SSH Access**

Ensure you have copied your public SSH key to the server before doing this step - once password auth is disabled, a key is the only way in.

```bash
ssh-copy-id user@host
```

Then open the SSH config:

```bash
sudo nano /etc/ssh/sshd_config
```

Update the following directives:

```text
PasswordAuthentication no
PermitRootLogin no
AllowUsers your_username
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
```

Restart the SSH daemon:

```bash
sudo systemctl restart ssh
```

> **Note:** In Phase 6 we route SSH itself through the Cloudflare Tunnel, which means port 22 never needs to be exposed to the public internet at all. The UFW `allow ssh` rule added below can be removed at that point.

**4. Configure Firewall (UFW)**

Since Cloudflare Tunnels establish an _outbound_ connection, no inbound ports need to be opened for web traffic. The only inbound rule needed at this stage is SSH - and even that goes away in Phase 6.

```bash
sudo apt install ufw -y

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable
```

Verify the rules:

```bash
sudo ufw status verbose
```

**5. Kernel & AppArmor Hardening**

Tighten kernel exposure and verify mandatory access controls are active.

```bash
# Check AppArmor is running
sudo aa-status

# Apply hardening sysctl settings
sudo tee /etc/sysctl.d/99-hardening.conf <<EOF
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
EOF

sudo sysctl --system
```

To disable USB storage on a headless server (reduces physical attack surface):

```bash
echo "install usb-storage /bin/false" | sudo tee /etc/modprobe.d/disable-usb-storage.conf
```

**6. Install Fail2ban**

Provides automatic IP banning after repeated failed authentication attempts.

```bash
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

The default configuration protects SSH. Verify it is active:

```bash
sudo fail2ban-client status sshd
```

---

## Phase 2: Domain Registration & Cloudflare Setup

**1. Acquire a Free Domain**

- Register an account and claim a free domain at a free registrar such as [nic.us.kg](https://nic.us.kg/) or similar.
- Note your domain name (e.g., `pitrified.qzz.io`).

**2. Add Domain to Cloudflare**

- Create a free account at [Cloudflare](https://dash.cloudflare.com/).
- Click **Add a Site** and enter your domain.
- Select the **Free** tier.
- Cloudflare will scan for existing DNS records. For a brand new domain this will return **0 records - this is expected and correct**. There is nothing to import. Click through.
- Cloudflare will provide two nameservers (e.g., `xxx.ns.cloudflare.com`).

**3. Update Nameservers at Your Registrar**

- Return to your registrar's dashboard.
- Replace the default nameservers with the two Cloudflare nameservers.
- Wait 5–15 minutes for DNS propagation.

Once active, Cloudflare is the authoritative DNS provider for your domain. All DNS records are now managed from the Cloudflare dashboard.

**4. Cloudflare Edge Security Settings**

Apply these settings in the Cloudflare dashboard once DNS is live. These harden the edge before any traffic reaches your box.

- **SSL/TLS → Overview** → Set mode to **Full (Strict)**. This ensures end-to-end encrypted connections and rejects invalid certificates.
- **SSL/TLS → Edge Certificates** → Set minimum TLS version to **TLS 1.2**.
- **SSL/TLS → Edge Certificates → HSTS** → _Enable only after confirming HTTPS works end-to-end_ (i.e., after Phase 4 is complete and a subdomain loads correctly in a browser without errors). HSTS tells browsers to never use HTTP, and enabling it prematurely on a misconfigured site can lock you out.
  Suggested settings: max-age 6 months, `includeSubDomains` on, **preload off** - preload puts the domain on a browser-shipped list and is effectively irreversible.
  **Re-using a zone (box migration):** HSTS is a zone-level setting, so it may already be enabled from the previous setup. Check it _before_ repointing DNS: if it is on and HTTPS breaks mid-transition, browsers hard-fail instead of falling back to HTTP. Disable it before the cutover and re-enable after the end-to-end test. If it was ever enabled _with preload_, the toggle does not help - keep the transition HTTPS-only.
- **Security → Settings** → Enable **Bot Fight Mode** to block automated scanners at the edge.
- **Security → WAF** → Enable the **Cloudflare Managed Ruleset**. This is available on the free tier and provides a baseline web application firewall at zero cost. If the WAF page is not visible, look under **Security → Overview** for a "Managed rules" card, or under **Security → Application Security** - the nav label varies by account.
  > Both Bot Fight Mode and the managed WAF can challenge or block Telegram's servers calling a bot webhook. If you deploy a bot (Phase 7), the Access bypass there covers the identity check only - also confirm Bot Fight Mode is not intercepting the webhook path.
- **Notifications** → Set up alerts for tunnel health and unusual traffic spikes.

---

## Phase 3: Landing Page via nginx

Rather than hosting a static landing page on Cloudflare Pages, we serve it directly from the Linux box via nginx. This keeps everything in one place, allows the page to eventually show live service status, and means one fewer external dependency.

The landing page lives at the root domain (e.g., `pitrified.qzz.io`) and links to all tunnelled subdomains.

**1. Install nginx**

```bash
sudo apt install nginx -y
```

**2. Place the Landing Page**

Symlink `/var/www/hub` to the `sites/landing/` folder in this repo so that nginx serves the files directly from the checkout. To update the landing page, edit `sites/landing/index.html` and nginx picks up the change immediately.

```bash
sudo mkdir -p /var/www
sudo ln -sfn /path/to/linux-box-cloudflare/sites/landing /var/www/hub
```

Or run the provided script (see `scripts/README.md`) which resolves the repo path automatically:

```bash
sudo bash scripts/deploy-configs.sh
```

The landing page lives in `sites/landing/` of the [linux-box-cloudflare](https://github.com/Pitrified/linux-box-cloudflare) repo.

**Home-directory permissions:** recent Ubuntu releases create home directories as `750`,
so the nginx worker (`www-data`) cannot traverse `/home/<user>` to reach the symlinked
checkout and every request 404s (`stat() ... Permission denied` in the error log).
Grant traverse-only access to `www-data` alone, rather than opening the home to all users:

```bash
sudo setfacl -m u:www-data:--x /home/<user>
# undo: sudo setfacl -x u:www-data /home/<user>
```

**3. Create an nginx Site Config**

We use port `8090` to avoid conflicts with nginx's default port 80 listener, and bind
**loopback only**: the tunnel connects from localhost, so nothing on the LAN should be
able to reach the site directly and bypass the Cloudflare edge (WAF, Access policies).
This rule applies to **every tunnelled backend**, not just nginx - bind apps to
`127.0.0.1`, never `0.0.0.0`.

```bash
sudo nano /etc/nginx/sites-available/hub
```

```nginx
server {
    listen 127.0.0.1:8090;
    server_name localhost;

    root /var/www/hub;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

**4. Enable the Site and Restart nginx**

```bash
sudo ln -s /etc/nginx/sites-available/hub /etc/nginx/sites-enabled/hub
sudo nginx -t          # verify config syntax before restarting
sudo systemctl restart nginx
```

Quick local test - should return your HTML:

```bash
curl http://localhost:8090
```

---

## Phase 4: Multiple Apps via Cloudflare Tunnel

All traffic - the landing page, apps, and the bot - is routed through a single Cloudflare Tunnel. The tunnel makes an outbound connection from your box to Cloudflare's edge; no inbound ports are needed.

**1. Install `cloudflared`**

Install from Cloudflare's apt repository, not by downloading the release binary by hand.
`cloudflared` is the box's one internet-facing, long-lived daemon; a hand-placed binary in
`/usr/local/bin` is invisible to `unattended-upgrades` and silently ages, while the apt
package is verified against Cloudflare's signing key and picked up by automatic updates.

```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt update && sudo apt install cloudflared -y
```

If `apt update` 404s on the cloudflared repo, your release's codename is not published
on pkg.cloudflare.com yet (seen with Ubuntu 26.04 `resolute`). Replace
`$(lsb_release -cs)` in the sources line with the latest published LTS codename
(e.g. `noble`) - the package is a static binary, so the dist name is nominal.

**2. Authenticate and Create Tunnel**

```bash
# Opens a browser window to authenticate with your Cloudflare account
cloudflared tunnel login

# Create the tunnel
cloudflared tunnel create my-server
```

This generates a JSON credentials file in `~/.cloudflared/` named after the tunnel's UUID. **Copy the UUID** - you need it for the config file.

**3. Secure the Credentials File**

The credentials JSON grants full control over the tunnel. Lock it down immediately and move it to a root-owned system location since `cloudflared` runs as a system service.

```bash
sudo mkdir -p /etc/cloudflared
sudo mv ~/.cloudflared/*.json /etc/cloudflared/
sudo chmod 600 /etc/cloudflared/*.json
sudo chown root:root /etc/cloudflared/*.json
```

**4. Configure Ingress Rules**

```bash
mkdir -p ~/.cloudflared
nano ~/.cloudflared/config.yml
```

Populate with your tunnel UUID, the root domain pointing at nginx, and all app subdomains:

```yaml
tunnel: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
credentials-file: /etc/cloudflared/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json

ingress:
  # Root domain - landing page served by nginx
  - hostname: pitrified.qzz.io
    service: http://localhost:8090

  # App 1
  - hostname: app1.pitrified.qzz.io
    service: http://localhost:8080

  # App 2
  - hostname: app2.pitrified.qzz.io
    service: http://localhost:3000

  # Telegram Bot Listener
  - hostname: bot.pitrified.qzz.io
    service: http://localhost:5000

  # Catch-all (required - must be last)
  - service: http_status:404
```

**5. Route DNS & Start Service**

```bash
# Map each hostname to the tunnel (creates CNAME records in Cloudflare DNS automatically)
cloudflared tunnel route dns my-server pitrified.qzz.io
cloudflared tunnel route dns my-server app1.pitrified.qzz.io
cloudflared tunnel route dns my-server app2.pitrified.qzz.io
cloudflared tunnel route dns my-server bot.pitrified.qzz.io
```

`route dns` refuses a hostname that already has a DNS record (`record already exists`).
On a re-used zone - e.g. migrating a box, where stale CNAMEs still point at the old
tunnel - add `--overwrite-dns`:

```bash
cloudflared tunnel route dns --overwrite-dns my-server pitrified.qzz.io
```

Before installing the service, deploy the config to `/etc/cloudflared/config.yml`. The
`sudo cloudflared service install` command runs as root, so `~` expands to `/root/` - it
will not find files in your home directory. In this repo the config is tracked at
`configs/cloudflared/config.yml` and deployed by the script (see "Config File Tracking"
below):

```bash
sudo bash scripts/deploy-configs.sh
```

Do **not** copy `cert.pem` to `/etc/cloudflared/`. It is the account-scoped credential
used only by management commands (`tunnel login` / `create` / `route dns` / `delete`);
`tunnel run` and the installed service never read it. Keeping it off the serving box means
a box compromise exposes only the revocable per-tunnel JSON, never the whole account.
Ideally run all management commands from a separate trusted machine and copy only the
`<UUID>.json` to the box.

Then install and start the service:

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

**6. End-to-End Connectivity Test**

Open `https://pitrified.qzz.io` in a browser. Seeing the landing page confirms the full stack is working: tunnel, Cloudflare DNS, edge TLS, and local nginx are all connected.

Once this works, go back to the Cloudflare dashboard and enable **HSTS** (see Phase 2, step 4) - HTTPS is now confirmed working.

_Reference: [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)_

---

## Phase 5: Zero Trust Security (Google Auth)

Protect your applications so only authorised users can access them. Zero Trust Access sits in front of all your subdomains and enforces an identity check before any request reaches the tunnel.

**1. Create the Access Application**

1. Navigate to the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/).
2. Go to **Access** > **Applications** > **Add an Application** → **Self-hosted**.
3. **Application Configuration:**
   - Application Name: `Internal Apps`
   - Subdomain: `*` (wildcard covers all subdomains)
   - Domain: `pitrified.qzz.io`

4. **Policy Configuration:**
   - Policy Name: `Allow Friends`
   - Action: **Allow**
   - Include: `Emails` → add the specific Gmail addresses of authorised users.

**2. Also Protect the Root Domain**

The wildcard `*.pitrified.qzz.io` matches subdomains only - it does **not** cover the root domain `pitrified.qzz.io` itself. The landing page will be publicly accessible unless you explicitly add the root domain to the same Access application.

In the Access application configuration, click **Add domain** and add `pitrified.qzz.io` (no wildcard) alongside the existing `*.pitrified.qzz.io` entry. The same policy applies to both. After saving, visiting the root domain will also trigger the Google auth challenge.

Whether to protect the root domain is a choice: leaving it public makes the landing page a portal anyone can see (but the apps behind it are still protected). Protecting it restricts the entire domain to authorised users only.

> **Standing rule:** a new ingress hostname in `config.yml` plus `route dns` is publicly reachable the moment it exists. Never add one without confirming it is covered by an Access application (the wildcard covers subdomains; the apex needs its own entry). Do this phase immediately after Phase 4 - every hour in between is an hour the backends are exposed with no auth.

**3. Optional: Device Posture Checks**

Under **Settings → WARP Client**, you can require device-level conditions before access is granted - such as minimum OS version or disk encryption being enabled. Useful if multiple people access your apps from personal devices.

---

## Phase 6: Secure SSH from Anywhere (via Tunnel)

The most secure approach to remote SSH is to route it through the existing Cloudflare Tunnel rather than exposing port 22 to the internet. Combined with the Zero Trust Access policy, this means SSH requires both a valid private key **and** a Google authentication challenge - with no open inbound ports on the box.

**1. Add SSH to the Tunnel Ingress**

Edit `/etc/cloudflared/` and add an SSH entry:

```yaml
ingress:
  - hostname: pitrified.qzz.io
    service: http://localhost:8090
  - hostname: ssh.pitrified.qzz.io
    service: ssh://localhost:22
  # ... rest of entries ...
  - service: http_status:404
```

Route DNS and restart:

```bash
cloudflared tunnel route dns my-server ssh.pitrified.qzz.io
sudo systemctl restart cloudflared
```

**2. Remove the UFW SSH Exception**

SSH no longer arrives as a direct inbound connection. Remove the last remaining inbound firewall rule - the box now has zero open inbound ports:

```bash
sudo ufw delete allow ssh
sudo ufw reload
sudo ufw status verbose   # should show: Status: active, no incoming rules
```

**3. Connect from a Client Machine**

Install `cloudflared` on the client and connect:

```bash
# Connect directly
cloudflared access ssh --hostname ssh.pitrified.qzz.io
```

For seamless `ssh` command usage, add this to `~/.ssh/config` on the client:

```text
Host ssh.pitrified.qzz.io
    ProxyCommand cloudflared access ssh --hostname %h
    User your_username
    IdentityFile ~/.ssh/id_ed25519
```

Then simply: `ssh ssh.pitrified.qzz.io`

---

## Phase 7: Telegram Bot Integration (Webhook Bypass)

Telegram's servers need to reach the bot's webhook endpoint directly. Because they cannot pass the Google Auth screen, a specific bypass rule is required for that path only. This is a surgical bypass - only the exact webhook URL is exempted, not the whole subdomain.

**1. Create the Bypass Policy**

1. In the Zero Trust Dashboard, go to **Access** > **Applications** > **Add an Application** → **Self-hosted**.
2. **Application Configuration:**
   - Application Name: `Telegram Webhook`
   - Subdomain: `bot`
   - Domain: `pitrified.qzz.io`
   - Path: `webhook` (or whatever specific URL path your bot uses)

3. **Policy Configuration:**
   - Policy Name: `Telegram IP Bypass`
   - Action: **Bypass** - _critical: do not select Allow_
   - Include: `IP Ranges`. Enter the official Telegram subnets:
     - `149.154.160.0/20`
     - `91.108.4.0/22`

_Reference: [Official Telegram Webhook IP List](https://core.telegram.org/bots/webhooks#psa-supported-ip-addresses-and-ports)_

**2. Register the Webhook with Telegram**

The IP-range bypass above removes the Access check for those ranges, so add Telegram's
own application-level authentication: register the webhook with a `secret_token`, and have
the bot reject any request whose `X-Telegram-Bot-Api-Secret-Token` header does not match.
The IP bypass then only limits who can knock; the secret decides who gets in.

Read the bot token from its credentials file rather than pasting it on the command line
(pasting puts it in shell history and process listings):

```bash
BOT_TOKEN="$(cat ~/cred/tg-bot/token)"          # wherever the token lives
WEBHOOK_SECRET="$(openssl rand -hex 32)"        # store alongside the token for the bot to check

curl -F "url=https://bot.pitrified.qzz.io/webhook" \
  -F "secret_token=${WEBHOOK_SECRET}" \
  "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook"
```

---

## Infrastructure as Code (Managing Cloudflare Programmatically)

Every step in this guide that uses the Cloudflare dashboard can be managed as code instead, enabling version control, reproducibility, and automated deployments.

### Terraform (Recommended)

Cloudflare maintains an official Terraform provider covering tunnels, DNS records, Access applications and policies, WAF rules, and more.

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_tunnel" "my_server" {
  account_id = var.account_id
  name       = "my-server"
  secret     = base64encode(random_bytes.tunnel_secret.hex)
}

resource "cloudflare_record" "root" {
  zone_id = var.zone_id
  name    = "@"
  value   = "${cloudflare_tunnel.my_server.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_access_application" "internal_apps" {
  zone_id          = var.zone_id
  name             = "Internal Apps"
  domain           = "*.pitrified.qzz.io"
  session_duration = "24h"
}

resource "cloudflare_access_policy" "allow_friends" {
  application_id = cloudflare_access_application.internal_apps.id
  zone_id        = var.zone_id
  name           = "Allow Friends"
  precedence     = 1
  decision       = "allow"

  include {
    email = ["you@gmail.com"]
  }
}
```

Never commit your API token to version control. Use environment variables:

```bash
export TF_VAR_cloudflare_api_token="your_token_here"
terraform init && terraform apply
```

### `cloudflared` CLI Scripting

The `cloudflared` binary is fully scriptable and can be wrapped in shell scripts or Ansible playbooks for repeatable setup:

```bash
#!/bin/bash
TUNNEL_NAME="my-server"
DOMAIN="pitrified.qzz.io"
SUBDOMAINS=("app1" "app2" "bot" "ssh")

cloudflared tunnel create $TUNNEL_NAME 2>/dev/null || echo "Tunnel already exists"

for sub in "${SUBDOMAINS[@]}"; do
  cloudflared tunnel route dns $TUNNEL_NAME "${sub}.${DOMAIN}"
done

sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

### Cloudflare REST API

Every dashboard action has a REST API equivalent. Useful for lightweight scripting without Terraform:

```bash
# List all tunnels
curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq '.result[].name'
```

### Wrangler CLI (Pages Deployments)

If you use Cloudflare Pages for any static sub-sites, `wrangler` handles deployments from CI/CD pipelines:

```bash
npm install -g wrangler
wrangler pages deploy ./site --project-name=my-landing-page
```

> **Pages vs Workers:** When creating a new application in the Cloudflare dashboard, always choose the **Pages** tab for static sites. The `npx wrangler deploy` command and the "Path to your worker" field belong to **Workers** (serverless functions) - a completely different product. For a static site served from a Git repo, use Pages → Connect to Git, set the build output directory to `site`, and leave the build command empty.

---

## Documentation: MkDocs & Zensical

A natural use of Cloudflare Pages (or a dedicated subdomain via tunnel) is hosting project documentation. The recommended approach for Python projects is **MkDocs with the Material theme**, with an eye toward migrating to **Zensical** as it matures.

### MkDocs + Material (Recommended Today)

MkDocs with Material for MkDocs is the battle-tested standard for Python project documentation.

```bash
pip install mkdocs-material mkdocstrings[python]
```

```yaml
# mkdocs.yml
site_name: My Project
theme:
  name: material

plugins:
  - search
  - mkdocstrings:
      handlers:
        python:
          options:
            docstring_style: google

nav:
  - Home: index.md
  - API Reference: api.md
```

Reference a module in a docs page to auto-generate API docs from its docstrings:

```markdown
<!-- docs/api.md -->

# API Reference

::: mypackage.mymodule
```

To deploy to Cloudflare Pages, set the Pages build command to:

```bash
pip install mkdocs-material mkdocstrings[python] && mkdocs build
```

And the output directory to `site`.

### Zensical (Watch & Migrate When Ready)

Zensical is a next-generation static site generator built by the Material for MkDocs team from scratch in Rust. It is the correct long-term direction but is currently in **alpha**.

**Why it matters:** MkDocs itself has been unmaintained since August 2024, making it a supply chain risk. Zensical was purpose-built to replace both MkDocs and Material for MkDocs in a single coherent stack, with a Rust-based differential build engine (ZRX) that delivers 4–5× faster incremental rebuilds.

**Current state (early 2026):**

- Reads your existing `mkdocs.yml` natively - no config changes required to try it.
- Markdown content, template overrides, custom CSS and JS are all compatible without modification.
- Incremental (serve-mode) builds are already 4–5× faster than MkDocs.
- The module system - required for third-party extensibility including API docs - is in development and initially gated to Zensical Spark (paid tier) members.
- Full Python API documentation support (the mkdocstrings author has joined the team) is on the roadmap but not yet shipped.

**Migration when ready:**

```bash
pip install zensical

# Drop-in replacement - no changes to mkdocs.yml needed
zensical build
zensical serve
```

**When to migrate:** Watch for the module system public release and mkdocstrings parity in Zensical. At that point the switch is a one-line change to your build command. The `mkdocs.yml` config, all Markdown content, and the Cloudflare Pages deploy pipeline remain identical.

_References: [Zensical](https://zensical.org/) · [Compatibility](https://zensical.org/compatibility/) · [Roadmap](https://zensical.org/about/roadmap/) · [mkdocstrings](https://mkdocstrings.github.io/) · [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)_

---

## Config File Tracking (Git-Backed, Deployed as Copies)

Several system config files created during this guide are tracked in the repo under `configs/` and deployed to their `/etc/` paths as **root-owned copies** by `scripts/deploy-configs.sh`. The repo is the source of truth; the script is the deploy gate - it shows a diff of every pending change before installing.

| Repo path | System path |
| --- | --- |
| `configs/cloudflared/config.yml` | `/etc/cloudflared/config.yml` |
| `configs/nginx/hub` | `/etc/nginx/sites-available/hub` |
| `configs/sysctl/99-hardening.conf` | `/etc/sysctl.d/99-hardening.conf` |

Copies, not symlinks, on purpose: a symlink from `/etc/` into a user-writable checkout of a public repo lets any user-level compromise - or a `git pull` of a bad commit - silently change root-consumed config (kernel sysctls, nginx, tunnel ingress) with no privilege boundary. With copies, live config only changes through `sudo` + the script's diff step. The corollary: **treat `git pull` on this repo as a config change** and review the diff before re-deploying.

> **Not tracked:** `/etc/cloudflared/<UUID>.json` (tunnel credentials) - this file is a secret and must never be committed to git.

### Editing a config

Edit the file in the repo, deploy (the script diffs and validates), then restart the service:

```bash
# example: update cloudflare tunnel ingress rules
nano configs/cloudflared/config.yml
sudo bash scripts/deploy-configs.sh
sudo systemctl restart cloudflared
git add configs/cloudflared/config.yml && git commit -m "update tunnel ingress"
```

For nginx the deploy script already runs `nginx -t`; restart with `sudo systemctl restart nginx`. For sysctl changes apply with `sudo sysctl --system`.

### Re-deploying (after cloning or moving the repo)

If the repo is cloned fresh or moved, re-run the deploy script:

```bash
sudo bash scripts/deploy-configs.sh
```

This script resolves the repo root from its own path, deploys all three configs (showing diffs), links `/var/www/hub` to the landing page, and validates each service config.

## Decommissioning a Box or Tunnel

When a box is retired or replaced by a fresh tunnel, revoke what it held - repointing DNS alone does not invalidate anything:

- **Delete the old tunnel** from the management machine: `cloudflared tunnel delete <NAME-or-UUID>`. This revokes its credentials JSON server-side; until then, anyone with a copy of that JSON (old disk, backups) can run the tunnel and serve traffic for any hostname still CNAMEd to it.
- **Delete stale DNS records** for hostnames the new box does not serve, so they do not dangle at a dead tunnel.
- **Remove stale backups**: delete the old tunnel's JSON from the password manager or wherever it was backed up.
- **Wipe the old disk** if the hardware leaves your control.
