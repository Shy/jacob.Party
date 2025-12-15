#!/bin/bash
set -e

echo "🔧 Preparing deployment configuration"
echo "======================================"
echo ""

# Check prerequisites
if [ ! -f ".env" ]; then
    echo "❌ .env file not found"
    echo "   Copy .env.example to .env and fill in your values"
    exit 1
fi

if [ ! -f "certs/client.pem" ] || [ ! -f "certs/client.key" ]; then
    echo "❌ Certificate files not found in certs/"
    echo "   Generate certificates first (see certs/README.md)"
    exit 1
fi

# Source .env to get values
source .env

# Check required values
REQUIRED_VARS=(
    "TEMPORAL_HOST"
    "TEMPORAL_NAMESPACE"
    "GOOGLE_MAPS_API_KEY"
)

MISSING_VARS=()
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        MISSING_VARS+=("$VAR")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "❌ Missing required environment variables in .env:"
    for VAR in "${MISSING_VARS[@]}"; do
        echo "   - $VAR"
    done
    exit 1
fi

echo "✅ Environment variables validated"
echo ""

# Prompt for GitHub repo
echo "📦 GitHub Configuration"
echo "----------------------"
read -p "Enter your GitHub repo (e.g., username/jasonParty): " GITHUB_REPO

if [ -z "$GITHUB_REPO" ]; then
    echo "❌ GitHub repo is required"
    exit 1
fi

echo ""
echo "🔐 Processing certificates"
echo "-------------------------"

# Read certificate contents
CLIENT_CERT=$(cat certs/client.pem)
CLIENT_KEY=$(cat certs/client.key)

echo "✅ Certificates loaded"
echo ""

# Create app.yaml with actual values
echo "📝 Generating .do/app.yaml with your configuration"
echo "-------------------------------------------------"

cat > .do/app.yaml << EOF
name: jacob-party
region: nyc

services:
  - name: jacob-party-server
    github:
      repo: ${GITHUB_REPO}
      branch: main
      deploy_on_push: true

    source_dir: /
    dockerfile_path: server/Dockerfile

    http_port: 8080

    instance_count: 1
    instance_size_slug: basic-xs

    health_check:
      http_path: /api/state
      initial_delay_seconds: 30
      period_seconds: 30
      timeout_seconds: 10
      success_threshold: 1
      failure_threshold: 3

    envs:
      - key: APP_NAME
        value: "jacob"

      - key: SERVER_HOST
        value: "0.0.0.0"

      - key: SERVER_PORT
        value: "8080"

      - key: TEMPORAL_TLS_ENABLED
        value: "true"

      - key: TEMPORAL_HOST
        value: "${TEMPORAL_HOST}"

      - key: TEMPORAL_NAMESPACE
        value: "${TEMPORAL_NAMESPACE}"

      - key: TEMPORAL_PORT
        value: "${TEMPORAL_PORT:-7233}"

      - key: TEMPORAL_TASK_QUEUE
        value: "${TEMPORAL_TASK_QUEUE:-party-queue}"

      - key: TEMPORAL_CLIENT_CERT_CONTENT
        type: SECRET
        value: |
$(echo "$CLIENT_CERT" | sed 's/^/          /')

      - key: TEMPORAL_CLIENT_KEY_CONTENT
        type: SECRET
        value: |
$(echo "$CLIENT_KEY" | sed 's/^/          /')

      - key: GOOGLE_MAPS_API_KEY
        type: SECRET
        value: "${GOOGLE_MAPS_API_KEY}"

      - key: ALLOWED_DEVICE_IDS
        value: "${ALLOWED_DEVICE_IDS:-}"

# Uncomment and configure when you're ready to add a custom domain:
# domains:
#   - domain: party.yourdomain.com
#     type: PRIMARY
EOF

echo "✅ Configuration file created: .do/app.yaml"
echo ""

# Add to .gitignore if not already there
if ! grep -q "^.do/app.yaml$" .gitignore 2>/dev/null; then
    echo ".do/app.yaml" >> .gitignore
    echo "✅ Added .do/app.yaml to .gitignore (contains secrets)"
else
    echo "✅ .do/app.yaml already in .gitignore"
fi

echo ""
echo "=========================================="
echo "✅ Deployment configuration ready!"
echo "=========================================="
echo ""
echo "Your app will deploy from: ${GITHUB_REPO}"
echo ""
echo "⚠️  IMPORTANT: Do NOT commit .do/app.yaml (contains secrets)"
echo ""
echo "Next steps:"
echo "  1. Review .do/app.yaml to verify values"
echo "  2. Run: ./test-before-deploy.sh (optional but recommended)"
echo "  3. Run: ./deploy-to-do.sh"
echo ""
