using System.Diagnostics;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Text.Json;

namespace IpBump;

/// <summary>Windows service (runs as LocalSystem). Listens on a local named pipe and applies IP settings.</summary>
public class IpService : ServiceBase
{
    public const string Name = "IpBumpSvc";
    public const string PipeName = "IpBump.v1";

    CancellationTokenSource _cts;
    Task _loop;

    public IpService()
    {
        ServiceName = Name;
        CanStop = true;
    }

    protected override void OnStart(string[] args)
    {
        _cts = new CancellationTokenSource();
        _loop = Task.Run(() => RunAsync(_cts.Token));
    }

    protected override void OnStop()
    {
        _cts?.Cancel();
        try { _loop?.Wait(3000); } catch { /* shutting down */ }
    }

    static async Task RunAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                using var pipe = CreatePipe();
                await pipe.WaitForConnectionAsync(ct);
                await HandleAsync(pipe, ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
            catch (Exception ex)
            {
                try { EventLog.WriteEntry("Application", "IpBump service: " + ex.Message, EventLogEntryType.Warning); } catch { }
                await Task.Delay(250, CancellationToken.None);
            }
        }
    }

    static NamedPipeServerStream CreatePipe()
    {
        var sec = new PipeSecurity();
        // No remote access, signed-in local users may talk to it, SYSTEM owns it.
        sec.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null),
            PipeAccessRights.FullControl, AccessControlType.Deny));
        sec.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
            PipeAccessRights.ReadWrite, AccessControlType.Allow));
        sec.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            PipeAccessRights.FullControl, AccessControlType.Allow));

        return NamedPipeServerStreamAcl.Create(PipeName, PipeDirection.InOut, 1,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 0, 0, sec);
    }

    static async Task HandleAsync(NamedPipeServerStream pipe, CancellationToken ct)
    {
        var utf8 = new UTF8Encoding(false);
        using var reader = new StreamReader(pipe, utf8, false, 4096, leaveOpen: true);
        using var writer = new StreamWriter(pipe, utf8, 4096, leaveOpen: true) { AutoFlush = true };

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));   // a stuck client can't block the service

        ApplyResponse response;
        try
        {
            string line = await reader.ReadLineAsync(timeout.Token);
            var cfg = JsonSerializer.Deserialize<IpConfig>(line ?? "");
            NetApply.Apply(cfg);
            response = new ApplyResponse(true, "");
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
        {
            response = new ApplyResponse(false, ex.Message);
        }

        await writer.WriteLineAsync(JsonSerializer.Serialize(response));
        try { pipe.WaitForPipeDrain(); } catch { }
    }
}
