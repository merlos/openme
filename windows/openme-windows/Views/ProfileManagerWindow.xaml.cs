using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using OpenMeKit;
using openme_windows.ViewModels;

namespace openme_windows.Views;

/// <summary>Profile Manager window — list + edit pane.</summary>
public partial class ProfileManagerWindow : Window
{
    private readonly ProfileManagerViewModel _vm;

    public ProfileManagerWindow(ProfileStore store, KnockManager knockManager)
    {
        InitializeComponent();

        _vm = new ProfileManagerViewModel(store, knockManager);
        DataContext = _vm;
    }

    // ── Private key show/hide ─────────────────────────────────────────────────

    private void PrivKeyBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (_vm.EditingProfile is null) return;
        _vm.EditingProfile.PrivateKey = PrivKeyBox.Password;
    }

    private void ShowPrivKey_Checked(object sender, RoutedEventArgs e)
    {
        if (_vm.EditingProfile is null) return;
        PrivKeyBox.Visibility      = Visibility.Collapsed;
        PrivKeyPlainBox.Visibility = Visibility.Visible;
        PrivKeyPlainBox.Text       = _vm.EditingProfile.PrivateKey;
    }

    private void ShowPrivKey_Unchecked(object sender, RoutedEventArgs e)
    {
        if (_vm.EditingProfile is null) return;
        _vm.EditingProfile.PrivateKey = PrivKeyPlainBox.Text;
        PrivKeyBox.Password           = PrivKeyPlainBox.Text;
        PrivKeyPlainBox.Visibility    = Visibility.Collapsed;
        PrivKeyBox.Visibility         = Visibility.Visible;
    }

    // ── Button handlers ───────────────────────────────────────────────────────

    private void SaveButton_Click(object sender, RoutedEventArgs e)
        => _vm.SaveProfile();

    private void DeleteButton_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            $"Delete profile '{_vm.SelectedEntry?.Name}'? This cannot be undone.",
            "Delete Profile", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (result == MessageBoxResult.Yes)
            _vm.DeleteSelected();
    }

    private async void KnockButton_Click(object sender, RoutedEventArgs e)
        => await _vm.KnockSelectedAsync();

    private void ContinuousKnockButton_Click(object sender, RoutedEventArgs e)
    {
        if (_vm.IsContinuousKnocking) _vm.StopContinuousKnock();
        else                           _vm.StartContinuousKnock();
    }
}


