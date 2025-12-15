#!/bin/bash
set -e

echo "🚀 Jacob Party - Digital Ocean App Platform Deployment"
echo ""

# Check if doctl is installed
if ! command -v doctl &> /dev/null; then
    echo "❌ doctl CLI not found. Install it first:"
    echo "   brew install doctl"
    echo "   doctl auth init"
    exit 1
fi

# Check if logged in
if ! doctl auth list &> /dev/null; then
    echo "❌ Not authenticated with Digital Ocean"
    echo "   Run: doctl auth init"
    exit 1
fi

echo "📋 Step 1: Preparing environment variables"
echo ""

# Check if certs exist
if [ ! -f "certs/client.pem" ] || [ ! -f "certs/client.key" ]; then
    echo "⚠️  Warning: Certificate files not found in certs/"
    echo "   If using mTLS, make sure to:"
    echo "   1. Generate certs (see certs/README.md)"
    echo "   2. Add contents to .do/app.yaml manually"
    echo ""
fi

# Read .env for reference values
if [ -f ".env" ]; then
    echo "✅ Found .env file - using as reference"
    source .env
else
    echo "⚠️  No .env file found - you'll need to configure manually"
fi

echo ""
echo "📝 Step 2: Update .do/app.yaml with your values:"
echo ""
echo "Required changes in .do/app.yaml:"
echo "  1. github.repo: Set to your GitHub repo (e.g., 'username/jasonParty')"
echo "  2. TEMPORAL_HOST: Set to your namespace.tmprl.cloud"
echo "  3. TEMPORAL_NAMESPACE: Set to your namespace"
echo "  4. TEMPORAL_CLIENT_CERT_CONTENT: Paste certificate PEM contents"
echo "  5. TEMPORAL_CLIENT_KEY_CONTENT: Paste private key contents"
echo "  6. GOOGLE_MAPS_API_KEY: Set your Google Maps API key"
echo ""

# Offer to copy cert contents to clipboard (macOS only)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "💡 Quick tip - Copy certificate contents to clipboard:"
    echo "   cat certs/client.pem | pbcopy  # Then paste into app.yaml"
    echo "   cat certs/client.key | pbcopy  # Then paste into app.yaml"
    echo ""
fi

read -p "Have you updated .do/app.yaml with all values? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Please update .do/app.yaml first, then run this script again"
    exit 1
fi

echo ""
echo "🔍 Step 3: Validating app.yaml"
if ! grep -q "REPLACE_WITH" .do/app.yaml; then
    echo "✅ No placeholder values found"
else
    echo "❌ Found REPLACE_WITH placeholders - please update .do/app.yaml"
    grep -n "REPLACE_WITH" .do/app.yaml
    exit 1
fi

echo ""
echo "🚀 Step 4: Deploying to Digital Ocean App Platform"
echo ""

# Check if app already exists
APP_NAME="jacob-party"
if doctl apps list --format Name --no-header | grep -q "^${APP_NAME}$"; then
    echo "📦 Updating existing app: ${APP_NAME}"
    APP_ID=$(doctl apps list --format ID,Name --no-header | grep "${APP_NAME}" | awk '{print $1}')
    doctl apps update "$APP_ID" --spec .do/app.yaml
    echo ""
    echo "✅ App updated successfully!"
else
    echo "📦 Creating new app: ${APP_NAME}"
    doctl apps create --spec .do/app.yaml
    echo ""
    echo "✅ App created successfully!"
fi

echo ""
echo "🔗 Getting app details..."
APP_ID=$(doctl apps list --format ID,Name --no-header | grep "${APP_NAME}" | awk '{print $1}')
echo ""
echo "App ID: ${APP_ID}"
echo "Dashboard: https://cloud.digitalocean.com/apps/${APP_ID}"
echo ""

echo "📊 Deployment will take 5-10 minutes. Monitor progress:"
echo "   doctl apps list-deployments ${APP_ID}"
echo "   doctl apps logs ${APP_ID} jacob-party-server --type run --follow"
echo ""

echo "⏳ Waiting for deployment to start..."
sleep 10

echo ""
echo "📝 Tailing logs (press Ctrl+C to stop)..."
doctl apps logs "$APP_ID" jacob-party-server --type run --follow
