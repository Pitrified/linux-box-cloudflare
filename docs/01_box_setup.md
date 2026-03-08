# Technical Guide: Exposing a Local Linux Environment via Cloudflare (CGNAT/Hotspot Friendly)

This document outlines the end-to-end process of securely exposing local web applications and a Telegram bot listener to the internet from behind a Carrier-Grade NAT (CGNAT) or mobile hotspot.

It utilizes a zero-cost stack: a `.us.kg` domain, Cloudflare Tunnels, Cloudflare Pages, and Cloudflare Zero Trust.

---

## Phase 1: Clean House Essentials (Local Hardening)

Before connecting your machine to the Cloudflare edge, secure the local host.

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

_(This automatically enables ESM infrastructure and application updates)._

**3. Secure SSH Access**

Ensure you have copied your public SSH key to the server (`ssh-copy-id user@host`). Then, disable password authentication.

```bash
sudo nano /etc/ssh/sshd_config
```

Update the following directives:

```text
PasswordAuthentication no
PermitRootLogin no
```

Restart the SSH daemon: `sudo systemctl restart ssh`

**4. Configure Firewall (UFW)**

Since Cloudflare Tunnels establish an _outbound_ connection, no inbound ports need to be opened for web traffic. Install UFW if you haven't already, then lock it down.

```bash
# Install UFW if it is not present
sudo apt install ufw -y

# Configure basic rules
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable
```

**5. Kernel & AppArmor Hardening**

Tighten kernel exposure and verify mandatory access controls are active.

```bash
# Verify AppArmor is running and check profile status
sudo aa-status

# Restrict kernel pointer exposure and dmesg to root only
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

Provides automatic IP banning after repeated failed authentication attempts, as a last line of defence.

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

- Register an account and claim a free domain at [nic.us.kg](https://nic.us.kg/).
- Note your domain name (e.g., `yourdomain.us.kg`).

**2. Add Domain to Cloudflare**

- Create a free account at [Cloudflare](https://dash.cloudflare.com/).
- Click **Add a Site** and enter `yourdomain.us.kg`.
- Select the **Free** tier.
- Cloudflare will provide two Nameservers (e.g., `dave.ns.cloudflare.com`).

**3. Update Nameservers**

- Return to the `nic.us.kg` dashboard.
- Replace the default nameservers with the Cloudflare nameservers.
- Wait 5–15 minutes for DNS propagation.

**4. Cloudflare Security Settings (Dashboard)**

Once DNS is active, harden the Cloudflare edge configuration:

- **SSL/TLS** → Set mode to **Full (Strict)** and minimum TLS version to **TLS 1.2**.
- **SSL/TLS → Edge Certificates** → Enable **HSTS** (HTTP Strict Transport Security). Set `max-age` to at least 6 months.
- **Security → Settings** → Enable **Bot Fight Mode** to block automated scanners at the edge.
- **Security → WAF** → Enable the **Cloudflare Managed Ruleset** (available on the free tier). This provides a baseline web application firewall at zero cost.
- **Notifications** → Set up alerts for tunnel health and unusual traffic spikes.

---

## Phase 3: The Hybrid Architecture (Cloudflare Pages)

To save local bandwidth and ensure high availability, host your static landing page (the portal to your apps) on Cloudflare Pages.

### Supported Build Languages & Frameworks

Cloudflare Pages is a **static site / JAMstack** platform. It supports a broad range of build tools and frameworks at the build stage, but does not run persistent server processes — those remain on the Linux box routed via tunnel. Supported ecosystems include:

- **Static HTML/CSS/JS** — deploy as-is, no build step needed.
- **Node.js** — React, Vue, Svelte, Astro, Next.js (static export), Nuxt (static), and similar frameworks. Specify the Node version via the `NODE_VERSION` environment variable in the Pages build settings.
- **Python** — static site generators such as MkDocs, Material for MkDocs, and Zensical (see the [Documentation section](#documentation-mkdocs--zensical) below). Pelican is also supported.
- **Go** — Hugo, one of the fastest static site generators available.
- **Ruby** — Jekyll and related generators.
- **Rust** — sites compiled to WebAssembly (WASM).

For the landing page in this guide, plain HTML is sufficient. For richer documentation sites, MkDocs or Zensical are the recommended choice (see below).

**1. Prepare the Repository**

- Create a simple `index.html` file containing links to your future subdomains (e.g., `https://app1.yourdomain.us.kg`).
- Push this to a public or private GitHub repository.

