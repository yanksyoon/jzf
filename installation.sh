#!/bin/bash

# ┌─────────────────────────────────────────────────────────────────────┐
# │                                                                     │
# │  Install Unified Juju FZF Gateway: "j"                              │
# │  Works on: Bash, Zsh, Fish                                          │
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
# │    - jq installed                                                   │
# │                                                                     │
# └─────────────────────────────────────────────────────────────────────┘

set -euo pipefail

# Detect current shell
CURRENT_SHELL="$(basename "$SHELL")"

case "$CURRENT_SHELL" in
    bash)   CONFIG_FILE="${HOME}/.bashrc" ;;
    zsh)    CONFIG_FILE="${HOME}/.zshrc" ;;
    fish)   CONFIG_FILE="${HOME}/.config/fish/config.fish" ;;
    *)      echo "❌ Unsupported shell: $CURRENT_SHELL"; exit 1 ;;
esac

TARGET_FILE_BASH_ZSH="${HOME}/.juju-fzf-unified.bash"
TARGET_FILE_FISH="${HOME}/.config/fish/functions/j.fish"

# ────────────── Check Dependencies ──────────────

command -v juju >/dev/null 2>&1 || { echo "❌ juju CLI not found. Please install Juju first."; exit 1; }
command -v fzf >/dev/null 2>&1 || { echo "❌ fzf not found. Install it: https://github.com/junegunn/fzf"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ jq not found. Install it: sudo apt-get update && sudo apt-get install -y jq"; exit 1; }

# ────────────── Define Unified "j" Function (Bash/Zsh) ──────────────

mkdir -p "$(dirname "$TARGET_FILE_BASH_ZSH")"

cat > "$TARGET_FILE_BASH_ZSH" << 'EOF'
# Unified Juju FZF Gateway (installed by installer)

j() {
    local cmd="$1"

    # If no args, show help
    if [[ $# -eq 0 ]]; then
        _j_show_help
        return 0
    fi

    case "$cmd" in
        help|--help|-h)
            _j_show_help
            return 0
            ;;

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
                shift
            else
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
                shift
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
            juju "$@"
            ;;
    esac
}

# ────────────── HELP FUNCTION ──────────────

_j_show_help() {
    cat << 'HELP'
🚀 Unified Juju FZF Gateway — "j"

Smart fuzzy-selector wrapper for Juju CLI with TAB completion.

USAGE:
    j [COMMAND] [ARGS...]

COMMANDS:
    help, -h, --help           → Show this help
    controllers                → Fuzzy switch Juju controller
    models                     → Fuzzy switch Juju model
    ssh [UNIT] [juju-args...]  → SSH to unit (fuzzy select if no unit given)
    debug-log [UNIT] [...]     → Show debug-log for unit (fuzzy if no unit)
    destroy-model [MODEL] [...]→ Destroy model (fuzzy if no model given)
    <anything else>            → Passthrough to "juju <anything else>"

TAB COMPLETION:
    j <TAB>                    → Complete subcommands
    j ssh <TAB>                → Complete unit names
    j destroy-model <TAB>      → Complete model names

EXAMPLES:
    j controllers              → fuzzy-select and switch controller
    j models                   → fuzzy-select and switch model
    j ssh                      → fuzzy-select unit, then SSH
    j ssh ubuntu/0 --proxy     → SSH directly with args
    j status                   → runs "juju status"
    j deploy nginx             → runs "juju deploy nginx"
    j destroy-model dev        → destroys model "dev" (no FZF)

💡 PRO TIPS:
    → Already aliased as "j" (no need to alias)
    → Restart shell or run: source ~/.bashrc (or ~/.zshrc)

HELP
}

EOF

# ────────────── Bash/Zsh Completion ──────────────

if [[ "$CURRENT_SHELL" == "bash" ]]; then
    cat >> "$TARGET_FILE_BASH_ZSH" << 'EOF'

_j_completion() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local commands="config controllers models show-unit ssh debug-log destroy-model help"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        show-unit|ssh|debug-log)
            if [[ $COMP_CWORD -ge 2 ]]; then
                local units
                units=$(juju status --format=json 2>/dev/null | jq -r '.applications[]?.units|keys[]?' 2>/dev/null)
                [[ -n "$units" ]] && COMPREPLY=( $(compgen -W "$units" -- "$cur") )
            fi
            ;;
        destroy-model|models)
            if [[ $COMP_CWORD -ge 2 ]]; then
                local models
                models=$(juju models --format=json 2>/dev/null | jq -r '.models[].name' 2>/dev/null)
                [[ -n "$models" ]] && COMPREPLY=( $(compgen -W "$models" -- "$cur") )
            fi
            ;;
        config)
            if [[ $COMP_CWORD -ge 2 ]]; then
                local applications
                applications=$(juju status --format=json | jq -r '.applications | keys[]' 2>/dev/null)
                [[ -n "$applications" ]] && COMPREPLY=( $(compgen -W "$applications" -- "$cur") )
            fi
            ;;
        controllers)
            if [[ $COMP_CWORD -ge 2 ]]; then
                local controllers
                controllers=$(juju controllers --format=json 2>/dev/null | jq -r '.controllers|keys[]?' 2>/dev/null)
                [[ -n "$controllers" ]] && COMPREPLY=( $(compgen -W "$controllers" -- "$cur") )
            fi
            ;;
    esac
}

