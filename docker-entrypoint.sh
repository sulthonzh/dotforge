#!/bin/bash
set -euo pipefail
# shellcheck disable=SC2016 # SC2016 false positives: single-quoting is intentional to prevent variable expansion in case/grep patterns

# Initialize temp_passwd_file early (before trap) to prevent unbound variable errors in cleanup
temp_passwd_file=""

# Cleanup function to remove SSH keys, agent, docker context, and report deployment status.
# Registered as trap BEFORE any sensitive resources are created so that failures during
# key registration, context creation, or login still clean up.
cleanup() {
  local exit_code=$?
  echo "Cleaning up..."
  # Remove SSH keys
  rm -f ~/.ssh/id_rsa ~/.ssh/id_rsa.pub 2>/dev/null || true
  # Remove temporary password file if it was created
  if [ -n "${temp_passwd_file}" ] && [ -f "$temp_passwd_file" ]; then
    rm -f "$temp_passwd_file"
  fi
  # Kill SSH agent if running
  if [ -n "${SSH_AGENT_PID+x}" ] && [ -n "$SSH_AGENT_PID" ]; then
    kill "$SSH_AGENT_PID" 2>/dev/null || true
  fi
  # Remove docker context
  docker context rm remote -f 2>/dev/null || true
  # Report deployment status via GITHUB_OUTPUT
  GITHUB_OUTPUT=${GITHUB_OUTPUT:-/dev/null}
  if [ "$exit_code" -eq 0 ]; then
    echo "deployment_status=success" >> "$GITHUB_OUTPUT"
  else
    echo "deployment_status=failed" >> "$GITHUB_OUTPUT"
  fi
  exit "$exit_code"
}

# Set trap for cleanup on exit and signals.
# ERR is intentionally omitted: under 'set -e', a failing command triggers ERR trap
# (running cleanup), then the script exits triggering EXIT trap (running cleanup again).
# EXIT alone covers all exit paths including signal-terminated and set -e failures.
trap cleanup EXIT SIGINT SIGTERM

execute_ssh(){
  echo "Execute Over SSH: $*"
  if ! ssh -q -t -i "$HOME/.ssh/id_rsa" \
      -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no \
      -p "$INPUT_REMOTE_DOCKER_PORT" \
      "$INPUT_REMOTE_DOCKER_HOST" "$@"; then
    echo "Error: SSH command failed: $*"
    exit 1
  fi
}

