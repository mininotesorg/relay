# Your own relay for Mininotes

Mininotes sends your notes straight from one device to another whenever it can. When it can't, for example a phone away from
home, a **relay** carries them. A relay only passes on what is sealed end to end, and holds it for a device that is away: it
cannot read your notes.

Mininotes comes with public relays. With your own, your notes go through a machine you control.

> **The same server can keep your backups too.** [mininotesorg/server](https://github.com/mininotesorg/server) installs the
> relay and a backup server with one command, or either alone. Its relay is this one: a relay installed from here is updated
> there, and keeps its identity.

## What you need

- A Linux server with a public IPv4 address. A small cloud server is enough (about 5 dollars a month): Ubuntu or Debian,
  512 MB of free memory, 1 GB of free disk.
- A terminal on it, as root (SSH).

## 1. Install the relay

On the server, run:

```bash
curl -fsSL https://raw.githubusercontent.com/mininotesorg/relay/main/install.sh | sudo bash
```

At the end it shows your relay's address, like `203.0.113.7:9501`.

If your provider has a firewall of its own (Vultr, Hetzner, AWS and most others), open **TCP port 9501** there too.

## 2. Add it in Mininotes

**Settings → Relays → Add a relay**, then type the address it showed. Mininotes keeps it only if the relay answers.

- **The same on all my devices**, on by default, gives it to your other devices too.
- To use only your own relay, turn off **Use the public relays**.

## Update or remove

- Update: run the same command again.
- Remove: `curl -fsSL https://raw.githubusercontent.com/mininotesorg/relay/main/install.sh | sudo bash -s -- --uninstall`

## What runs on your server

| | |
|---|---|
| Program | [maxima-server](https://github.com/eurobuddha/maxima) 0.4.36, checked by its SHA-256 before it runs |
| Port | 9501 TCP (`--port` to change it) |
| Memory | 128 MB, never more than 384 MB, and the first program stopped if the server runs out of memory |
| Data | `/var/lib/maxima`: the relay's identity, and up to 256 MB of sealed files waiting for a device that is away (`--files` to change it) |
| Runs as | its own user, `maxima`, in a locked-down service, `maxima-relay` |

It touches nothing else on the server. To see it: `systemctl status maxima-relay`.

## Credits

The relay is **maxima-server** by [eurobuddha](https://github.com/eurobuddha/maxima), under the MIT License. This repository
holds the install script and this guide, under the GPL-3.0-or-later, as [Mininotes](https://github.com/mininotesorg/mininotes) is.
