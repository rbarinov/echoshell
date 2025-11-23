#!/bin/bash
# Полный workflow: Build + Launch iOS & Watch + Complication support

echo "🔨 Building both apps..."

cd "/Users/roman/work/roman/EchoShell"

# Build Watch app
echo "⌚ Building Watch app..."
xcodebuild -project "EchoShell.xcodeproj" \
    -scheme "EchoShell Watch App" \
    -sdk watchsimulator \
    -configuration Debug \
    -derivedDataPath "./build" \
    ONLY_ACTIVE_ARCH=NO \
    build 2>&1 | grep -E "(BUILD|error:)" | tail -3

# Build iOS app
echo "📱 Building iOS app..."
xcodebuild -project "EchoShell.xcodeproj" \
    -scheme "EchoShell" \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -configuration Debug \
    -derivedDataPath "./build" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    build 2>&1 | grep -E "(BUILD|error:)" | tail -3

echo ""
echo "🚀 Launching apps..."

# Симуляторы
IPHONE_ID="0BBAFFB2-39DF-4F60-A87D-FDAC000B1030"
WATCH_ID="8C1B5D18-D2CA-4D93-8409-D6E978D31E8F"

# Установка и запуск Watch
WATCH_APP="./build/Build/Products/Debug-watchsimulator/EchoShell Watch App.app"
xcrun simctl install "$WATCH_ID" "$WATCH_APP"
echo "⌚ Watch app installed"

WATCH_PID=$(xcrun simctl launch "$WATCH_ID" "rbairnov.Roman-s-Second-WatchOS-App.watchkitapp" 2>&1)
echo "⌚ Watch app launched: $WATCH_PID"

sleep 2

# Установка и запуск iOS
IOS_APP="./build/Build/Products/Debug-iphonesimulator/EchoShell.app"
xcrun simctl install "$IPHONE_ID" "$IOS_APP"
echo "📱 iOS app installed"

IOS_PID=$(xcrun simctl launch "$IPHONE_ID" "rbairnov.Roman-s-Second-WatchOS-App" 2>&1)
echo "📱 iOS app launched: $IOS_PID"

echo ""
echo "✅ Done! Check simulators:"
echo "   📱 iPhone: Settings should sync to Watch"
echo "   ⌚ Watch: Recording should work"
echo ""
echo "To add Complication:"
echo "   1. On Watch simulator, force touch to edit watch face"
echo "   2. Add 'Audio Recorder' complication"
echo "   3. Tap it to launch app"

