using System.Diagnostics;

namespace OpenMeKit;

/// <summary>Outcome of a single knock attempt.</summary>
public enum KnockResult
{
    /// <summary>The UDP datagram was accepted by the OS for transmission.</summary>
    Success,
    /// <summary>The knock could not be completed.</summary>
    Failure,
}

/// <summary>Details returned after a knock attempt.</summary>
/// <param name="Result">Success or failure indicator.</param>
/// <param name="ProfileName">Name of the profile that was knocked.</param>
/// <param name="ErrorMessage">Human-readable error message, or <c>null</c> on success.</param>
public sealed record KnockOutcome(KnockResult Result, string ProfileName, string? ErrorMessage = null);

/// <summary>
/// Orchestrates SPA knock operations for named profiles.
/// </summary>
/// <remarks>
/// <para>
/// <c>KnockManager</c> is the recommended entry point for UI applications. It wraps
/// <see cref="KnockService"/> with profile resolution, result reporting, and a
/// <b>continuous knock</b> mode that automatically re-sends every 20 seconds so firewall
/// rules stay open during long sessions (e.g. SSH, RDP).
/// </para>
/// <para>
/// All public methods are thread-safe and can be called from any thread.
/// <see cref="OnKnockCompleted"/> is raised on the thread pool; marshal to the UI thread
/// as needed.
/// </para>
/// </remarks>
public sealed class KnockManager : IDisposable
{
    private readonly ProfileStore _store;
    private System.Threading.Timer? _continuousTimer;
    private volatile string? _continuousKnockProfile;
    private bool _disposed;

    private const int ContinuousIntervalMs = 20_000; // 20 s

    /// <summary>
    /// Raised whenever a knock completes (success or failure), including every
    /// repetition in continuous-knock mode.
    /// </summary>
    public event EventHandler<KnockOutcome>? OnKnockCompleted;

    /// <summary>
    /// The profile name currently being knocked in continuous mode, or <c>null</c> when idle.
    /// </summary>
    public string? ContinuousKnockProfile => _continuousKnockProfile;

    /// <summary>Creates a new <see cref="KnockManager"/> backed by the given <see cref="ProfileStore"/>.</summary>
    public KnockManager(ProfileStore store)
    {
        _store = store ?? throw new ArgumentNullException(nameof(store));
    }

    // ── Single knock ──────────────────────────────────────────────────────────

    /// <summary>
    /// Sends a single SPA knock for the named profile and reports the outcome via
    /// <see cref="OnKnockCompleted"/>.
    /// </summary>
    /// <param name="profileName">Name of the profile to knock (must exist in the store).</param>
    /// <param name="cancellationToken">Optional cancellation token.</param>
    public async Task KnockAsync(string profileName, CancellationToken cancellationToken = default)
    {
        var profile = _store.GetProfile(profileName);
        if (profile is null)
        {
            OnKnockCompleted?.Invoke(this, new KnockOutcome(KnockResult.Failure, profileName,
                $"Profile '{profileName}' not found."));
            return;
        }
        await KnockAsync(profile, cancellationToken);
    }

    /// <summary>
    /// Sends a single SPA knock using the supplied <see cref="Profile"/> directly.
    /// </summary>
    public async Task KnockAsync(Profile profile, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(profile);
        try
        {
            await KnockService.KnockAsync(
                profile.ServerHost,
                profile.ServerUdpPort,
                profile.ServerPubKey,
                profile.PrivateKey,
                cancellationToken);

            // Run post-knock command if configured
            if (!string.IsNullOrWhiteSpace(profile.PostKnock))
                RunPostKnock(profile.PostKnock);

            OnKnockCompleted?.Invoke(this, new KnockOutcome(KnockResult.Success, profile.Name));
        }
        catch (Exception ex)
        {
            OnKnockCompleted?.Invoke(this,
                new KnockOutcome(KnockResult.Failure, profile.Name, ex.Message));
        }
    }

    // ── Continuous knock ──────────────────────────────────────────────────────

    /// <summary>
    /// Starts knocking <paramref name="profileName"/> immediately and repeats every 20 seconds.
    /// </summary>
    /// <remarks>
    /// Calling this while a continuous knock is already running cancels the previous session
    /// first. Stop with <see cref="StopContinuousKnock"/>.
    /// </remarks>
    public void StartContinuousKnock(string profileName)
    {
        StopContinuousKnock();
        _continuousKnockProfile = profileName;

        // Knock immediately, then on a timer.
        _ = Task.Run(() => KnockAsync(profileName));

        _continuousTimer = new System.Threading.Timer(_ =>
        {
            if (_continuousKnockProfile == profileName)
                _ = Task.Run(() => KnockAsync(profileName));
        }, null, ContinuousIntervalMs, ContinuousIntervalMs);
    }

    /// <summary>
    /// Cancels the running continuous knock timer.
    /// Safe to call even when no continuous knock is active.
    /// </summary>
    public void StopContinuousKnock()
    {
        _continuousTimer?.Change(Timeout.Infinite, Timeout.Infinite);
        _continuousTimer?.Dispose();
        _continuousTimer = null;
        _continuousKnockProfile = null;
    }

    // ── Post-knock ────────────────────────────────────────────────────────────

    private static void RunPostKnock(string command)
    {
        try
        {
            // On Windows, delegate to cmd.exe so the user can use any shell syntax.
            Process.Start(new ProcessStartInfo
            {
                FileName        = "cmd.exe",
                Arguments       = $"/c {command}",
                UseShellExecute = true,
                CreateNoWindow  = false,
            });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[openme] post-knock command failed: {ex.Message}");
        }
    }

    // ── IDisposable ───────────────────────────────────────────────────────────

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        StopContinuousKnock();
    }
}
