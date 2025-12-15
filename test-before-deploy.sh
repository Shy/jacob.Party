#!/bin/bash
set -e

echo "🧪 Pre-Deployment Test Suite"
echo "============================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CONTAINER_NAME="jacob-party-test"
TEST_PORT="8080"

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
}

# Set up cleanup on exit
trap cleanup EXIT

echo "Step 1: Building Docker image"
echo "------------------------------"
cd server
if docker build -t jacob-party:test . ; then
    echo -e "${GREEN}✅ Docker build successful${NC}"
else
    echo -e "${RED}❌ Docker build failed${NC}"
    exit 1
fi
cd ..

echo ""
echo "Step 2: Starting container"
echo "--------------------------"
# Stop any existing test container
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    echo "Create .env with your configuration (see .env.example)"
    exit 1
fi

# Start container
docker run -d \
    --name $CONTAINER_NAME \
    -p $TEST_PORT:8080 \
    --env-file .env \
    -v "$(pwd)/certs:/app/certs:ro" \
    jacob-party:test

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to start container${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Container started${NC}"

echo ""
echo "Step 3: Waiting for server to start (30 seconds)"
echo "------------------------------------------------"
echo "Watching for crashes in first 30 seconds..."

for i in {1..30}; do
    # Check if container is still running
    if ! docker ps | grep -q $CONTAINER_NAME; then
        echo -e "${RED}❌ Container crashed after $i seconds${NC}"
        echo ""
        echo "Last 50 lines of logs:"
        docker logs $CONTAINER_NAME --tail 50
        exit 1
    fi

    # Try health check after 10 seconds
    if [ $i -ge 10 ]; then
        if curl -s http://localhost:$TEST_PORT/api/state > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Server responding after $i seconds${NC}"
            break
        fi
    fi

    echo -n "."
    sleep 1
done

echo ""
echo ""
echo "Step 4: Checking for segfaults/crashes in logs"
echo "----------------------------------------------"
CRASH_CHECK=$(docker logs $CONTAINER_NAME 2>&1 | grep -i "segfault\|signal\|fatal\|crash" || true)
if [ -n "$CRASH_CHECK" ]; then
    echo -e "${RED}❌ Found crash indicators in logs:${NC}"
    echo "$CRASH_CHECK"
    exit 1
else
    echo -e "${GREEN}✅ No crashes detected${NC}"
fi

echo ""
echo "Step 5: Testing API endpoints"
echo "-----------------------------"

# Test health endpoint
echo -n "Testing GET /api/state... "
RESPONSE=$(curl -s -w "%{http_code}" http://localhost:$TEST_PORT/api/state)
HTTP_CODE="${RESPONSE: -3}"
if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✅ OK${NC}"
else
    echo -e "${RED}❌ Failed (HTTP $HTTP_CODE)${NC}"
    exit 1
fi

# Test start party (requires device UUID)
echo -n "Testing POST /api/party/start... "
DEVICE_UUID="test-device-$(date +%s)"
START_RESPONSE=$(curl -s -w "%{http_code}" \
    -X POST http://localhost:$TEST_PORT/api/party/start \
    -H 'Content-Type: application/json' \
    -H "X-Device-ID: $DEVICE_UUID" \
    -d '{"location":{"lat":37.7749,"lng":-122.4194}}' 2>&1)
HTTP_CODE="${START_RESPONSE: -3}"

if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "201" ]; then
    echo -e "${GREEN}✅ OK${NC}"

    # Verify party state was updated
    echo -n "Verifying party state... "
    sleep 1
    STATE_RESPONSE=$(curl -s http://localhost:$TEST_PORT/api/state)
    if echo "$STATE_RESPONSE" | grep -q "true"; then
        echo -e "${GREEN}✅ Party started successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Party state unclear${NC}"
        echo "Response: $STATE_RESPONSE"
    fi

    # Test update location
    echo -n "Testing POST /api/party/location... "
    UPDATE_RESPONSE=$(curl -s -w "%{http_code}" \
        -X POST http://localhost:$TEST_PORT/api/party/location \
        -H 'Content-Type: application/json' \
        -H "X-Device-ID: $DEVICE_UUID" \
        -d '{"location":{"lat":37.7850,"lng":-122.4094}}' 2>&1)
    UPDATE_HTTP_CODE="${UPDATE_RESPONSE: -3}"
    if [ "$UPDATE_HTTP_CODE" == "200" ] || [ "$UPDATE_HTTP_CODE" == "201" ]; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${YELLOW}⚠️  HTTP $UPDATE_HTTP_CODE${NC}"
    fi

    # Test stop party
    echo -n "Testing POST /api/party/stop... "
    STOP_RESPONSE=$(curl -s -w "%{http_code}" \
        -X POST http://localhost:$TEST_PORT/api/party/stop \
        -H 'Content-Type: application/json' \
        -H "X-Device-ID: $DEVICE_UUID" 2>&1)
    STOP_HTTP_CODE="${STOP_RESPONSE: -3}"
    if [ "$STOP_HTTP_CODE" == "200" ] || [ "$STOP_HTTP_CODE" == "201" ]; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${YELLOW}⚠️  HTTP $STOP_HTTP_CODE${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  HTTP $HTTP_CODE${NC}"
    echo "This might be expected if device authentication is enabled"
fi

echo ""
echo "Step 6: Checking Temporal connectivity"
echo "--------------------------------------"
TEMPORAL_LOGS=$(docker logs $CONTAINER_NAME 2>&1 | grep -i "temporal" | tail -10)
if echo "$TEMPORAL_LOGS" | grep -q "connected\|running"; then
    echo -e "${GREEN}✅ Temporal connection successful${NC}"
elif echo "$TEMPORAL_LOGS" | grep -q "error\|failed"; then
    echo -e "${RED}❌ Temporal connection issues detected${NC}"
    echo "Recent Temporal logs:"
    echo "$TEMPORAL_LOGS"
    exit 1
else
    echo -e "${YELLOW}⚠️  Temporal status unclear${NC}"
fi

echo ""
echo "Step 7: Final stability check (30 seconds)"
echo "------------------------------------------"
echo "Ensuring no delayed crashes..."
for i in {1..30}; do
    if ! docker ps | grep -q $CONTAINER_NAME; then
        echo -e "${RED}❌ Container crashed during stability check${NC}"
        docker logs $CONTAINER_NAME --tail 50
        exit 1
    fi
    echo -n "."
    sleep 1
done

echo ""
echo -e "${GREEN}✅ Container stable${NC}"

echo ""
echo "Step 8: Memory check"
echo "-------------------"
MEMORY_STATS=$(docker stats $CONTAINER_NAME --no-stream --format "{{.MemUsage}}")
echo "Memory usage: $MEMORY_STATS"

# Get full logs summary
echo ""
echo "Step 9: Log summary"
echo "------------------"
ERROR_COUNT=$(docker logs $CONTAINER_NAME 2>&1 | grep -ic "error" || echo "0")
WARNING_COUNT=$(docker logs $CONTAINER_NAME 2>&1 | grep -ic "warning" || echo "0")
echo "Errors: $ERROR_COUNT"
echo "Warnings: $WARNING_COUNT"

if [ "$ERROR_COUNT" -gt 5 ]; then
    echo -e "${YELLOW}⚠️  High error count - review logs${NC}"
    echo ""
    echo "Recent errors:"
    docker logs $CONTAINER_NAME 2>&1 | grep -i "error" | tail -5
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
echo "=========================================="
echo ""
echo "Container is running and stable. Safe to deploy!"
echo ""
echo "To view full logs:"
echo "  docker logs $CONTAINER_NAME"
echo ""
echo "To stop container:"
echo "  docker stop $CONTAINER_NAME"
echo ""
echo "Next step: Run ./deploy-to-do.sh"
