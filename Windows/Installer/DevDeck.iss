#ifndef AppVersion
  #error AppVersion must come from the repository VERSION file through Build-WindowsInstaller.ps1.
#endif
#ifndef Architecture
  #error Architecture must come from Build-WindowsInstaller.ps1.
#endif
#ifndef InstallerBaseName
  #error InstallerBaseName must come from Build-WindowsInstaller.ps1.
#endif

#if Architecture == "arm64"
  #define AllowedArchitectures "arm64"
  #define InstallModeArchitecture "arm64"
  #define RuntimeArchitecture "arm64"
#else
  ; Keep the x64 installer off Arm64 now that a native delivery exists.
  #define AllowedArchitectures "x64compatible and not arm64"
  #define InstallModeArchitecture "x64compatible"
  #define RuntimeArchitecture "x64"
#endif

[Setup]
AppId=DevDeck
AppName=DevDeck
AppVersion={#AppVersion}
AppPublisher=DevDeck
AppPublisherURL=https://github.com/shumer/DevDeck
AppSupportURL=https://github.com/shumer/DevDeck
DefaultDirName={localappdata}\Programs\DevDeck
PrivilegesRequired=lowest
ArchitecturesAllowed={#AllowedArchitectures}
ArchitecturesInstallIn64BitMode={#InstallModeArchitecture}
MinVersion=10.0.22621
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableWelcomePage=no
CloseApplications=yes
; Detached project hosts must outlive setup just as they outlive the shell. An agent's MCP
; server is closed so its file can be replaced; the agent starts it again on its next call.
CloseApplicationsFilter=DevDeck.Shell.exe,DevDeckEngineHost.exe,DevDeckMCP.exe
RestartApplications=no
OutputDir={#InstallerOutput}
OutputBaseFilename={#InstallerBaseName}
SetupIconFile={#AppIcon}
UninstallDisplayIcon={app}\DevDeck.Shell.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupWindowTitle=Install DevDeck
WelcomeLabel1=Install DevDeck
WelcomeLabel2=DevDeck will be installed for your Windows account.
ReadyLabel1=Ready to install DevDeck
FinishedHeadingLabel=DevDeck is installed
FinishedLabel=DevDeck is ready to use.
FinishedLabelNoIcons=DevDeck is ready to use.
UninstallAppFullTitle=Remove DevDeck
ConfirmUninstall=Remove DevDeck? Settings and Credential Manager secrets will be kept.

[Files]
Source: "{#DeliveryDirectory}\*"; DestDir: "{app}"; Excludes: "*.dll,DevDeckProcessHost.exe"; Flags: ignoreversion recursesubdirs createallsubdirs
#include RuntimeFileEntries

[Icons]
Name: "{userprograms}\DevDeck"; Filename: "{app}\DevDeck.Shell.exe"; WorkingDir: "{app}"; AppUserModelID: "DevDeck.Shell"

[Run]
Filename: "{app}\DevDeck.Shell.exe"; Description: "Start DevDeck"; Flags: nowait postinstall skipifsilent; Check: ShouldStart
Filename: "{app}\DevDeck.Shell.exe"; Flags: nowait skipifnotsilent; Check: ShouldStart

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "DevDeck"; Flags: uninsdeletevalue

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{commonappdata}\DevDeck\NotificationAssets"

[Code]
const
  RuntimeURL = 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-{#RuntimeArchitecture}.exe';
  RuntimeKey = 'SOFTWARE\dotnet\Setup\InstalledVersions\{#RuntimeArchitecture}\sharedfx\Microsoft.WindowsDesktop.App';

function NeedsDeliveryFile(FileName, ExpectedHash: String): Boolean;
var
  Destination: String;
begin
  Destination := ExpandConstant('{app}\') + FileName;
  Result := True;
  if FileExists(Destination) then
    Result := CompareText(GetSHA256OfFile(Destination), ExpectedHash) <> 0;
end;

function GetCurrentProcessId: Cardinal;
  external 'GetCurrentProcessId@kernel32.dll stdcall';
function ProcessIdToSessionId(ProcessId: Cardinal; var SessionId: Cardinal): Boolean;
  external 'ProcessIdToSessionId@kernel32.dll stdcall';

function HasDesktopRuntime: Boolean;
var
  Names: TArrayOfString;
  Index: Integer;
begin
  Result := False;
  // The desktop runtime can register in either registry view.
  if RegGetValueNames(HKLM32, RuntimeKey, Names) then
    for Index := 0 to GetArrayLength(Names) - 1 do
      if Pos('10.', Names[Index]) = 1 then
        Result := True;
  if RegGetValueNames(HKLM64, RuntimeKey, Names) then
    for Index := 0 to GetArrayLength(Names) - 1 do
      if Pos('10.', Names[Index]) = 1 then
        Result := True;
end;

function CloseShell: Boolean;
var
  Locator, Services, Processes, Process: Variant;
  Index, ExitCode: Integer;
  SessionId: Cardinal;
  Executable: String;
begin
  Result := False;
  if not ProcessIdToSessionId(GetCurrentProcessId, SessionId) then Exit;
  Locator := CreateOleObject('WbemScripting.SWbemLocator');
  Services := Locator.ConnectServer('', 'root\CIMV2');
  Processes := Services.ExecQuery('SELECT ExecutablePath FROM Win32_Process WHERE Name="DevDeck.Shell.exe" AND SessionId=' + IntToStr(SessionId));
  if Processes.Count = 0 then begin
    Result := True;
    Exit;
  end;
  for Index := 0 to Processes.Count - 1 do begin
    Process := Processes.ItemIndex(Index);
    Executable := Process.ExecutablePath;
    if not Exec(Executable, '--quit', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then Exit;
    if ExitCode <> 0 then Exit;
  end;
  Processes := Services.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name="DevDeck.Shell.exe" AND SessionId=' + IntToStr(SessionId));
  Result := Processes.Count = 0;
end;

function ShouldStart: Boolean;
var
  Index: Integer;
begin
  Result := True;
  for Index := 1 to ParamCount do
    if CompareText(ParamStr(Index), '/NORESTARTAPP') = 0 then
      Result := False;
end;

procedure InitializeWizard;
var
  Page: TOutputMsgWizardPage;
begin
  if not HasDesktopRuntime then
    Page := CreateOutputMsgPage(wpWelcome, '.NET 10 Desktop Runtime', 'DevDeck needs the Microsoft desktop runtime.',
      'Setup will download the runtime from Microsoft. Windows will ask for administrator approval only for this runtime installation. DevDeck itself installs for your account without administrator rights.');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
begin
  Result := '';
  if not HasDesktopRuntime then begin
    try
      DownloadTemporaryFile(RuntimeURL, 'windowsdesktop-runtime-10-win-{#RuntimeArchitecture}.exe', '', nil);
    except
      Result := 'The .NET runtime could not be downloaded. Install it from ' + RuntimeURL + ' and run setup again.';
      Log(Result);
      if not WizardSilent then
        if MsgBox(Result + #13#10 + 'Open the download link?', mbError, MB_YESNO) = IDYES then
          ShellExec('open', RuntimeURL, '', '', SW_SHOWNORMAL, ewNoWait, ExitCode);
      Exit;
    end;
    if not ShellExec('runas', ExpandConstant('{tmp}\windowsdesktop-runtime-10-win-{#RuntimeArchitecture}.exe'),
      '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then begin
      Result := 'The .NET runtime was not installed. Allow its administrator request and try again.';
      Exit;
    end;
    if ((ExitCode <> 0) and (ExitCode <> 3010)) or not HasDesktopRuntime then begin
      Result := 'The .NET runtime installation did not finish. Exit code: ' + IntToStr(ExitCode) + '.';
      Exit;
    end;
  end;
  if not CloseShell then
    Result := 'Close DevDeck using Quit in its tray menu, then try again.';
end;

function InitializeUninstall: Boolean;
begin
  Result := CloseShell;
  if not Result and not UninstallSilent then
    MsgBox('Close DevDeck using Quit in its tray menu, then try again.', mbError, MB_OK);
end;
