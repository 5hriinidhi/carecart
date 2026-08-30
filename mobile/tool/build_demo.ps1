<#
  Judge-ready release build of the CareCart app, pointed at a seeded demo backend
  (Phase 6.4).

    .\tool\build_demo.ps1 -ApiBaseUrl https://demo.carecart.example
    .\tool\build_demo.ps1 -ApiBaseUrl http://192.168.1.20:8000 -Target appbundle

  --release strips asserts / turns kDebugMode off, so the /debug screen-gallery
  route is not registered. No debug banner, no print/debugPrint in lib/, no Dio
  payload logger (all enforced by tests). DEMO_MODE=true shows a "DEMO DATA" chip.
#>
param(
  [Parameter(Mandatory = $true)] [string]$ApiBaseUrl,
  [ValidateSet('apk', 'appbundle', 'ios')] [string]$Target = 'apk'
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

flutter pub get
flutter build $Target `
  --release `
  --dart-define=API_BASE_URL=$ApiBaseUrl `
  --dart-define=DEBUG_GALLERY=false `
  --dart-define=DEMO_MODE=true

Write-Host ""
Write-Host "Built $Target (release) -> API_BASE_URL=$ApiBaseUrl"
switch ($Target) {
  'apk'       { Write-Host "  build/app/outputs/flutter-apk/app-release.apk" }
  'appbundle' { Write-Host "  build/app/outputs/bundle/release/app-release.aab" }
}
