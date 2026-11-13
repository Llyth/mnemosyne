#!/usr/bin/env bash
# Builds the project-local Lua 5.1 (the language version of the WoW client) and
# LuaRocks in .lua/, then installs the test runner and the linter at pinned
# versions. Safe to run again, for example after a version below changes. CI
# runs it too.
set -euo pipefail

BUSTED_VERSION=2.2.0-1
LUACHECK_VERSION=1.2.0-1

cd "$(dirname "$0")/.."
# No readline: only the interactive prompt uses it, and its headers are often missing.
uv run --no-sync hererocks .lua --lua 5.1 --luarocks latest --no-readline
.lua/bin/luarocks install busted "$BUSTED_VERSION"
.lua/bin/luarocks install luacheck "$LUACHECK_VERSION"
