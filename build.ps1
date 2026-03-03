$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗"
Write-Host "║   IRFlow Timeline v2.1 - Windows Build (SQLite-backed)   ║"
Write-Host "╚══════════════════════════════════════════════════════════╝"
Write-Host ""

# ── Prerequisite checker ─────────────────────────────────────────────────────
function Check-Command {
    param([string]$cmd, [string]$install)
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: $cmd is required but not installed."
        Write-Host "  Install with: $install"
        exit 1
    }
}

Check-Command "node" "winget install OpenJS.NodeJS"
Check-Command "npm"  "winget install OpenJS.NodeJS"

$nodeVerString = (node -v).TrimStart('v')
$nodeMajor     = [int]($nodeVerString.Split('.')[0])
if ($nodeMajor -lt 18) {
    Write-Host "  ERROR: Node.js 18+ required (found v$nodeVerString)"
    exit 1
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-Host "  WARNING: Visual Studio Build Tools not detected."
    Write-Host "  Needed for native module compilation (better-sqlite3)."
    Write-Host "  Fix: Run PowerShell as Administrator, then:"
    Write-Host "       npm install --global windows-build-tools"
}

Write-Host "  OK: Node.js $(node -v) | npm $(npm -v)"
Write-Host ""

# ── Install dependencies ─────────────────────────────────────────────────────
Write-Host "  Installing dependencies..."

# Use --engine-strict=false to suppress EBADENGINE warnings
# Temporarily allow non-zero exit codes for npm (it writes warnings to stderr)
$ErrorActionPreference = "Continue"
$installOutput = npm install --engine-strict=false 2>&1
$ErrorActionPreference = "Stop"

# Show only meaningful lines, suppress noise
$installOutput |
    Where-Object { $_ -match "(added \d+|up to date|updated \d+)" } |
    Select-Object -First 5 |
    ForEach-Object { Write-Host "  $_" }

# Check npm actually succeeded by inspecting exit code
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: npm install failed (exit code $LASTEXITCODE)"
    Write-Host "  Run 'npm install' manually to see full output."
    exit 1
}
Write-Host "  Dependencies installed successfully."
Write-Host ""

# ── Rebuild native modules for Electron ──────────────────────────────────────
Write-Host "  Rebuilding native modules for Electron..."
$ErrorActionPreference = "Continue"
$rebuildCmd = ".\node_modules\.bin\electron-rebuild.cmd"
if (Test-Path $rebuildCmd) {
    & $rebuildCmd -f -w better-sqlite3 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
} else {
    npx electron-rebuild -f -w better-sqlite3 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
}
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  ERROR: electron-rebuild failed (exit code $LASTEXITCODE)."
    Write-Host "  Likely cause: missing Visual Studio Build Tools."
    Write-Host "  Fix (run PowerShell as Administrator):"
    Write-Host "       npm install --global windows-build-tools"
    exit 1
}
$ErrorActionPreference = "Stop"
Write-Host "  Native modules rebuilt successfully."
Write-Host ""

# ── Build menu ───────────────────────────────────────────────────────────────
Write-Host "Choose build type:"
Write-Host "  1) Development mode (hot reload + dev tools)"
Write-Host "  2) Quick start (build + run)"
Write-Host "  3) Unpacked folder (no installer)"
Write-Host "  4) Portable .exe (single file, no install needed)"
Write-Host "  5) NSIS installer .exe (standard Windows setup)"
Write-Host ""
$choice = Read-Host "Enter choice [1-5]"

$ErrorActionPreference = "Continue"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "  Starting dev mode..."
        Write-Host "  Renderer: http://localhost:5173"
        Write-Host "  App opens automatically when ready"
        npm run dev
    }
    "2" {
        Write-Host ""
        Write-Host "  Building renderer..."
        npm run build:renderer
        Write-Host "  Starting app..."
        npx electron .
    }
    "3" {
        Write-Host ""
        Write-Host "  Building unpacked folder..."
        npm run build:renderer
        npx electron-builder --win dir
        Write-Host ""
        Write-Host "  Done. Output in: release\win-unpacked\"
        if (Test-Path "release\win-unpacked") { Start-Process "release\win-unpacked" }
    }
    "4" {
        Write-Host ""
        Write-Host "  Building portable .exe..."
        npm run build:renderer
        npx electron-builder --win portable --x64
        Write-Host ""
        Write-Host "  Done. Output in: release\"
        if (Test-Path "release") { Start-Process "release" }
    }
    "5" {
        Write-Host ""
        Write-Host "  Building NSIS installer..."
        npm run dist:win
        Write-Host ""
        Write-Host "  Done. Output in: release\"
        if (Test-Path "release") { Start-Process "release" }
    }
    default {
        Write-Host "  Running quick start..."
        npm run build:renderer
        npx electron .
    }
}
