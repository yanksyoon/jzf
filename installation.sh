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
command -v fzf >/dev/null 2>&1 || { echo "❌ fzf not found. Install it: https://github.com/junegunn/fzf  "; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ jq not found. Install it: sudo apt-get update; sudo apt-get install -y jq;"; exit 1; }

# ────────────── Define Unified "jzf" Function + Completion ──────────────

cat > "$TARGET_FILE" << 'EOF'
# Unified Juju FZF Gateway (installed by install-juju-fzf-unified.sh)

jzf() {
    local cmd="$1"

    case "$cmd" in
        controllers)
            shift
            local controller="$1"
            if [[ -z "$controller" ]]; then
                controller=$(juju controllers --format=json | jq -r '.controllers | keys[]' | \
                        fzf --prompt='🪄 Controller > ' \
                            --pointer='👉' \
                            --height 40% \
                            --cycle \
                            --select-1 \
                            --exit-0 \
                            --no-multi)
            fi
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
            local model="$1"
            if [[ -z "$model" ]]; then
                model=$(juju models --format=json | jq -r '.models[].name' | \
                        fzf --prompt='🪄 Model > ' \
                            --pointer='👉' \
                            --height 40% \
                            --cycle \
                            --select-1 \
                            --exit-0 \
                            --no-multi)
            fi
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
            local unit="$1"
            if [[ -n "$unit" ]]; then
                # User provided unit → skip FZF
                shift  # consume $unit so "$@" is only extra args
            else
                # No unit → show FZF selector
                unit=$(juju status --format=json | jq -r '.applications[] | .units | keys[]' | \
                        fzf --prompt='🪄 Unit > ' \
                            --pointer='👉' \
                            --height 40% \
                            --cycle \
                            --select-1 \
                            --exit-0 \
                            --no-multi)
            fi
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
            local unit="$1"
            if [[ -n "$unit" ]]; then
                shift
                echo "→ juju debug-log -i $unit ${*:+[args: $*]}"
                juju debug-log -i "$unit" "$@"
            else
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
            fi
            ;;

        destroy-model)
            shift
            local model="$1"
            if [[ -n "$model" ]]; then
                shift  # consume $model so "$@" is only extra args
            else
                model=$(juju models --format=json | jq -r '.models[].name' | \
                        fzf --prompt='🪄 Model > ' \
                            --pointer='👉' \
                            --height 40% \
                            --cycle \
                            --select-1 \
                            --exit-0 \
                            --no-multi)
            fi
            if [[ -n "$model" ]]; then
                echo "→ juju destroy-model $model --no-wait --force --destroy-storage --no-prompt ${*:+[args: $*]}"
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

# ────────────── Bash Completion for jzf (self-contained) ──────────────

_jzf_completion() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Known jzf subcommands
    local commands="config controllers models show-unit ssh debug-log destroy-model"

    # If we're at first argument, complete subcommands
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    # Context-aware completion for 2nd+ arguments
    case "${COMP_WORDS[1]}" in
        show-unit|ssh|debug-log)
            if [[ $COMP_CWORD -ge 2 ]]; then
                local units
                units=$(juju status --format=json 2>/dev/null | jq -r '.applications[]?.units|keys[]?' 2>/dev/null)
                if [[ -n "$units" ]]; then
                    COMPREPLY=( $(compgen -W "$units" -- "$cur") )
                fi
            fi
            ;;
        destroy-model|models)
            if [[ $COMP_CWORD -ge 2 ]]; then
                local models
                models=$(juju models --format=json 2>/dev/null | jq -r '.models[].name' 2>/dev/null)
                if [[ -n "$models" ]]; then
                    COMPREPLY=( $(compgen -W "$models" -- "$cur") )
                fi
            fi
            ;;
        config)
            if [[ $COMP_CWORD -ge 2 ]]; then
                local applications
                applications=$(juju status --format=json | jq -r '.applications | keys[]' 2>/dev/null)
                if [[ -n "$applications" ]]; then
                    COMPREPLY=( $(compgen -W "$applications" -- "$cur") )
                fi
            fi
            ;;
        controllers)
            if [[ $COMP_CWORD -ge 2 ]]; then
                local controllers
                controllers=$(juju controllers --format=json 2>/dev/null | jq -r '.controllers|keys[]?' 2>/dev/null)
                if [[ -n "$controllers" ]]; then
                    COMPREPLY=( $(compgen -W "$controllers" -- "$cur") )
                fi
            fi
            ;;
        *)
            # No completion for passthrough commands
            ;;
    esac
}

# Register completion
complete -F _jzf_completion jzf
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
    echo "🎉 Unified Juju FZF Gateway 'jzf' installed successfully with TAB COMPLETION!"
    echo ""
    echo "Usage:"
    echo "  jzf config          → fuzzy show applications config"
    echo "  jzf controllers     → fuzzy switch controller"
    echo "  jzf models          → fuzzy switch model"
    echo "  jzf show-unit       → fuzzy show unit"
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
