using System.IO.Pipes;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace IpBump;

/// <summary>Tray-side: sends settings to the service and waits for the result.</summary>
public static class IpClient
{
    public static void Apply(IpConfig cfg)
    {
        var utf8 = new UTF8Encoding(false);
        try
        {
            using var pipe = new NamedPipeClientStream(".", IpService.PipeName, PipeDirection.InOut);
            pipe.Connect(3000);

            using var writer = new StreamWriter(pipe, utf8, 4096, leaveOpen: true) { AutoFlush = true };
            using var reader = new StreamReader(pipe, utf8, false, 4096, leaveOpen: true);
            writer.WriteLine(JsonSerializer.Serialize(cfg));

            string line = reader.ReadLine();
            var resp = JsonSerializer.Deserialize<ApplyResponse>(line ?? "");
            if (resp == null) throw new InvalidOperationException("No answer from the IpBump service.");
            if (!resp.Ok) throw new InvalidOperationException(resp.Error);
        }
        catch (TimeoutException)
        {
            // Service not installed/running. If we're elevated (e.g. debugging in Visual Studio
            // started as administrator) just apply directly.
            if (IsElevated()) { NetApply.Apply(cfg); return; }
            throw new InvalidOperationException(
                "The IpBump service isn't running. Reinstall IpBump, or start \"IpBump\" in services.msc.");
        }
    }

    static bool IsElevated() =>
        new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
}
