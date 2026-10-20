import Foundation

// One program, several roles, as IpBump.exe has on Windows:
//   IpBump               the menu bar app (runs as the signed-in user)
//   IpBump mcp           the server for AI agents (started by Claude, Gemini, ...)
//   IpBump claude-hook   started by Claude Code when a request fails; a refused connection gets a new IP
//   IpBump --version     prints the version
switch CommandLine.arguments.dropFirst().first?.lowercased() {
case "mcp":
    Task { exit(await MCPRole.run()) }
    dispatchMain()
case "claude-hook":
    exit(HookRole.run())
case "--version":
    print(Version.current)
default:
    AppMain.run()
}
