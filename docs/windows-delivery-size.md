# Windows delivery size

Measured on 2026-10-11, from main commit `febc716650f4b6d930598f3b7e63e799fd960973`.
Swift 6.4 (`swift-6.4-RELEASE`, x86_64-unknown-windows-msvc, +assertions), .NET SDK 10.0.401, Windows 11 25H2 build 26200.9457.
The installed .NET Desktop Runtime was 10.0.12. All sizes below use MiB (1,048,576 bytes).

## Reproduce

Close DevDeck, then run from a checkout with the Windows build prerequisites in Windows/README.md, PowerShell 7, and .NET 10 Desktop Runtime:

```powershell
pwsh -NoProfile -File Tools/Measure-WindowsDelivery.ps1
```

`-OutputDirectory dist` is the default. The script rejects output outside the repository, calls the existing builder without changing it, and creates `size-baseline`, `size-A`, `size-B`, `size-C` and their ZIPs below that directory. The existing `dist/` ignore rule covers them. Raw traces, module paths, publish logs and `results.json` are in `dist/size-measurement`, also ignored.

The live scenario uses an isolated preferences directory and a neutral local PowerShell HTTP project. No accounts or tokens are used. A temporary protocol forwarding harness drives the actual shell and actual engine through Start, HTTP 200, open settings, open log, Stop, port release and Quit. It reads the engine process modules after the scenario. Startup timings run the actual host directly, without the forwarding harness.

## Current delivery

This is a fresh run of Tools/Build-WindowsShell.ps1, with its output redirected to `dist/size-baseline`; it has the same contents as its normal `dist/windows-x64` delivery.

| Source | Files | Bytes | MiB |
| --- | ---: | ---: | ---: |
| Swift runtime DLLs from runtimeLibraryPaths | 19 | 61,132,584 | 58.301 |
| Our Swift products | 2 | 15,574,016 | 14.853 |
| .NET shell and embedded runtime | 1 | 197,700,099 | 188.542 |
| External localization resources | 13 | 284,374 | 0.271 |
| Total | 35 | 274,691,073 | 261.966 |

Files larger than 1 MiB, grouped by source:

| Source | File | Bytes | MiB |
| --- | --- | ---: | ---: |
| Swift runtime | _FoundationICU.dll | 38,234,112 | 36.463 |
| Swift runtime | swiftCore.dll | 6,064,128 | 5.783 |
| Swift runtime | FoundationEssentials.dll | 5,712,896 | 5.448 |
| Swift runtime | Foundation.dll | 4,680,192 | 4.463 |
| Swift runtime | FoundationNetworking.dll | 1,477,120 | 1.409 |
| Swift runtime | FoundationInternationalization.dll | 1,473,024 | 1.405 |
| Swift products | DevDeckEngineHost.exe | 12,235,776 | 11.669 |
| Swift products | DevDeckProcessHost.exe | 3,338,240 | 3.184 |
| .NET | DevDeck.Shell.exe | 197,700,099 | 188.542 |

Swift library dependencies are linked into the two products; no separate project DLLs are shipped. Icons and brand vectors are embedded in the shell executable. Fonts are system fonts, with no separate font files. The resource group above contains six localization pairs and Info.plist, with no file above 1 MiB.

In A and C the largest additional .NET file is `Microsoft.Windows.SDK.NET.dll`, 23,637,048 bytes (22.542 MiB). Framework dependent publishing still needs this projection assembly; it is not the installed Desktop Runtime.

## Loaded Swift runtime

The actual DevDeckEngineHost process loaded all 19 shipped runtime DLLs from the measured delivery directory. The comparison uses the names obtained from the toolchain's runtimeLibraryPaths, including its C++ runtime DLLs. The child PATH excludes the Swift toolchain, so a missing bundled DLL cannot silently resolve from that toolchain.

| Loaded DLL | Bytes |
| --- | ---: |
| _FoundationICU.dll | 38,234,112 |
| BlocksRuntime.dll | 11,264 |
| dispatch.dll | 236,032 |
| Foundation.dll | 4,680,192 |
| FoundationEssentials.dll | 5,712,896 |
| FoundationInternationalization.dll | 1,473,024 |
| FoundationNetworking.dll | 1,477,120 |
| MSVCP140.dll | 575,592 |
| swift_Concurrency.dll | 522,752 |
| swift_RegexParser.dll | 858,624 |
| swift_StringProcessing.dll | 700,928 |
| swiftCore.dll | 6,064,128 |
| swiftCRT.dll | 38,912 |
| swiftDispatch.dll | 145,408 |
| swiftObservation.dll | 120,320 |
| swiftSynchronization.dll | 76,288 |
| swiftWinSDK.dll | 34,816 |
| VCRUNTIME140_1.dll | 49,744 |
| VCRUNTIME140.dll | 120,432 |

