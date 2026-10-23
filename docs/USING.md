# Using Portlight

## Add your first server

The safest setup is a key made on the phone:

1. Open **Keys**, tap **+**, then **New Ed25519 key**. Or choose **New
   Secure Enclave key** for a key that can never leave the phone.
2. Open **Hosts**, tap **+**, and enter the hostname or IP and the
   username. Pick the provider to get its usual usernames, and set **Log
   in with** to your key.
3. Tap **Copy public key for this server** and add it to the server, as
   below.
4. Tap the host to connect. The first time, Portlight shows the server's
   fingerprint. Compare it, then tap **Trust and connect**.

### Putting the key on a server

Any Linux server you can already reach, for example from a laptop:

```sh
echo 'ssh-ed25519 AAAA… iPhone' >> ~/.ssh/authorized_keys
```

**AWS EC2.** Add the line to `~/.ssh/authorized_keys` for `ec2-user`
(Amazon Linux), `ubuntu` (Ubuntu) or `admin` (Debian). For new instances,
import the public key under **EC2 → Key pairs → Import key pair** and pick
it at launch.

**Google Cloud.** In **Compute Engine → Metadata → SSH keys**, add the line
Portlight copies. For GCP it ends with your username, which is how Google
knows which account to create. Or add it under the instance's own SSH keys.

**Azure.** Use the VM's **Reset password** blade with "Reset SSH public
key", or append the key to `~/.ssh/authorized_keys` for `azureuser`.

### Checking the fingerprint

On the server:

```sh
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

EC2 (**Actions → Monitor → Get system log**) and GCP (**serial port
output**) also print host key fingerprints at first boot.

## Bastions (jump hosts)

Add the bastion as a host first. Then, in the private server's settings,
set **Jump host** to it. Portlight connects to the bastion, then to the
server through it, and asks about each one's host key the first time.

## The terminal

- **Key bar.** Swipe sideways for more keys.
  - **ctrl** and **alt** apply to the next key you press. Tap twice to lock
    them, and once more to release.
  - Arrows and delete repeat while held.
  - **{ }** opens your snippets.
- **Pinch** to change the font size.
- **Long-press** to select. Copy keeps the text on this phone for two
  minutes.
- **Rotate** for a wider terminal. The server is told the new size.
- **Tabs.** The strip at the top lists open sessions. **⌄** goes back to your
  hosts while sessions stay open.
- When a session ends or drops, tap **Reconnect**.

Run `tmux new -A -s main` on the server, or set it as the host's **Run on
connect** command, so your work survives dropped connections.

## Importing what you already have

- **Settings → Import ~/.ssh/config** reads `Host` entries with their
  HostName, User, Port and ProxyJump.
- **Settings → Trusted host keys → Import** reads `known_hosts`, including
  hashed entries.
- **Keys → + → Import a private key** reads OpenSSH and PEM files, with
  passphrases. RSA keys aren't supported yet.

## Settings worth knowing

- **Lock.** Portlight always locks. You can allow up to five minutes away
  before it asks again.
- **Keepalive.** Helps idle connections survive on mobile networks.
- **Snippets.** Commands you run often, one tap from the key bar.
