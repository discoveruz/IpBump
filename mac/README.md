# IpBump for Mac

A menu bar app that moves your Mac to a different local IPv4 address with a click.

IpBump looks for an address on your network that no other device is using, switches the network service to it, and puts the old address back if the new one does not work. AI agents such as Claude Code and Gemini CLI can ask for the same thing through a built-in MCP server.

It changes the address on your local network (LAN) only. The public IP that websites see stays the same.

This is the Mac version of the Windows app in the [main README](../README.md).

## What it does

- **New address in one Option-click.** Option-click the address in the menu bar and about five seconds later the Mac has a free address on the same network. A plain click opens the menu.
- **The address is always in view.** The menu bar shows the whole address, or only its last number if you prefer.
- **No password prompt.** A small helper applies the changes in the background, so the app runs as an ordinary user.
- **Safe to try.** If another device claims the new address, IpBump tries the next one. If nothing works, the previous settings are put back.
- **Back to automatic.** One menu item hands the network service back to the network's DHCP server.
- **Works with AI agents.** Connect Claude Code, Gemini CLI or Claude Desktop from Settings. Claude Code can also get a new address by itself when its connection is refused.

## Requirements

- macOS 14 Sonoma or later, on Apple silicon or Intel.
- Nothing else.

## Install

The simplest way is one line in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/discoveruz/IpBump/main/mac/install.sh | sh
```

It downloads the installer from the [latest release](https://github.com/discoveruz/IpBump/releases/latest), checks its checksum and runs it.

You can also download `IpBump-<version>.pkg` from the latest release and open it, or [build it](#build) yourself. The installer is not signed, so macOS first says it can't check it for malicious software. Open **System Settings › Privacy & Security**, scroll down to the message about IpBump, choose **Open Anyway**, then open the installer again.

Either way, macOS asks for your password once, to install the helper. IpBump then starts by itself, and again at every login for every user. To stop that, switch IpBump off in **System Settings › General › Login Items & Extensions**.

On the first start the Settings window opens by itself. The network service your Mac is online with is already picked and its current values are filled in. Check them and press **Save**.

IpBump gives the service a manual address. If your router hands out addresses by DHCP, limit the search to a range the router does not use, when you can. An address that is free now could otherwise be given to another device later.

## Use

| Action | Result |
| --- | --- |
| Click the address in the menu bar | Open the menu |
| Option-click it | Move to a free address |
| Open IpBump again (from Applications or Spotlight) | Open Settings |

The menu:

- The first line shows the current address and network service, or why the last change failed.
- **Change IP now** moves to a free address.
- **Switch back to automatic (DHCP)** lets the network assign the address again.
- **Settings…** opens the settings window.
- **Quit IpBump** closes the menu bar app. The helper keeps running.

The menu bar also tells you how things are going:

| Menu bar | Meaning |
| --- | --- |
| `192.168.1.189` | The current address, or only `189` when the full address is switched off |
| `192.168.1.…` | A change is running |
| ⚠ and the address | The last change failed; the menu says why |
| `No IP` | The service has no address |

If you can't see the address: a full menu bar hides items behind a MacBook's camera notch. Make room, or switch off **Show the full address in the menu bar**.

### Settings

| Setting | What it is for |
| --- | --- |
| Network service | The service IpBump manages, such as Wi-Fi or Ethernet |
| IP address, subnet mask, router, DNS | What **Save** applies to the service, like the TCP/IP and DNS settings in System Settings |
| Free address search: From, To | Where to look for a free address. Empty means the whole network. |
| Let AI agents change the IP | Off by default. See [AI agents](#ai-agents). |
| Show the full address in the menu bar | Off shows only its last number |
| Show a notification after each change | A notification with the old and new address |

Settings are stored per Mac user in `~/Library/Application Support/IpBump/settings.json`.

## AI agents

`IpBump mcp` is an [MCP](https://modelcontextprotocol.io) server on stdin and stdout. It offers two tools:

| Tool | What it does |
| --- | --- |
| `get_ip_status` | Returns the service's address, subnet mask, router, DNS servers, whether the address is manual or from DHCP, and whether agents may change it. Read-only. |
| `change_ip` | Moves the Mac to a free address and returns the old and the new one. Takes about five seconds; open network connections are reset. |

To set an agent up:

1. Open Settings, turn on **Let AI agents (Claude, Gemini) change the IP** and press **Save**.
2. Open Settings again and press **Connect** next to the agent. The agent must have been started at least once by your Mac account.
3. Restart the agent.

**Connect** writes into the agent's own configuration and leaves the rest of each file as it was, down to the order of its keys and who may read it:

| Agent | File | What is added |
| --- | --- | --- |
| Claude Code | `~/.claude.json` | the `ipbump` MCP server |
| Claude Code | `~/.claude/settings.json` | a `StopFailure` hook |
| Gemini CLI | `~/.gemini/settings.json` | the `ipbump` MCP server |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | the `ipbump` MCP server |

**Disconnect** takes the same entries out again.

### Claude Code: a new address when the connection is refused

Claude Code runs its `StopFailure` hook whenever a request ends with an API error. IpBump's hook, `IpBump claude-hook`, changes the address only when that error is a refused connection (`ECONNREFUSED`). Rate limits, sign-in problems and errors reported by the API itself are left alone. The hook also does nothing while **Let AI agents change the IP** is off.

### Other MCP clients

Add the server by hand:

```json
{
  "mcpServers": {
    "ipbump": {
      "command": "/Applications/IpBump.app/Contents/MacOS/IpBump",
      "args": ["mcp"]
    }
  }
}
```

## How it works

| Program | Role |
| --- | --- |
| `IpBump.app` | The menu bar app. Runs as the signed-in user. |
| `IpBump mcp` | The MCP server. Started by the AI agent. |
| `IpBump claude-hook` | Started by Claude Code when a request fails. |
| `/Library/PrivilegedHelperTools/io.github.discoveruz.ipbump.helper` | The helper. A launchd daemon that runs as root. |

A change goes through three steps:

1. **Find a free address.** The helper sends ARP requests, eight addresses at a time, starting after the current address and wrapping around at the end of the search range. An address nobody answers for within 1.5 seconds counts as free. ARP is used rather than ping because firewalls drop pings, but a device cannot hold an address without answering ARP. The router and the DNS servers are skipped. The helper sends these requests, not the app: since macOS 15, apps need your permission to reach the local network, and launchd daemons do not.
2. **Apply it.** The app, the MCP server and the hook have no right to change network settings. They send the request over a local socket to the helper, which checks it (the service must exist, every address must be valid IPv4) and applies it with `networksetup`.
3. **Check it.** IpBump waits until macOS uses the new address, then asks once more whether another device answers for it. If one does, the next free address is tried, up to three times. If the change still fails, the previous settings are put back.

Only one change runs at a time, whoever asked for it. As on Windows, every user of the Mac may ask the helper for a change.

### Source layout

| Path | Contents |
| --- | --- |
| `mac/Sources/IpBumpCore` | The rules: the search, the change with its retries, the helper's checks, Connect and Disconnect, the hook, the MCP tools. No macOS API, so all of it runs under test |
| `mac/Sources/IpBumpMac` | Reading network settings, the helper's socket, the change lock |
| `mac/Sources/ipbump-helper`, `mac/Sources/CBPF` | The helper: ARP over BPF, and `networksetup` |
| `mac/Sources/IpBump` | The menu bar app, the Settings window, `mcp` and `claude-hook` |
| `mac/Tests` | Unit tests, tests that read this Mac's network settings, and tests that run the built `IpBump` |
| `mac/Packaging`, `mac/build-installer.sh` | The installer |
| `mac/make-icon.swift` | Draws `mac/Assets/IpBump.icns` |

## Build

You need macOS 14 or later and Xcode 26 or later.

Run the tests:

```sh
swift test --package-path mac
```

Build the installer:

```sh
mac/build-installer.sh
```

It builds IpBump for Apple silicon and Intel, wraps it into `mac/dist/IpBump-<version>.pkg` and writes the package's checksum beside it. The version number is set in one place for Windows and Mac, `IpBump/IpBump.csproj`. `mac/build-installer.sh --app-only` stops at `mac/dist/IpBump.app`.

The result is unsigned. With an Apple Developer ID, set these first and macOS shows no warnings:

| Variable | Value |
| --- | --- |
| `IPBUMP_SIGN_APP` | `Developer ID Application: <name> (<team>)` |
| `IPBUMP_SIGN_INSTALLER` | `Developer ID Installer: <name> (<team>)` |
| `IPBUMP_NOTARY_PROFILE` | a profile saved with `xcrun notarytool store-credentials` |

To run IpBump from source without installing it, start a helper of your own as root and point the app at it:

```sh
swift build --package-path mac
sudo mac/.build/debug/ipbump-helper --socket /tmp/ipbump-dev.sock         # in one Terminal window
IPBUMP_HELPER_SOCKET=/tmp/ipbump-dev.sock mac/.build/debug/IpBump       # in another
```

A build outside `IpBump.app` shows no notifications. `sudo mac/.build/debug/ipbump-helper --probe "Wi-Fi" 192.168.1.1 192.168.1.50` prints the addresses another device answers for.

To release, upload `IpBump-<version>.pkg` and `IpBump-<version>.pkg.sha256` to the same GitHub release as the Windows installer. `install.sh` takes the newest release's `.pkg`.

## Uninstall

Choose **Uninstall IpBump…** at the bottom of Settings, or run:

```sh
sudo /Applications/IpBump.app/Contents/Resources/uninstall.sh
```

It removes the app, the helper and the login item. It leaves three things as they are:

- **Your network settings.** Choose **Switch back to automatic (DHCP)** first if you want that back.
- **Your agents' configuration.** Press **Disconnect** for each connected agent first.
- **Your IpBump settings** in `~/Library/Application Support/IpBump`.

## License

[MIT](../LICENSE)

IpBump for Mac is built with the [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) and the packages it uses: SwiftNIO, Swift Log, Swift System, Swift Collections, Swift Atomics and EventSource. Their licences are in `IpBump.app/Contents/Resources/THIRD-PARTY-NOTICES.txt`.
