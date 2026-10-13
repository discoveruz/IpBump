using System.Windows;
using Microsoft.Win32;
using Wpf.Ui.Appearance;

namespace IpBump;

/// <summary>The tray app: no main window, just the tray icon and (on demand) the settings window.</summary>
public partial class App : Application
{
    TrayApp _tray;

    public int Run(EventWaitHandle showSettings)
    {
        Startup += (_, _) =>
        {
            ApplicationThemeManager.ApplySystemTheme();
            _tray = new TrayApp();
            // Signalled when the user starts IpBump a second time
            ThreadPool.RegisterWaitForSingleObject(showSettings,
                (_, _) => Dispatcher.BeginInvoke(_tray.OpenSettings), null, Timeout.Infinite, executeOnlyOnce: false);
        };
        Exit += (_, _) => _tray?.Dispose();

        // The tray icon lives for days: follow Windows when it switches between dark and light
        SystemEvents.UserPreferenceChanged += (_, e) =>
        {
            if (e.Category == UserPreferenceCategory.General)
                Dispatcher.BeginInvoke(() => ApplicationThemeManager.ApplySystemTheme());
        };
        return Run();
    }
}
