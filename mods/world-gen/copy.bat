@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
echo ========================================
echo 复制Mod到Steam DST目录
echo ========================================
echo.

set "SOURCE_DIR=%~dp0"
set "TARGET_PARENT=C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods"
set "TARGET_DIR=!TARGET_PARENT!\world-gen"

echo 源目录: %SOURCE_DIR%
echo 目标目录: !TARGET_DIR!
echo.

REM 检查目标目录的父目录是否存在
if not exist "!TARGET_PARENT!" (
    echo [错误] 找不到Steam DST目录: !TARGET_PARENT!
    echo 请确认：
    echo 1. Steam已安装
    echo 2. DST已安装
    echo 3. 路径是否正确
    echo.
    pause
    exit /b 1
)

echo 正在复制...
REM 如果目标目录已存在，先删除
if exist "!TARGET_DIR!" (
    echo 目标目录已存在，将覆盖...
    rmdir /S /Q "!TARGET_DIR!" 2>nul
)

REM 创建目标目录
mkdir "!TARGET_DIR!" 2>nul

REM 使用xcopy复制文件
xcopy /E /I /Y "%SOURCE_DIR%*" "!TARGET_DIR!\" >nul 2>&1

if !ERRORLEVEL! EQU 0 (
    echo.
    echo [成功] Mod已复制到Steam目录！
    echo.
    echo 下一步：
    echo 1. 启动游戏
    echo 2. 在Mods菜单中启用"World Gen"
    echo 3. 创建新世界测试
    echo.
) else (
    echo.
    echo [错误] 复制失败，错误代码: !ERRORLEVEL!
    echo 可能的原因：
    echo 1. 需要管理员权限
    echo 2. 目标目录被占用
    echo 3. 磁盘空间不足
    echo.
    echo 尝试以管理员身份运行此脚本
    echo.
    pause
)

endlocal

