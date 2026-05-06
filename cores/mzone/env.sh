#!/bin/bash

# Source this from anywhere inside the mzone core:
#   source env.sh

MZONE_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MZONE_ENV_PWD="$PWD"
cd "$MZONE_ENV_DIR/../.."
source ./setprj.sh
cd "$MZONE_ENV_PWD"

if [ -d "$HOME/github/verilator/bin" ]; then
    case ":$PATH:" in
        *":$HOME/github/verilator/bin:"*) ;;
        *) export PATH="$HOME/github/verilator/bin:$PATH" ;;
    esac
fi

unset MZONE_ENV_DIR
unset MZONE_ENV_PWD
