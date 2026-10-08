# Windows shell POC

The Windows POC uses .NET 10 WPF as a native shell around `DevDeckEngineHost`. The shell owns
windows, the tray icon, Credential Manager access and URL launching. Text, card order, semantic
tones, actions, availability and fallback card models come from the Swift engine.

Build the delivery directory from PowerShell:

```powershell
.\Tools\Build-WindowsShell.ps1
```

The default output is `dist\windows-x64`. It contains the self-contained WPF executable, the two
Swift hosts, localization resources and only the Swift runtime DLLs reached from those hosts.
The test project is built separately and is rejected if any of its files enter the delivery
directory.

Store a token through hidden console input. The command prints and logs no credential:

```powershell
.\dist\windows-x64\DevDeck.Shell.exe --set-token github
```

Run the shell with the non-secret configuration file used by the engine:

```powershell
.\dist\windows-x64\DevDeck.Shell.exe --config C:\path\to\config.json
```

Run the separate shell checks:

```powershell
dotnet run --project .\Windows\DevDeck.Shell.Tests\DevDeck.Shell.Tests.csproj
```
