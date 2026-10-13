using System.ComponentModel;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace IpBump;

/// <summary>
/// An AI agent on this PC and its connection to IpBump (the Connect buttons in the settings window).
/// Connecting writes into the agent's own configuration what "claude mcp add" or "gemini mcp add" would:
/// start "IpBump.exe mcp" as an MCP server. Claude Code is also told to run "IpBump.exe claude-hook"
/// whenever it gives up on a request.
/// </summary>
public class Agent : INotifyPropertyChanged
{
    const string FailureHook = "StopFailure";   // Claude Code's name for "the turn ended with an API error"

    static readonly JsonSerializerOptions Layout = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,   // leaves ' & and non-English text readable, not \uXXXX
    };

    readonly string _folder;    // exists once the agent has been started by this user
    readonly string _servers;   // the file that lists its MCP servers
    readonly string _hooks;     // the file that lists its hooks, for an agent that can react to a failed request

    Agent(string name, string folder, string servers, string hooks = null)
    {
        Name = name; _folder = folder; _servers = servers; _hooks = hooks;
    }

    public string Name { get; }
    public event PropertyChangedEventHandler PropertyChanged;

    public static Agent[] All()
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string claude = Path.Combine(home, ".claude"), gemini = Path.Combine(home, ".gemini");

        // Claude Desktop from the Microsoft Store may keep a private copy of %APPDATA%\Claude; that copy wins
        const string config = "claude_desktop_config.json";
        string[] places =
        [
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                @"Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Claude"),
        ];
        string desktop = places.FirstOrDefault(p => File.Exists(Path.Combine(p, config)))
                      ?? places.FirstOrDefault(Directory.Exists) ?? places[1];

        return
        [
            new("Claude Code", claude, Path.Combine(home, ".claude.json"), Path.Combine(claude, "settings.json")),
            new("Gemini CLI", gemini, Path.Combine(gemini, "settings.json")),
            new("Claude Desktop", desktop, Path.Combine(desktop, config)),
        ];
    }

    /// <summary>Whether the agent is set up to start this copy of IpBump, not one that was installed elsewhere.</summary>
    public bool Connected
    {
        get
        {
            try
            {
                return IsThisExe(Read(_servers)["mcpServers"]?[AgentServer.Name])
                    && (_hooks == null || Handlers(Read(_hooks)).SelectMany(list => list).Any(IsThisExe));
            }
            catch (Exception ex) when (Unusable(ex)) { return false; }   // Connect says what is wrong with the file
        }
    }

    public void Connect()
    {
        if (!Directory.Exists(_folder))
            throw new InvalidOperationException($"{Name} was not found for your Windows account. Start it once, then connect again.");
        try
        {
            Edit(_servers, config => Section(config, "mcpServers")[AgentServer.Name] =
                new JsonObject { ["command"] = Exe, ["args"] = new JsonArray("mcp") });

            if (_hooks != null) Edit(_hooks, config =>
            {
                RemoveHandlers(config);   // an IpBump installed somewhere else may have left its own
                var hooks = Section(config, "hooks");
                if (hooks[FailureHook] is not JsonArray groups) hooks[FailureHook] = groups = new JsonArray();
                // "args" makes Claude Code start the exe directly, so no shell has to cope with the path
                var handler = new JsonObject { ["type"] = "command", ["command"] = Exe, ["args"] = new JsonArray("claude-hook") };
                groups.Add(new JsonObject { ["hooks"] = new JsonArray(handler) });
            });
        }
        finally { PropertyChanged?.Invoke(this, new(nameof(Connected))); }
    }

    public void Disconnect()
    {
        try
        {
            Edit(_servers, config => (config["mcpServers"] as JsonObject)?.Remove(AgentServer.Name));
            if (_hooks != null) Edit(_hooks, RemoveHandlers);
        }
        finally { PropertyChanged?.Invoke(this, new(nameof(Connected))); }
    }

    static string Exe => Environment.ProcessPath;

    /// <summary>The program a server entry or a hook handler starts.</summary>
    static string Command(JsonNode entry) =>
        entry is JsonObject o && o["command"] is JsonValue v && v.TryGetValue(out string path) ? path : "";

    static bool IsThisExe(JsonNode entry) => Command(entry).Equals(Exe, StringComparison.OrdinalIgnoreCase);

    static bool IsIpBump(JsonNode entry) =>
        Path.GetFileName(Command(entry)).Equals(Path.GetFileName(Exe), StringComparison.OrdinalIgnoreCase);

    /// <summary>Claude Code keeps them as  "hooks": { "StopFailure": [ { "hooks": [ handler, ... ] }, ... ] }</summary>
    static List<JsonArray> Handlers(JsonObject config) =>
        ((config["hooks"] as JsonObject)?[FailureHook] as JsonArray)?
            .OfType<JsonObject>().Select(group => group["hooks"]).OfType<JsonArray>().ToList() ?? [];

    /// <summary>Takes IpBump's handlers out, along with the wrappers that are empty without them.</summary>
    static void RemoveHandlers(JsonObject config)
    {
        foreach (var handlers in Handlers(config))
        {
            foreach (var ours in handlers.Where(IsIpBump).ToList()) handlers.Remove(ours);
            if (handlers.Count == 0) handlers.Parent.Parent.AsArray().Remove(handlers.Parent);
        }
        if (config["hooks"] is not JsonObject hooks) return;
        if (hooks[FailureHook] is JsonArray { Count: 0 }) hooks.Remove(FailureHook);
        if (hooks.Count == 0) config.Remove("hooks");
    }

    static JsonObject Section(JsonObject config, string name) => config[name] switch
    {
        JsonObject there => there,
        null => (JsonObject)(config[name] = new JsonObject()),
        _ => throw new JsonException($"\"{name}\" is not a JSON object."),
    };

    static JsonObject Read(string file)
    {
        string text = File.Exists(file) ? File.ReadAllText(file) : "";
        return text.Trim() == "" ? new JsonObject()
            : JsonNode.Parse(text) as JsonObject ?? throw new JsonException("It does not hold a JSON object.");
    }

    static void Edit(string file, Action<JsonObject> change)
    {
        try
        {
            var config = Read(file);
            string before = config.ToJsonString();
            change(config);
            if (config.ToJsonString() == before) return;

            // Written aside and moved into place, so the agent never reads half a file
            string aside = file + ".ipbump.tmp";
            File.WriteAllText(aside, config.ToJsonString(Layout));
            try { File.Move(aside, file, overwrite: true); }
            finally { File.Delete(aside); }   // only still there if the move failed
        }
        catch (Exception ex) when (Unusable(ex))
        {
            throw new InvalidOperationException($"Could not update {file}. {ex.Message}");
        }
    }

    // A file that is locked, is not JSON, or holds something else where the servers or hooks belong
    static bool Unusable(Exception ex) =>
        ex is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or ArgumentException;
}
