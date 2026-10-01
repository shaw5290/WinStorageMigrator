@echo off
chcp 936 >nul
setlocal EnableDelayedExpansion

:: --------------------------------------------------
:: 0. 锁定 PowerShell 绝对路径
:: --------------------------------------------------
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell"

:: --------------------------------------------------
:: 1. 自动检查并提升管理员权限
:: --------------------------------------------------
fltmc >nul 2>&1
if %errorLevel% neq 0 (
    echo 正在请求管理员权限...
    "%PS_EXE%" -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

:: --------------------------------------------------
:: 2. 基础路径配置
:: --------------------------------------------------
set "SOURCE_DIR=%USERPROFILE%"
set "TARGET_DIR=D:%USERPROFILE:~2%"

set "DIR_BAK=_bak"
set "FILE_BAK=.bak"

:MainMenu
cls
echo ===================================================
echo     全量用户目录与文件迁移映射工具 (WinStorageMigrator)
echo ===================================================
echo 当前来源: %SOURCE_DIR%
echo 当前目标: %TARGET_DIR%
echo ===================================================
echo [1] 开始全量迁移与更新映射 (全路径修复版)
echo [2] 清理 源目录 (C盘) 的备份残留 (*_bak)
echo [3] 清理 目标目录 (D盘) 的备份残留
echo [4] 强制提权并删除 C:\Windows.old
echo [5] 赋予管理员完全控制权限
echo [6] 创建新项目目录并建立快捷映射 (mklink)
echo [0] 退出程序
echo ===================================================
set "CHOICE="
set /p CHOICE="请输入对应数字并回车: "

if defined CHOICE set "CHOICE=!CHOICE:"=!"

if "!CHOICE!"=="1" goto DoMigrate
if "!CHOICE!"=="2" goto SetupCleanupSource
if "!CHOICE!"=="3" goto SetupCleanupTarget
if "!CHOICE!"=="4" goto DeleteWindowsOld
if "!CHOICE!"=="5" goto GrantPermission
if "!CHOICE!"=="6" goto CreateProjectLink
if "!CHOICE!"=="0" exit /b 0

goto MainMenu

:SetupCleanupSource
set "CLEANUP_DIR=%SOURCE_DIR%"
goto DoCleanup

:SetupCleanupTarget
set "CLEANUP_DIR=%TARGET_DIR%"
goto DoCleanup

:: ==========================================
:: [功能 1] 执行迁移与映射
:: ==========================================
:DoMigrate
echo.
echo ===================================================
echo 正在生成迁移核心脚本，请稍候...
echo ===================================================

set "PS_CORE_FILE=%TEMP%\migrator_core_%RANDOM%.ps1"
if exist "%PS_CORE_FILE%" del /f /q "%PS_CORE_FILE%"

>> "%PS_CORE_FILE%" echo $sourceDir = '%SOURCE_DIR%'
>> "%PS_CORE_FILE%" echo $targetDir = '%TARGET_DIR%'
>> "%PS_CORE_FILE%" echo $roboExe = "$env:SystemRoot\System32\robocopy.exe"
>> "%PS_CORE_FILE%" echo $ignorePatterns = @('AppData', 'Application Data', 'Local Settings', 'Start Menu', 'Cookies', 'Recent', 'SendTo', 'NetHood', 'PrintHood', 'Templates', '3D Objects', 'NTUSER.DAT*', 'ntuser.ini*', 'usrclass.dat*', 'desktop.ini', 'My Documents', '「开始」菜单')
>> "%PS_CORE_FILE%" echo $excludeSubDirs = @('Tencent Files', 'xwechat_files', 'Cache', 'CrashDumps')
>> "%PS_CORE_FILE%" echo.
>> "%PS_CORE_FILE%" echo function Process-Item {
>> "%PS_CORE_FILE%" echo     param([System.IO.FileSystemInfo]$item)
>> "%PS_CORE_FILE%" echo     $itemName = $item.Name
>> "%PS_CORE_FILE%" echo.
>> "%PS_CORE_FILE%" echo     $isIgnored = $false
>> "%PS_CORE_FILE%" echo     foreach ($pattern in $ignorePatterns) {
>> "%PS_CORE_FILE%" echo         if ($itemName -like $pattern) { $isIgnored = $true; break }
>> "%PS_CORE_FILE%" echo     }
>> "%PS_CORE_FILE%" echo     if ($isIgnored -or $itemName.EndsWith('_bak') -or $itemName.EndsWith('.bak')) {
>> "%PS_CORE_FILE%" echo         Write-Host "[跳过忽略/系统关键项] $itemName" -ForegroundColor Gray
>> "%PS_CORE_FILE%" echo         return
>> "%PS_CORE_FILE%" echo     }
>> "%PS_CORE_FILE%" echo.
>> "%PS_CORE_FILE%" echo     $srcPath = $item.FullName
>> "%PS_CORE_FILE%" echo     $expPath = Join-Path $targetDir $itemName
>> "%PS_CORE_FILE%" echo.
>> "%PS_CORE_FILE%" echo     if ($item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
>> "%PS_CORE_FILE%" echo         $curTarget = (Get-Item -LiteralPath $srcPath -Force).Target
>> "%PS_CORE_FILE%" echo         if ($curTarget -is [array]) { $curTarget = $curTarget[0] }
>> "%PS_CORE_FILE%" echo         if ($curTarget) {
>> "%PS_CORE_FILE%" echo             $curNorm = $curTarget.TrimEnd('\')
>> "%PS_CORE_FILE%" echo             $expNorm = $expPath.TrimEnd('\')
>> "%PS_CORE_FILE%" echo             if ($curNorm -ieq $expNorm) {
>> "%PS_CORE_FILE%" echo                 Write-Host "[已正确映射] $itemName =^> $curNorm" -ForegroundColor Green
>> "%PS_CORE_FILE%" echo                 return
>> "%PS_CORE_FILE%" echo             } else {
>> "%PS_CORE_FILE%" echo                 Write-Host ""
>> "%PS_CORE_FILE%" echo                 Write-Host "【重定向映射】检测到 $itemName 旧目标: $curNorm" -ForegroundColor Yellow
>> "%PS_CORE_FILE%" echo                 Write-Host "               准备重定向至新目标: $expNorm" -ForegroundColor Yellow
>> "%PS_CORE_FILE%" echo                 if (-not (Test-Path -LiteralPath $expNorm)) {
>> "%PS_CORE_FILE%" echo                     $null = New-Item -ItemType Directory -Path $expNorm -Force
>> "%PS_CORE_FILE%" echo                 }
>> "%PS_CORE_FILE%" echo                 if ((Test-Path -LiteralPath $curNorm) -and ($curNorm -ine $expNorm)) {
>> "%PS_CORE_FILE%" echo                     Write-Host "  -[数据合并] 正在将旧目标文件迁移合并至 $expNorm ..." -ForegroundColor Cyan
>> "%PS_CORE_FILE%" echo                     $null = ^& $roboExe "$curNorm" "$expNorm" /E /COPY:DAT /R:1 /W:1 /XD $excludeSubDirs /NJH /NJS /NDL /NC /NS /NP
>> "%PS_CORE_FILE%" echo                 }
>> "%PS_CORE_FILE%" echo                 Write-Host "  -[解绑旧链接] 清理原软链接..." -ForegroundColor Cyan
>> "%PS_CORE_FILE%" echo                 if ($item.PSIsContainer) {
>> "%PS_CORE_FILE%" echo                     [System.IO.Directory]::Delete($srcPath)
>> "%PS_CORE_FILE%" echo                 } else {
>> "%PS_CORE_FILE%" echo                     [System.IO.File]::Delete($srcPath)
>> "%PS_CORE_FILE%" echo                 }
>> "%PS_CORE_FILE%" echo                 Write-Host "  -[创建新映射] 建立至 $expNorm 的 Junction 联接..." -ForegroundColor Cyan
>> "%PS_CORE_FILE%" echo                 if ($item.PSIsContainer) {
>> "%PS_CORE_FILE%" echo                     $null = New-Item -ItemType Junction -Path $srcPath -Value $expNorm -Force
>> "%PS_CORE_FILE%" echo                 } else {
>> "%PS_CORE_FILE%" echo                     $null = New-Item -ItemType SymbolicLink -Path $srcPath -Value $expNorm -Force
>> "%PS_CORE_FILE%" echo                 }
>> "%PS_CORE_FILE%" echo                 Write-Host "  -[成功] $itemName 已重新绑定至 $expNorm ！" -ForegroundColor Green
>> "%PS_CORE_FILE%" echo                 return
>> "%PS_CORE_FILE%" echo             }
>> "%PS_CORE_FILE%" echo         }
>> "%PS_CORE_FILE%" echo     }
>> "%PS_CORE_FILE%" echo.
>> "%PS_CORE_FILE%" echo     Write-Host ""
>> "%PS_CORE_FILE%" echo     Write-Host "【新迁移项目】正在处理: $itemName" -ForegroundColor White
>> "%PS_CORE_FILE%" echo     $suffix = if ($item.PSIsContainer) { '_bak' } else { '.bak' }
>> "%PS_CORE_FILE%" echo     $bakPath = $srcPath + $suffix
>> "%PS_CORE_FILE%" echo     try {
>> "%PS_CORE_FILE%" echo         Rename-Item -LiteralPath $srcPath -NewName (Split-Path $bakPath -Leaf) -ErrorAction Stop
>> "%PS_CORE_FILE%" echo         Write-Host "  -[步骤1] 成功重命名备份: $bakPath" -ForegroundColor Cyan
>> "%PS_CORE_FILE%" echo     } catch {
>> "%PS_CORE_FILE%" echo         Write-Host "  -[失败] 目录或文件正在被系统/程序占用，已安全跳过。" -ForegroundColor Red
>> "%PS_CORE_FILE%" echo         return
>> "%PS_CORE_FILE%" echo     }
>> "%PS_CORE_FILE%" echo.
>> "%PS_CORE_FILE%" echo     if ($item.PSIsContainer) {
>> "%PS_CORE_FILE%" echo         Write-Host "  -[步骤2] 复制数据到 D 盘..." -ForegroundColor Cyan
>> "%PS_CORE_FILE%" echo         if (-not (Test-Path -LiteralPath $expPath)) { $null = New-Item -ItemType Directory -Path $expPath -Force }
>> "%PS_CORE_FILE%" echo         $null = ^& $roboExe "$bakPath" "$expPath" /E /COPY:DAT /R:1 /W:1 /XD $excludeSubDirs /NJH /NJS /NDL /NC /NS /NP
>> "%PS_CORE_FILE%" echo         if (Test-Path -LiteralPath $expPath) {
>> "%PS_CORE_FILE%" echo             Write-Host "  -[步骤3] 创建 Junction 目录联接..." -ForegroundColor Cyan
>> "%PS_CORE_FILE%" echo             $null = New-Item -ItemType Junction -Path $srcPath -Value $expPath -Force
>> "%PS_CORE_FILE%" echo             Write-Host "  -[成功] $itemName 迁移与映射完毕！" -ForegroundColor Green
>> "%PS_CORE_FILE%" echo         } else {
>> "%PS_CORE_FILE%" echo             Write-Host "  -[错误] 复制文件失败，还原备份目录..." -ForegroundColor Red
>> "%PS_CORE_FILE%" echo             Rename-Item -LiteralPath $bakPath -NewName $itemName
>> "%PS_CORE_FILE%" echo         }
>> "%PS_CORE_FILE%" echo     } else {
>> "%PS_CORE_FILE%" echo         Write-Host "  -[步骤2] 复制文件到 D 盘..." -ForegroundColor Cyan
>> "%PS_CORE_FILE%" echo         if (-not (Test-Path -LiteralPath (Split-Path $expPath))) { $null = New-Item -ItemType Directory -Path (Split-Path $expPath) -Force }
>> "%PS_CORE_FILE%" echo         Copy-Item -LiteralPath $bakPath -Destination $expPath -Force
>> "%PS_CORE_FILE%" echo         Write-Host "  -[步骤3] 创建符号链接..." -ForegroundColor Cyan
>> "%PS_CORE_FILE%" echo         $null = New-Item -ItemType SymbolicLink -Path $srcPath -Value $expPath -Force
>> "%PS_CORE_FILE%" echo         Write-Host "  -[成功] $itemName 迁移与映射完毕！" -ForegroundColor Green
>> "%PS_CORE_FILE%" echo     }
>> "%PS_CORE_FILE%" echo }
>> "%PS_CORE_FILE%" echo.
>> "%PS_CORE_FILE%" echo foreach ($item in (Get-ChildItem -LiteralPath $sourceDir -Force)) { Process-Item $item }

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_CORE_FILE%"

if exist "%PS_CORE_FILE%" del /f /q "%PS_CORE_FILE%"

echo.
echo ===================================================
echo 迁移与映射流程执行结束！
echo ===================================================
pause
goto MainMenu

:: ==========================================
:: [功能 2/3] 清理套娃与残留备份
:: ==========================================
:DoCleanup
echo.
echo ===================================================
echo 即将强行清理 [%CLEANUP_DIR%] 下的备份数据！
echo 包含规则: 带有 "%DIR_BAK%" 的目录，及 "%FILE_BAK%" 的文件。
echo ===================================================
set "CONFIRM="
set /p CONFIRM="确认执行清理? [Y/N]: "
if defined CONFIRM set "CONFIRM=!CONFIRM:"=!"

if /I not "!CONFIRM!"=="Y" (
    echo [提示] 已取消清理。
    pause
    goto MainMenu
)

echo.
for /d %%D in ("!CLEANUP_DIR!\*%DIR_BAK%*") do (
    echo     -[删除] 目录: %%~nxD
    rmdir /s /q "%%D"
)

for %%F in ("!CLEANUP_DIR!\*%FILE_BAK%*") do (
    echo     -[删除] 文件: %%~nxF
    del /f /q "%%F"
)

echo.
echo 清理完毕！
pause
goto MainMenu

:: ==========================================
:: [功能 4] 删除 C:\Windows.old
:: ==========================================
:DeleteWindowsOld
echo.
set "TARGET_OLD=C:\Windows.old"

if not exist "%TARGET_OLD%" (
    echo [提示] 找不到 %TARGET_OLD%，该目录可能已被清理。
    pause
    goto MainMenu
)

set "CONFIRM="
set /p CONFIRM="彻底删除 %TARGET_OLD%？[Y/N]: "
if defined CONFIRM set "CONFIRM=!CONFIRM:"=!"

if /I "!CONFIRM!"=="Y" (
    takeown /F "%TARGET_OLD%" /A /R /D Y >nul 2>&1
    icacls "%TARGET_OLD%" /grant *S-1-5-32-544:F /T /C /Q >nul 2>&1
    rd /s /q "%TARGET_OLD%"
    echo 已尝试删除。
) else (
    echo 已取消。
)
pause
goto MainMenu

:: ==========================================
:: [功能 5] 赋予管理员完全控制权限
:: ==========================================
:GrantPermission
echo.
set "TARGET_DIR_PERM="
set /p TARGET_DIR_PERM="请输入目录路径 (直接回车默认处理当前目录): "

if "%TARGET_DIR_PERM%"=="" set "TARGET_DIR_PERM=%cd%"
set "TARGET_DIR_PERM=%TARGET_DIR_PERM:"=%"

if not exist "%TARGET_DIR_PERM%" (
    echo [错误] 找不到指定的目录: %TARGET_DIR_PERM%
    pause
    goto MainMenu
)

takeown /F "%TARGET_DIR_PERM%" /A /R /D Y >nul 2>&1
icacls "%TARGET_DIR_PERM%" /grant *S-1-5-32-544:F /T /C /Q >nul 2>&1
echo 权限修改完成！
pause
goto MainMenu

:: ==========================================
:: [功能 6] 创建项目目录并建立快捷映射
:: ==========================================
:CreateProjectLink
echo.
:InputProjectName
set "PROJECT_NAME="
set /p PROJECT_NAME="1. 请输入你要创建的项目名称: "
if defined PROJECT_NAME set "PROJECT_NAME=!PROJECT_NAME:"=!"

if "%PROJECT_NAME%"=="" goto InputProjectName

set "PROJECT_SOURCE=D:\workspace\postal\code\%PROJECT_NAME%"

if not exist "%PROJECT_SOURCE%" mkdir "%PROJECT_SOURCE%"

set "DO_LINK="
set /p DO_LINK="2. 是否创建快捷映射 (mklink)? [Y/N] (默认Y): "
if defined DO_LINK set "DO_LINK=!DO_LINK:"=!"
if /I "!DO_LINK!"=="N" (
    pause
    goto MainMenu
)

set "LINK_BASE="
set /p LINK_BASE="3. 映射目标父目录 (默认 C:\project): "
if "%LINK_BASE%"=="" set "LINK_BASE=C:\project"
set "LINK_BASE=%LINK_BASE:"=%"

set "LINK_DIR=%LINK_BASE%\%PROJECT_NAME%"

if not exist "%LINK_BASE%" mkdir "%LINK_BASE%"

if exist "%LINK_DIR%" (
    rmdir "%LINK_DIR%" 2>nul || rmdir /s /q "%LINK_DIR%"
)

mklink /J "%LINK_DIR%" "%PROJECT_SOURCE%"
echo [成功] 映射完成: %LINK_DIR% -^> %PROJECT_SOURCE%
pause
goto MainMenu