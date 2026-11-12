# 本地一键门禁：静态门禁 + CodeLinter（需 DevEco Studio / Command Line Tools）
# 用法：powershell -ExecutionPolicy Bypass -File scripts/gate.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  Write-Host '== 1/4 版本一致性门禁（V-01~V-03） ==' -ForegroundColor Cyan
  node scripts/check-version.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 2/4 占位文案门禁 ==' -ForegroundColor Cyan
  node scripts/check-coming-soon.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 3/4 分层架构门禁（R-01~R-09） ==' -ForegroundColor Cyan
  node scripts/check-architecture.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 4/4 CodeLinter ==' -ForegroundColor Cyan
  devecocli check lint
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host 'GATE PASS' -ForegroundColor Green
} finally {
  Pop-Location
}
