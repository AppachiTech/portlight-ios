# Demo server

A throwaway SSH server for screen recordings and screenshots. It runs in
Docker on your Mac, so a phone on the same Wi-Fi can connect to it. It's a
made-up host called `atlas` with user `dev`, a tidy prompt, a small sample
project (`~/shop-api`, with some git history and one uncommitted change),
and `htop`, `tmux`, `git` and `vim`. Recordings never show a real server's
name, address or history.

## Use it

```sh
demo/server/demo-server.sh up            # build and start; prints host, port, fingerprints
```

1. In Portlight: **Keys → + → New Ed25519 key**, open it and tap **Copy**
   (Universal Clipboard carries it to the Mac).
2. Allow it:
   ```sh
   demo/server/demo-server.sh key 'ssh-ed25519 AAAA… iPhone'
   ```
3. In Portlight: **Hosts → +**, host = the IP it printed, port `2222`, user
   `dev`, log in with that key. Connect, check the fingerprint matches, and
   trust it.

It listens on port 2222. If that's taken, start it on another one with
`PORT=2223 demo/server/demo-server.sh up`.

Stop it when you're done:

```sh
demo/server/demo-server.sh down
```

The allowed keys are kept in a Docker volume (`portlight-demo-keys`), so
they survive `down` and `up`. Rebuilding the image makes new host keys:
forget the old one in **Settings → Trusted host keys** first.

## Claude Code

To show speak-to-type with an agent, build with Claude Code installed:

```sh
demo/server/demo-server.sh up --with-claude
```

Then run `claude` on the server and log in **before** you start
recording, since the login screen shows your account.

## Suvadu

To show [Suvadu](https://suvadu.sh) recording what's run on the server,
build with it installed (on its own, or together with Claude Code):

```sh
demo/server/demo-server.sh up --with-suvadu
demo/server/demo-server.sh up --with-claude --with-suvadu
```

Every command typed in the terminal is recorded, and with Claude Code
installed too, so is every command Claude runs (`suv init claude-code` is
done for you). Try `suv search`, `suv agent` and `suv agent prompts` on
the server. Its history starts empty, so run a few commands before you
record.

## Safety

Only key login is allowed, for the one `dev` user, and port forwarding is
off. It still listens on your network while it runs, so stop it when
you've finished recording.

The plain server installs only Ubuntu packages. `--with-claude` and
`--with-suvadu` also download those tools from their official sources (npm,
and `downloads.appachi.tech`, whose installer checks the download's SHA-256)
while the image builds. Read the [Dockerfile](Dockerfile) first if you want
to know exactly what runs.

Claude Code's login lives inside the container, so `up` and `down` discard
it; log in again after either.
