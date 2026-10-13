using System.Text.Json;

namespace IpBump;

public record ChangeResult(string Adapter, string OldIp, string NewIp);

/// <summary>Who changed the IP last. Written after every change so the tray app can report changes made by an AI agent.</summary>
public record LastChange(DateTime At, string From, string To, string Source)
{
    public const string FileName = "last-change.json";
    static string FilePath => Path.Combine(UserSettings.Folder, FileName);

    public static LastChange Load()
    {
        try { return JsonSerializer.Deserialize<LastChange>(File.ReadAllText(FilePath)); }
        catch { return null; }   // not written yet, or being written right now
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(UserSettings.Folder);
            // Written aside and moved into place, so the tray app never reads half a file
            File.WriteAllText(FilePath + ".tmp", JsonSerializer.Serialize(this));
            File.Move(FilePath + ".tmp", FilePath, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Only a note for the tray icon; the IP change itself already succeeded
        }
    }
}

/// <summary>The IP changes themselves, shared by the tray icon, the settings window and the AI-agent server.</summary>
public static class IpChanger
{
    public const string Tray = "tray";

    /// <summary>Finds an address nobody is using and switches to it.</summary>
    public static ChangeResult ToFreeAddress(UserSettings s, string source, Action<string> progress = null) => Locked(() =>
    {
        var before = Current(s);
        if (!before.Up) throw new InvalidOperationException($"\"{s.Adapter}\" is not connected.");

        var taken = new List<string>();
        bool replaced = false;   // once the old address is gone, any failure must put it back
        try
        {
            for (int attempt = 0; attempt < 3; attempt++)
            {
                progress?.Invoke("Looking for a free address…");
                string ip = IpScanner.FindFree(s, before.Ip, taken)
                    ?? throw new InvalidOperationException("Every address in the search range is in use.");

                progress?.Invoke($"Applying {ip}…");
                IpClient.Apply(s.ToConfig(ip));
                replaced = true;
                var check = NetApply.WaitUntilUsable(s.Adapter, ip);
                if (check == AddressCheck.Usable)
                {
                    new LastChange(DateTime.UtcNow, before.Ip, ip, source).Save();
                    return new ChangeResult(s.Adapter, before.Ip, ip);
                }
                if (check == AddressCheck.TimedOut) break;
                taken.Add(ip);   // a device that stayed silent during the scan claimed it; try the next one
            }

            throw new InvalidOperationException(taken.Count > 0
                ? $"Other devices claimed {string.Join(", ", taken)}. The previous address was put back."
                : "Windows did not start using the new address. The previous address was put back.");
        }
        catch when (replaced)
        {
            Restore(before);
            throw;
        }
    });

    /// <summary>Applies exactly what is in the settings (the "Save" button).</summary>
    public static void ApplySettings(UserSettings s) => Locked(() =>
    {
        var before = Current(s);
        IpClient.Apply(s.ToConfig(s.Ip));
        if (before.Up && NetApply.WaitUntilUsable(s.Adapter, s.Ip) == AddressCheck.Duplicate)
        {
            Restore(before);
            throw new InvalidOperationException($"Another device is already using {s.Ip}. The previous address was put back.");
        }
        new LastChange(DateTime.UtcNow, before.Ip, s.Ip, Tray).Save();
        return true;
    });

    /// <summary>Hands the adapter back to the network's DHCP server.</summary>
    public static void UseDhcp(UserSettings s) => Locked(() =>
    {
        Current(s);
        IpClient.Apply(new IpConfig { Adapter = s.Adapter, Dhcp = true });
        return true;
    });

    static AdapterState Current(UserSettings s)
    {
        if (string.IsNullOrEmpty(s.Adapter))
            throw new InvalidOperationException("IpBump isn't set up yet. Open its settings and pick a network adapter.");
        return NetApply.ReadCurrent(s.Adapter)
            ?? throw new InvalidOperationException($"Network adapter \"{s.Adapter}\" was not found.");
    }

    static void Restore(AdapterState before)
    {
        if (!before.Dhcp && !NetApply.IsIPv4(before.Ip)) return;   // there was nothing usable to go back to
        try { IpClient.Apply(before); } catch { /* the caller reports the original problem */ }
    }

    // The tray icon and an agent may ask at the same moment; one change at a time.
    static T Locked<T>(Func<T> change)
    {
        using var gate = new Mutex(false, @"Local\IpBump.Change");
        try
        {
            if (!gate.WaitOne(TimeSpan.FromSeconds(30)))
                throw new InvalidOperationException("Another IP change is still running. Try again in a moment.");
        }
        catch (AbandonedMutexException) { /* the other process died mid-change; the lock is ours now */ }

        try { return change(); }
        finally { gate.ReleaseMutex(); }
    }
}
