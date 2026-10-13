using System.Reflection;
using System.ServiceProcess;

namespace IpBump;

static class Program
{
    public static string Version => Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "";

    // One exe, several roles:
    //   IpBump.exe                      -> tray app (runs as the signed-in user)
    //   IpBump.exe mcp                  -> server for AI agents (started by Claude, Gemini, ...)
    //   IpBump.exe claude-hook          -> started by Claude Code when a request fails; a refused connection gets a new IP
    //   IpBump.exe --service            -> Windows service (runs as SYSTEM, applies IP changes)
    //   IpBump.exe --install-service    -> used by the installer
    //   IpBump.exe --uninstall-service  -> used by the uninstaller
    [STAThread]
    static int Main(string[] args)
    {
        string mode = args.Length > 0 ? args[0].ToLowerInvariant() : "";

        switch (mode)
        {
            case "mcp":
                return AgentServer.Run();
            case "claude-hook":
                return AgentServer.RunClaudeHook();
            case "--service":
                ServiceBase.Run(new IpService());
                return 0;
            case "--install-service":
                return ServiceSetup.Install();
            case "--uninstall-service":
                return ServiceSetup.Uninstall();
        }

        // One tray icon per user session. Starting IpBump again opens the settings of the one already running.
        using var mutex = new Mutex(true, @"Local\IpBump.Tray", out bool first);
        using var showSettings = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\IpBump.ShowSettings");
        if (!first) { showSettings.Set(); return 0; }

        var app = new App();
        app.InitializeComponent();
        return app.Run(showSettings);
    }
}
