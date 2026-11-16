# MU Solo S6E3 with Bots

A work-in-progress offline MU Online Season 6 Episode 3 setup. It pairs the native MuMain client with OpenMU, its server-side player bots, and a private PostgreSQL database.

The first target is Apple Silicon on macOS 26. The long-term goal is to package and test the same experience on Windows, Linux, and any other desktop platforms supported by both upstream projects.

## macOS

After extracting the two build archives, open **MU Server.app**. When it says your world is ready, open **MU Client.app** and log in with **solo / soloplay**. Create a character in the game. Use **Stop Server and Quit** in the server window to save and shut down the local world. The intended setup requires no Docker, separate database installation, or internet connection during play.

The server starts with one realm at upstream rates and twelve bots starting from level 1. Characters, bot progress, and world configuration are stored in `~/Library/Application Support/MU Solo/database`, outside the app. Server and database logs are in the adjacent `logs` folder.

## Build and verify

The **Build MU Solo for macOS** workflow builds the pair on an Apple Silicon runner and checks server startup, bot creation, shutdown, and database persistence across a restart. It uploads the app archives only from a private repository, since the client archive includes upstream game data. A first successful build and an in-game login test on a Mac are still required. The build uses ad hoc signatures and has no Developer ID signature or notarization.

To build from an Apple Silicon Mac with Xcode command line tools, .NET 10, Python 3, Bison, and Flex, run `MU_SOLO_SMOKE_TEST=1 bash macos/build.sh`. Build downloads require internet access. For personal builds, the workflow assembles the client from the upstream runtime and its matching game data archive. The repository contains only the packaging code.

To update the pair, change the pins in `macos/upstream.env` and rebuild. The server patches check their source anchors and fail the build when they need updating. Before using an updated build with an existing world, stop the server, copy the `MU Solo` data directory, and verify the update on a copy. A fresh-world CI run does not verify migrations from an existing save.

- [OpenMU](https://github.com/MUnique/OpenMU) and [bot configuration](https://openmu-docs.munique.net/server-features/bots/)
- [MuMain](https://github.com/sven-n/MuMain) and its [release assembly instructions](https://github.com/sven-n/MuMain/blob/main/docs/build/README.md#assemble-a-release)
