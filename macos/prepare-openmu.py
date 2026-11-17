"""Apply the local deployment changes to the pinned OpenMU checkout."""

from pathlib import Path
import sys


def replace(path, old, new):
    file = source / path
    contents = file.read_text(encoding="utf-8")
    if contents.count(old) != 1:
        raise SystemExit(f"OpenMU changed in {path}; review the packaging changes.")
    file.write_text(contents.replace(old, new), encoding="utf-8")


source = Path(sys.argv[1])
replace(
    "src/Network/Listener.cs",
    "this._clientListener = new TcpListener(IPAddress.Any, this._port);",
    "this._clientListener = new TcpListener(IPAddress.Loopback, this._port);",
)
replace(
    "src/Startup/Program.cs",
    "var exitToken = exitCts.Token;",
    """var exitToken = exitCts.Token;
        using var term = System.Runtime.InteropServices.PosixSignalRegistration.Create(
            System.Runtime.InteropServices.PosixSignal.SIGTERM, signal =>
            {
                signal.Cancel = true;
                exitCts.Cancel();
            });""",
)
replace(
    "src/Startup/Program.cs",
    "initialization.CreateInitialDataAsync(3, true)",
    "initialization.CreateInitialDataAsync(1, true)",
)
replace(
    "src/Startup/Program.cs",
    '        this._logger.Information("Admin Panel bound to urls: {urls}", string.Join("; ", host.Urls));',
    """        this._logger.Information("Admin Panel bound to urls: {urls}", string.Join("; ", host.Urls));
        if (addAdminPanel && Environment.GetEnvironmentVariable("MU_SOLO_ADMIN_URL_FILE") is { Length: > 0 } adminUrlFile)
        {
            var stagingFile = adminUrlFile + ".new";
            await File.WriteAllTextAsync(stagingFile, host.Urls.Single()).ConfigureAwait(false);
            File.Move(stagingFile, adminUrlFile, overwrite: true);
        }
""".rstrip(),
)
replace(
    "src/Web/AdminPanel/WebApplicationExtensions.cs",
    'FileProvider = new PhysicalFileProvider(Path.Combine(Directory.GetCurrentDirectory(), "logs")),',
    """FileProvider = new PhysicalFileProvider(
                System.Environment.GetEnvironmentVariable("MU_SOLO_LOG_DIRECTORY")
                ?? Path.Combine(Directory.GetCurrentDirectory(), "logs")),""",
)
replace(
    "src/Web/AdminPanel/Pages/LogFiles.razor",
    'var logsPath = Path.Combine(Directory.GetCurrentDirectory(), "logs");',
    """var logsPath = System.Environment.GetEnvironmentVariable("MU_SOLO_LOG_DIRECTORY")
            ?? Path.Combine(Directory.GetCurrentDirectory(), "logs");""",
)
replace(
    "src/Persistence/Initialization/VersionSeasonSix/TestAccounts/TestAccountsInitialization.cs",
    """        for (int i = 0; i < 10; i++)""",
    """        // An empty personal account for the local app.
        if (Environment.GetEnvironmentVariable("MU_SOLO_LOCAL") == "1")
        {
            var account = this.Context.CreateNew<MUnique.OpenMU.DataModel.Entities.Account>();
            account.LoginName = "solo";
            account.PasswordHash = BCrypt.Net.BCrypt.HashPassword("soloplay");
            account.Vault = this.Context.CreateNew<MUnique.OpenMU.DataModel.Entities.ItemStorage>();
            return;
        }

        for (int i = 0; i < 10; i++)""",
)
replace(
    "src/GameLogic/Bots/BotFeaturePlugIn.cs",
    "return new BotConfiguration();",
    """return new BotConfiguration
        {
            Enabled = true,
            NumberOfAccounts = 12,
            MaxCharactersPerAccount = 1,
            PresenceRotation = false,
            StartAsFreshCharacters = true,
        };""",
)
replace(
    "src/GameLogic/Bots/BotFeaturePlugIn.cs",
    "    private static readonly TimeSpan StartupDelay = TimeSpan.FromSeconds(15);",
    """    private static readonly TimeSpan StartupDelay = TimeSpan.FromSeconds(15);

    private static readonly int? LocalBotCount =
        int.TryParse(System.Environment.GetEnvironmentVariable("MU_SOLO_BOT_COUNT"), out var count)
        && count is >= 0 and <= 600 ? count : null;""",
)
replace(
    "src/GameLogic/Bots/BotFeaturePlugIn.cs",
    "    private readonly ConcurrentDictionary<IGameContext, ServerState> _states = new();",
    """    private readonly ConcurrentDictionary<IGameContext, ServerState> _states = new();
    private BotConfiguration? _configuration;""",
)
replace(
    "src/GameLogic/Bots/BotFeaturePlugIn.cs",
    "    public BotConfiguration? Configuration { get; set; }",
    """    public BotConfiguration? Configuration
    {
        get => this._configuration;
        set
        {
            if (value is not null && LocalBotCount is { } count)
            {
                // Apply the launcher setting to defaults and to already saved worlds.
                value.Enabled = true;
                value.NumberOfAccounts = count;
                value.MaxCharactersPerAccount = 1;
                value.PresenceRotation = false;
            }

            this._configuration = value;
        }
    }""",
)
