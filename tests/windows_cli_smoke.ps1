$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$jakeExe = Join-Path $repoRoot "zig-out/bin/jake.exe"

if (-not (Test-Path $jakeExe)) {
    throw "Jake binary not found at $jakeExe"
}

function Get-GitBashPath {
    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles "Git/bin/bash.exe"
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} "Git/bin/bash.exe"
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw "Git Bash was not found in the standard Program Files locations."
}

function Invoke-Jake {
    # Note: parameter is named $Arguments (not $Args) because $Args is a PowerShell
    # automatic variable. Declaring `param($Args)` does not actually bind the value
    # to the declared parameter on invocation — `@Args` then splats empty and the
    # external program is run with zero arguments.
    param(
        [string[]] $Arguments,
        [string] $WorkingDirectory
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }

    try {
        $output = & $script:jakeExe @Arguments 2>&1 | Out-String
        return @{
            ExitCode = $LASTEXITCODE
            Output = $output.Trim()
        }
    }
    finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Assert-Success {
    param(
        [hashtable] $Result,
        [string] $Label
    )

    if ($Result.ExitCode -ne 0) {
        throw "$Label failed with exit code $($Result.ExitCode)`n$($Result.Output)"
    }
}

function Assert-Contains {
    param(
        [string] $Text,
        [string] $Needle,
        [string] $Label
    )

    if (-not $Text.Contains($Needle)) {
        throw "$Label did not contain '$Needle'`n$Text"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("jake-windows-smoke-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

$previousPath = $env:PATH
$previousShell = $env:SHELL
$previousUserProfile = $env:USERPROFILE

try {
    $fakeBin = Join-Path $tempRoot "fakebin"
    New-Item -ItemType Directory -Path $fakeBin | Out-Null

    $fakeToolPaths = @(
        (Join-Path $fakeBin "fake-tool.cmd"),
        (Join-Path $tempRoot "fake-tool.cmd")
    )
    foreach ($path in $fakeToolPaths) {
        Set-Content -Path $path -Value "@echo off`r`necho fake-tool`r`n"
    }

    if (-not $env:USERPROFILE -and $env:HOMEDRIVE -and $env:HOMEPATH) {
        $env:USERPROFILE = "$($env:HOMEDRIVE)$($env:HOMEPATH)"
    }

    $env:PATH = "$fakeBin;$($env:PATH)"
    $env:SHELL = Get-GitBashPath

    $completionResult = Invoke-Jake -Arguments @("--completions")
    Assert-Success -Result $completionResult -Label "completion auto-detect"
    Assert-Contains -Text $completionResult.Output -Needle "complete -F _jake jake" -Label "completion auto-detect"

    $jakefilePath = Join-Path $tempRoot "Jakefile"
    @'
task env-check:
    @if env(USERPROFILE)
        echo env-ok
    @else
        exit 1
    @end

task home-check:
    echo {{home()}}

task shell-check:
    echo {{shell_config()}}

task needs-path:
    @needs fake-tool
    echo path-ok

task needs-relative:
    @needs ./fake-tool
    echo relative-ok
'@ | Set-Content -Path $jakefilePath

    $envResult = Invoke-Jake -Arguments @("-f", $jakefilePath, "env-check") -WorkingDirectory $tempRoot
    Assert-Success -Result $envResult -Label "env(USERPROFILE) condition"
    Assert-Contains -Text $envResult.Output -Needle "env-ok" -Label "env(USERPROFILE) condition"

    $homeResult = Invoke-Jake -Arguments @("-f", $jakefilePath, "home-check") -WorkingDirectory $tempRoot
    Assert-Success -Result $homeResult -Label "home() function"
    if ($env:USERPROFILE) {
        Assert-Contains -Text $homeResult.Output -Needle $env:USERPROFILE -Label "home() function"
    }

    $shellResult = Invoke-Jake -Arguments @("-f", $jakefilePath, "shell-check") -WorkingDirectory $tempRoot
    Assert-Success -Result $shellResult -Label "shell_config() function"
    Assert-Contains -Text $shellResult.Output -Needle ".bashrc" -Label "shell_config() function"

    # --- DEBUG: state going into @needs PATH lookup ---
    Write-Host "DEBUG fakeBin=$fakeBin"
    Write-Host "DEBUG fake-tool exists=$(Test-Path (Join-Path $fakeBin 'fake-tool.cmd'))"
    Write-Host "DEBUG PATHEXT=$env:PATHEXT"
    Write-Host "DEBUG PATH first-entry=$($env:PATH.Split(';')[0])"
    $whereResult = & where.exe fake-tool 2>&1 | Out-String
    Write-Host "DEBUG where.exe fake-tool=$whereResult"
    $jakeZdbg = Join-Path $tempRoot "zdbg.txt"
    $env:JAKE_ZDEBUG_FILE = $jakeZdbg
    # --- END DEBUG ---

    $pathNeedsResult = Invoke-Jake -Arguments @("-f", $jakefilePath, "needs-path") -WorkingDirectory $tempRoot

    if (Test-Path $jakeZdbg) {
        Write-Host "DEBUG zdbg file contents:"
        Get-Content $jakeZdbg | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "DEBUG zdbg file not created"
    }
    Remove-Item Env:JAKE_ZDEBUG_FILE -ErrorAction SilentlyContinue
    Assert-Success -Result $pathNeedsResult -Label "@needs PATH lookup"
    Assert-Contains -Text $pathNeedsResult.Output -Needle "path-ok" -Label "@needs PATH lookup"

    $relativeNeedsResult = Invoke-Jake -Arguments @("-f", $jakefilePath, "needs-relative") -WorkingDirectory $tempRoot
    Assert-Success -Result $relativeNeedsResult -Label "@needs relative lookup"
    Assert-Contains -Text $relativeNeedsResult.Output -Needle "relative-ok" -Label "@needs relative lookup"
}
finally {
    $env:PATH = $previousPath

    if ($null -ne $previousShell) {
        $env:SHELL = $previousShell
    }
    else {
        Remove-Item Env:SHELL -ErrorAction SilentlyContinue
    }

    if ($null -ne $previousUserProfile) {
        $env:USERPROFILE = $previousUserProfile
    }
    else {
        Remove-Item Env:USERPROFILE -ErrorAction SilentlyContinue
    }

    Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
}
