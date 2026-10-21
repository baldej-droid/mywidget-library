param(
    [ValidateSet('all','demo','dice')][string]$Widget = 'all',
    [string]$Godot = $env:GODOT_BIN,
    [switch]$RebakeDice
)
$ErrorActionPreference = 'Stop'
$libraryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Godot) {
    $workspaceGodot = Join-Path $libraryRoot '../tools/godot/Godot_v4.5.2-stable_win64_console.exe'
    $Godot = if (Test-Path $workspaceGodot) { (Resolve-Path $workspaceGodot).Path } else { 'godot' }
}
$buildRoot = Join-Path $libraryRoot '.build'
New-Item -ItemType Directory -Force "$buildRoot/temp", "$buildRoot/profile", "$libraryRoot/downloads", "$libraryRoot/docs/screenshots" | Out-Null
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$previousAppData = $env:APPDATA
function Invoke-Godot([string[]]$Arguments) {
    & $Godot @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Godot failed: $Arguments" }
}
try {
    $env:TEMP = "$buildRoot/temp"
    $env:TMP = $env:TEMP
    $env:APPDATA = "$buildRoot/profile"
    $selectedWidgets = if ($Widget -eq 'all') { @('demo','dice') } else { @($Widget) }
    foreach ($widgetName in $selectedWidgets) {
        $sourceDir = Join-Path $libraryRoot "sources/$widgetName"
        $assetDir = Join-Path $libraryRoot "assets/$widgetName"
        $packageDir = Join-Path $buildRoot "packages/$widgetName"
        New-Item -ItemType Directory -Force $packageDir,$assetDir | Out-Null
        $manifestPath = Join-Path $libraryRoot "manifests/$widgetName.json"
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        if ($widgetName -eq 'demo') {
            Copy-Item $manifestPath "$sourceDir/metadata.json" -Force
            Invoke-Godot @('--headless','--path',$sourceDir,'--script','tests/test_demo.gd')
            foreach ($language in @('ru','en')) {
                Invoke-Godot @('--path',$sourceDir,'--','--locale',$language,'--showcase','--capture',"$libraryRoot/docs/screenshots/demo-$language.png")
            }
        } else {
            if ($RebakeDice) { Invoke-Godot @('--headless','--path',$sourceDir,'--script','tools/bake_models.gd') }
            Invoke-Godot @('--headless','--path',$sourceDir,'--script','tests/test_dice.gd')
            Invoke-Godot @('--path',$sourceDir,'--script','tests/test_touch_render.gd')
            Invoke-Godot @('--path',$sourceDir,'--','--result','6','--capture',"$libraryRoot/docs/screenshots/dice.png")
            Invoke-Godot @('--path',$sourceDir,'--','--sides','2','--capture',"$libraryRoot/docs/screenshots/coin.png")
        }
        Invoke-Godot @('--path',$sourceDir,'--script','tools/render_art.gd','--','--icon','--output',"$assetDir/avatar.png")
        Invoke-Godot @('--path',$sourceDir,'--script','tools/render_art.gd','--','--output',"$assetDir/banner.png")
        Invoke-Godot @('--headless','--path',$sourceDir,'--export-pack','Android',"$packageDir/$($manifest.files.pck)")
        Invoke-Godot @('--headless','--main-pack',"$packageDir/$($manifest.files.pck)",'--quit-after','3')
        Copy-Item $manifestPath "$packageDir/meta.json" -Force
        Copy-Item "$assetDir/avatar.png","$assetDir/banner.png" $packageDir -Force
        $archivePath = Join-Path $libraryRoot "downloads/$widgetName-$($manifest.version).zip"
        Compress-Archive -Path "$packageDir/*" -DestinationPath $archivePath -Force
        Write-Output "BUILT $archivePath"
    }
    $catalogItems = foreach ($widgetName in @('demo','dice')) {
        $manifest = Get-Content "$libraryRoot/manifests/$widgetName.json" -Raw | ConvertFrom-Json
        $archivePath = Join-Path $libraryRoot "downloads/$widgetName-$($manifest.version).zip"
        if (Test-Path $archivePath) {
            [ordered]@{
                magicId = $manifest.magicId
                name = $manifest.name
                version = $manifest.version
                description = $manifest.description
                downloadUrl = "https://github.com/baldej-droid/mywidget-library/raw/refs/heads/main/downloads/$widgetName-$($manifest.version).zip"
                avatarUrl = "https://raw.githubusercontent.com/baldej-droid/mywidget-library/main/assets/$widgetName/avatar.png"
                bannerUrl = "https://raw.githubusercontent.com/baldej-droid/mywidget-library/main/assets/$widgetName/banner.png"
                size = (Get-Item $archivePath).Length
                sha256 = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    [ordered]@{schemaVersion=1; widgets=@($catalogItems)} | ConvertTo-Json -Depth 8 | Set-Content "$libraryRoot/catalog.json" -Encoding utf8
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    $env:APPDATA = $previousAppData
}
