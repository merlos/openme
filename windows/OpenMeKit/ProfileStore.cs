using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace OpenMeKit;

/// <summary>
/// JSON-backed profile store persisted in <c>%APPDATA%\openme\profiles.json</c>.
/// </summary>
/// <remarks>
/// <para>
/// All mutating operations immediately flush the store to disk. The file is written
/// atomically (write to a temp file, then replace) to avoid corruption on sudden power loss.
/// </para>
/// <para>
/// The store is also able to import from — and export to — the YAML format used by the
/// openme CLI and the other platform clients.
/// </para>
/// </remarks>
public sealed class ProfileStore
{
    // ── Storage ───────────────────────────────────────────────────────────────

    private static readonly string DefaultStorePath =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                     "openme", "profiles.json");

    private readonly string _storePath;

    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented            = true,
        PropertyNamingPolicy     = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition   = JsonIgnoreCondition.WhenWritingNull,
        Encoder                  = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNameCaseInsensitive = true,
    };

    // In-memory list; writes are always flushed immediately.
    private List<Profile> _profiles = [];

    // ── Events ────────────────────────────────────────────────────────────────

    /// <summary>Raised after any mutating operation (save, delete, rename).</summary>
    public event EventHandler? ProfilesChanged;

    // ── Construction ──────────────────────────────────────────────────────────

    /// <summary>
    /// Creates a profile store that persists to the default location
    /// (<c>%APPDATA%\openme\profiles.json</c>).
    /// </summary>
    public ProfileStore() : this(DefaultStorePath) { }

    /// <summary>Creates a profile store that persists to the given file path (testing).</summary>
    public ProfileStore(string storePath)
    {
        _storePath = storePath;
        Load();
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    /// <summary>Returns a snapshot of all profile entries (no key material).</summary>
    public IReadOnlyList<ProfileEntry> Entries =>
        _profiles.Select(p => new ProfileEntry(p.Name, p.ServerHost, p.ServerUdpPort))
                 .ToList()
                 .AsReadOnly();

    /// <summary>Returns all profiles including key material.</summary>
    public IReadOnlyList<Profile> Profiles => _profiles.AsReadOnly();

    /// <summary>
    /// Returns the full <see cref="Profile"/> for <paramref name="name"/>,
    /// or <c>null</c> if not found.
    /// </summary>
    public Profile? GetProfile(string name) =>
        _profiles.FirstOrDefault(p => p.Name == name);

    // ── Write ─────────────────────────────────────────────────────────────────

    /// <summary>Saves or updates a profile. If a profile with the same name exists it is replaced.</summary>
    public void SaveProfile(Profile profile)
    {
        ArgumentNullException.ThrowIfNull(profile);
        if (string.IsNullOrWhiteSpace(profile.Name))
            throw new ArgumentException("Profile name must not be empty.", nameof(profile));

        var idx = _profiles.FindIndex(p => p.Name == profile.Name);
        if (idx >= 0) _profiles[idx] = profile.Clone();
        else          _profiles.Add(profile.Clone());

        Flush();
    }

    /// <summary>Saves a collection of profiles, merging with any existing ones.</summary>
    public void SaveAll(IEnumerable<Profile> profiles)
    {
        foreach (var p in profiles) SaveProfile(p);
    }

    /// <summary>Deletes the profile with the given name. No-op if it does not exist.</summary>
    public void DeleteProfile(string name)
    {
        var removed = _profiles.RemoveAll(p => p.Name == name);
        if (removed > 0) Flush();
    }

    /// <summary>Renames a profile. Throws if <paramref name="oldName"/> is not found.</summary>
    public void RenameProfile(string oldName, string newName)
    {
        var profile = _profiles.FirstOrDefault(p => p.Name == oldName)
            ?? throw new KeyNotFoundException($"Profile '{oldName}' not found.");

        if (_profiles.Any(p => p.Name == newName))
            throw new InvalidOperationException($"A profile named '{newName}' already exists.");

        profile.Name = newName;
        Flush();
    }

    // ── YAML import/export ────────────────────────────────────────────────────

    /// <summary>
    /// Parses a YAML string (produced by <c>openme add</c>) and saves all contained
    /// profiles into the store.
    /// </summary>
    /// <returns>The list of newly saved profile names.</returns>
    public IReadOnlyList<string> ImportYaml(string yaml)
    {
        var parsed = ClientConfigParser.ParseYaml(yaml);
        foreach (var p in parsed.Values)
            SaveProfile(p);
        return parsed.Keys.ToList().AsReadOnly();
    }

    /// <summary>Exports all stored profiles as a <c>config.yaml</c>-compatible string.</summary>
    public string ExportYaml() => ClientConfigParser.ToYaml(_profiles);

    // ── Persistence ───────────────────────────────────────────────────────────

    private void Load()
    {
        if (!File.Exists(_storePath)) return;
        try
        {
            var json = File.ReadAllText(_storePath);
            var stored = JsonSerializer.Deserialize<StoredProfiles>(json, _jsonOptions);
            _profiles = stored?.Profiles ?? [];
        }
        catch (Exception ex)
        {
            // Log but do not throw — start with an empty store.
            System.Diagnostics.Debug.WriteLine($"[openme] ProfileStore load error: {ex.Message}");
            _profiles = [];
        }
    }

    private void Flush()
    {
        var dir = Path.GetDirectoryName(_storePath)!;
        Directory.CreateDirectory(dir);

        var tmp = _storePath + ".tmp";
        var json = JsonSerializer.Serialize(new StoredProfiles { Profiles = _profiles }, _jsonOptions);
        File.WriteAllText(tmp, json, System.Text.Encoding.UTF8);
        File.Move(tmp, _storePath, overwrite: true);

        ProfilesChanged?.Invoke(this, EventArgs.Empty);
    }

    // ── Private DTOs ──────────────────────────────────────────────────────────

    private sealed class StoredProfiles
    {
        public List<Profile> Profiles { get; set; } = [];
    }
}
