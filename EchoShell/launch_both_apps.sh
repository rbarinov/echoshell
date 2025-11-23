#!/bin/bash
# Скрипт для запуска обоих приложений одновременно

echo "🚀 Launching iOS + watchOS apps..."

# Парные симуляторы
IPHONE_ID="0BBAFFB2-39DF-4F60-A87D-FDAC000B1030"  # Sym iPhone 16 Pro with Watch
WATCH_ID="8C1B5D18-D2CA-4D93-8409-D6E978D31E8F"   # Sym Apple Watch Ultra 2

# Пути к собранным приложениям
IOS_APP="/Users/roman/Library/Developer/Xcode/DerivedData/Roman's_Second_WatchOS_App-crjoknsipijstnfyntcyjpyxccbq/Build/Products/Debug-iphonesimulator/EchoShell.app"
WATCH_APP="/Users/roman/Library/Developer/Xcode/DerivedData/Roman's_Second_WatchOS_App-crjoknsipijstnfyntcyjpyxccbq/Build/Products/Debug-watchsimulator/EchoShell Watch App.app"

# Запуск Watch приложения
echo "⌚ Installing Watch app..."
xcrun simctl install "$WATCH_ID" "$WATCH_APP"

echo "⌚ Launching Watch app..."
xcrun simctl launch "$WATCH_ID" "rbairnov.Roman-s-Second-WatchOS-App.watchkitapp"

# Небольшая пауза
sleep 2

# Запуск iOS приложения
echo "📱 Installing iOS app..."
xcrun simctl install "$IPHONE_ID" "$IOS_APP"

echo "📱 Launching iOS app..."
xcrun simctl launch "$IPHONE_ID" "rbairnov.Roman-s-Second-WatchOS-App"

echo "✅ Both apps launched!"
echo ""
echo "Now check:"
echo "  📱 iPhone Simulator - should show 'Apple Watch Connected'"
echo "  ⌚ Watch Simulator - should show recording buttons"

