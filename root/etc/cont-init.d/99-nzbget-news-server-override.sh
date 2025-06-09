#!/usr/bin/with-contenv bash
# shellcheck disable=SC1008

# Function to update NZBGet config value or add it if it doesn't exist.
# Usage: update_nzb_config "ConfigKey" "NewValue" "/path/to/nzbget.conf"
update_nzb_config() {
  local key="$1"
  local new_value="$2"
  local config_file="$3"

  if [ ! -f "$config_file" ]; then
    echo "NZBGet config: $config_file not found. Skipping modification of $key."
    return
  fi

  local escaped_key=$(printf '%s\n' "$key" | sed 's/[.^$*[\]]/\\&/g') # Escape for grep/sed key matching
  local sed_value=$(printf '%s\n' "$new_value" | sed -e 's/[\/&]/\\&/g' -e 's/\[\][][^$.*]/\\&/g') # Escape for sed value

  if grep -q -E "^${escaped_key}[[:space:]]*=" "$config_file"; then
    sed -i "s|^${escaped_key}[[:space:]]*=.*|${key}=${sed_value}|" "$config_file"
    echo "NZBGet config: Updated $key"
  else
    echo "${key}=${new_value}" >> "$config_file"
    echo "NZBGet config: Added $key"
  fi
}

# Function to remove specific NZBGet config lines by literal key match
# Usage: remove_nzb_config_literal_key "Server1.SSL" "/path/to/nzbget.conf"
remove_nzb_config_literal_key() {
  local key_to_remove="$1"
  local config_file="$2"

  if [ ! -f "$config_file" ]; then
    return
  fi
  
  local sed_pattern_for_removal=""
  if [ "$key_to_remove" == "Server1.SSL" ]; then
    sed_pattern_for_removal="^Server1\\.SSL[[:space:]]*="
  elif [ "$key_to_remove" == "Server1.Encrypt" ]; then
    sed_pattern_for_removal="^Server1\\.Encrypt[[:space:]]*="
  elif [ "$key_to_remove" == "Server1.Encryption" ]; then
    sed_pattern_for_removal="^Server1\\.Encryption[[:space:]]*="
  elif [ "$key_to_remove" == "Server1.Disabled" ]; then
    sed_pattern_for_removal="^Server1\\.Disabled[[:space:]]*="
  elif [ "$key_to_remove" == "Server1.Enabled" ]; then # Also remove Server1.Enabled
    sed_pattern_for_removal="^Server1\\.Enabled[[:space:]]*="
  else
    echo "NZBGet config: Unknown key for literal removal: $key_to_remove. Pattern not set."
    return
  fi
  
  if grep -q -E "$sed_pattern_for_removal" "$config_file"; then
    sed -i "/${sed_pattern_for_removal}/d" "$config_file"
    echo "NZBGet config: Removed lines matching literal key '$key_to_remove'"
  fi
}

NZBGET_CONF_FILE="/config/nzbget.conf"

if [ ! -f "$NZBGET_CONF_FILE" ]; then
  echo "NZBGet config: CRITICAL - $NZBGET_CONF_FILE does not exist when 99-script started. LSIO base scripts should have created this. Cannot apply custom server settings reliably."
fi

echo "NZBGet config: Applying PATH settings..."
update_nzb_config "MainDir" "/downloads" "$NZBGET_CONF_FILE"
update_nzb_config "DestDir" "/downloads/completed" "$NZBGET_CONF_FILE"
update_nzb_config "InterDir" "/downloads/intermediate" "$NZBGET_CONF_FILE"
update_nzb_config "ScriptDir" "/config/scripts" "$NZBGET_CONF_FILE" # Standard LSIO location for scripts
update_nzb_config "QueueDir" "/downloads/queue" "$NZBGET_CONF_FILE"
update_nzb_config "TempDir" "/downloads/tmp" "$NZBGET_CONF_FILE"
update_nzb_config "NzbDir" "/downloads/nzb" "$NZBGET_CONF_FILE"
update_nzb_config "LogFile" "/config/nzbget.log" "$NZBGET_CONF_FILE"

echo "NZBGet config: Applying Server1 settings from environment variables if set..."

# Only configure Server1 if NZBGET_S1_ENABLED is 'yes' (or not 'no')
# For this iteration, we assume if NZBGET_S1_ENABLED is set, it implies 'yes' effectively
# A more robust check would be: if [ "$NZBGET_S1_ENABLED" == "yes" ]; then ... fi

if [ -n "$NZBGET_S1_NAME" ]; then update_nzb_config "Server1.Name" "$NZBGET_S1_NAME" "$NZBGET_CONF_FILE"; fi
if [ -n "$NZBGET_S1_HOST" ]; then update_nzb_config "Server1.Host" "$NZBGET_S1_HOST" "$NZBGET_CONF_FILE"; fi
if [ -n "$NZBGET_S1_PORT" ]; then update_nzb_config "Server1.Port" "$NZBGET_S1_PORT" "$NZBGET_CONF_FILE"; fi
if [ -n "$NZBGET_S1_USER" ]; then update_nzb_config "Server1.Username" "$NZBGET_S1_USER" "$NZBGET_CONF_FILE"; fi
if [ -n "$NZBGET_S1_PASS" ]; then update_nzb_config "Server1.Password" "$NZBGET_S1_PASS" "$NZBGET_CONF_FILE"; fi
if [ -n "$NZBGET_S1_CONN" ]; then update_nzb_config "Server1.Connections" "$NZBGET_S1_CONN" "$NZBGET_CONF_FILE"; fi
if [ -n "$NZBGET_S1_LEVEL" ]; then update_nzb_config "Server1.Level" "$NZBGET_S1_LEVEL" "$NZBGET_CONF_FILE"; fi

# Handle Encryption (SSL/TLS)
if [ -n "$NZBGET_S1_SSL" ]; then
  if [ -f "$NZBGET_CONF_FILE" ]; then
    remove_nzb_config_literal_key "Server1.SSL" "$NZBGET_CONF_FILE"
    remove_nzb_config_literal_key "Server1.Encrypt" "$NZBGET_CONF_FILE"
    remove_nzb_config_literal_key "Server1.Encryption" "$NZBGET_CONF_FILE"
    update_nzb_config "Server1.Encryption" "$NZBGET_S1_SSL" "$NZBGET_CONF_FILE"
  else
    echo "NZBGet config: $NZBGET_CONF_FILE not found when attempting to set Server1.Encryption."
  fi
fi

# Ensure any explicit enable/disable keys for Server1 are removed, as LSIO/NZBGet handles this implicitly
if [ -f "$NZBGET_CONF_FILE" ]; then
    remove_nzb_config_literal_key "Server1.Disabled" "$NZBGET_CONF_FILE"
    remove_nzb_config_literal_key "Server1.Enabled" "$NZBGET_CONF_FILE"
    echo "NZBGet config: Ensured Server1.Disabled and Server1.Enabled are removed."
fi

echo "NZBGet config: Server1 settings script finished." 

echo "--- BEGIN /config/nzbget.conf DUMP (after 99-nzbget-news-server-override.sh) ---"
if [ -f "$NZBGET_CONF_FILE" ]; then
  cat "$NZBGET_CONF_FILE"
else
  echo "$NZBGET_CONF_FILE not found at end of script."
fi
echo "--- END /config/nzbget.conf DUMP ---" 