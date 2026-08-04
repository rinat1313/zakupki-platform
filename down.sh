#!/usr/bin/env bash
exec "$(cd "$(dirname "$0")" && pwd)/up.sh" --down "$@"
