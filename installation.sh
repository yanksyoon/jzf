#!/bin/bash

# ┌─────────────────────────────────────────────────────────────────────┐
# │                                                                     │
# │  Install Unified Juju FZF Gateway: "j"                              │
# │                                                                     │
# │  Usage:                                                             │
# │    j controllers    → fuzzy switch controller                       │
# │    j models         → fuzzy switch model                            │
# │    j ssh [args...]  → fuzzy select unit, then juju ssh [args]       │
# │    j <anything else> → passthrough to juju <anything else>          │
# │                                                                     │
# │  Requirements:                                                      │
# │    - juju CLI installed and configured                              │
# │    - fzf installed                                                  │
# │                                                                     │
# └─────────────────────────────────────────────────────────────────────┘

set -euo pipefail

BASH_CONFIG="${HOME}/.bashrc"
TARGET_FILE="${HOME}/.juju-fzf-unified.bash"

# ────────────── Check Dependencies ──────────────

command -v juju >/dev/null 2>&1 || { echo "❌ juju CLI not found. Please install Juju first."; exit 1; }
command -v fzf >/dev/null 2>&1 || { echo "❌ fzf not found. Install it: https://github.com/junegunn/fzf"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ fzf not found. Install it: sudo apt-get update; sudo apt-get install -y jq;"; exit 1; }

# ────────────── Define Unified "j" Function ──────────────

cat > "$TARGET_FILE" << 'EOF'
# Unified Juju FZF Gateway (installed by install-juju-fzf-unified.sh)

jzf() {
    local cmd="$1"

    case "$cmd" in
        controllers)
            shift
            local controller
            controller=$(juju controllers --format=json | jq -r '.controllers | keys[]' | \
                    fzf --prompt='🪄 Controller > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            if [[ -n "$controller" ]]; then
                echo "→ juju switch $controller"
                juju switch "$controller"
            else
                echo "⚠️  No controller selected."
                return 1
            fi
            ;;

        models)
            shift
            local model
            model=$(juju models --format=json | jq -r '.models[].name' | \
                    fzf --prompt='🪄 Model > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            if [[ -n "$model" ]]; then
                echo "→ juju switch $model"
                juju switch "$model"
            else
                echo "⚠️  No model selected."
                return 1
            fi
            ;;

        ssh)
            shift
            local unit
            unit=$(juju status --format=json | jq -r '.applications[] | .units | keys[]' | \
                    fzf --prompt='🪄 Model > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            if [[ -n "$unit" ]]; then
                echo "→ juju ssh $unit ${*:+[args: $*]}"
                juju ssh "$unit" "$@"
            else
                echo "⚠️  No unit selected."
                return 1
            fi
            ;;

        debug-log)
            shift
            local unit
            unit=$(juju status --format=json | jq -r '.applications[] | .units | keys[]' | \
                    fzf --prompt='🪄 Unit > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            if [[ -n "$unit" ]]; then
                echo "→ juju debug-log -i $unit ${*:+[args: $*]}"
                juju debug-log -i "$unit" "$@"
            else
                echo "→ juju debug-log ${*:+[args: $*]} (no unit selected)"
                juju debug-log "$@"
            fi
            ;;

        destroy-model)
            shift
            local model
            model=$(juju models --format=json | jq -r '.models[].name' | \
                    fzf --prompt='🪄 Model > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            if [[ -n "$model" ]]; then
                echo "→ juju destroy-model $model --no-wait --force --destroy-storage --no-prompt"
                juju destroy-model "$model" --no-wait --force --destroy-storage --no-prompt "$@"
            else
                echo "⚠️  No model selected."
                return 1
            fi
            ;;

        *)
            # Passthrough: delegate everything to original juju
            juju "$@"
            ;;
    esac
}
EOF

# ────────────── Inject into .bashrc ──────────────

if ! grep -q ".juju-fzf-unified.bash" "$BASH_CONFIG" 2>/dev/null; then
    echo "" >> "$BASH_CONFIG"
    echo "# Unified Juju FZF Gateway" >> "$BASH_CONFIG"
    echo "source \"$TARGET_FILE\"" >> "$BASH_CONFIG"
    echo "✅ Added source line to $BASH_CONFIG"
else
    echo "ℹ️  Source line already exists in $BASH_CONFIG"
fi

# ────────────── Source and Notify ──────────────

if [[ -f "$TARGET_FILE" ]]; then
    source "$TARGET_FILE" 2>/dev/null || true
    echo ""
    echo "🎉 Unified Juju FZF Gateway 'jzf' installed successfully!"
    echo ""
    echo "Usage:"
    echo "  jzf controllers     → fuzzy switch controller"
    echo "  jzf models          → fuzzy switch model"
    echo "  jzf ssh [args...]   → fuzzy SSH to unit (supports args like --proxy)"
    echo "  jzf debug-log [args...]→ fuzzy print debug-log of a unit (supports args like --replay)"
    echo "  jzf destroy-model [args...]→ fuzzy destroy model"
    echo "  jzf <anything else> → runs 'juju <anything else>' directly"
    echo ""
    echo "Example:"
    echo "  jzf status"
    echo "  jzf deploy nginx"
    echo "  jzf ssh --proxy"
    echo ""
    echo "To activate now: source ~/.bashrc"
    echo "Or restart your terminal."
else
    echo "❌ Installation failed: target file not created."
    exit 1
fi
