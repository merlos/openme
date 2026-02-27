using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using OpenMeKit;

namespace openme_windows.ViewModels;

/// <summary>ViewModel for the Profile Manager window.</summary>
public sealed class ProfileManagerViewModel : INotifyPropertyChanged
{
    private readonly ProfileStore  _store;
    private readonly KnockManager  _knockManager;

    // ── Observable state ──────────────────────────────────────────────────────

    public ObservableCollection<ProfileEntry> Profiles { get; } = [];

    private ProfileEntry? _selectedEntry;
    public ProfileEntry? SelectedEntry
    {
        get => _selectedEntry;
        set
        {
            SetField(ref _selectedEntry, value);
            LoadEditingProfile();
            OnPropertyChanged(nameof(HasSelection));
            OnPropertyChanged(nameof(IsContinuousKnocking));
        }
    }

    private Profile? _editingProfile;
    public Profile? EditingProfile
    {
        get => _editingProfile;
        private set { SetField(ref _editingProfile, value); OnPropertyChanged(nameof(IsEditing)); }
    }

    public bool IsEditing => EditingProfile is not null;
    public bool HasSelection => SelectedEntry is not null;

    private string? _errorMessage;
    public string? ErrorMessage
    {
        get => _errorMessage;
        set => SetField(ref _errorMessage, value);
    }

    private string? _feedbackMessage;
    public string? FeedbackMessage
    {
        get => _feedbackMessage;
        set => SetField(ref _feedbackMessage, value);
    }

    private bool _isKnocking;
    public bool IsKnocking
    {
        get => _isKnocking;
        set => SetField(ref _isKnocking, value);
    }

    public bool IsContinuousKnocking =>
        SelectedEntry is not null &&
        _knockManager.ContinuousKnockProfile == SelectedEntry.Name;

    // ── Construction ──────────────────────────────────────────────────────────

    public ProfileManagerViewModel(ProfileStore store, KnockManager knockManager)
    {
        _store        = store;
        _knockManager = knockManager;

        _store.ProfilesChanged         += (_, _) => ReloadProfiles();
        _knockManager.OnKnockCompleted += OnKnockCompleted;

        ReloadProfiles();
    }

    // ── Commands ──────────────────────────────────────────────────────────────

    /// <summary>Saves the current <see cref="EditingProfile"/> back to the store.</summary>
    public void SaveProfile()
    {
        if (EditingProfile is null) return;
        ErrorMessage = null;
        try
        {
            // If the user changed the name, we need to delete the old entry first.
            if (SelectedEntry is not null && SelectedEntry.Name != EditingProfile.Name)
                _store.DeleteProfile(SelectedEntry.Name);

            _store.SaveProfile(EditingProfile);
            // Select the updated entry
            SelectedEntry = Profiles.FirstOrDefault(e => e.Name == EditingProfile.Name);
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
    }

    /// <summary>Deletes the currently selected profile.</summary>
    public void DeleteSelected()
    {
        if (SelectedEntry is null) return;
        _store.DeleteProfile(SelectedEntry.Name);
        EditingProfile = null;
        SelectedEntry  = null;
    }

    /// <summary>Sends a single knock for the selected profile.</summary>
    public async Task KnockSelectedAsync()
    {
        if (SelectedEntry is null) return;
        IsKnocking    = true;
        FeedbackMessage = null;
        await _knockManager.KnockAsync(SelectedEntry.Name);
        IsKnocking = false;
    }

    /// <summary>Starts continuous knock for the selected profile.</summary>
    public void StartContinuousKnock()
    {
        if (SelectedEntry is null) return;
        _knockManager.StartContinuousKnock(SelectedEntry.Name);
        OnPropertyChanged(nameof(IsContinuousKnocking));
    }

    /// <summary>Stops any active continuous knock.</summary>
    public void StopContinuousKnock()
    {
        _knockManager.StopContinuousKnock();
        OnPropertyChanged(nameof(IsContinuousKnocking));
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    private void ReloadProfiles()
    {
        var prevName = SelectedEntry?.Name;
        Profiles.Clear();
        foreach (var e in _store.Entries)
            Profiles.Add(e);

        // Restore selection if the entry still exists
        SelectedEntry = prevName is not null
            ? Profiles.FirstOrDefault(e => e.Name == prevName)
            : null;
    }

    private void LoadEditingProfile()
    {
        EditingProfile = SelectedEntry is null
            ? null
            : _store.GetProfile(SelectedEntry.Name)?.Clone();
    }

    private void OnKnockCompleted(object? sender, KnockOutcome outcome)
    {
        FeedbackMessage = outcome.Result == KnockResult.Success
            ? $"✓ {outcome.ProfileName} — knocked successfully"
            : $"✗ {outcome.ProfileName}: {outcome.ErrorMessage}";

        // Clear feedback after 4 s
        _ = Task.Delay(4000).ContinueWith(_ => { FeedbackMessage = null; },
            System.Threading.Tasks.TaskScheduler.Default);
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
