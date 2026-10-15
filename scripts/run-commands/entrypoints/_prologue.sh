#!/usr/bin/env bash
# entrypoints/_prologue.sh — must be concatenated FIRST when building a
# combined mcol run command (before the component scripts and the per-type
# entrypoint). It marks the combined context so the component scripts' self-
# execution guards stay silent; do not run it standalone.

set -euo pipefail
export MCOL_COMBINED=1
