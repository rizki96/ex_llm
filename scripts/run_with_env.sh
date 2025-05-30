#!/bin/bash
# Wrapper script to run commands with environment variables loaded

# Load environment variables from ~/.env
if [ -f ~/.env ]; then
    set -a  # automatically export all variables
    source ~/.env
    set +a  # turn off automatic export
fi

# Run the command passed as arguments
"$@"