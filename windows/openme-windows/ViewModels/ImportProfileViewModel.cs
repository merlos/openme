using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using OpenMeKit;

namespace openme_windows.ViewModels;

/// <summary>ViewModel for the Import Profile window.</summary>
public sealed class ImportProfileViewModel : INotifyPropertyChanged
{
    private readonly ProfileStore _store;

    // ── Observable state ──────────────────────────────────────────────────────

    private string _yamlText = string.Empty;
    public string YamlText
    {
        get => _yamlText;
        set
        {
            SetField(ref _yamlText, value);
            // Reset preview state on every edit.
            ParsedNames.Clear();
            ParseError  = null;
            ImportDone  = false;
        }
    }

    public ObservableCollection<string> ParsedNames { get; } = [];

    public bool HasProfiles => ParsedNames.Count > 0;

    private string? _parseError;
    public string? ParseError
    {
        get => _parseError;
        set { SetField(ref _parseError, value); OnPropertyChanged(nameof(HasError)); }
    }

    private bool _importDone;
    public bool ImportDone
    {
        get => _importDone;
        set => SetField(ref _importDone, value);
    }

    public bool HasError => ParseError is not null;

    private bool _isLoading;
    public bool IsLoading
    {
        get => _isLoading;
        set => SetField(ref _isLoading, value);
    }

    // ── Construction ──────────────────────────────────────────────────────────

    public ImportProfileViewModel(ProfileStore store)
    {
        _store = store;
        ParsedNames.CollectionChanged += (_, _) => OnPropertyChanged(nameof(HasProfiles));
    }

    // ── Commands ──────────────────────────────────────────────────────────────

    /// <summary>
    /// Parses <see cref="YamlText"/> and populates <see cref="ParsedNames"/> with a preview.
    /// Does NOT save to the store yet.
    /// </summary>
    public void ParseYaml()
    {
        ParsedNames.Clear();
        ParseError = null;
        ImportDone = false;

        if (string.IsNullOrWhiteSpace(YamlText))
        {
            ParseError = "Paste the YAML block output by 'openme add' first.";
            return;
        }

        try
        {
            var parsed = ClientConfigParser.ParseYaml(YamlText);
            foreach (var name in parsed.Keys.OrderBy(k => k))
                ParsedNames.Add(name);
        }
        catch (ClientConfigException ex) { ParseError = ex.Message; }
        catch (Exception ex)             { ParseError = $"Unexpected error: {ex.Message}"; }
    }

    /// <summary>
    /// Imports all parsed profiles into the store.
    /// </summary>
    public void ImportProfiles()
    {
        if (ParsedNames.Count == 0) { ParseYaml(); return; }

        IsLoading = true;
        ParseError = null;
        try
        {
            _store.ImportYaml(YamlText);
            ImportDone = true;
            YamlText   = string.Empty;
        }
        catch (Exception ex) { ParseError = ex.Message; }
        finally { IsLoading = false; }
    }

    /// <summary>Pastes text from the Windows clipboard into <see cref="YamlText"/>.</summary>
    public void PasteFromClipboard()
    {
        if (Clipboard.ContainsText())
            YamlText = Clipboard.GetText();
    }

    // ── INotifyPropertyChanged ────────────────────────────────────────────────

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }
}
