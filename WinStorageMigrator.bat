@echo off
setlocal EnableDelayedExpansion

:: --------------------------------------------------
:: 0. 修复管理员模式下的工作目录偏移问题
:: --------------------------------------------------
cd /d "%~dp0"

:: --------------------------------------------------
:: 1. 基础配置区
:: --------------------------------------------------
set "SOURCE_DIR=C:\Users\shaw"
set "TARGET_DIR=D:\Users\shaw"

:: 备份后缀配置 (含防套娃截取长度)
set "DIR_BAK=_bak"
set "FILE_BAK=.bak"
set "BAK_LEN=4"

:: 黑名单配置 (用空格分隔；若名字有空格用双引号包裹)
set IGNORE_LIST=AppData "Application Data" "Local Settings" "Start Menu" Cookies Recent SendTo NetHood PrintHood Templates "3D Objects"

:: --------------------------------------------------
:: 2. 管理员权限检查
:: --------------------------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [错误] 权限不足！请右键选择 "以管理员身份运行"。
    pause
    exit /b 1
)

:: ==========================================
:: 交互式主菜单
:: ==========================================
:MainMenu
cls
echo ===================================================
echo   全量用户目录与文件迁移映射工具 (WinStorageMigrator)
echo ===================================================
echo 当前来源: %SOURCE_DIR%
echo 当前目标: %TARGET_DIR%
echo 拦截规则: 备份后缀设为 [%DIR_BAK%] 和 [%FILE_BAK%]
echo 忽略黑名单: %IGNORE_LIST%
echo 当前工作目录: %cd%
echo ===================================================
echo [1] 开始全量迁移与映射 (包含黑名单过滤与防套娃)
echo [2] 清理 源目录 (C盘) 的备份残留
echo [3] 清理 目标目录 (D盘) 的套娃垃圾
echo [4] 强制提权并删除 C:\Windows.old (释放系统空间)
echo [5] 赋予管理员完全控制权限 (默认当前目录，可指定)
echo [6] 创建新项目目录并建立快捷映射 (mklink)
echo [0] 退出程序
echo ===================================================
set "CHOICE="
set /p CHOICE="请输入对应数字并回车: "

if "%CHOICE%"=="1" goto DoMigrate
if "%CHOICE%"=="2" goto SetupCleanupSource
if "%CHOICE%"=="3" goto SetupCleanupTarget
if "%CHOICE%"=="4" goto DeleteWindowsOld
if "%CHOICE%"=="5" goto GrantPermission
if "%CHOICE%"=="6" goto CreateProjectLink
if "%CHOICE%"=="0" exit /b 0

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
echo 正在深度扫描 [%SOURCE_DIR%] ...
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

rem -----------------------------------------
rem 阶段一：处理原生一级目录 (应用黑名单与防套娃)
rem -----------------------------------------
for /d %%D in ("%SOURCE_DIR%\*") do (
    set "ITEM_NAME=%%~nxD"
    set "SKIP="
    
    rem 1. 拦截黑名单目录
    for %%I in (%IGNORE_LIST%) do (
        if /I "!ITEM_NAME!"=="%%~I" set "SKIP=1"
    )
    
    rem 2. 拦截带有备份后缀的文件夹 (防套娃)
    if /I "!ITEM_NAME:~-%BAK_LEN%!"=="%DIR_BAK%" set "SKIP=1"
    
    rem 3. 拦截已经是重解析点 (Junction/Symlink) 的目录
    fsutil reparsepoint query "%%D" >nul 2>&1
    if !errorLevel! equ 0 set "SKIP=1"
    
    if defined SKIP (
        echo [跳过] 黑名单/备份目录/已映射: !ITEM_NAME!
    ) else (
        echo.
        echo 【目录】正在处理: !ITEM_NAME!
        
        rem 尝试备份原文件夹
        ren "%%D" "!ITEM_NAME!%DIR_BAK%" 2>nul
        if exist "%%D" (
            echo   -[失败] 目录被系统死锁，已安全跳过。
        ) else (
            echo   -[步骤1] 已备份为: !ITEM_NAME!%DIR_BAK%
            echo   -[步骤2] 正在迁移数据...
            robocopy "%SOURCE_DIR%\!ITEM_NAME!%DIR_BAK%" "%TARGET_DIR%\!ITEM_NAME!" /E /COPY:DAT /R:1 /W:1 /NJH /NJS /NDL /NC /NS /NP >nul
            echo   -[步骤3] 创建 mklink /J...
            mklink /J "%%D" "%TARGET_DIR%\!ITEM_NAME!" >nul
            echo   -[成功] 目录映射完毕！
        )
    )
)

