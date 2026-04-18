#!/usr/bin/env bash

BASE="http://localhost:4221"
echo "=== GET / ==="
curl -si -H "Connection: close" "$BASE/"

echo -e "\n\n=== GET /echo/{str} ==="
curl -si -H "Connection: close" "$BASE/echo/hello-world"

echo -e "\n\n=== GET /user-agent ==="
curl -si -H "Connection: close" -H "User-Agent: my-test-agent/1.0" "$BASE/user-agent"

echo -e "\n\n=== POST /files/{str} (write file) ==="
curl -si -X POST "$BASE/files/test.txt" \
  -H "Connection: close" \
  -H "Content-Type: text/plain" \
  -d "hello from curl"

echo -e "\n\n=== GET /files/{str} (read file) ==="
curl -si -H "Connection: close" "$BASE/files/test.txt"

echo -e "\n\n=== GET /files/{str} (not found) ==="
curl -si -H "Connection: close" "$BASE/files/nonexistent.txt"