complete -F _j_completion j

EOF

elif [[ "$CURRENT_SHELL" == "zsh" ]]; then
    cat >> "$TARGET_FILE_BASH_ZSH" << 'EOF'

autoload -Uz compinit && compinit

_j_zsh_completion() {
    local -a cmds
    cmds=(
        'controllers:fuzzy switch controller'
        'models:fuzzy switch model'
        'ssh:fuzzy SSH to unit'
        'debug-log:fuzzy debug-log for unit'
        'destroy-model:fuzzy destroy model'
        'help:show help'
        '*:passthrough to juju'
    )

    if (( CURRENT == 2 )); then
        _describe 'command' cmds
        return
    fi

    case $words[2] in
        ssh|debug-log|show-unit)
            local -a units
            units=(${(f)"$(juju status --format=json 2>/dev/null | jq -r '.applications[]?.units|keys[]?' 2>/dev/null)"})
            _describe 'unit' units
            ;;
        models|destroy-model)
            local -a models
            models=(${(f)"$(juju models --format=json 2>/dev/null | jq -r '.models[].name' 2>/dev/null)"})
            _describe 'model' models
            ;;
        controllers)
            local -a controllers
            controllers=(${(f)"$(juju controllers --format=json 2>/dev/null | jq -r '.controllers|keys[]?' 2>/dev/null)"})
            _describe 'controller' controllers
            ;;
        config)
            local -a apps
            apps=(${(f)"$(juju status --format=json 2>/dev/null | jq -r '.applications | keys[]' 2>/dev/null)"})
            _describe 'application' apps
            ;;
    esac
}

compdef _j_zsh_completion j

EOF

fi

# ────────────── Fish Function & Completion ──────────────

if [[ "$CURRENT_SHELL" == "fish" ]]; then
    mkdir -p "$(dirname "$TARGET_FILE_FISH")"

    cat > "$TARGET_FILE_FISH" << 'EOF'
