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

Ensure you have copied your public SSH key to the server before doing this step — once password auth is disabled, a key is the only way in.

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
Protocol 2
```

Restart the SSH daemon:

```bash
sudo systemctl restart ssh
```

> **Note:** In Phase 6 we route SSH itself through the Cloudflare Tunnel, which means port 22 never needs to be exposed to the public internet at all. The UFW `allow ssh` rule added below can be removed at that point.

**4. Configure Firewall (UFW)**

Since Cloudflare Tunnels establish an _outbound_ connection, no inbound ports need to be opened for web traffic. The only inbound rule needed at this stage is SSH — and even that goes away in Phase 6.

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
- Cloudflare will scan for existing DNS records. For a brand new domain this will return **0 records — this is expected and correct**. There is nothing to import. Click through.
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
- **Security → Settings** → Enable **Bot Fight Mode** to block automated scanners at the edge.
- **Security → WAF** → Enable the **Cloudflare Managed Ruleset**. This is available on the free tier and provides a baseline web application firewall at zero cost. If the WAF page is not visible, look under **Security → Overview** for a "Managed rules" card, or under **Security → Application Security** — the nav label varies by account.
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

Create a dedicated directory for the hub site and place your `index.html` there:

```bash
sudo mkdir -p /var/www/hub
sudo cp /path/to/index.html /var/www/hub/index.html
sudo chown -R www-data:www-data /var/www/hub
```

The `index.html` file lives in the `site/` directory of the [linux-box-cloudflare](https://github.com/Pitrified/linux-box-cloudflare) repo. To update the landing page, edit that file and re-copy it here, or set up a git pull workflow.

**3. Create an nginx Site Config**

We use port `8090` to avoid conflicts with nginx's default port 80 listener.

```bash
sudo nano /etc/nginx/sites-available/hub
```

```nginx
server {
    listen 8090;
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

Quick local test — should return your HTML:

```bash
curl http://localhost:8090
```

---

## Phase 4: Multiple Apps via Cloudflare Tunnel

All traffic — the landing page, apps, and the bot — is routed through a single Cloudflare Tunnel. The tunnel makes an outbound connection from your box to Cloudflare's edge; no inbound ports are needed.

**1. Install `cloudflared`**

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
chmod +x cloudflared
sudo mv cloudflared /usr/local/bin/
```

**2. Authenticate and Create Tunnel**

```bash
# Opens a browser window to authenticate with your Cloudflare account
cloudflared tunnel login

# Create the tunnel
cloudflared tunnel create my-server
```

This generates a JSON credentials file in `~/.cloudflared/` named after the tunnel's UUID. **Copy the UUID** — you need it for the config file.

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
  # Root domain — landing page served by nginx
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

  # Catch-all (required — must be last)
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

Before installing the service, copy the config to `/etc/cloudflared/`. The `sudo cloudflared service install` command runs as root, so `~` expands to `/root/` — it will not find files in your home directory.

```bash
sudo mkdir -p /etc/cloudflared
sudo cp /home/YOUR_USERNAME/.cloudflared/config.yml /etc/cloudflared/config.yml
sudo cp /home/YOUR_USERNAME/.cloudflared/cert.pem /etc/cloudflared/cert.pem
```

Then install and start the service:

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

**6. End-to-End Connectivity Test**

Open `https://pitrified.qzz.io` in a browser. Seeing the landing page confirms the full stack is working: tunnel, Cloudflare DNS, edge TLS, and local nginx are all connected.

Once this works, go back to the Cloudflare dashboard and enable **HSTS** (see Phase 2, step 4) — HTTPS is now confirmed working.

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

The wildcard `*.pitrified.qzz.io` matches subdomains only — it does **not** cover the root domain `pitrified.qzz.io` itself. The landing page will be publicly accessible unless you explicitly add the root domain to the same Access application.

In the Access application configuration, click **Add domain** and add `pitrified.qzz.io` (no wildcard) alongside the existing `*.pitrified.qzz.io` entry. The same policy applies to both. After saving, visiting the root domain will also trigger the Google auth challenge.

Whether to protect the root domain is a choice: leaving it public makes the landing page a portal anyone can see (but the apps behind it are still protected). Protecting it restricts the entire domain to authorised users only.

**3. Optional: Device Posture Checks**

Under **Settings → WARP Client**, you can require device-level conditions before access is granted — such as minimum OS version or disk encryption being enabled. Useful if multiple people access your apps from personal devices.

---

## Phase 6: Secure SSH from Anywhere (via Tunnel)

The most secure approach to remote SSH is to route it through the existing Cloudflare Tunnel rather than exposing port 22 to the internet. Combined with the Zero Trust Access policy, this means SSH requires both a valid private key **and** a Google authentication challenge — with no open inbound ports on the box.

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

SSH no longer arrives as a direct inbound connection. Remove the last remaining inbound firewall rule — the box now has zero open inbound ports:

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

Telegram's servers need to reach the bot's webhook endpoint directly. Because they cannot pass the Google Auth screen, a specific bypass rule is required for that path only. This is a surgical bypass — only the exact webhook URL is exempted, not the whole subdomain.

**1. Create the Bypass Policy**

1. In the Zero Trust Dashboard, go to **Access** > **Applications** > **Add an Application** → **Self-hosted**.
2. **Application Configuration:**
   - Application Name: `Telegram Webhook`
   - Subdomain: `bot`
   - Domain: `pitrified.qzz.io`
   - Path: `webhook` (or whatever specific URL path your bot uses)

3. **Policy Configuration:**
   - Policy Name: `Telegram IP Bypass`
   - Action: **Bypass** — _critical: do not select Allow_
   - Include: `IP Ranges`. Enter the official Telegram subnets:
     - `149.154.160.0/20`
     - `91.108.4.0/22`

_Reference: [Official Telegram Webhook IP List](https://core.telegram.org/bots/webhooks#psa-supported-ip-addresses-and-ports)_

**2. Register the Webhook with Telegram**

```bash
curl -F "url=https://bot.pitrified.qzz.io/webhook" \
  https://api.telegram.org/bot<YOUR_BOT_TOKEN>/setWebhook
```

_(Replace `<YOUR_BOT_TOKEN>` with the token provided by BotFather.)_

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

> **Pages vs Workers:** When creating a new application in the Cloudflare dashboard, always choose the **Pages** tab for static sites. The `npx wrangler deploy` command and the "Path to your worker" field belong to **Workers** (serverless functions) — a completely different product. For a static site served from a Git repo, use Pages → Connect to Git, set the build output directory to `site`, and leave the build command empty.

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

- Reads your existing `mkdocs.yml` natively — no config changes required to try it.
- Markdown content, template overrides, custom CSS and JS are all compatible without modification.
- Incremental (serve-mode) builds are already 4–5× faster than MkDocs.
- The module system — required for third-party extensibility including API docs — is in development and initially gated to Zensical Spark (paid tier) members.
- Full Python API documentation support (the mkdocstrings author has joined the team) is on the roadmap but not yet shipped.

**Migration when ready:**

```bash
pip install zensical

# Drop-in replacement — no changes to mkdocs.yml needed
zensical build
zensical serve
```

**When to migrate:** Watch for the module system public release and mkdocstrings parity in Zensical. At that point the switch is a one-line change to your build command. The `mkdocs.yml` config, all Markdown content, and the Cloudflare Pages deploy pipeline remain identical.

_References: [Zensical](https://zensical.org/) · [Compatibility](https://zensical.org/compatibility/) · [Roadmap](https://zensical.org/about/roadmap/) · [mkdocstrings](https://mkdocstrings.github.io/) · [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)_
