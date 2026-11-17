# MU Solo S6E3 with Bots

A work-in-progress offline MU Online Season 6 Episode 3 setup. It pairs the native MuMain client with OpenMU, its server-side player bots, and a private PostgreSQL database.

The first target is Apple Silicon on macOS 26. The long-term goal is to package and test the same experience on Windows, Linux, and any other desktop platforms supported by both upstream projects.

## macOS

Download **MU-Solo-macOS-arm64** from a successful [macOS build](https://github.com/adrian-daniel-militaru/mu-solo-s6e3-bots/actions/workflows/macos.yml) while signed in to GitHub. Extract the two app archives. Open **MU Server.app**, wait for your world to be ready, then open **MU Client.app**. The first client launch downloads the pinned MuMain runtime and game data from MuMain's own releases. It keeps them on your Mac for offline play.

Log in with **solo / soloplay** and create a character in the game. Use **Stop Server and Quit** in the server window to save and shut down the local world. Both apps run without Docker or a separate database installation.

If macOS blocks the first launch of this test build, see [Apple's instructions for opening an app that hasn't been notarized](https://support.apple.com/en-us/102445#openanyway).

The server starts with one realm at upstream rates and 12 bots starting from level 1. To change the population, enter 0–600 in **Bots** and click **Apply and Restart** in MU Server. This disconnects the client, so reconnect once the server is ready. The app remembers your choice. Bots above a reduced count stay offline and keep their progress. Increasing the count brings existing bots back and creates any additional bots at level 1.

Characters, bot progress, and world configuration are stored in `~/Library/Application Support/MU Solo/database`, outside the app. Server and database logs are in the adjacent `logs` folder.

## Control panel

Click **Open Control Panel** in MU Server. Sign in as **admin** and use **Copy Admin Password** to get the password generated for your Mac. The panel opens in your browser and listens only on your Mac.

- **Configuration → General** has normal and master XP rates and level caps. [Game configuration](https://openmu-docs.munique.net/admin-panel/game-configuration/)
- **Configuration → Plugins → Reset Feature** has the reset level, Zen and item costs, and point rewards. Activate the plugin to enable character resets. [Plugins](https://openmu-docs.munique.net/admin-panel/plugins/)
- **Configuration** also includes drop tables, merchants, monsters, and the map editor. [OpenMU admin panel](https://openmu-docs.munique.net/admin-panel/overview/)

Save your changes and use **Servers → Reload configuration and restart all game servers** for settings that are loaded at startup. To use OpenMU's full bot settings, first select **Manage bots in Control Panel** in MU Server and click **Apply and Restart**. Then edit **Bots** on the Plugins page.

## Build and verify

The **Build MU Solo for macOS** workflow builds the pair on an Apple Silicon runner and checks server startup, bot creation, shutdown, and database persistence across a restart. The build uses ad hoc signatures and has no Developer ID signature or notarization. In-game compatibility needs a separate test on a Mac.

To build from an Apple Silicon Mac with Xcode command line tools, .NET 10, Python 3, Bison, and Flex, run `MU_SOLO_SMOKE_TEST=1 bash macos/build.sh`. This downloads and bundles the upstream runtime and game data during the build, so the resulting client can open offline on its first launch. Set `MU_SOLO_CLIENT_DOWNLOAD_ON_FIRST_OPEN=1` to build the smaller launcher used by GitHub Actions.

To update the pair, change the pins in `macos/upstream.env` and rebuild. The server patches check their source anchors and fail the build when they need updating. Before using an updated build with an existing world, stop the server, copy the `MU Solo` data directory, and verify the update on a copy. A fresh-world CI run does not verify migrations from an existing save.

- [OpenMU](https://github.com/MUnique/OpenMU) and [bot configuration](https://openmu-docs.munique.net/server-features/bots/)
- [MuMain](https://github.com/sven-n/MuMain) and its [release assembly instructions](https://github.com/sven-n/MuMain/blob/main/docs/build/README.md#assemble-a-release)
