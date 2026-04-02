# ============================================================
# Entropy Addict RPG — Automatic Project Fixer
# Run from your Godot project root:
#   cd C:\Users\habil\Documents\entropy-addict-v-3
#   powershell -ExecutionPolicy Bypass -File SETUP.ps1
# ============================================================

$base = $PSScriptRoot
Set-Location $base

function MkDir-Safe($p) { if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Write-File($path, $content) {
    $dir = Split-Path $path
    MkDir-Safe $dir
    [System.IO.File]::WriteAllText((Join-Path $base $path), $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [OK] $path"
}

Write-Host ""
Write-Host "=== Entropy Addict RPG — Auto Setup ===" -ForegroundColor Cyan
Write-Host ""

# ── Create all folders ─────────────────────────────────────────────────────────
Write-Host "[1/4] Creating folder structure..."
@(
    "scripts\globals","scripts\ai","scripts\system",
    "scripts\entities","scripts\ui",
    "scenes\main","scenes\world","scenes\ui",
    "data\prompts","data\dialogue","data\config",
    "resources\themes","resources\constants",
    "assets\fonts","assets\icons","assets\sfx",
    "cache\ai_responses","exports"
) | ForEach-Object { MkDir-Safe $_ }
Write-Host "  Done." -ForegroundColor Green

# ── Copy from entropy-fixed if present ────────────────────────────────────────
Write-Host ""
Write-Host "[2/4] Copying fixed files..."

$src = Join-Path $base "entropy-fixed"
if (!(Test-Path $src)) {
    Write-Host "  [WARN] entropy-fixed folder not found next to SETUP.ps1" -ForegroundColor Yellow
    Write-Host "  Place the downloaded 'entropy-fixed' folder here and re-run." -ForegroundColor Yellow
} else {
    $files = @(
        "scripts\globals\game_state.gd",
        "scripts\ai\ai_manager.gd",
        "scripts\system\combat_manager.gd",
        "scripts\system\world.gd",
        "scripts\system\loot_system.gd",
        "scripts\entities\player_character.gd",
        "scripts\entities\enemy_entity.gd",
        "scripts\ui\main_menu.gd",
        "scripts\ui\character_creation.gd",
        "scripts\ui\prologue.gd",
        "scripts\ui\combat_ui.gd",
        "scripts\ui\hud.gd",
        "scripts\ui\level_up_ui.gd",
        "scenes\main\main_menu.tscn",
        "scenes\world\world.tscn",
        "scenes\ui\character_creation.tscn",
        "scenes\ui\prologue.tscn",
        "scenes\ui\combat_ui.tscn",
        "scenes\ui\level_up_ui.tscn",
        "project.godot"
    )
    foreach ($f in $files) {
        $from = Join-Path $src $f
        $to   = Join-Path $base $f
        if (Test-Path $from) {
            $toDir = Split-Path $to
            MkDir-Safe $toDir
            Copy-Item $from $to -Force
            Write-Host "  [OK] $f" -ForegroundColor Green
        } else {
            Write-Host "  [MISS] $f - not found in entropy-fixed" -ForegroundColor Yellow
        }
    }
}

# ── Delete old misplaced files from root ─────────────────────────────────────
Write-Host ""
Write-Host "[3/4] Removing old root-level script files..."
@("world.gd","ai_manager.gd","enemy_entity.gd","player_character.gd") | ForEach-Object {
    $old = Join-Path $base $_
    if (Test-Path $old) {
        Remove-Item $old -Force
        Write-Host "  [REMOVED] $_" -ForegroundColor DarkGray
    }
}

# ── Write .gitignore and icon ─────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/4] Writing support files..."

Write-File ".gitignore" @"
.godot/
*.translation
*.import
export.cfg
export_presets.cfg
exports/
cache/
.DS_Store
Thumbs.db
*.bak
*.swp
*~
*.log
"@

if (!(Test-Path (Join-Path $base "icon.svg"))) {
    Write-File "icon.svg" @'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
  <rect width="128" height="128" fill="#0d0d14"/>
  <text x="64" y="82" font-size="58" text-anchor="middle" fill="#4a90d9" font-family="monospace">EA</text>
</svg>
'@
} else {
    Write-Host "  icon.svg already exists, skipping."
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DONE. Project structure is now correct." -ForegroundColor Green
Write-Host "============================================================"
Write-Host ""
Write-Host " NEXT - do these 4 things in Godot:" -ForegroundColor White
Write-Host ""
Write-Host " 1. Project > Project Settings > AutoLoad" -ForegroundColor Yellow
Write-Host "    Add these IN ORDER (Singleton checked for all):"
Write-Host "      Name: GameState     Path: res://scripts/globals/game_state.gd"
Write-Host "      Name: AIManager     Path: res://scripts/ai/ai_manager.gd"
Write-Host "      Name: CombatManager Path: res://scripts/system/combat_manager.gd"
Write-Host "      Name: LootSystem    Path: res://scripts/system/loot_system.gd"
Write-Host ""
Write-Host " 2. Project > Project Settings > Application > Run > Main Scene" -ForegroundColor Yellow
Write-Host "    Set to: res://scenes/main/main_menu.tscn"
Write-Host ""
Write-Host " 3. In a SEPARATE terminal (keep it open):" -ForegroundColor Yellow
Write-Host "    ollama serve"
Write-Host ""
Write-Host " 4. Press F5" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to close"