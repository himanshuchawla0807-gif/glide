#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build
xcrun swiftc Sources/SearchCore.swift Tests/SearchCoreTests.swift -o .build/core-tests
.build/core-tests
xcrun swiftc Sources/BridgeProtocol.swift Tests/BridgeWireTests.swift -o .build/wire-tests
.build/wire-tests
node Tests/companion.test.mjs
