# IpBump

A Windows tray app and Mac menu bar app that moves your computer to a different local IPv4 address with a double-click (an Option-click on a Mac).

IpBump looks for an address on your network that no other device is using, switches the network adapter to it, and puts the old address back if the new one does not work. AI agents such as Claude Code and Gemini CLI can ask for the same thing through a built-in MCP server.

It changes the address on your local network (LAN) only. The public IP that websites see stays the same.

This page describes the Windows app. The Mac app does the same from the menu bar: see [IpBump for Mac](mac/README.md).

## What it does

- **New address in one double-click.** Double-click the tray icon and about five seconds later the PC has a free address on the same network.
- **The address is always in view.** The tray icon shows the last number of the address. On Windows 11 the full address is also written on the taskbar, beside the clock.
- **No administrator prompt.** A small Windows service applies the changes, so the tray app runs as an ordinary user.
- **Safe to try.** If another device claims the new address, IpBump tries the next one. If nothing works, the previous settings are put back.
- **Back to automatic.** One menu item hands the adapter back to the network's DHCP server.
- **Works with AI agents.** Connect Claude Code, Gemini CLI or Claude Desktop from the settings window. Claude Code can also get a new address by itself when its connection is refused.

## Requirements

- Windows 10 version 1809 or later, 64-bit. The address on the taskbar needs Windows 11.
- Nothing else. The installer carries its own copy of .NET.

IpBump for Mac needs macOS 14 Sonoma or later, on Apple silicon or Intel.

## Install

### Windows