**2. Deploy to Cloudflare Pages**

- In the Cloudflare Dashboard, navigate to **Workers & Pages** > **Create application** > **Pages** > **Connect to Git**.
- Select your repository and deploy.
- Go to the **Custom Domains** tab for your new Page and add your root domain: `yourdomain.us.kg`.

_Reference: [Cloudflare Pages Documentation](https://developers.cloudflare.com/pages/)_

---

## Phase 4: Multiple Apps via Cloudflare Tunnel

Your dynamic applications (hosted on the Linux box) will be served via subdomains routed through a single Cloudflare Tunnel.

**1. Install `cloudflared`**

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
chmod +x cloudflared
sudo mv cloudflared /usr/local/bin/
```

**2. Authenticate and Create Tunnel**

```bash
# Login to Cloudflare
cloudflared tunnel login

# Create the tunnel (replace 'my-server' with a name of your choice)
cloudflared tunnel create my-server
```

_Note: Creating the tunnel **automatically generates** a JSON credentials file in the `~/.cloudflared/` directory. The file will be named with your new Tunnel's UUID (e.g., `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json`). Copy this UUID string, as you will need it for the configuration file._

**3. Secure the Credentials File**

The generated JSON credentials file grants full control over the tunnel. Lock down its permissions immediately:

```bash
chmod 600 ~/.cloudflared/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json
```

If running `cloudflared` as a system service, move the file to a root-owned location:

```bash
sudo mkdir -p /etc/cloudflared
sudo mv ~/.cloudflared/*.json /etc/cloudflared/
sudo chmod 600 /etc/cloudflared/*.json
sudo chown root:root /etc/cloudflared/*.json
```

**4. Configure Ingress Rules**

Create the configuration directory and file:

```bash
mkdir -p ~/.cloudflared
nano ~/.cloudflared/config.yml
```

Populate the file using your Tunnel UUID and local application ports:

```yaml
tunnel: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
credentials-file: /etc/cloudflared/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json

ingress:
  # App 1
  - hostname: app1.yourdomain.us.kg
    service: http://localhost:8080
  # App 2
  - hostname: app2.yourdomain.us.kg
    service: http://localhost:3000
  # Telegram Bot Listener
  - hostname: bot.yourdomain.us.kg
    service: http://localhost:5000
  # Catch-all (Required)
  - service: http_status:404
```

**5. Route DNS & Start Service**

```bash
# Map DNS for each subdomain to the tunnel
cloudflared tunnel route dns my-server app1.yourdomain.us.kg
cloudflared tunnel route dns my-server app2.yourdomain.us.kg
cloudflared tunnel route dns my-server bot.yourdomain.us.kg

# Install as a background service
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

_Reference: [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)_

---

## Phase 5: Zero Trust Security (Google Auth)

Protect your applications so only authorized users can access them.

1. Navigate to the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/).
2. Go to **Access** > **Applications** > **Add an Application** (Self-hosted).
3. **Application Configuration:**

- Application Name: `Internal Apps`
- Subdomain: `*` (Asterisk covers all subdomains)
- Domain: `yourdomain.us.kg`

4. **Policy Configuration:**

- Policy Name: `Allow Friends`
- Action: **Allow**
- Include: `Emails` → Add the specific Gmail addresses of your authorized users.

**Optional: Device Posture Checks**

Zero Trust Access can verify device state before granting access — not just identity. Under **Settings → WARP Client**, you can enforce requirements such as OS version minimums, disk encryption being enabled, or the presence of endpoint security software. This is particularly valuable if multiple people access your apps from personal devices.

---

## Phase 6: Secure SSH from Anywhere (via Tunnel)

The most secure way to SSH into this machine from any location is to route SSH traffic through the existing Cloudflare Tunnel rather than exposing port 22 to the public internet. This means no inbound ports whatsoever need to be open.

**1. Add SSH to the Tunnel Ingress**

Add an SSH entry to `~/.cloudflared/config.yml`:

```yaml
ingress:
  # ... existing entries ...
  - hostname: ssh.yourdomain.us.kg
    service: ssh://localhost:22
  - service: http_status:404
```

Route DNS for the new subdomain:

```bash
cloudflared tunnel route dns my-server ssh.yourdomain.us.kg
sudo systemctl restart cloudflared
```

**2. Remove the UFW SSH Exception**

Since SSH no longer arrives as an inbound connection, you can remove the direct port allowance and close the last remaining inbound rule:

```bash
sudo ufw delete allow ssh
sudo ufw reload
```

Your machine now has **zero open inbound ports**.

**3. Connect via Tunnel**

On any client machine, install `cloudflared` and connect:

```bash
# Install cloudflared on the client (macOS example)
brew install cloudflared

# Connect
cloudflared access ssh --hostname ssh.yourdomain.us.kg
```

Or add a `~/.ssh/config` entry for seamless `ssh` command use:

```text
Host ssh.yourdomain.us.kg
    ProxyCommand cloudflared access ssh --hostname %h
    User your_username
    IdentityFile ~/.ssh/id_ed25519
```

Then simply: `ssh ssh.yourdomain.us.kg`

**4. Harden `sshd_config` Further**

Beyond the basics in Phase 1, add these additional directives:

```text
AllowUsers your_username
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
Protocol 2
```

Restart the daemon after changes: `sudo systemctl restart ssh`

**5. Combine with Zero Trust MFA**

Because the SSH subdomain is protected by the same Cloudflare Access policy as all other subdomains, the Google 2FA challenge is enforced _before_ the SSH handshake begins. This means SSH access requires both a valid private key **and** Google authentication — a meaningful second factor with no extra configuration.

---

## Phase 7: Telegram Bot Integration (Webhook Bypass)

Because Telegram's servers cannot pass your Google Auth screen, you must create a bypass rule specifically for the bot's webhook endpoint.

**1. Create the Bypass Policy**

1. In the Zero Trust Dashboard, go to **Access** > **Applications** > **Add an Application** (Self-hosted).
2. **Application Configuration:**

- Application Name: `Telegram Webhook`
- Subdomain: `bot`
- Domain: `yourdomain.us.kg`
- Path: `webhook` (or whatever specific URL path your bot uses).

3. **Policy Configuration:**

- Policy Name: `Telegram IP Bypass`
- Action: **Bypass** (CRITICAL: Do _not_ select Allow)
- Include: `IP Ranges`. Enter the official Telegram subnets:
  - `149.154.160.0/20`
  - `91.108.4.0/22`

_Reference: [Official Telegram Webhook IP List](https://core.telegram.org/bots/webhooks#psa-supported-ip-addresses-and-ports)_

**2. Register the Webhook with Telegram**

Execute this command from any terminal to tell Telegram where to send payloads:

```bash
curl -F "url=https://bot.yourdomain.us.kg/webhook" https://api.telegram.org/bot<YOUR_BOT_TOKEN>/setWebhook
```

_(Replace `<YOUR_BOT_TOKEN>` with the token provided by BotFather)._

---

## Infrastructure as Code (Managing Cloudflare Programmatically)

The setup described above uses the Cloudflare dashboard manually. Everything can be managed as code for reproducibility, version control, and automated deployments.

### Terraform (Recommended)

Cloudflare maintains an official Terraform provider, covering tunnels, DNS records, Access applications and policies, firewall rules, and Pages deployments.

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

# Tunnel
resource "cloudflare_tunnel" "my_server" {
  account_id = var.account_id
  name       = "my-server"
  secret     = base64encode(random_bytes.tunnel_secret.hex)
}

# DNS record pointing subdomain at tunnel
resource "cloudflare_record" "app1" {
  zone_id = var.zone_id
  name    = "app1"
  value   = "${cloudflare_tunnel.my_server.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# Zero Trust Access Application
resource "cloudflare_access_application" "internal_apps" {
  zone_id          = var.zone_id
  name             = "Internal Apps"
  domain           = "*.yourdomain.us.kg"
  session_duration = "24h"
}

# Access Policy
resource "cloudflare_access_policy" "allow_friends" {
  application_id = cloudflare_access_application.internal_apps.id
  zone_id        = var.zone_id
  name           = "Allow Friends"
  precedence     = 1
  decision       = "allow"

  include {
    email = ["friend@gmail.com", "you@gmail.com"]
  }
}
```

Store your API token securely — never commit it to version control. Use environment variables or a secrets manager:

```bash
export TF_VAR_cloudflare_api_token="your_token_here"
terraform init && terraform apply
```

### `cloudflared` CLI Scripting

The `cloudflared` binary used throughout this guide is itself fully scriptable. Tunnel creation, DNS routing, and ingress configuration are all CLI-driven and can be wrapped in shell scripts or Ansible playbooks:

```bash
#!/bin/bash
# Idempotent tunnel setup script
TUNNEL_NAME="my-server"
DOMAIN="yourdomain.us.kg"
SUBDOMAINS=("app1" "app2" "bot" "ssh")

cloudflared tunnel create $TUNNEL_NAME 2>/dev/null || echo "Tunnel already exists"

for sub in "${SUBDOMAINS[@]}"; do
  cloudflared tunnel route dns $TUNNEL_NAME "${sub}.${DOMAIN}"
done

sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

### Wrangler CLI (Pages Deployments)

For Cloudflare Pages, the `wrangler` CLI handles deployments from CI/CD pipelines:

```bash
npm install -g wrangler
wrangler pages deploy ./dist --project-name=my-landing-page
```

This integrates naturally with GitHub Actions for automated deploys on push.

### Cloudflare REST API

Every dashboard action has a REST API equivalent. Useful for lightweight scripting without Terraform:

```bash
# Example: list all tunnels
curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq '.result[].name'
```

---

## Documentation: MkDocs & Zensical

A natural use of Cloudflare Pages in this stack is hosting project documentation. The recommended approach for Python projects is **MkDocs with the Material theme**, with an eye toward migrating to **Zensical** as it matures.

### MkDocs + Material (Recommended Today)

MkDocs with Material for MkDocs is the battle-tested standard for Python project documentation. Key features relevant to this stack:

- **Python API docs via mkdocstrings** — automatically generates API reference pages from docstrings. Supports Google, NumPy, and reStructuredText docstring styles.
- **Deploys to Cloudflare Pages** — the `mkdocs build` output is a standard static site that deploys without any build configuration changes in the Pages dashboard. Set the build command to `pip install mkdocs-material mkdocstrings[python] && mkdocs build` and the output directory to `site`.
- **`mkdocs.yml` is portable** — when Zensical reaches feature parity, migration requires no changes to your config file or Markdown content.

Minimal setup for a Python project:

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

```markdown
<!-- docs/api.md -->

# API Reference

::: mypackage.mymodule
```

### Zensical (Watch & Migrate When Ready)

Zensical is a next-generation static site generator built by the Material for MkDocs team, designed to replace both MkDocs and Material for MkDocs in a single coherent stack. It is the correct long-term direction, but is currently in **alpha**.

**Why it matters:** MkDocs itself has been unmaintained since August 2024, making it a supply chain risk. Zensical was built from scratch (in Rust) to overcome fundamental architectural limitations that couldn't be resolved within MkDocs.

**Current state (as of early 2026):**

- Reads your existing `mkdocs.yml` natively — no config migration required.
- Markdown content, template overrides, custom CSS and JS all work without changes.
- Repeated (incremental) builds are already 4–5× faster than MkDocs.
- The module system (required for third-party extensibility, including API docs) is in development and initially gated to Zensical Spark members.
- Full Python API documentation support (via the mkdocstrings author joining the team) is on the roadmap but not yet shipped.

**The migration path when ready:**

```bash
# Install Zensical (when available)
pip install zensical

# Build your existing project — no changes to mkdocs.yml needed
zensical build

# Serve locally
zensical serve
```

**When to migrate:** Watch for the module system public release and mkdocstrings parity in Zensical. At that point, switching is low-risk: same config format, same Markdown, same Cloudflare Pages deploy pipeline — just swap the build command from `mkdocs build` to `zensical build`.

**Zensical Spark** is the professional tier for organisations that want to influence the roadmap, receive priority support, and access the module API before it is publicly released. If documentation is business-critical, it is worth evaluating.

_References: [Zensical](https://zensical.org/) · [Zensical Compatibility](https://zensical.org/compatibility/) · [Zensical Roadmap](https://zensical.org/about/roadmap/) · [mkdocstrings](https://mkdocstrings.github.io/)_
