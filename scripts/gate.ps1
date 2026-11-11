# 本地一键门禁：静态门禁 + CodeLinter（需 DevEco Studio / Command Line Tools）
# 用法：powershell -ExecutionPolicy Bypass -File scripts/gate.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  Write-Host '== 1/3 占位文案门禁 ==' -ForegroundColor Cyan
  node scripts/check-coming-soon.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 2/3 分层架构门禁（R-01~R-09） ==' -ForegroundColor Cyan
  node scripts/check-architecture.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 3/3 CodeLinter ==' -ForegroundColor Cyan
  devecocli check lint
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host 'GATE PASS' -ForegroundColor Green
} finally {
  Pop-Location
}
