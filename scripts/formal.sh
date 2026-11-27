#!/bin/bash
# =============================================================================
# Project: ProEm - Open Source Protocol Emulator
# File: scripts/formal.sh
# Type: Script: run every formal proof (SymbiYosys)
# Author: Paul Vincent Bezzina
# Language: Bash
# Description: Runs the prove and cover tasks of every .sby in formal/ and prints one line per proof. With FORMAL_DEEP=1 it
# also runs the long tasks (uart_rx wide, return_path line), which take about 20 minutes together.
# =============================================================================
set -e
cd "$(dirname "$0")/../formal"
fail=0
for f in *.sby; do
  name=${f%.sby}
  tasks="prove cover"
  if [ -n "$FORMAL_DEEP" ]; then
    tasks=""
  fi
  start=$(date +%s)
  if sby -f "$f" $tasks > "$name.log" 2>&1; then
    echo "PASS  $name (${tasks:-all tasks}, $(( $(date +%s) - start ))s)"
  else
    echo "FAIL  $name, see formal/$name.log"
    fail=1
  fi
done
exit $fail
