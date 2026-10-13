# Mesh Security

**One switch that shields a jailbroken iPod: no more `alpine`, no open ports, only the apps you allow go online.**

Jailbroken iPods ship with the root password `alpine` and an open SSH port. Worms like ikee spread exactly that way, from device to device on the same Wi-Fi. Mesh Security closes that hole and shows you what your apps are talking to.

## What the switch does

- **Password:** accounts still on `alpine` (root and mobile) get a random 8-character password, shown once in the app.
- **Incoming:** every port is closed by the built-in firewall (`pf`). Exceptions you choose (SSH, FileTransfer, a custom port) stay open, but only from your own Wi-Fi.
- **Outgoing:** only apps you allow get through. Mesh with its Tor is allowed by default.
- **Off:** everything goes back exactly as it was, password included.

## Also in the app

- **Connections:** every app, incoming and outgoing, logged on the device. Any destination can be blocked with one tap.
- **Kill switch:** cuts everything at once. Reconnecting restores the previous state.
- **Reset all:** removes every change. Uninstalling the package does the same.
- English and German.

## How it works

- A small setuid helper (`msguard`) is the only part with root rights. It only accepts the real app as its caller (checked by path, user, no debugger, no `DYLD_` variables) and builds firewall rules from a fixed template. Nothing the app passes ends up in a rule unchecked.
- Before every change the original state is saved, so "off" and "reset" restore it.
- The firewall can't tell apps apart (they all run as `mobile`). So the helper watches each app's sockets. When an allowed app opens a connection, that destination is unlocked. TCP retries after about a second, then it goes through.

## Limits

- If an attacker already has root, no app on the same device can stop them. Mesh Security makes it much less likely to get that far. It's not a cleanup tool.
- A blocked app can reach a destination that an allowed app just unlocked.
- Very short connections between two checks (every 2 s) may be missing from the log.

## Install

Via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** on the iPod, or download the `.deb` from the [latest release](https://github.com/SecondTrack/security/releases/latest) and install it with `dpkg -i`, then run `uicache`.

## Build

With [Theos](https://theos.dev): `make package`. Tests run on a Mac with `sh tests/run.sh`. Design and security notes are in `docs/` (German).

## License

GPL-3.0, see [LICENSE](LICENSE).
Not affiliated with Apple. iPod is a trademark of Apple Inc.