Shipped runtime DLLs not loaded: none, 0 bytes. C therefore removes no files and equals A. No DLL had to be returned. A module snapshot shows loading, not which functions were exercised; it does not establish coverage of every feature.

## Publishing variants

| Variant | Folder bytes | Folder MiB | ZIP bytes | ZIP MiB | Files | Starts, seconds | Mean, seconds |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Current builder | 274,691,073 | 261.966 | 106,982,620 | 102.027 | 35 | 1.723 / 1.703 / 1.660 | 1.695 |
| A | 101,910,251 | 97.189 | 35,634,686 | 33.984 | 41 | 1.633 / 1.605 / 1.598 | 1.612 |
| B, untrimmed fallback | 158,694,156 | 151.343 | 104,866,225 | 100.008 | 35 | 2.418 / 2.334 / 2.417 | 2.390 |
| C | 101,910,251 | 97.189 | 35,634,686 | 33.984 | 41 | 1.607 / 2.265 / 1.666 | 1.846 |

A uses `--self-contained false` and requires an installed .NET 10 Desktop Runtime. B uses `--self-contained true -p:PublishReadyToRun=false -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true`; native libraries are included for extraction. C starts with A and removes unloaded Swift runtime DLLs, of which this measurement found none. Publish flags are passed on the command line; no csproj was edited.

ZIPs use standard Compress-Archive with its default compression. Sizes exclude traces, ZIPs themselves and extracted single file runtime caches. Timings measure process creation to the first incoming `card.changed` in `--trace`, not completion of window painting. Each trial starts a new process with an empty bundle extraction directory; the operating system file cache is not flushed and the machine is not rebooted between trials. Three samples show scheduling variation, especially the second C sample despite identical A and C contents.

The requested trimmed B fails before execution in `Microsoft.NET.RuntimeIdentifierInference.targets(305,5)`:

```text
error NETSDK1175: Windows Forms is not supported or recommended with trimming enabled. Please go to https://aka.ms/dotnet-illink/windows-forms for more details.
```

The shell's tray uses Windows Forms, so this SDK check rejects the publish before a WPF trimming runtime symptom can be tested. B was then measured with `-p:PublishTrimmed=false` and all other requested flags retained. The restriction was not suppressed.

Start and Stop, HTTP response and port release, settings and log opening passed in the current delivery and all three variants. Engine stderr contained no module loading errors. The test was run with installed Desktop Runtime 10.0.12; A's missing runtime experience was not tested on a machine without that runtime.

## What I would choose and why

For A, I would choose it where installing .NET 10 Desktop Runtime is acceptable, because it gives the smallest download at 33.984 MiB.
For B, I would choose the untrimmed fallback for a standalone delivery, because it needs no separately installed .NET runtime and reduces unpacked size by 110.623 MiB, although ZIP savings are only 2.018 MiB and first startup is slower.
For C, I would keep A instead, because every shipped Swift DLL is loaded and C gives no additional saving.

No default publishing choice was changed. A separate product avoiding Foundation dependencies would need dependency and Package.swift work; this snapshot provides no defensible byte saving for such a change, so none is proposed as a measured optimization here.

## Validation and limits

A second complete invocation reproduced every folder byte count, ZIP byte count and file count exactly, with 0 bytes difference for the current delivery and A, B and C. Its mean startup times were 1.68, 1.70, 2.37 and 1.60 seconds respectively. The output path guard also rejected an outside repository destination.

Windows `swift build` passed with no project warnings. DevDeckWindowsCoreTests passed 15 tests and DevDeckEngineTests passed 26 tests, including the golden comparisons. `dotnet build Windows/DevDeck.Windows.slnx -c Release -warnaserror` passed, and DevDeck.Shell.Tests passed 92 tests. Mac checks were not run.

Application sources, csproj files, the existing builder, installer, autostart, notifications and CI were unchanged. Output directories remain ignored. The measurement requires an interactive Windows session and no other running shell, because the shell enforces a single instance.
