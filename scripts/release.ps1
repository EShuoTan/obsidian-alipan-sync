param(
	[switch]$NoPublish
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectName = "alipan-sync"
$ReleaseZipPrefix = "alipan-sync"
$BuildArgs = @("run", "build")
$Assets = @(
	@{ Source = "dist/manifest.json"; Name = "manifest.json" },
	@{ Source = "dist/main.js"; Name = "main.js" },
	@{ Source = "dist/styles.css"; Name = "styles.css" }
)
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Invoke-Checked {
	param(
		[Parameter(Mandatory = $true)][string]$FilePath,
		[Parameter(Mandatory = $true)][string[]]$Arguments,
		[Parameter(Mandatory = $true)][string]$WorkingDirectory
	)

	Push-Location $WorkingDirectory
	try {
		& $FilePath @Arguments
		if ($LASTEXITCODE -ne 0) {
			throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
		}
	} finally {
		Pop-Location
	}
}

function Get-GitOutput {
	param(
		[Parameter(Mandatory = $true)][string[]]$Arguments,
		[Parameter(Mandatory = $true)][string]$WorkingDirectory
	)

	Push-Location $WorkingDirectory
	try {
		$output = & git @Arguments
		if ($LASTEXITCODE -ne 0) {
			throw "Git command failed with exit code ${LASTEXITCODE}: git $($Arguments -join ' ')"
		}
		return $output
	} finally {
		Pop-Location
	}
}

function Get-GitStatusPaths {
	param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

	$status = Get-GitOutput -Arguments @("status", "--porcelain") -WorkingDirectory $WorkingDirectory
	$paths = @()
	foreach ($line in $status) {
		if ($line.Length -lt 4) {
			continue
		}
		$path = $line.Substring(3)
		if ($path.Contains(" -> ")) {
			$path = ($path -split " -> ", 2)[1]
		}
		$paths += ($path -replace "\\", "/")
	}
	return $paths
}

function Assert-OnlyExpectedReleaseChanges {
	param(
		[Parameter(Mandatory = $true)][string]$WorkingDirectory,
		[Parameter(Mandatory = $true)][string[]]$ExpectedPaths
	)

	$dirtyPaths = Get-GitStatusPaths -WorkingDirectory $WorkingDirectory
	$unexpected = @()
	foreach ($path in $dirtyPaths) {
		if ($ExpectedPaths -notcontains $path) {
			$unexpected += $path
		}
	}
	if ($unexpected) {
		throw "Git tree has non-release changes in ${WorkingDirectory}: $($unexpected -join ', ')"
	}
}

function Assert-CommandExists {
	param([Parameter(Mandatory = $true)][string]$Name)

	if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
		throw "Required command not found in PATH: $Name"
	}
}

function Get-ManifestVersion {
	param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

	$manifest = Get-Content -LiteralPath (Join-Path $WorkingDirectory "manifest.json") -Raw | ConvertFrom-Json
	return $manifest.version
}

function Get-HeadVersionTag {
	param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

	$tags = Get-GitOutput -Arguments @("tag", "--points-at", "HEAD") -WorkingDirectory $WorkingDirectory
	foreach ($tag in $tags) {
		if ($tag -match "^\d+\.\d+\.\d+$") {
			return $tag
		}
	}
	return $null
}

function Test-GitTagPointsAtHead {
	param(
		[Parameter(Mandatory = $true)][string]$WorkingDirectory,
		[Parameter(Mandatory = $true)][string]$Version
	)

	$tags = Get-GitOutput -Arguments @("tag", "--points-at", "HEAD") -WorkingDirectory $WorkingDirectory
	return ($tags -contains $Version)
}

function Test-GitHubReleaseExists {
	param(
		[Parameter(Mandatory = $true)][string]$WorkingDirectory,
		[Parameter(Mandatory = $true)][string]$Version
	)

	Push-Location $WorkingDirectory
	try {
		& gh release view $Version *> $null
		return ($LASTEXITCODE -eq 0)
	} catch {
		return $false
	} finally {
		Pop-Location
	}
}

