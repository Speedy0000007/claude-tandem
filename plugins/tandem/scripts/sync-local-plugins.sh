#!/bin/bash
# Sync local directory-based plugin marketplaces into Claude Code's plugin cache.
# Replaces cached copies with symlinks to source directories, so changes are live.
#
# Install as a user-level SessionStart hook (see CONFIGURATION.md).
# Works for any local directory marketplace, not just Tandem.

KNOWN_FILE="$HOME/.claude/plugins/known_marketplaces.json"
INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"

[ -f "$KNOWN_FILE" ] || exit 0
[ -f "$INSTALLED_FILE" ] || exit 0
command -v jq &>/dev/null || exit 0

# Find local directory-based marketplaces
jq -r 'to_entries[] | select(.value.type == "local_directory") | "\(.key)\t\(.value.path)"' "$KNOWN_FILE" 2>/dev/null | while IFS=$'\t' read -r MARKETPLACE_ID SOURCE_DIR; do
  [ -z "$MARKETPLACE_ID" ] && continue
  [ -d "$SOURCE_DIR" ] || continue

  # Find installed plugins from this marketplace
  jq -r --arg mid "$MARKETPLACE_ID" '
    to_entries[] | select(.value.marketplace_id == $mid) | "\(.key)\t\(.value.install_path)"
  ' "$INSTALLED_FILE" 2>/dev/null | while IFS=$'\t' read -r PLUGIN_ID CACHE_PATH; do
    [ -z "$CACHE_PATH" ] && continue

    # Determine source plugin dir from marketplace structure
    PLUGIN_NAME="${PLUGIN_ID##*/}"
    SOURCE_PLUGIN="$SOURCE_DIR/plugins/$PLUGIN_NAME"
    [ -d "$SOURCE_PLUGIN" ] || continue

    # Already a correct symlink? Skip.
    if [ -L "$CACHE_PATH" ]; then
      CURRENT_TARGET=$(readlink "$CACHE_PATH" 2>/dev/null)
      [ "$CURRENT_TARGET" = "$SOURCE_PLUGIN" ] && continue
    fi

    # Replace cache with symlink
    rm -rf "$CACHE_PATH"
    ln -s "$SOURCE_PLUGIN" "$CACHE_PATH"
  done
done

exit 0
