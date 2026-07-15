param(
	[string]$CommitMessage = "build and push changes"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

pnpm build

$Branch = (git branch --show-current).Trim()
if (-not $Branch) {
	throw "Cannot push because the repository is in detached HEAD state."
}

git add -A

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
	Write-Host "No changes to commit. Pushing current branch..."
} else {
	git commit -m $CommitMessage
}

git push origin $Branch