function Get-TrackedReleaseFiles {
	param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

	$candidates = @("package.json", "manifest.json", "versions.json")
	$files = @()
	foreach ($candidate in $candidates) {
		$tracked = Get-GitOutput -Arguments @("ls-files", "--", $candidate) -WorkingDirectory $WorkingDirectory
		if ($tracked) {
			$files += $candidate
		}
	}
	return $files
}

function Restore-PnpmShimNoise {
	param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

	$shimPaths = @(
		"packages/remote-explorer/node_modules/.bin/rslib",
		"packages/remote-explorer/node_modules/.bin/tsc",
		"packages/remote-explorer/node_modules/.bin/tsserver"
	)
	Get-GitOutput -Arguments (@("restore", "--") + $shimPaths) -WorkingDirectory $WorkingDirectory | Out-Null
}

function Bump-Version {
	param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

	$script = @'
const fs = require("node:fs");

function readJson(file) {
	return JSON.parse(fs.readFileSync(file, "utf8"));
}

function writeJson(file, value) {
	fs.writeFileSync(file, JSON.stringify(value, null, "\t") + "\n");
}

function bumpPatch(version) {
	const parts = version.split(".");
	if (parts.length < 2) {
		throw new Error(`Unsupported version: ${version}`);
	}
	const last = Number(parts[parts.length - 1]);
	if (!Number.isInteger(last) || last < 0) {
		throw new Error(`Unsupported version: ${version}`);
	}
	parts[parts.length - 1] = String(last + 1);
	return parts.join(".");
}

const manifest = readJson("manifest.json");
const packageJson = readJson("package.json");
const currentVersion = manifest.version || packageJson.version;
if (!currentVersion) {
	throw new Error("Cannot find current version in manifest.json or package.json");
}

const nextVersion = bumpPatch(currentVersion);
manifest.version = nextVersion;
packageJson.version = nextVersion;
writeJson("manifest.json", manifest);
writeJson("package.json", packageJson);

const versions = fs.existsSync("versions.json") ? readJson("versions.json") : {};
versions[nextVersion] = manifest.minAppVersion;
writeJson("versions.json", versions);

console.log(nextVersion);
'@

	$tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "obsidian-alipan-version-bump-$([System.Guid]::NewGuid().ToString('N')).cjs"
	Set-Content -LiteralPath $tempScript -Value $script -Encoding UTF8
	Push-Location $WorkingDirectory
	try {
		$version = & node $tempScript
		if ($LASTEXITCODE -ne 0) {
			throw "Version bump failed in $WorkingDirectory"
		}
		return ($version | Select-Object -Last 1).Trim()
	} finally {
		Pop-Location
		Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
	}
}

function Start-Or-ResumeReleaseVersion {
	param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

	$trackedReleaseFiles = Get-TrackedReleaseFiles -WorkingDirectory $WorkingDirectory
	$dirtyPaths = Get-GitStatusPaths -WorkingDirectory $WorkingDirectory
	if ($dirtyPaths) {
		Assert-OnlyExpectedReleaseChanges -WorkingDirectory $WorkingDirectory -ExpectedPaths $trackedReleaseFiles
		$version = Get-ManifestVersion -WorkingDirectory $WorkingDirectory
		Write-Host "Continuing existing release changes for $ProjectName at $version"
		return $version
	}

	$headVersionTag = Get-HeadVersionTag -WorkingDirectory $WorkingDirectory
	if ($headVersionTag) {
		Write-Host "Continuing tagged release for $ProjectName at $headVersionTag"
		return $headVersionTag
	}

	$version = Bump-Version -WorkingDirectory $WorkingDirectory
	Write-Host "Bumped $ProjectName to $version"
	return $version
}

