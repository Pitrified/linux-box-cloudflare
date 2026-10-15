# The Trusted Machine

The box is low-secret by design (see [01_box_setup.md](01_box_setup.md)).
The credentials it does not hold live on a second machine, the trusted one: currently `g4`.

| Held here | Not on the box because |
| --- | --- |
| The GitHub SSH key | An unattended box with push rights is one compromise away from rewriting every repo |
| Browser logins (GitHub, Cloudflare dashboard, Google) | Same reason, for every account behind them |
| Cloudflare management: `cloudflared` CLI, `cert.pem` when needed | `cert.pem` is account-scoped; the box needs only the revocable tunnel JSON |
| The Gramps admin credentials | See `docs/admin-machine.md` in `genealogy-gramps-fn` |

It runs no public service and no tunnel.

---

## GitHub SSH key

A dedicated key, used only for GitHub:

```bash
ssh-keygen -t ed25519 -C "<user>@<host> github" -f ~/.ssh/id_ed25519_github

cat >> ~/.ssh/config <<'EOF'
Host github.com
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config

# pin GitHub's host keys from its API instead of trusting the first connection
curl -fsS https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com " + .' >> ~/.ssh/known_hosts
```

Add `~/.ssh/id_ed25519_github.pub` in GitHub, Settings, SSH and GPG keys.

**Load it with a lifetime, per working session:**

```bash
ssh-add -t 1h ~/.ssh/id_ed25519_github
ssh -T git@github.com     # "Hi <user>! You've successfully authenticated"
```

When the hour is up, a push fails with `Please make sure you have the correct access rights and the repository exists`.
That message means the key has expired from the agent, not that the remote has changed: run `ssh-add` again.

`ssh-add -c` (confirm each use) is not used: it needs `ssh-askpass`, which is not installed, and the GNOME agent has no display to ask on in a remote session.

## Reaching GitHub from the box

The box has no GitHub credentials. To push or pull private repos there, connect with agent forwarding while the key is loaded here:

```bash
ssh -A <box>
```

Inside that session git on the box uses this machine's agent.
While the session is open, root on the box could use the agent too: that is the reason for the one-hour lifetime, and for using `-A` only when a push or pull is needed.
Unattended work on the box (remote-control sessions, timers) cannot reach GitHub, which is intended.

## Remote access to this machine

Through openssh-server on the tailnet only, with password login.
Tailscale SSH is off here: it answers port 22 on the tailnet address itself, and it would let any tailnet device with the right ACL in without a password.

```bash
sudo apt install -y openssh-server

sudo tee /etc/ssh/sshd_config.d/10-hardening.conf >/dev/null <<'EOF'
PermitRootLogin no
AllowUsers <user>
MaxAuthTries 3
X11Forwarding no
EOF
sudo sshd -t && sudo systemctl restart ssh

# port 22 from the tailnet only
sudo ufw allow in on tailscale0 to any port 22 proto tcp

# check sshd answers before taking Tailscale SSH away
ssh -o StrictHostKeyChecking=accept-new <user>@localhost 'echo openssh-works'
```

Then turn Tailscale SSH off.
Run this at the machine, or from a session that does not itself ride on Tailscale SSH (VS Code Remote-SSH does): it may drop those sessions.

```bash
sudo tailscale set --ssh=false
sudo tailscale debug prefs | grep RunSSH     # "RunSSH": false
```

Check from another tailnet device with `ssh <user>@<this-host>`. Revert with `sudo tailscale set --ssh`.

`PasswordAuthentication` stays on, unlike the box sshd settings in [01_box_setup.md](01_box_setup.md): port 22 is reachable from the tailnet only, and this machine is reached rarely, from devices that may not hold a key.
Fail2ban ([01_box_setup.md](01_box_setup.md) step 6) is not installed on `g4`.

## Moving the trusted role

The role follows the key and the logins, not the hardware.
To move it: create a new GitHub key on the new machine and delete the old one in GitHub, log in to the browsers again, and set up the Gramps admin machine there from its own doc.
The box's lid and linger settings ([always-on-server.md](always-on-server.md), [01_box_setup.md](01_box_setup.md)) do not belong on this machine; revert them if it was a box before.
