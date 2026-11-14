# 本地一键门禁：静态门禁 + CodeLinter（需 DevEco Studio / Command Line Tools）
# 用法：powershell -ExecutionPolicy Bypass -File scripts/gate.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  Write-Host '== 1/8 版本一致性门禁（V-01~V-03） ==' -ForegroundColor Cyan
  node scripts/check-version.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 2/8 占位文案门禁 ==' -ForegroundColor Cyan
  node scripts/check-coming-soon.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 3/8 分层架构门禁（R-01~R-09） ==' -ForegroundColor Cyan
  node scripts/check-architecture.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 4/8 契约完整性门禁（K-01~K-04） ==' -ForegroundColor Cyan
  node scripts/check-contracts.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 5/8 深色 token 门禁（D-01~D-03） ==' -ForegroundColor Cyan
  node scripts/check-dark-tokens.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 6/8 对比度门禁（C-01~C-04） ==' -ForegroundColor Cyan
  node scripts/check-contrast.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 7/8 合规门禁（X-01~X-04，M13） ==' -ForegroundColor Cyan
  node scripts/check-compliance.mjs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host '== 8/8 CodeLinter ==' -ForegroundColor Cyan
  devecocli check lint
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host 'GATE PASS' -ForegroundColor Green
} finally {
  Pop-Location
}