rem -----------------------------------------
rem 阶段二：处理原生单体文件 (应用黑名单与防套娃)
rem -----------------------------------------
for %%F in ("%SOURCE_DIR%\*") do (
    set "ITEM_NAME=%%~nxF"
    set "SKIP="
    
    rem 1. 拦截黑名单文件
    for %%I in (%IGNORE_LIST%) do (
        if /I "!ITEM_NAME!"=="%%~I" set "SKIP=1"
    )
    
    rem 2. 拦截带有备份后缀的文件 (防套娃)
    if /I "!ITEM_NAME:~-%BAK_LEN%!"=="%FILE_BAK%" set "SKIP=1"
    
    rem 3. 拦截已经是符号链接的文件
    fsutil reparsepoint query "%%F" >nul 2>&1
    if !errorLevel! equ 0 set "SKIP=1"
    
    if defined SKIP (
        echo [跳过] 黑名单/备份文件/已映射: !ITEM_NAME!
    ) else (
        echo.
        echo 【文件】正在处理: !ITEM_NAME!
        
        rem 尝试备份原文件
        ren "%%F" "!ITEM_NAME!%FILE_BAK%" 2>nul
        if exist "%%F" (
            echo   -[失败] 文件正在运行或被锁定，已安全跳过。
        ) else (
            echo   -[步骤1] 已备份为: !ITEM_NAME!%FILE_BAK%
            echo   -[步骤2] 正在迁移数据...
            copy /Y "%SOURCE_DIR%\!ITEM_NAME!%FILE_BAK%" "%TARGET_DIR%\!ITEM_NAME!" >nul
            echo   -[步骤3] 创建 mklink...
            mklink "%%F" "%TARGET_DIR%\!ITEM_NAME!" >nul
            echo   -[成功] 文件映射完毕！
        )
    )
)

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
echo 即将强制深度清理 [%CLEANUP_DIR%] 下的备份垃圾！
echo 包含规则: 带有 "%DIR_BAK%" 的目录，及 "%FILE_BAK%" 的文件。
echo 【警告】删除后不可从回收站恢复！
echo ===================================================
set "CONFIRM="
set /p CONFIRM="确认执行清理? [Y/N]: "

if /I not "!CONFIRM!"=="Y" (
    echo [提示] 已取消清理。
    pause
    goto MainMenu
)

echo.
echo ---------------------------------------------------
echo [清理 1/2] 正在检索并删除备份目录...
for /d %%D in ("!CLEANUP_DIR!\*%DIR_BAK%*") do (
    echo   -[删除] 目录: %%~nxD
    rmdir /s /q "%%D"
)

echo ---------------------------------------------------
echo [清理 2/2] 正在检索并删除备份文件...
for %%F in ("!CLEANUP_DIR!\*%FILE_BAK%*") do (
    echo   -[删除] 文件: %%~nxF
    del /f /q "%%F"
)

echo.
echo ===================================================
echo [%CLEANUP_DIR%] 备份与套娃垃圾清理完毕！
echo ===================================================
pause
goto MainMenu


:: ==========================================
:: [功能 4] 删除 C:\Windows.old
:: ==========================================
:DeleteWindowsOld
echo.
echo ===================================================
set "TARGET_OLD=C:\Windows.old"

if not exist "%TARGET_OLD%" (
    echo [提示] 找不到 %TARGET_OLD%，该目录可能已被清理。
    echo.
    pause
    goto MainMenu
)

echo 【警告】即将强行夺取权限并彻底删除 %TARGET_OLD% ！
set "CONFIRM="
set /p CONFIRM="是否确认执行？[Y/N]: "

if /I "%CONFIRM%"=="Y" goto ExecDeleteOld
echo [提示] 已取消删除操作。
echo.
pause
goto MainMenu

:ExecDeleteOld
echo.
echo [步骤 1/3] 正在强制获取所有权 (此步骤耗时较长，请耐心等待)...
takeown /F "%TARGET_OLD%" /A /R /D Y >nul 2>&1

echo [步骤 2/3] 正在赋予管理员完全控制权限...
icacls "%TARGET_OLD%" /grant *S-1-5-32-544:F /T /C /Q >nul 2>&1

echo [步骤 3/3] 正在执行彻底物理删除...
rd /s /q "%TARGET_OLD%"

if exist "%TARGET_OLD%" (
    echo [警告] 部分文件被系统底层死锁，无法彻底删除。请尝试重启电脑后再次执行。
) else (
    echo [成功] %TARGET_OLD% 已被彻底删除，C 盘空间已释放！
)
echo.
pause
goto MainMenu


