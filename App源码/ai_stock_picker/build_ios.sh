#!/bin/bash
# ==============================================
# 蓝图极智 AI 选股 - iOS IPA 构建脚本
# ==============================================
# 运行环境要求: macOS + Xcode 14+
# 首次运行: chmod +x build_ios.sh && ./build_ios.sh
# ==============================================

set -e

echo "========================================="
echo "  蓝图极智 AI 选股 - iOS IPA 构建"
echo "========================================="

# 1. 检查 macOS 环境
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 此脚本仅支持 macOS 环境"
    exit 1
fi

# 2. 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ 未找到 Flutter，正在安装 Flutter 3.0.0..."
    git clone -b 3.0.0 --depth 1 https://github.com/flutter/flutter.git /tmp/flutter-3.0.0
    export PATH="/tmp/flutter-3.0.0/bin:$PATH"
fi

FLUTTER_VERSION=$(flutter --version 2>/dev/null | head -1)
echo "✅ Flutter: $FLUTTER_VERSION"

# 3. 检查 Xcode
if ! xcode-select -p &> /dev/null; then
    echo "❌ 未找到 Xcode，请先安装 Xcode 14+"
    exit 1
fi
echo "✅ Xcode: $(xcodebuild -version | head -1)"

# 4. 安装依赖
echo ""
echo "📦 安装 Flutter 依赖..."
flutter clean
flutter pub get

# 5. 检查 iOS 项目
if [ ! -d "ios" ]; then
    echo "📁 创建 iOS 平台目录..."
    flutter create --platforms=ios .
fi

echo "✅ iOS 项目已就绪"

# 6. 构建 Release IPA
echo ""
echo "🔨 开始构建 iOS Release..."
flutter build ios --release --no-codesign 2>&1

# 7. 查找生成的 Runner.app
RUNNER_APP=$(find build/ios -name "Runner.app" -type d 2>/dev/null | head -1)

if [ -z "$RUNNER_APP" ]; then
    echo ""
    echo "⚠️  Runner.app 未找到，尝试以 debug 模式构建..."
    flutter build ios --debug --no-codesign
    RUNNER_APP=$(find build/ios -name "Runner.app" -type d 2>/dev/null | head -1)
fi

if [ -z "$RUNNER_APP" ]; then
    echo "❌ Runner.app 构建失败"
    echo "请尝试在 Xcode 中打开 ios/Runner.xcworkspace 手动构建"
    exit 1
fi

echo "✅ Runner.app: $RUNNER_APP"

# 8. 生成 IPA
echo ""
echo "📱 生成 IPA 文件..."
mkdir -p build/ios/ipa/Payload
cp -R "$RUNNER_APP" build/ios/ipa/Payload/
cd build/ios/ipa
zip -qr "../../蓝图极智-v2.0.2.ipa" Payload/
cd ../../..

IPA_PATH=$(ls build/ios/蓝图极智-v2.0.2.ipa 2>/dev/null || ls build/蓝图极智-v2.0.2.ipa 2>/dev/null)

if [ -n "$IPA_PATH" ]; then
    IPA_SIZE=$(du -h "$IPA_PATH" | cut -f1)
    echo ""
    echo "========================================="
    echo "  ✅ IPA 构建成功！"
    echo "  📁 路径: $IPA_PATH"
    echo "  📦 大小: $IPA_SIZE"
    echo "========================================="
    echo ""
    echo "安装方式:"
    echo "  1. 通过 Xcode 安装到设备:"
    echo "     Xcode → Window → Devices → 拖入 $IPA_PATH"
    echo ""
    echo "  2. 通过 Apple Configurator 2 安装"
    echo ""
    echo "  3. 如需分发 (TestFlight/企业签名):"
    echo "     - 在 Xcode 中配置签名证书"
    echo "     - Archive → Distribute App"
    echo ""
else
    echo ""
    echo "⚠️  IPA 打包可能未完全成功"
    echo "请手动打包: cd build/ios/ipa && zip -qr ../../蓝图极智-v2.0.2.ipa Payload/"
fi
