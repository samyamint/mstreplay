# Building STREPLAY for macOS

You need macOS 12 or later, the [.NET SDK](https://dotnet.microsoft.com/download) (8 or newer), Apple's Command Line Tools (`xcode-select --install`), and STRAFTAT installed. The game's own DLLs are referenced from your install and never committed.

## Build and package

```sh
dotnet build -c Release -t:ThunderstorePack
```

The build finds the game at `~/Library/Application Support/Steam/steamapps/common/STRAFTAT`, using assemblies inside `STRAFTAT.app/Contents/Resources/Data/Managed`. For a different Steam library, copy `local.props.example` to `local.props` and edit `GameDir`, or run:

```sh
dotnet build -c Release -t:ThunderstorePack -p:GameDir="/Volumes/Games/steamapps/common/STRAFTAT"
```

You can also point `GameDir` at the `.app` bundle itself, or set `-p:ManagedDir="/full/path/to/Managed"` directly. `local.props` is git-ignored.

`tools/build-native.sh` compiles and ad-hoc signs a universal **arm64 + x86_64** `streplay-encoder` using Swift and Apple's AVFoundation. The build outputs `bin/Release/streplay.dll` and `bin/Release/streplay-encoder`. No FFmpeg is downloaded, invoked, linked, or packaged. The Swift helper can also be built alone with `sh tools/build-native.sh`.

The package is `dist/STREPLAY-macOS-1.1.0.zip`. It contains both files in `BepInEx/plugins/streplay/`, plus the manifest, icon, README and changelog. Keep the executable beside the DLL when installing into a macOS BepInEx 5 profile. The package uses the upstream 1.1.0 version. Building does not publish or upload it.

## Optional local deployment

Builds do not automatically modify a Mac mod-manager profile. To opt in, close the game and set the full plugins path for your chosen profile:

```sh
dotnet build -c Release -p:PluginsDir="/full/path/to/profile/BepInEx/plugins"
```

Both files are copied into a `streplay` subfolder. BepInEx itself and the game's launch setup are managed separately.

## Checks

```sh
python3 tests/test-native.py
dotnet build -c Debug
```

The native integration tests feed synthetic bottom-up RGBA frames and a stereo WAV into the actual encoder, then decode the movies with AVFoundation. They check all three codecs, sound, colors, orientation, frame timing, early EOF (render cancellation), partial pipe reads, malformed input, and preservation of existing outputs. They require only Python 3 and Command Line Tools; no third-party Python packages. The C# launcher can also be exercised with `python3 tests/test-launcher.py` (.NET SDK 8 or newer).

Debug builds include the scripted in-game harness in `src/AutoTest.cs`; Release packages exclude it. Test a real recording and replay in-game before publishing: automated encoder tests do not exercise Unity rendering, Metal readback, game hooks, or your BepInEx launch configuration.

Build this macOS package on a Mac. On other platforms the managed plugin still builds against supplied game DLLs and can export PNG sequences, but native video packaging requires Apple's toolchain.
