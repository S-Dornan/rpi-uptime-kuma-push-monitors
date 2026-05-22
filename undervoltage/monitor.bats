#!/usr/bin/env bats

# Copyright (C) 2026 Sam Dornan
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

# monitor.bats

setup() {
  # 1. Create a temporary directory for our mock binaries
  export MOCK_DIR="$(mktemp -d)"
  
  # 2. Prepend our mock directory to the PATH
  export PATH="${MOCK_DIR}:${PATH}"

  # 3. Setup dummy environment variables required by the script
  export CF_CLIENT_ID="dummy_id"
  export CF_CLIENT_SECRET="dummy_secret"
  export PUSH_URL="http://dummy-kuma.local/api/push"
  export PUSH_INTERVAL="60"

  # 4. Mock 'sleep' to break the infinite loop
  # By calling 'exit 0', the script terminates successfully after one loop iteration
  echo '#!/bin/sh' > "${MOCK_DIR}/sleep"
  echo 'exit 0' >> "${MOCK_DIR}/sleep"
  chmod +x "${MOCK_DIR}/sleep"

  # 5. Mock 'curl' to log its arguments to a file so we can inspect them
  export CURL_LOG="${MOCK_DIR}/curl.log"
  echo '#!/bin/sh' > "${MOCK_DIR}/curl"
  echo 'echo "$@" > "${CURL_LOG}"' >> "${MOCK_DIR}/curl"
  chmod +x "${MOCK_DIR}/curl"
}

teardown() {
  # Clean up the temporary directory after each test
  rm -rf "${MOCK_DIR}"
}

@test "Reports UP when hex bit is 0x0" {
  # Mock vcgencmd to simulate a healthy Pi
  echo '#!/bin/sh' > "${MOCK_DIR}/vcgencmd"
  echo 'echo "throttled=0x0"' >> "${MOCK_DIR}/vcgencmd"
  chmod +x "${MOCK_DIR}/vcgencmd"

  # Run the target script
  run /usr/local/bin/monitor.sh

  # Assert the script exited successfully (due to our mocked sleep)
  [ "$status" -eq 0 ]

  # Assert curl was called with the correct status and message
  run grep -q "status=up" "${CURL_LOG}"
  [ "$status" -eq 0 ]
  
  run grep -q "msg=OK" "${CURL_LOG}"
  [ "$status" -eq 0 ]
}

@test "Reports DOWN when hex bit indicates undervoltage (e.g., 0x50000)" {
  # Mock vcgencmd to simulate an undervoltage warning
  echo '#!/bin/sh' > "${MOCK_DIR}/vcgencmd"
  echo 'echo "throttled=0x50000"' >> "${MOCK_DIR}/vcgencmd"
  chmod +x "${MOCK_DIR}/vcgencmd"

  # Run the target script
  run /usr/local/bin/monitor.sh

  # Assert the script exited successfully
  [ "$status" -eq 0 ]

  # Assert curl was called with the DOWN state and the hex code in the message
  run grep -q "status=down" "${CURL_LOG}"
  [ "$status" -eq 0 ]
  
  run grep -q "msg=Hardware_Warning_0x50000" "${CURL_LOG}"
  [ "$status" -eq 0 ]
}

@test "Reports DOWN when vcgencmd binary is missing" {
  # Mock vcgencmd to return a standard command-not-found exit code
  echo '#!/bin/sh' > "${MOCK_DIR}/vcgencmd"
  echo 'exit 127' >> "${MOCK_DIR}/vcgencmd"
  chmod +x "${MOCK_DIR}/vcgencmd"

  # Run the target script
  run /usr/local/bin/monitor.sh

  # Assert the script exited cleanly (handled the error gracefully)
  [ "$status" -eq 0 ]

  # Assert Kuma gets the exact failure reason
  run grep -q "status=down" "${CURL_LOG}"
  [ "$status" -eq 0 ]
  
  run grep -q "msg=Binary_Missing_Or_Error" "${CURL_LOG}"
  [ "$status" -eq 0 ]
}
