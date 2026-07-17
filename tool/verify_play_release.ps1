param(
    [string]$BundlePath = "build/app/outputs/bundle/release/app-release.aab"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$gradle = Get-Content -Raw -LiteralPath "android/app/build.gradle.kts"
$settings = Get-Content -Raw -LiteralPath "android/settings.gradle.kts"
$mainActivity = Get-Content -Raw -LiteralPath "android/app/src/main/kotlin/kalsubai/wrkfarm/MainActivity.kt"
$pubspec = Get-Content -Raw -LiteralPath "pubspec.yaml"

Require ($settings -match 'com\.android\.application"\) version "9\.') "AGP 9.x or newer is required for Play release builds."
Require ($gradle -match 'ndkVersion = "28\.') "NDK r28 or newer must be pinned."
Require ($gradle -match 'isMinifyEnabled = true') "R8 minification is not enabled for release."
Require ($gradle -match 'isShrinkResources = true') "Release resource shrinking is not enabled."
Require ($gradle -match 'proguard-android-optimize\.txt') "The optimized default R8 rules are not configured."
Require ($mainActivity -match 'WindowCompat\.enableEdgeToEdge\(window\)') "Android edge-to-edge is not enabled in MainActivity."

$deprecatedWindowUsage = rg -n "setStatusBarColor|setNavigationBarColor|LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES" android/app/src 2>$null
Require (-not $deprecatedWindowUsage) "App-owned deprecated edge-to-edge APIs are present:`n$deprecatedWindowUsage"

$razorpayRotation = rg -n "allow_rotation.*true" lib 2>$null
Require ($null -ne $razorpayRotation) "Razorpay checkout must set allow_rotation to true for large screens."

$asyncPreferences = rg -n "SharedPreferencesAsync|SharedPreferencesWithCache" lib 2>$null
Require (-not $asyncPreferences) "DataStore APIs are now used. Remove the libdatastore exclusion and verify its NDK/16 KB compatibility."

Require (Test-Path -LiteralPath $BundlePath) "Release bundle not found: $BundlePath"
$bundleEntries = & jar tf $BundlePath
Require ($LASTEXITCODE -eq 0) "Unable to inspect the release bundle."
Require (-not ($bundleEntries -match 'libdatastore_shared_counter\.so')) "The obsolete DataStore r20 native library is still packaged."

$manifest = "build/app/intermediates/packaged_manifests/release/processReleaseManifestForPackage/AndroidManifest.xml"
Require (Test-Path -LiteralPath $manifest) "Packaged release manifest not found. Build the release bundle first."
$manifestText = Get-Content -Raw -LiteralPath $manifest
Require ($manifestText -notmatch 'screenOrientation=') "A packaged activity restricts screen orientation."
Require ($manifestText -notmatch 'resizeableActivity="false"') "A packaged activity disables resizing."
Require ($manifestText -match 'resizeableActivity="true"') "Large-screen resizability is not explicit in the packaged manifest."
Require ($manifestText -match 'package="kalsubai\.wrkfarm"') "The bundle uses the wrong production application ID."

$version = [regex]::Match($pubspec, '(?m)^version:\s*([^+\s]+)\+(\d+)\s*$')
Require ($version.Success) "pubspec.yaml must contain a versionName+versionCode value."
$versionName = [regex]::Escape($version.Groups[1].Value)
$versionCode = [regex]::Escape($version.Groups[2].Value)
Require ($manifestText -match "android:versionName=`"$versionName`"") "Packaged versionName does not match pubspec.yaml."
Require ($manifestText -match "android:versionCode=`"$versionCode`"") "Packaged versionCode does not match pubspec.yaml."

$mapping = "build/app/outputs/mapping/release/mapping.txt"
Require (Test-Path -LiteralPath $mapping) "R8 mapping output is missing; the bundle was not optimized."

$sdkLine = Get-Content -LiteralPath "android/local.properties" | Where-Object { $_ -like "sdk.dir=*" } | Select-Object -First 1
Require ($null -ne $sdkLine) "sdk.dir is missing from android/local.properties."
$sdk = $sdkLine.Substring("sdk.dir=".Length).Replace("\\", "\")
$objdump = Join-Path $sdk "ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-objdump.exe"
Require (Test-Path -LiteralPath $objdump) "NDK r28 llvm-objdump was not found."

$nativeRoot = "build/app/intermediates/stripped_native_libs/release/stripReleaseDebugSymbols/out/lib"
Require (Test-Path -LiteralPath $nativeRoot) "Stripped release libraries were not found."
$badLibraries = @()
Get-ChildItem -LiteralPath $nativeRoot -Recurse -Filter *.so |
    Where-Object { $_.Directory.Name -in @("arm64-v8a", "x86_64") } |
    ForEach-Object {
    $loads = & $objdump -p $_.FullName | Select-String -Pattern "LOAD"
    if ($loads -match 'align 2\*\*(?:[0-9]|1[0-3])(?:\D|$)') {
        $badLibraries += $_.FullName
    }
}
Require ($badLibraries.Count -eq 0) ("Native libraries below 16 KB ELF alignment:`n" + ($badLibraries -join "`n"))

Write-Host "Play release verification passed: $BundlePath"
