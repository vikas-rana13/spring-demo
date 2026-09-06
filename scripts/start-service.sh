#!/bin/bash
set -euo pipefail

# Enterprise Defaults (Falls back to safe values for manual SSH execution)
PORT="${APP_PORT:-8080}"
APP_DIR="${APP_DIR:-/home/$(whoami)/app}"
JAR_NAME="${JAR_NAME:-app.jar}"
APP_LOG="${APP_LOG:-app.log}"

echo "============================================="
echo "=== Service Lifecycle Management ==="
echo "=== Target Directory: ${APP_DIR} ==="
echo "=== Application Port: ${PORT} ==="
echo "============================================="

cd "${APP_DIR}"

# 1. Dynamic Port Search (Port-centric Process Cleanup)
echo "Locating processes bound to Port ${PORT}..."
if command -v lsof &> /dev/null; then
    OLD_PID=$(lsof -t -i:"${PORT}" || true)
else
    # Fallback to netstat if running on a restricted environment
    OLD_PID=$(netstat -nlp 2>/dev/null | grep ":${PORT} " | awk '{print $7}' | cut -d'/' -f1 || true)
fi

if [ -n "${OLD_PID}" ]; then
    echo "Found active application running on PID: ${OLD_PID}"
    echo "Terminating service gracefully (SIGTERM)..."
    kill -15 "${OLD_PID}"
    
    # Grace period loop (up to 10s)
    for i in {1..10}; do
        if ! kill -0 "${OLD_PID}" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    
    # Hard kill if process refuses to close
    if kill -0 "${OLD_PID}" 2>/dev/null; then
        echo "Process did not shut down in time. Force-killing (SIGKILL)..."
        kill -9 "${OLD_PID}"
    fi
    echo "Previous instance terminated successfully."
else
    echo "No active processes detected on Port ${PORT}."
fi

# 2. Run Application Background Daemon
if [ -f "${JAR_NAME}" ]; then
    echo "Launching service daemon..."
    nohup java -jar "${JAR_NAME}" > "${APP_LOG}" 2>&1 &
    NEW_PID=$!
    echo "Daemon active with PID: ${NEW_PID}"
else
    echo "Error: Target executable JAR (${APP_DIR}/${JAR_NAME}) is missing!" >&2
    exit 1
fi

# 3. Dynamic Health / Startup Verification
echo "Verifying health check socket binding..."
sleep 5
if lsof -i:"${PORT}" &> /dev/null; then
    echo "=== SUCCESS: Service launched successfully on Port ${PORT}! ==="
else
    echo "=== ERROR: Service failed to bind to Port ${PORT} within grace period. Check logs in ${APP_DIR}/${APP_LOG} ===" >&2
    exit 1
fi
