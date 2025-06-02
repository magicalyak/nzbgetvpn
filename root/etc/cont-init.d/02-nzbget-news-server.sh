#!/usr/bin/with-contenv bash
# shellcheck disable=SC1008

# Function to set NZBGet config value if the corresponding environment variable is set
# Usage: set_nzb_config_from_env "NZBGetConfigKey" "$ENVIRONMENT_VARIABLE_VALUE" "/path/to/nzbget.conf"
set_nzb_config_from_env() {
  local key="$1"
  local env_var_value="$2"
  local config_file="$3"

  # Only proceed if the environment variable is set and not empty
  if [ -z "$env_var_value" ]; then
    return
  fi

  # Ensure config file exists (it really should be created by the base LSIO image)
  if [ ! -f "$config_file" ]; then
    echo "NZBGet config: $config_file not found. Attempting to create and write setting."
    # The NZBGet application itself should create this on first run if missing.
    # Forcing a touch here might be okay, but rely on NZBGet or LSIO base.
    touch "$config_file"
  fi

  # Escape common sed special characters / and & in the value
  # Also escape basic regex characters used in the grep pattern to avoid issues if value contains them
  local sed_value=$(printf '%s\n' "$env_var_value" | sed -e 's/[\/&]/\\&/g' -e 's/\[\][][^$.*]/\\&/g')


  # Check if key exists (match key possibly followed by spaces and then '=')
  # Escape regex characters in key for grep
  local escaped_key=$(printf '%s\n' "$key" | sed 's/[.^$*[\]]/\\&/g')
  if grep -q -E "^${escaped_key}[[:space:]]*=" "$config_file"; then
    # Key exists, update it
    sed -i "s|^${escaped_key}[[:space:]]*=.*|${key}=${sed_value}|" "$config_file" # Use original key for replacement
    echo "NZBGet config: Updated $key"
  else
    # Key does not exist, add it
    echo "${key}=${env_var_value}" >> "$config_file" # Append original value, not sed_value
    echo "NZBGet config: Added $key"
  fi
}

NZBGET_CONF_FILE="/config/nzbget.conf"

if [ ! -f "$NZBGET_CONF_FILE" ]; then
  echo "NZBGet config: WARNING - $NZBGET_CONF_FILE does not exist. NZBGet process should create this file. Settings will be applied once it's created or to an empty file now."
fi

echo "NZBGet config: Applying Server1 settings from environment variables if set..."

set_nzb_config_from_env "Server1.Name" "$NZBGET_S1_NAME" "$NZBGET_CONF_FILE"
set_nzb_config_from_env "Server1.Host" "$NZBGET_S1_HOST" "$NZBGET_CONF_FILE"
set_nzb_config_from_env "Server1.Port" "$NZBGET_S1_PORT" "$NZBGET_CONF_FILE"
set_nzb_config_from_env "Server1.Username" "$NZBGET_S1_USER" "$NZBGET_CONF_FILE"
set_nzb_config_from_env "Server1.Password" "$NZBGET_S1_PASS" "$NZBGET_CONF_FILE"
set_nzb_config_from_env "Server1.Connections" "$NZBGET_S1_CONN" "$NZBGET_CONF_FILE"
set_nzb_config_from_env "Server1.SSL" "$NZBGET_S1_SSL" "$NZBGET_CONF_FILE" # Expects 'yes' or 'no'
set_nzb_config_from_env "Server1.Level" "$NZBGET_S1_LEVEL" "$NZBGET_CONF_FILE"

# Handle Server1.Disabled based on NZBGET_S1_ENABLED
if [ -n "$NZBGET_S1_ENABLED" ]; then
  actual_val_for_disabled=""
  if [ "$NZBGET_S1_ENABLED" == "yes" ]; then
    actual_val_for_disabled="no"
  elif [ "$NZBGET_S1_ENABLED" == "no" ]; then
    actual_val_for_disabled="yes"
  else
    echo "NZBGet config: Invalid value for NZBGET_S1_ENABLED: '$NZBGET_S1_ENABLED'. Expected 'yes' or 'no'. Server1.Disabled not changed."
  fi

  if [ -n "$actual_val_for_disabled" ]; then
    key_for_disabled="Server1.Disabled"
    
    if [ ! -f "$NZBGET_CONF_FILE" ]; then touch "$NZBGET_CONF_FILE"; fi
    
    escaped_key_for_disabled=$(printf '%s\n' "$key_for_disabled" | sed 's/[.^$*[\]]/\\&/g')
    sed_value_for_disabled=$(printf '%s\n' "$actual_val_for_disabled" | sed -e 's/[\/&]/\\&/g' -e 's/\[\][][^$.*]/\\&/g')

    if grep -q -E "^${escaped_key_for_disabled}[[:space:]]*=" "$NZBGET_CONF_FILE"; then
      sed -i "s|^${escaped_key_for_disabled}[[:space:]]*=.*|${key_for_disabled}=${sed_value_for_disabled}|" "$NZBGET_CONF_FILE"
      echo "NZBGet config: Updated Server1.Disabled to $actual_val_for_disabled (NZBGET_S1_ENABLED=$NZBGET_S1_ENABLED)"
    else
      echo "${key_for_disabled}=${actual_val_for_disabled}" >> "$NZBGET_CONF_FILE"
      echo "NZBGet config: Added Server1.Disabled=$actual_val_for_disabled (NZBGET_S1_ENABLED=$NZBGET_S1_ENABLED)"
    fi
  fi
fi

echo "NZBGet config: Server1 settings script finished." 