Download `IpBump-Setup-<version>.exe` from the [latest release](https://github.com/discoveruz/IpBump/releases/latest) and run it. You can also [build the installer](#build) yourself.

The installer is not signed, so Windows may show "Windows protected your PC". Choose **More info**, then **Run anyway**.

The installer asks for administrator rights once, to register the service. It offers two options:

- start IpBump for every user at sign-in (on by default)
- a desktop shortcut (off by default)

On the first start the settings window opens by itself. The adapter your PC is online with is already picked and its current values are filled in. Check them and press **Save**.

IpBump gives the adapter a manual address. If your router hands out addresses by DHCP, limit the search to a range the router does not use, when you can. An address that is free now could otherwise be given to another device later.

### Mac

In Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/discoveruz/IpBump/main/mac/install.sh | sh
```

It downloads `IpBump-<version>.pkg` from the latest release, checks its checksum and installs it. You can also download the `.pkg` yourself and open it. It is not signed: when macOS refuses to open it, choose **Open Anyway** in **System Settings › Privacy & Security** and open it again.

Either way, macOS asks for your password once, to install the helper that applies the changes. On the first start the settings window opens by itself, as on Windows. After that, Option-click the address in the menu bar for a new one. The rest is in [IpBump for Mac](mac/README.md).

## Use

| Action | Result |
| --- | --- |
| Double-click the tray icon or the address on the taskbar | Move to a free address |
| Right-click either one | Open the menu |
| Start IpBump again | Open Settings |

The menu:

- The first line shows the current address and adapter, or why the last change failed.
- **Change IP now** does the same as a double-click.
- **Switch back to automatic (DHCP)** lets the network assign the address again.
- **Settings…** opens the settings window.
- **Exit** closes the tray app. The service keeps running.

The tray icon also tells you how things are going:

| Icon | Meaning |
| --- | --- |
| Orange tile with a number | The last number of the current address |
| Orange tile with `…` | A change is running |
| Red tile with `!` | The last change failed; the menu says why |
| Grey tile with `–` | The adapter has no address |

### Settings

| Setting | What it is for |
| --- | --- |
| Network adapter | The adapter IpBump manages |
| IP address, subnet mask, gateway, DNS | What **Save** applies to the adapter, like Windows' own "Edit IP settings" |
| Free address search: From, To | Where to look for a free address. Empty means the whole network. |
| Let AI agents change the IP | Off by default. See [AI agents](#ai-agents). |
| Show the IP address on the taskbar | The label beside the clock (Windows 11) |
| Show a notification after each change | A Windows notification with the old and new address |

Settings are stored per Windows user in `%APPDATA%\IpBump\settings.json`.

## AI agents

`IpBump.exe mcp` is an [MCP](https://modelcontextprotocol.io) server on stdin and stdout. It offers two tools:

| Tool | What it does |
| --- | --- |
| `get_ip_status` | Returns the adapter's address, subnet mask, gateway, DNS servers, whether the address is manual or from DHCP, and whether agents may change it. Read-only. |
| `change_ip` | Moves the PC to a free address and returns the old and the new one. Takes about five seconds; open network connections are reset. |

To set an agent up:

1. Open Settings, turn on **Let AI agents (Claude, Gemini) change the IP** and press **Save**.
2. Open Settings again and press **Connect** next to the agent. The agent must have been started at least once by your Windows account.
3. Restart the agent.

**Connect** writes into the agent's own configuration:

| Agent | File | What is added |
| --- | --- | --- |
| Claude Code | `~/.claude.json` | the `ipbump` MCP server |
| Claude Code | `~/.claude/settings.json` | a `StopFailure` hook |
| Gemini CLI | `~/.gemini/settings.json` | the `ipbump` MCP server |
| Claude Desktop | `%APPDATA%\Claude\claude_desktop_config.json` | the `ipbump` MCP server |

**Disconnect** takes the same entries out again.

### Claude Code: a new address when the connection is refused

Claude Code runs its `StopFailure` hook whenever a request ends with an API error. IpBump's hook, `IpBump.exe claude-hook`, changes the address only when that error is a refused connection (`ECONNREFUSED`). Rate limits, sign-in problems and errors reported by the API itself are left alone. The hook also does nothing while **Let AI agents change the IP** is off.

### Other MCP clients

Add the server by hand, with the path IpBump is installed in:

```json
{
  "mcpServers": {
    "ipbump": {
      "command": "C:\\Program Files\\IpBump\\IpBump.exe",
      "args": ["mcp"]
    }
  }
}
```

## How it works

One exe has several roles:

| Command | Role |
| --- | --- |
| `IpBump.exe` | The tray app. Runs as the signed-in user. |
| `IpBump.exe mcp` | The MCP server. Started by the AI agent. |
| `IpBump.exe claude-hook` | Started by Claude Code when a request fails. |
| `IpBump.exe --service` | The Windows service `IpBumpSvc`. Runs as SYSTEM. |
| `IpBump.exe --install-service`, `--uninstall-service` | Used by the installer and the uninstaller. |

A change goes through three steps:

1. **Find a free address.** IpBump sends ARP requests, eight addresses at a time, starting after the current address and wrapping around at the end of the search range. An address nobody answers for within 1.5 seconds counts as free. ARP is used rather than ping because firewalls drop pings, but a device cannot hold an address without answering ARP. The gateway and the DNS servers are skipped.
2. **Apply it.** The tray app, the MCP server and the hook have no right to change network settings. They send the request over a local named pipe to the service, which checks it (the adapter must exist, every address must be valid IPv4) and applies it with `netsh`.
3. **Check it.** Windows asks the network whether anyone else has the new address before it starts using it. IpBump waits for that verdict. If another device claimed the address, the next free one is tried, up to three times. If the change still fails, the previous settings are put back.

Only one change runs at a time, whoever asked for it.

### Source layout

| File | Contents |
| --- | --- |
| `IpBump/Program.cs` | Picks the role from the command line |
| `IpBump/TrayApp.cs`, `TrayBadge.cs` | The tray icon and its menu |
| `IpBump/TaskbarLabel.cs` | The address on the Windows 11 taskbar |
| `IpBump/SettingsWindow.xaml` | The settings window |
| `IpBump/IpChanger.cs`, `IpScanner.cs` | The change itself and the search for a free address |
| `IpBump/IpService.cs`, `IpClient.cs`, `NetApply.cs` | The service, the pipe to it, and the `netsh` calls |
| `IpBump/AgentServer.cs`, `Agent.cs` | The MCP server, the Claude Code hook, and the Connect buttons |
| `installer/IpBump.iss` | The Inno Setup script |
| `tools/make-icon.ps1` | Draws `IpBump/Assets/IpBump.ico` |
| `mac/` | IpBump for Mac, laid out in [its own README](mac/README.md#source-layout) |

## Build

This builds the Windows version. IpBump for Mac is built on a Mac: see [IpBump for Mac](mac/README.md#build).

You need:

- Windows
- the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (`winget install JRSoftware.InnoSetup`)

Then run:

```bat
build-installer.bat
```

It publishes the app with its own copy of .NET and wraps it into `installer\output\IpBump-Setup-<version>.exe`. The version number is set in one place, `IpBump\IpBump.csproj`.

To build only the app:

```bat
dotnet publish IpBump\IpBump.csproj -c Release
```

The result is in `IpBump\bin\Release\net8.0-windows\win-x64\publish\`.

To run IpBump from source without installing the service, start it as administrator, for example from Visual Studio started as administrator. With no service to talk to, an elevated IpBump applies the changes itself.

## Uninstall

Remove IpBump under **Settings > Apps > Installed apps**. The uninstaller removes the service and the program files. It leaves three things as they are:

- **Your network settings.** Choose **Switch back to automatic (DHCP)** first if you want that back.
- **Your agents' configuration.** Press **Disconnect** for each connected agent first.
- **Your IpBump settings** in `%APPDATA%\IpBump`.

On a Mac, choose **Uninstall IpBump…** at the bottom of Settings. [IpBump for Mac](mac/README.md#uninstall) says what it removes.

## License

[MIT](LICENSE)

IpBump is built with .NET, WPF-UI, H.NotifyIcon and the Model Context Protocol C# SDK. Their licences are in [installer/THIRD-PARTY-NOTICES.txt](installer/THIRD-PARTY-NOTICES.txt), which the installer also places next to the app. IpBump for Mac is built with the Model Context Protocol Swift SDK; see [IpBump for Mac](mac/README.md#license).
