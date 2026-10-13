using System.Text.Json;

namespace IpBump;

/// <summary>Per-user settings, stored in %APPDATA%\IpBump\settings.json (each Windows user has their own).</summary>
public class UserSettings
{
    public string Adapter { get; set; } = "";
    public string Ip { get; set; } = "";
    public string Mask { get; set; } = "";
    public string Gateway { get; set; } = "";
    public string Dns1 { get; set; } = "";
    public string Dns2 { get; set; } = "";
    /// <summary>Where to look for free addresses. Empty = the whole subnet.</summary>
    public string RangeStart { get; set; } = "";
    public string RangeEnd { get; set; } = "";
    /// <summary>Whether AI agents (through "IpBump.exe mcp") may change the IP.</summary>
    public bool AllowAgents { get; set; }
    public bool ShowNotifications { get; set; } = true;
    /// <summary>Whether the address is also written on the taskbar, beside the tray icons (Windows 11).</summary>
    public bool ShowOnTaskbar { get; set; } = true;

    public static string Folder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "IpBump");
    static string FilePath => Path.Combine(Folder, "settings.json");

    public static UserSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<UserSettings>(File.ReadAllText(FilePath)) ?? new UserSettings();
        }
        catch { /* corrupt file -> defaults */ }
        return new UserSettings();
    }

    public void Save()
    {
        Directory.CreateDirectory(Folder);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }

    public IpConfig ToConfig(string ip) => new()
    {
        Adapter = Adapter, Ip = ip, Mask = Mask, Gateway = Gateway, Dns1 = Dns1, Dns2 = Dns2,
    };
}
