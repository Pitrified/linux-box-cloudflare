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
- Wait 5-15 minutes for DNS propagation.

---

## Phase 3: The Hybrid Architecture (Cloudflare Pages)

To save local bandwidth and ensure high availability, host your static landing page (the portal to your apps) on Cloudflare Pages.

**1. Prepare the Repository**

- Create a simple `index.html` file containing links to your future subdomains (e.g., `https://app1.yourdomain.us.kg`).
- Push this to a public or private GitHub repository.

**2. Deploy to Cloudflare Pages**

- In the Cloudflare Dashboard, navigate to **Workers & Pages** > **Create application** > **Pages** > **Connect to Git**.
- Select your repository and deploy.
- Go to the **Custom Domains** tab for your new Page and add your root domain: `yourdomain.us.kg`.

_Reference: [Cloudflare Pages Documentation_](https://developers.cloudflare.com/pages/)

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

**3. Configure Ingress Rules**
Create the configuration directory and file:

```bash
mkdir -p ~/.cloudflared
nano ~/.cloudflared/config.yml
```

Populate the file using your Tunnel UUID and local application ports:

```yaml
tunnel: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
credentials-file: /home/YOUR_LINUX_USER/.cloudflared/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json

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

**4. Route DNS & Start Service**

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

_Reference: [Cloudflare Tunnel Documentation_](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)

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
- Include: `Emails` -> Add the specific Gmail addresses of your authorized users.

---

## Phase 6: Telegram Bot Integration (Webhook Bypass)

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

_Reference: [Official Telegram Webhook IP List_](https://www.google.com/search?q=https://core.telegram.org/bots/webhooks%23psa-supported-ip-addresses-and-ports)

**2. Register the Webhook with Telegram**
Execute this command from any terminal to tell Telegram where to send payloads:

```bash
curl -F "url=https://bot.yourdomain.us.kg/webhook" https://api.telegram.org/bot<YOUR_BOT_TOKEN>/setWebhook
```

_(Replace `<YOUR_BOT_TOKEN>` with the token provided by BotFather)._
