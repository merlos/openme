using System.IO;
using System.Windows;
using OpenMeKit;
using openme_windows.ViewModels;

namespace openme_windows.Views;

/// <summary>Import Profile window — paste or drag-drop a YAML config file.</summary>
public partial class ImportProfileWindow : Window
{
    private readonly ImportProfileViewModel _vm;

    public ImportProfileWindow(ProfileStore store)
    {
        InitializeComponent();

        _vm = new ImportProfileViewModel(store);
        DataContext = _vm;

        Resources.Add("BoolToVisibility", new BoolToVisibilityConverter());
        Resources.Add("NullToVisibility", new NullToVisibilityConverter());
    }

    // ── Button handlers ───────────────────────────────────────────────────────

    private void PasteButton_Click(object sender, RoutedEventArgs e)
        => _vm.PasteFromClipboard();

    private void ParseButton_Click(object sender, RoutedEventArgs e)
        => _vm.ParseYaml();

    private void ImportButton_Click(object sender, RoutedEventArgs e)
        => _vm.ImportProfiles();

    // ── Drag-drop support ─────────────────────────────────────────────────────

    private void YamlTextBox_DragOver(object sender, DragEventArgs e)
    {
        // Accept file drops (.yaml / .yml) or plain text.
        if (e.Data.GetDataPresent(DataFormats.FileDrop) ||
            e.Data.GetDataPresent(DataFormats.Text))
        {
            e.Effects = DragDropEffects.Copy;
        }
        else
        {
            e.Effects = DragDropEffects.None;
        }
        e.Handled = true;
    }

    private void YamlTextBox_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            var files = (string[])e.Data.GetData(DataFormats.FileDrop);
            var file  = files.FirstOrDefault(f =>
                f.EndsWith(".yaml", StringComparison.OrdinalIgnoreCase) ||
                f.EndsWith(".yml",  StringComparison.OrdinalIgnoreCase));

            if (file is not null)
            {
                try   { _vm.YamlText = File.ReadAllText(file); }
                catch (Exception ex)
                { MessageBox.Show($"Could not read file: {ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error); }
                return;
            }
        }

        if (e.Data.GetDataPresent(DataFormats.Text))
            _vm.YamlText = (string)e.Data.GetData(DataFormats.Text);
    }
}
