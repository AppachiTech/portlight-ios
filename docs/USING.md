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

- **Key bar.** Swipe sideways for more keys. The button at its left edge
  hides the keyboard, which brings the voice strip back.
  - **ctrl** and **alt** apply to the next key you press. Tap twice to lock
    them, and once more to release.
  - Arrows and delete repeat while held.
  - **{ }** opens your saved commands.
- **Text size.** The **A−** and **A+** buttons in the tab bar change it a
  point at a time, or pinch. **⋯ → Fit 80 columns** picks the size that shows
  80 characters across, handy for output that wraps in portrait.
- **Rotate.** The rotate button in the tab bar turns the terminal to
  landscape or back, even with the phone's rotation lock on. **⋯ →
  Orientation** can also make it follow the phone. The server is told the
  new size. Leaving the terminal always goes back to following the phone.
- **Keyboard.** The terminal shrinks to the space above the keyboard, so the
  last lines stay in view while you type.
- **Long-press** to select. Copy keeps the text on this phone for two
  minutes.
- **Tabs.** The strip at the top lists open sessions. **⌄** goes back to your
  hosts while sessions stay open.
- When a session ends or drops, tap **Reconnect**.

Run `tmux new -A -s main` on the server, or set it as the host's **Run on
connect** command, so your work survives dropped connections.

### Speak to type

A strip under the terminal takes speech, so the keyboard can stay down: one
row in landscape, two in portrait. Turn it off under **Settings → Voice
input** or **⋯ → Speak to type**.

1. Tap **Speak** and say what to type, then **Stop**. The words land in the
   draft, in lower case.
2. Tap into the draft to edit it (the strip moves up above the keyboard),
   tap **✕** to clear it, or tap **Speak** again to add more.
3. Tap **Insert** to type it into the terminal. It never presses Return, so
   you can check it first, then tap **⏎**.

It's made for talking to tools like Claude Code: say the instruction in
plain English, check it, send it. The strip also has **⌨︎** for the
keyboard, saved commands, Esc, Ctrl-C and Tab. While you type in the
terminal the strip steps aside; hide the keyboard to bring it back. Speech
is recognised on the iPhone itself; the first time, iOS asks for the
microphone and speech recognition.

### Saved commands

Commands you run often, like `git status` or `terraform plan`, one tap away
from **{ }** on the key bar or the voice strip. Add them there with **+**,
or in **Settings → Saved commands**. Each one can press Return for you;
leave that off for commands that change things, like `terraform apply`, so
you can read them first.

Saved commands are stored as plain text, so Portlight won't save one that
looks like it contains a password, key or token. Refer to secrets instead,
for example `$GITHUB_TOKEN`, `$(gh auth token)` or `--password-stdin < file`.

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
- **Saved commands.** Commands you run often, one tap from the key bar.
