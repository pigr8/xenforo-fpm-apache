#!/bin/bash
set -euo pipefail

# Applying desidered PUID to user Nobody
sed -i 's/:1000:100:/:'$PUID':100:/g' /etc/passwd

exec "$@"