:: ==========================================
:: [功能 5] 赋予管理员完全控制权限
:: ==========================================
:GrantPermission
echo.
echo ===================================================
set "TARGET_DIR="
set /p TARGET_DIR="请输入需要提权的目录路径 (直接回车默认处理当前目录): "

rem 如果直接回车，赋值为当前路径
if "%TARGET_DIR%"=="" set "TARGET_DIR=%cd%"

rem 路径处理：去除用户误输入的双引号
set "TARGET_DIR=%TARGET_DIR:"=%"

if not exist "%TARGET_DIR%" (
    echo [错误] 找不到指定的目录: %TARGET_DIR%
    echo.
    pause
    goto MainMenu
)

echo.
echo 准备为 [%TARGET_DIR%] 及其所有子文件赋予最高控制权限。
set "CONFIRM="
set /p CONFIRM="是否确认执行？[Y/N]: "

if /I "%CONFIRM%"=="Y" goto ExecGrantPerm
echo [提示] 已取消提权操作。
echo.
pause
goto MainMenu

:ExecGrantPerm
echo.
echo [步骤 1/2] 正在将所有权强行分配给管理员组...
takeown /F "%TARGET_DIR%" /A /R /D Y >nul 2>&1

echo [步骤 2/2] 正在授予完全控制权限 (Full Control)...
icacls "%TARGET_DIR%" /grant *S-1-5-32-544:F /T /C /Q >nul 2>&1

echo [成功] 权限修改完毕！你现在可以自由修改、移动或删除该目录下的文件了。
echo.
pause
goto MainMenu


:: ==========================================
:: [功能 6] 创建项目目录并建立快捷映射
:: ==========================================
:CreateProjectLink
echo.
echo ===================================================
echo           创建项目目录并(可选)自定义快捷映射
echo ===================================================
echo.

:InputProjectName
set "PROJECT_NAME="
set /p PROJECT_NAME="1. 请输入你要创建的项目名称: "

if "%PROJECT_NAME%"=="" (
    echo [错误] 名称不能为空，请重新输入！
    echo.
    goto InputProjectName
)

set "PROJECT_SOURCE=D:\workspace\postal\code\%PROJECT_NAME%"

echo.
echo ----------------------------------------
echo 项目名称: %PROJECT_NAME%
echo 真实路径: %PROJECT_SOURCE%
echo ----------------------------------------
echo.

if not exist "%PROJECT_SOURCE%" (
    echo [执行] 正在 D 盘创建真实代码目录...
    mkdir "%PROJECT_SOURCE%"
    echo [成功] 真实目录创建完毕！
) else (
    echo [提示] 真实目录 "%PROJECT_SOURCE%" 已经存在。
)

echo.

:AskProjectLink
set "DO_LINK="
set /p DO_LINK="2. 是否为该项目创建快捷映射 (mklink)? [Y/N] (默认Y): "
if /I "%DO_LINK%"=="N" (
    echo [提示] 已跳过映射创建。
    pause
    goto MainMenu
)

:InputProjectLinkBase
set "LINK_BASE="
set /p LINK_BASE="3. 请输入映射目标父目录 (直接回车使用默认路径 C:\project): "

if "%LINK_BASE%"=="" set "LINK_BASE=C:\project"
set "LINK_BASE=%LINK_BASE:"=%"

set "LINK_DIR=%LINK_BASE%\%PROJECT_NAME%"

echo.
echo 准备将 [%LINK_DIR%] 映射到真实路径...

if not exist "%LINK_BASE%" (
    echo [执行] 映射的基础目录不存在，正在自动创建 "%LINK_BASE%"...
    mkdir "%LINK_BASE%"
)

if exist "%LINK_DIR%" (
    echo.
    echo [警告] 目标映射路径已被占用: %LINK_DIR%
    set "DO_OVERWRITE="
    set /p DO_OVERWRITE="是否删除旧文件夹并重新覆盖映射? [Y/N] (默认N): "
    if /I not "!DO_OVERWRITE!"=="Y" (
        echo [提示] 已取消覆盖，跳过映射操作。
        pause
        goto MainMenu
    )
    
    echo [执行] 正在删除旧目录/链接...
    rmdir /s /q "%LINK_DIR%"
    
    if exist "%LINK_DIR%" (
        echo [错误] 删除失败！请检查文件夹是否被其他程序占用。
        pause
        goto MainMenu
    )
)

echo [执行] 正在创建快捷目录联接...
mklink /J "%LINK_DIR%" "%PROJECT_SOURCE%"
if !errorLevel! equ 0 (
    echo [成功] 映射完成！你可以通过自定义路径直接访问代码了。
) else (
    echo [失败] 创建链接时发生错误。
)

echo.
pause
goto MainMenu