# Enhanced input validation to prevent shell injection and path traversal
validate_input() {
  local input_name="$1"
  local input_value="$2"

  # Check for empty input
  if [ -z "$input_value" ]; then
    echo "Error: $input_name cannot be empty"
    exit 1
  fi

  # Check for shell metacharacters that could cause command injection
  # Use printf instead of echo to avoid -e/-n/-E being interpreted as echo flags
  if printf '%s' "$input_value" | grep -qE '[;&|`$()<>\"'"'"']'; then
    echo "Error: $input_name contains dangerous characters that could cause command injection"
    exit 1
  fi

  # Check for control characters (newline, CR, tab) using case statement
  # POSIX-compatible, works in BusyBox/Alpine without grep bracket expression issues
  case "$input_value" in
    *$'\n'*|*$'\r'*|*$'\t'*)
      echo "Error: $input_name contains control characters (newline/tab/null)"
      exit 1
      ;;
  esac

  # Check for path traversal attempts (..), absolute paths, and suspicious patterns
  # Skip validation for args and stack_file_name as they may need special characters
  # deploy_path legitimately uses absolute paths (/opt/...) and home expansion (~/...)
  # so it is exempted from the /* and ~* checks, but still checked for ..
  if [[ "$input_name" != "args" && "$input_name" != "stack_file_name" ]]; then
    case "$input_value" in
      *..*)
        echo "Error: $input_name contains path traversal patterns (..)"
        exit 1
        ;;
    esac
    if [[ "$input_name" != "deploy_path" ]]; then
      case "$input_value" in
        /*|~*|'${'*|'$'*)
          echo "Error: $input_name contains potentially dangerous path patterns"
          exit 1
          ;;
      esac
    fi
  fi
}

# Reject environment variable expansion in values that should be literal paths
# Must run after main validate_input to ensure it applies to all inputs including exempted ones
# deploy_path is checked because it's expanded in shell commands, which could leak environment variables
# args is excluded because it needs to pass through as-is to docker-compose/docker-swarm
validate_env_expansion() {
  local input_name="$1"
  local input_value="$2"

  if [[ "$input_name" != "args" ]]; then
    case "$input_value" in
      *'${'*|'$'*)
        echo "Error: $input_name contains environment variable expansion patterns"
        exit 1
        ;;
    esac
  fi

  # Additional URL-specific validation for docker_registry_uri
  # Allow : and / for URLs but block command substitution patterns
  if [ "$input_name" = "docker_registry_uri" ]; then
    if printf '%s' "$input_value" | grep -qE '\$\(|`|\$\{'; then
      echo "Error: docker_registry_uri contains command substitution patterns"
      exit 1
    fi
  fi
}

# Set default values for optional inputs
if [ -z "${INPUT_REMOTE_DOCKER_PORT+x}" ]; then
  INPUT_REMOTE_DOCKER_PORT=22
fi

# Validate required inputs
if [ -z "${INPUT_REMOTE_DOCKER_HOST+x}" ]; then
    echo "Error: Input remote_docker_host is required!"
    exit 1
fi

# Validate remote_docker_host format (should be user@host)
if ! printf '%s' "$INPUT_REMOTE_DOCKER_HOST" | grep -qE '^[^@]+@[^@]+$'; then
  echo "Error: remote_docker_host must be in format 'user@host'"
  exit 1
fi

if [ -z "${INPUT_SSH_PUBLIC_KEY+x}" ]; then
    echo "Error: Input ssh_public_key is required!"
    exit 1
fi

if [ -z "${INPUT_SSH_PRIVATE_KEY+x}" ]; then
    echo "Error: Input ssh_private_key is required!"
    exit 1
fi

if [ -z "${INPUT_ARGS+x}" ]; then
  echo "Error: Input args is required!"
  exit 1
fi

# Set defaults for optional inputs
if [ -z "${INPUT_DEPLOY_PATH+x}" ]; then
  INPUT_DEPLOY_PATH=~/docker-deployment
fi

if [ -z "${INPUT_STACK_FILE_NAME+x}" ]; then
  INPUT_STACK_FILE_NAME=docker-compose.yml
fi

if [ -z "${INPUT_DEPLOYMENT_MODE+x}" ]; then
  INPUT_DEPLOYMENT_MODE=docker-compose
fi

if [ -z "${INPUT_COPY_STACK_FILE+x}" ]; then
  INPUT_COPY_STACK_FILE=false
fi

if [ -z "${INPUT_KEEP_FILES+x}" ]; then
  INPUT_KEEP_FILES=4
fi

if [ -z "${INPUT_DOCKER_REGISTRY_URI+x}" ]; then
  INPUT_DOCKER_REGISTRY_URI=https://registry.hub.docker.com
fi

if [ -z "${INPUT_PULL_IMAGES_FIRST+x}" ]; then
  INPUT_PULL_IMAGES_FIRST=false
fi

if [ -z "${INPUT_DOCKER_PRUNE+x}" ]; then
  INPUT_DOCKER_PRUNE=false
fi

# Enhanced input validation
validate_input "remote_docker_host" "$INPUT_REMOTE_DOCKER_HOST"
validate_env_expansion "remote_docker_host" "$INPUT_REMOTE_DOCKER_HOST"
validate_input "args" "$INPUT_ARGS"
validate_env_expansion "args" "$INPUT_ARGS"
validate_input "deploy_path" "$INPUT_DEPLOY_PATH"
validate_env_expansion "deploy_path" "$INPUT_DEPLOY_PATH"
validate_input "stack_file_name" "$INPUT_STACK_FILE_NAME"
validate_env_expansion "stack_file_name" "$INPUT_STACK_FILE_NAME"

# Validate pre_deployment_command_args if provided
if [ -n "${INPUT_PRE_DEPLOYMENT_COMMAND_ARGS+x}" ] && [ -n "${INPUT_PRE_DEPLOYMENT_COMMAND_ARGS}" ]; then
  validate_input "pre_deployment_command_args" "$INPUT_PRE_DEPLOYMENT_COMMAND_ARGS"
  validate_env_expansion "pre_deployment_command_args" "$INPUT_PRE_DEPLOYMENT_COMMAND_ARGS"
fi

# Validate registry inputs if provided
if [ -n "${INPUT_DOCKER_REGISTRY_URI+x}" ] && [ -n "${INPUT_DOCKER_REGISTRY_URI}" ]; then
  validate_input "docker_registry_uri" "$INPUT_DOCKER_REGISTRY_URI"
  validate_env_expansion "docker_registry_uri" "$INPUT_DOCKER_REGISTRY_URI"
fi

if [ -n "${INPUT_DOCKER_REGISTRY_USERNAME+x}" ] && [ -n "${INPUT_DOCKER_REGISTRY_USERNAME}" ]; then
  validate_input "docker_registry_username" "$INPUT_DOCKER_REGISTRY_USERNAME"
fi

# Note: docker_registry_password is intentionally NOT validated via validate_input.
# Passwords commonly contain $, (), etc. that validate_input blocks. The password is
# safely handled via temp file + --password-file, never used in shell expansion.

# Ensure numeric inputs are valid numbers
if ! [[ "$INPUT_REMOTE_DOCKER_PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: remote_docker_port must be a number between 1 and 65535: $INPUT_REMOTE_DOCKER_PORT"
  exit 1
fi
if [ "$INPUT_REMOTE_DOCKER_PORT" -lt 1 ] || [ "$INPUT_REMOTE_DOCKER_PORT" -gt 65535 ]; then
  echo "Error: remote_docker_port must be between 1 and 65535: $INPUT_REMOTE_DOCKER_PORT"
  exit 1
fi

if ! [[ "$INPUT_KEEP_FILES" =~ ^[0-9]+$ ]]; then
  echo "Error: keep_files must be a positive integer: $INPUT_KEEP_FILES"
  exit 1
fi
if [ "$INPUT_KEEP_FILES" -lt 1 ]; then
  echo "Error: keep_files must be at least 1: $INPUT_KEEP_FILES"
  exit 1
fi

# Increment keep_files for cleanup logic
# Use 10# prefix to force base-10 interpretation (leading zeros would cause octal parsing)
INPUT_KEEP_FILES=$((10#$INPUT_KEEP_FILES+1))

# Validate boolean inputs
# Must be exactly 'true' or 'false' to prevent silent failures from invalid values like 'yes', '1', etc.
for var_name in INPUT_COPY_STACK_FILE INPUT_PULL_IMAGES_FIRST INPUT_DOCKER_PRUNE; do
  value="${!var_name}"
  if [ "$value" != "true" ] && [ "$value" != "false" ]; then
    echo "Error: $var_name must be 'true' or 'false', got: $value"
    exit 1
  fi
done

STACK_FILE="${INPUT_STACK_FILE_NAME}"
DEPLOYMENT_COMMAND_OPTIONS=""

if [ "$INPUT_COPY_STACK_FILE" = "true" ]; then
  STACK_FILE="$INPUT_DEPLOY_PATH/$STACK_FILE"
else
  DEPLOYMENT_COMMAND_OPTIONS=" --log-level debug --host ssh://$INPUT_REMOTE_DOCKER_HOST:$INPUT_REMOTE_DOCKER_PORT"
fi

case "$INPUT_DEPLOYMENT_MODE" in

  docker-swarm)
    DEPLOYMENT_COMMAND="docker $DEPLOYMENT_COMMAND_OPTIONS stack deploy --compose-file \"$STACK_FILE\""
  ;;

  docker-compose)
    DEPLOYMENT_COMMAND="docker-compose -f \"$STACK_FILE\" $DEPLOYMENT_COMMAND_OPTIONS"
  ;;

  *)
    echo "Error: deployment_mode must be 'docker-compose' or 'docker-swarm', got: $INPUT_DEPLOYMENT_MODE"
    exit 1
  ;;
esac

echo "Registering SSH keys..."

# register the private key with the agent.
mkdir -p ~/.ssh
chmod 700 ~/.ssh
printf '%s\n' "$INPUT_SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
printf '%s\n' "$INPUT_SSH_PUBLIC_KEY" > ~/.ssh/id_rsa.pub
chmod 600 ~/.ssh/id_rsa.pub
eval "$(ssh-agent)"
ssh-add ~/.ssh/id_rsa

# Note: ssh-keyscan was removed — execute_ssh uses UserKnownHostsFile=/dev/null and
# StrictHostKeyChecking=no, so known_hosts is never consulted. The keyscan added
# 5-10s latency and could hang on unreachable hosts for nothing.

echo "Creating docker context"
# Remove existing context if it exists to avoid conflicts
if docker context ls 2>/dev/null | grep -q '^remote '; then
  docker context rm remote -f 2>/dev/null || echo "Warning: Could not remove existing remote context"
fi

if ! docker context create remote --docker "host=ssh://$INPUT_REMOTE_DOCKER_HOST:$INPUT_REMOTE_DOCKER_PORT"; then
  echo "Error: Failed to create docker context"
  exit 1
fi

if ! docker context use remote; then
  echo "Error: Failed to switch to docker context"
  exit 1
fi

if [ -n "${INPUT_DOCKER_REGISTRY_USERNAME+x}" ] && [ -n "${INPUT_DOCKER_REGISTRY_USERNAME}" ] && [ -n "${INPUT_DOCKER_REGISTRY_PASSWORD+x}" ] && [ -n "${INPUT_DOCKER_REGISTRY_PASSWORD}" ]; then
  echo "Connecting to $INPUT_DOCKER_REGISTRY_URI..."
  # Use a temporary file for the password to avoid leaving it in process lists
  # Create with umask 077 to ensure file is created with mode 0600 directly (no race condition)
  temp_passwd_file="$(mktemp)"
  ( umask 077 && printf '%s' "$INPUT_DOCKER_REGISTRY_PASSWORD" > "$temp_passwd_file" )
  if ! docker login -u "$INPUT_DOCKER_REGISTRY_USERNAME" --password-file "$temp_passwd_file" "$INPUT_DOCKER_REGISTRY_URI"; then
    echo "Error: Docker login failed"
    rm -f "$temp_passwd_file"
    exit 1
  fi
  rm -f "$temp_passwd_file"
fi

if [ "$INPUT_COPY_STACK_FILE" = 'true' ] ; then
  echo "Copying stack file to remote server..."
  execute_ssh "mkdir -p \"$INPUT_DEPLOY_PATH/stacks\" || true"
  FILE_NAME="docker-stack-$(date +%Y%m%d%H%M%S).yaml"

  # Copy stack file to remote server
  if ! scp -i "$HOME/.ssh/id_rsa" \
      -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no \
      -P "$INPUT_REMOTE_DOCKER_PORT" \
      "$INPUT_STACK_FILE_NAME" "$INPUT_REMOTE_DOCKER_HOST:$INPUT_DEPLOY_PATH/stacks/$FILE_NAME"; then
    echo "Error: Failed to copy stack file"
    exit 1
  fi

  # Create symlink and clean up old files
  execute_ssh "ln -nfs \"$INPUT_DEPLOY_PATH/stacks/$FILE_NAME\" \"$INPUT_DEPLOY_PATH/$INPUT_STACK_FILE_NAME\""
  execute_ssh "cd \"$INPUT_DEPLOY_PATH/stacks\" && ls -t docker-stack-* 2>/dev/null | tail -n +$INPUT_KEEP_FILES | while read -r file; do rm -f \"\$file\" 2>/dev/null; done || true"
fi

# Run pre-deployment commands if specified (docker-compose mode)
# Pre-deployment commands (e.g., 'config' validation) must run BEFORE pulling images
# so that invalid configs fail fast without wasting bandwidth on image pulls.
if [ -n "${INPUT_PRE_DEPLOYMENT_COMMAND_ARGS+x}" ] && [ "$INPUT_DEPLOYMENT_MODE" = 'docker-compose' ] ; then
  echo "Running pre-deployment commands..."
  if [ "$INPUT_COPY_STACK_FILE" = 'true' ] ; then
    execute_ssh "${DEPLOYMENT_COMMAND} ${INPUT_PRE_DEPLOYMENT_COMMAND_ARGS}"
  else
    eval "${DEPLOYMENT_COMMAND} ${INPUT_PRE_DEPLOYMENT_COMMAND_ARGS}" 2>&1
  fi
fi

# Pull images if requested (after pre-deployment validation, before deployment)
if [ "$INPUT_PULL_IMAGES_FIRST" = 'true' ] ; then
  if [ "$INPUT_DEPLOYMENT_MODE" != 'docker-compose' ] ; then
    echo "Warning: pull_images_first is only supported in docker-compose mode, skipping pull."
  else
    echo "Pulling images..."
    if [ "$INPUT_COPY_STACK_FILE" = 'true' ] ; then
      execute_ssh "${DEPLOYMENT_COMMAND} pull"
    else
      eval "${DEPLOYMENT_COMMAND} pull" 2>&1
    fi
  fi
fi

# Run deployment
if [ "$INPUT_COPY_STACK_FILE" = 'true' ] ; then
  echo "Running deployment..."
  execute_ssh "${DEPLOYMENT_COMMAND} ${INPUT_ARGS}"
else
  echo "Connecting to $INPUT_REMOTE_DOCKER_HOST... Command: ${DEPLOYMENT_COMMAND} ${INPUT_ARGS}"
  eval "${DEPLOYMENT_COMMAND} ${INPUT_ARGS}" 2>&1
fi

# Run docker system prune AFTER deployment so we don't remove images needed for deployment
if [ "$INPUT_DOCKER_PRUNE" = 'true' ] ; then
  echo "WARNING: This will remove unused images, containers, and networks."
  echo "Note: Volumes are NOT removed (no --volumes flag). Add --volumes to the prune command if volume cleanup is needed."
  echo "This is a destructive operation that cannot be undone."
  echo "Proceeding with docker prune automatically..."
  if ! docker --log-level debug --host "ssh://$INPUT_REMOTE_DOCKER_HOST:$INPUT_REMOTE_DOCKER_PORT" system prune -a -f; then
    echo "Error: Docker prune failed"
    exit 1
  fi
fi
