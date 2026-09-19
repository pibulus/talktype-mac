#!/usr/bin/env bash
set -e

# TalkType Screenshot Processor
# Calls universal snap-app with TalkType's custom brand settings

if command -v snap-app >/dev/null 2>&1; then
    exec snap-app --name "TalkType" --theme cream "$@"
elif [ -f "$HOME/.local/bin/snap-app" ]; then
    exec "$HOME/.local/bin/snap-app" --name "TalkType" --theme cream "$@"
else
    echo "Delegating to local fallback..."
    bash "$HOME/.claude/scripts/dev-tools/snap-app.sh" --name "TalkType" --theme cream "$@"
fi
