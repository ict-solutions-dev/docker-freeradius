#!/bin/bash

# Enable debug output
exec 2>/tmp/handle-restart.log
set -x

send_response() {
    local status="$1"
    local message="$2"
    local content_length=${#message}
    printf "HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" "$status" "$content_length" "$message"
}

# Read the request line by line, handling both \n and \r\n
IFS= read -r request || exit 1

# Log the request for debugging
echo "Received request: $request" >&2

if ! echo "$request" | grep -q "^POST /restart HTTP/1.1"; then
    send_response "405 Method Not Allowed" "Only POST /restart is supported"
    exit 1
fi

# Read headers until empty line
auth_header=""
while IFS= read -r line || [ -n "$line" ]; do
    # Remove carriage returns
    line="${line%$'\r'}"
    [ -z "$line" ] && break
    if [[ "$line" =~ ^Authorization:\ (.*)$ ]]; then
        auth_header="${BASH_REMATCH[1]}"
    fi
done

# Log authentication attempt
echo "Auth header: $auth_header" >&2
echo "Expected token: Bearer ${CONTROL_TOKEN}" >&2

expected_token="Bearer ${CONTROL_TOKEN}"

if [ -z "${CONTROL_TOKEN}" ]; then
    send_response "500 Internal Server Error" "Control token not configured"
    exit 1
fi

if [ "$auth_header" != "$expected_token" ]; then
    send_response "401 Unauthorized" "Invalid token"
    exit 1
fi

# Find freeradius PID
FreeRADIUS_PID=$(pgrep freeradius)
if [ -z "$FreeRADIUS_PID" ]; then
    send_response "500 Internal Server Error" "FreeRADIUS server not running"
    exit 1
fi

# Send SIGHUP to reload configuration
kill -HUP "$FreeRADIUS_PID"

send_response "200 OK" "FreeRADIUS server reloaded"
exit 0
