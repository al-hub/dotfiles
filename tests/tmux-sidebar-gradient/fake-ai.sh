#!/usr/bin/env bash
set -euo pipefail

control_file="$1"
counter=0

printf 'fake ai session\n'
printf 'ready\n'

while true; do
    mode="$(cat "$control_file" 2>/dev/null || printf 'exit')"
    case "$mode" in
        active)
            counter=$((counter + 1))
            printf 'working %04d\n' "$counter"
            sleep 0.2
            ;;
        waiting)
            sleep 0.2
            ;;
        exit)
            exit 0
            ;;
        *)
            printf 'unknown control mode: %s\n' "$mode" >&2
            exit 2
            ;;
    esac
done
