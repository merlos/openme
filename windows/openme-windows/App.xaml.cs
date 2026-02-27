using System.Windows;
using System.Windows.Controls;
using Hardcodet.Wpf.TaskbarNotification;
using OpenMeKit;
using openme_windows.Views;

namespace openme_windows;

/// <summary>
/// openme system-tray application entry point.
/// </summary>
/// <remarks>
/// The app lives entirely in the Windows notification area (system tray).
/// No main window is shown on startup; windows are opened on demand via the
/// context menu. <c>ShutdownMode="OnExplicitShutdown"</c> keeps the process
/// alive until the user chooses "Quit" from the tray menu.
/// </remarks>
public partial class App : Application
{
    private TaskbarIcon?     _taskbarIcon;
    private ProfileStore?    _store;
    private KnockManager?    _knockManager;

    private ProfileManagerWindow? _profileManagerWindow;
    private ImportProfileWindow?  _importProfileWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _store        = new ProfileStore();
        _knockManager = new KnockManager(_store);

        _knockManager.OnKnockCompleted += OnKnockCompleted;
        _store.ProfilesChanged         += (_, _) => Dispatcher.Invoke(RebuildContextMenu);

        _taskbarIcon = new TaskbarIcon
        {
            ToolTipText = "openme",
            // If Resources/openme.ico exists it will be loaded by the .csproj Resource entry.
            // Fall back to a built-in application icon if the file is absent.
            IconSource = TryLoadIcon(),
        };
        _taskbarIcon.TrayMouseDoubleClick += (_, _) => OpenProfileManager();

        RebuildContextMenu();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _knockManager?.Dispose();
        _taskbarIcon?.Dispose();
        base.OnExit(e);
    }

    // ── Context menu ──────────────────────────────────────────────────────────

    private void RebuildContextMenu()
    {
        if (_taskbarIcon is null || _store is null) return;

        var menu = new ContextMenu();

        var entries = _store.Entries;
        if (entries.Count == 0)
        {
            var noProfiles = new MenuItem { Header = "No profiles configured", IsEnabled = false };
            menu.Items.Add(noProfiles);
        }
        else
        {
            foreach (var entry in entries)
                menu.Items.Add(BuildProfileMenuItem(entry));
        }

        menu.Items.Add(new Separator());

        // Continuous knock status
        if (_knockManager!.ContinuousKnockProfile is { } active)
        {
            var stop = new MenuItem { Header = $"Stop continuous knock ({active})" };
            stop.Click += (_, _) => _knockManager.StopContinuousKnock();
            menu.Items.Add(stop);
            menu.Items.Add(new Separator());
        }

        // Management
        var manageItem = new MenuItem { Header = "Manage Profiles…" };
        manageItem.Click += (_, _) => OpenProfileManager();
        menu.Items.Add(manageItem);

        var importItem = new MenuItem { Header = "Import Profile…" };
        importItem.Click += (_, _) => OpenImportProfile();
        menu.Items.Add(importItem);

        menu.Items.Add(new Separator());

        var websiteItem = new MenuItem { Header = "Website" };
        websiteItem.Click += (_, _) => OpenUrl("https://openme.merlos.org");
        menu.Items.Add(websiteItem);

        var docsItem = new MenuItem { Header = "Documentation" };
        docsItem.Click += (_, _) => OpenUrl("https://openme.merlos.org/docs");
        menu.Items.Add(docsItem);

        menu.Items.Add(new Separator());

        var quitItem = new MenuItem { Header = "Quit openme" };
        quitItem.Click += (_, _) => { Shutdown(); };
        menu.Items.Add(quitItem);

        _taskbarIcon.ContextMenu = menu;
    }

    private MenuItem BuildProfileMenuItem(ProfileEntry entry)
    {
        var profileMenu = new MenuItem { Header = entry.Name };

        var knockItem = new MenuItem { Header = "Knock" };
        knockItem.Click += async (_, _) =>
        {
            if (_knockManager is not null)
                await _knockManager.KnockAsync(entry.Name);
        };
        profileMenu.Items.Add(knockItem);

        bool isContinuous = _knockManager?.ContinuousKnockProfile == entry.Name;
        if (isContinuous)
        {
            var stopItem = new MenuItem { Header = "Stop Continuous Knock" };
            stopItem.Click += (_, _) =>
            {
                _knockManager?.StopContinuousKnock();
                RebuildContextMenu();
            };
            profileMenu.Items.Add(stopItem);
        }
        else
        {
            var startItem = new MenuItem { Header = "Start Continuous Knock" };
            startItem.Click += (_, _) =>
            {
                _knockManager?.StartContinuousKnock(entry.Name);
                RebuildContextMenu();
            };
            profileMenu.Items.Add(startItem);
        }

        return profileMenu;
    }

    // ── Window helpers ────────────────────────────────────────────────────────

    private void OpenProfileManager()
    {
        if (_profileManagerWindow is { IsVisible: true })
        {
            _profileManagerWindow.Activate();
            return;
        }
        _profileManagerWindow = new ProfileManagerWindow(_store!, _knockManager!);
        _profileManagerWindow.Closed += (_, _) => _profileManagerWindow = null;
        _profileManagerWindow.Show();
    }

    private void OpenImportProfile()
    {
        if (_importProfileWindow is { IsVisible: true })
        {
            _importProfileWindow.Activate();
            return;
        }
        _importProfileWindow = new ImportProfileWindow(_store!);
        _importProfileWindow.Closed += (_, _) => _importProfileWindow = null;
        _importProfileWindow.Show();
    }

    // ── Knock feedback ────────────────────────────────────────────────────────

    private void OnKnockCompleted(object? sender, KnockOutcome outcome)
    {
        Dispatcher.Invoke(() =>
        {
            // Rebuild menu to update continuous-knock state if it changed.
            RebuildContextMenu();

            // Show an OS balloon notification for knock results.
            if (_taskbarIcon is null) return;

            if (outcome.Result == KnockResult.Success)
                _taskbarIcon.ShowBalloonTip("openme", $"✓ {outcome.ProfileName} — knocked successfully",
                    BalloonIcon.Info);
            else
                _taskbarIcon.ShowBalloonTip("openme", $"✗ {outcome.ProfileName}: {outcome.ErrorMessage}",
                    BalloonIcon.Error);
        });
    }

    // ── Misc helpers ──────────────────────────────────────────────────────────

    private static void OpenUrl(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); }
        catch { /* best effort */ }
    }

    private static System.Windows.Media.ImageSource? TryLoadIcon()
    {
        try
        {
            // The icon is embedded as a resource — resolve via pack URI.
            var uri = new Uri("pack://application:,,,/Resources/openme.ico", UriKind.Absolute);
            var decoder = System.Windows.Media.Imaging.BitmapDecoder.Create(
                uri,
                System.Windows.Media.Imaging.BitmapCreateOptions.None,
                System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
            return decoder.Frames[0];
        }
        catch
        {
            return null; // TaskbarIcon will fall back to the default application icon
        }
    }
}