function New-ReleaseZip {
	param(
		[Parameter(Mandatory = $true)][string]$WorkingDirectory,
		[Parameter(Mandatory = $true)][string]$Version
	)

	$releaseDir = Join-Path $WorkingDirectory ".release-assets"
	$versionDir = Join-Path $releaseDir $Version
	if (Test-Path $versionDir) {
		Remove-Item -LiteralPath $versionDir -Recurse -Force
	}
	New-Item -ItemType Directory -Path $versionDir | Out-Null

	foreach ($asset in $Assets) {
		$source = Join-Path $WorkingDirectory $asset.Source
		if (-not (Test-Path $source)) {
			throw "Missing release asset: $source"
		}
		Copy-Item -LiteralPath $source -Destination (Join-Path $versionDir $asset.Name)
	}

	$zipPath = Join-Path $releaseDir "$ReleaseZipPrefix-$Version.zip"
	if (Test-Path $zipPath) {
		Remove-Item -LiteralPath $zipPath -Force
	}
	Compress-Archive -Path (Join-Path $versionDir "*") -DestinationPath $zipPath
	return $zipPath
}

Assert-CommandExists -Name "git"
Assert-CommandExists -Name "node"
Assert-CommandExists -Name "pnpm"
if (-not $NoPublish) {
	Assert-CommandExists -Name "gh"
}

Write-Host "==> Releasing $ProjectName from $Root"
Invoke-Checked -FilePath "pnpm" -Arguments @("install", "--frozen-lockfile") -WorkingDirectory $Root
Restore-PnpmShimNoise -WorkingDirectory $Root

$version = Start-Or-ResumeReleaseVersion -WorkingDirectory $Root
Invoke-Checked -FilePath "pnpm" -Arguments $BuildArgs -WorkingDirectory $Root

$zipPath = New-ReleaseZip -WorkingDirectory $Root -Version $version
Write-Host "Prepared release assets and zip: $zipPath"

if ($NoPublish) {
	Write-Host "Release summary: $ProjectName $version local-only"
	exit 0
}

$assetArgs = @()
foreach ($asset in $Assets) {
	$assetArgs += (Join-Path $Root $asset.Source)
}
$assetArgs += $zipPath

if (Test-GitTagPointsAtHead -WorkingDirectory $Root -Version $version) {
	Write-Host "Using existing tag at HEAD: $version"
	Get-GitOutput -Arguments @("push", "origin", "HEAD") -WorkingDirectory $Root | Out-Null
	Get-GitOutput -Arguments @("push", "origin", $version) -WorkingDirectory $Root | Out-Null
} else {
	$tagExists = Get-GitOutput -Arguments @("tag", "--list", $version) -WorkingDirectory $Root
	if ($tagExists) {
		throw "Tag already exists but does not point at HEAD: $version"
	}

	$trackedReleaseFiles = Get-TrackedReleaseFiles -WorkingDirectory $Root
	Get-GitOutput -Arguments (@("add", "--") + $trackedReleaseFiles) -WorkingDirectory $Root | Out-Null
	Get-GitOutput -Arguments @("commit", "-m", "Release $version") -WorkingDirectory $Root | Out-Null
	Get-GitOutput -Arguments @("tag", $version) -WorkingDirectory $Root | Out-Null
	Get-GitOutput -Arguments @("push", "origin", "HEAD") -WorkingDirectory $Root | Out-Null
	Get-GitOutput -Arguments @("push", "origin", $version) -WorkingDirectory $Root | Out-Null
}

if (Test-GitHubReleaseExists -WorkingDirectory $Root -Version $version) {
	Write-Host "GitHub Release already exists: $version"
} else {
	Invoke-Checked -FilePath "gh" -Arguments (@(
		"release", "create", $version
		"--title", $version
		"--notes", "Release $version for manual installation."
	) + $assetArgs) -WorkingDirectory $Root
}

Write-Host "Release summary: $ProjectName $version published"
