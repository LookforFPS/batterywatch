#!/bin/bash

# Runs the HID helper test suites (next to this script) and summarizes.
# Usage: ./run_tests.sh [suite.py ...]   (defaults to all suites)

cd "$(dirname "$(readlink -f "$0")")"

if [ "$#" -gt 0 ]; then
    suites=("$@")
else
    suites=(test_read_hid_devices.py)
fi

failed=0
for suite in "${suites[@]}"; do
    if output=$(python3 "$suite" 2>&1); then
        echo "PASS  $suite  |  $(echo "$output" | tail -1)"
    else
        echo "FAIL  $suite"
        echo "$output" | tail -30
        failed=1
    fi
done

echo
if [ "$failed" -eq 0 ]; then
    echo "All HID helper test suites passed."
else
    echo "One or more HID helper test suites failed."
    exit 1
fi