function j
    set cmd $argv[1]

    if test (count $argv) -eq 0
        _j_show_help
        return 0
    end

    switch $cmd
        case help --help -h
            _j_show_help
            return 0

        case controllers
            set -e argv[1]
            set controller $argv[1]
            if test -z "$controller"
                set controller (juju controllers --format=json | jq -r '.controllers | keys[]' | \
                    fzf --prompt='🪄 Controller > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            end
            if test -n "$controller"
                echo "→ juju switch $controller"
                juju switch "$controller"
            else
                echo "⚠️  No controller selected."
                return 1
            end

        case models
            set -e argv[1]
            set model $argv[1]
            if test -z "$model"
                set model (juju models --format=json | jq -r '.models[].name' | \
                    fzf --prompt='🪄 Model > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            end
            if test -n "$model"
                echo "→ juju switch $model"
                juju switch "$model"
            else
                echo "⚠️  No model selected."
                return 1
            end

        case ssh
            set -e argv[1]
            set unit $argv[1]
            if test -n "$unit"
                set -e argv[1]
            else
                set unit (juju status --format=json | jq -r '.applications[] | .units | keys[]' | \
                    fzf --prompt='🪄 Unit > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            end
            if test -n "$unit"
                echo "→ juju ssh $unit"(test -n "$argv" && echo " [args: $argv]")
                juju ssh "$unit" $argv
            else
                echo "⚠️  No unit selected."
                return 1
            end

        case debug-log
            set -e argv[1]
            set unit $argv[1]
            if test -n "$unit"
                set -e argv[1]
                echo "→ juju debug-log -i $unit"(test -n "$argv" && echo " [args: $argv]")
                juju debug-log -i "$unit" $argv
            else
                set unit (juju status --format=json | jq -r '.applications[] | .units | keys[]' | \
                    fzf --prompt='🪄 Unit > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
                if test -n "$unit"
                    echo "→ juju debug-log -i $unit"(test -n "$argv" && echo " [args: $argv]")
                    juju debug-log -i "$unit" $argv
                else
                    echo "→ juju debug-log"(test -n "$argv" && echo " [args: $argv]")" (no unit selected)"
                    juju debug-log $argv
                end
            end

        case destroy-model
            set -e argv[1]
            set model $argv[1]
            if test -z "$model"
                set model (juju models --format=json | jq -r '.models[].name' | \
                    fzf --prompt='🪄 Model > ' \
                        --pointer='👉' \
                        --height 40% \
                        --cycle \
                        --select-1 \
                        --exit-0 \
                        --no-multi)
            end
            if test -n "$model"
                echo "→ juju destroy-model $model --no-wait --force --destroy-storage --no-prompt"(test -n "$argv" && echo " [args: $argv]")
                juju destroy-model "$model" --no-wait --force --destroy-storage --no-prompt $argv
            else
                echo "⚠️  No model selected."
                return 1
            end

        case '*'
            juju $argv
    end
end

function _j_show_help
    cat << HELP
🚀 Unified Juju FZF Gateway — "j"

Smart fuzzy-selector wrapper for Juju CLI with TAB completion.

USAGE:
    j [COMMAND] [ARGS...]

COMMANDS:
    help, -h, --help           → Show this help
    controllers                → Fuzzy switch Juju controller
    models                     → Fuzzy switch Juju model
    ssh [UNIT] [juju-args...]  → SSH to unit (fuzzy select if no unit given)
    debug-log [UNIT] [...]     → Show debug-log for unit (fuzzy if no unit)
    destroy-model [MODEL] [...]→ Destroy model (fuzzy if no model given)
    <anything else>            → Passthrough to "juju <anything else>"

TAB COMPLETION:
    j <TAB>                    → Complete subcommands
    j ssh <TAB>                → Complete unit names
    j destroy-model <TAB>      → Complete model names

EXAMPLES:
    j controllers              → fuzzy-select and switch controller
    j models                   → fuzzy-select and switch model
    j ssh                      → fuzzy-select unit, then SSH
    j ssh ubuntu/0 --proxy     → SSH directly with args
    j status                   → runs "juju status"
    j deploy nginx             → runs "juju deploy nginx"
    j destroy-model dev        → destroys model "dev" (no FZF)

💡 PRO TIPS:
    → Already named "j" — no alias needed
    → Restart fish or run: source ~/.config/fish/config.fish

HELP
end

# Fish completions
complete -c j -n "__fish_seen_subcommand_from ''" -a "help controllers models ssh debug-log destroy-model" -d "Juju FZF Gateway Commands"
complete -c j -n "__fish_seen_subcommand_from ssh debug-log show-unit" -f -a "(juju status --format=json 2>/dev/null | jq -r '.applications[]?.units|keys[]?' 2>/dev/null)"
complete -c j -n "__fish_seen_subcommand_from models destroy-model" -f -a "(juju models --format=json 2>/dev/null | jq -r '.models[].name' 2>/dev/null)"
complete -c j -n "__fish_seen_subcommand_from controllers" -f -a "(juju controllers --format=json 2>/dev/null | jq -r '.controllers|keys[]?' 2>/dev/null)"
complete -c j -n "__fish_seen_subcommand_from config" -f -a "(juju status --format=json 2>/dev/null | jq -r '.applications | keys[]' 2>/dev/null)"

EOF

fi

# ────────────── Inject into Shell Config ──────────────

if [[ "$CURRENT_SHELL" == "fish" ]]; then
    # Fish auto-loads functions from ~/.config/fish/functions/
    # No need to source, but notify user
    echo "✅ Fish function 'j' installed to $TARGET_FILE_FISH"
else
    # Bash/Zsh: source the file in config
    if ! grep -q ".juju-fzf-unified.bash" "$CONFIG_FILE" 2>/dev/null; then
        echo "" >> "$CONFIG_FILE"
        echo "# Unified Juju FZF Gateway" >> "$CONFIG_FILE"
        echo "source \"$TARGET_FILE_BASH_ZSH\"" >> "$CONFIG_FILE"
        echo "✅ Added source line to $CONFIG_FILE"
    else
        echo "ℹ️  Source line already exists in $CONFIG_FILE"
    fi
fi

# ────────────── Source and Notify ──────────────

echo ""
echo "🎉 Unified Juju FZF Gateway 'j' installed successfully for $CURRENT_SHELL with TAB COMPLETION!"
echo ""

if [[ "$CURRENT_SHELL" == "fish" ]]; then
    echo "→ Restart fish or run: source ~/.config/fish/config.fish"
else
    echo "→ Restart shell or run: source $CONFIG_FILE"
fi

echo ""
echo "Try it:"
echo "  j controllers"
echo "  j models"
echo "  j ssh"
echo "  j status"
