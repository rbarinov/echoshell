#!/bin/bash

# Quick Start Script for EchoShell - Voice-Controlled Terminal System

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 EchoShell - Voice-Controlled Terminal System - Quick Start"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if we're in the right directory
if [ ! -d "tunnel-server" ] || [ ! -d "laptop-app" ]; then
    echo "❌ Error: Please run this script from the echoshell directory"
    exit 1
fi

echo "📦 Step 1: Installing tunnel-server dependencies..."
cd tunnel-server
if [ ! -d "node_modules" ]; then
    npm install
else
    echo "   ✅ Dependencies already installed"
fi

echo ""
echo "📦 Step 2: Installing laptop-app dependencies..."
cd ../laptop-app
if [ ! -d "node_modules" ]; then
    npm install
else
    echo "   ✅ Dependencies already installed"
fi

echo ""
echo "🔑 Step 3: Checking environment configuration..."
if [ ! -f ".env" ]; then
    echo "   ⚠️  Creating .env file from template..."
    cp .env.example .env
    echo ""
    echo "   🛠️  IMPORTANT: Edit laptop-app/.env and add your OPENAI_API_KEY"
    echo "   Then run this script again, or start manually with:"
    echo "      cd tunnel-server && npm run dev    # Terminal 1"
    echo "      cd laptop-app && npm run dev       # Terminal 2"
    exit 0
fi

# Check if OPENAI_API_KEY is set
if grep -q "OPENAI_API_KEY=sk-your-actual-key-here" .env || grep -q "OPENAI_API_KEY=$" .env; then
    echo "   ⚠️  Please add your OpenAI API key to laptop-app/.env"
    echo "   Edit the file and replace 'sk-your-actual-key-here' with your actual key"
    exit 1
fi

echo "   ✅ Environment configured"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 To start the system, open TWO terminal windows:"
echo ""
echo "   Terminal 1: cd tunnel-server && npm run dev"
echo "   Terminal 2: cd laptop-app && npm run dev"
echo ""
echo "Then:"
echo "   1. Open iPhone app"
echo "   2. Settings → Switch to Laptop Mode"
echo "   3. Scan QR code from Terminal 2"
echo "   4. Start voice commanding!"
echo ""
echo "📖 For detailed instructions, see: SETUP_GUIDE.md"
echo ""
