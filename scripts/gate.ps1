# 本地一键门禁：静态门禁 + CodeLinter（需 DevEco Studio / Command Line Tools）
# 用法：powershell -ExecutionPolicy Bypass -File scripts/gate.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  Write-Host '== 1/6 版本一致性门禁（V-01~V-03） ==' -ForegroundColor Cyan
  node scripts/check-version.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 2/6 占位文案门禁 ==' -ForegroundColor Cyan
  node scripts/check-coming-soon.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 3/6 分层架构门禁（R-01~R-09） ==' -ForegroundColor Cyan
  node scripts/check-architecture.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 4/6 深色 token 门禁（D-01~D-03） ==' -ForegroundColor Cyan
  node scripts/check-dark-tokens.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 5/6 对比度门禁（C-01~C-04） ==' -ForegroundColor Cyan
  node scripts/check-contrast.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 6/6 CodeLinter ==' -ForegroundColor Cyan
  devecocli check lint
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host 'GATE PASS' -ForegroundColor Green
} finally {
  Pop-Location
}
