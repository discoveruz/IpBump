using System.Diagnostics;

namespace IpBump;

/// <summary>Registers / removes the Windows service. Called by the installer (which runs as admin).</summary>
static class ServiceSetup
{
    public static int Install()
    {
        string bin = $"\"{Environment.ProcessPath}\" --service";

        if (Sc("query", IpService.Name) == 0)
        {
            Sc("stop", IpService.Name);
            Thread.Sleep(1500);
            Sc("config", IpService.Name, "binPath=", bin, "start=", "auto");
        }
        else
        {
            int rc = Sc("create", IpService.Name, "binPath=", bin, "start=", "auto", "DisplayName=", "IpBump");
            if (rc != 0) return rc;
        }

        Sc("description", IpService.Name, "Applies IPv4 settings requested by the IpBump tray app.");
        Sc("failure", IpService.Name, "reset=", "86400", "actions=", "restart/5000/restart/5000/restart/5000");
        Sc("start", IpService.Name);
        return 0;
    }

    public static int Uninstall()
    {
        Sc("stop", IpService.Name);
        Thread.Sleep(1500);
        Sc("delete", IpService.Name);
        return 0;
    }

    static int Sc(params string[] args)
    {
        var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "sc.exe"))
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        using var p = Process.Start(psi)!;
        p.StandardOutput.ReadToEnd();
        p.StandardError.ReadToEnd();
        p.WaitForExit();
        return p.ExitCode;
    }
}
