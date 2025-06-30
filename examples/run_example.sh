#!/bin/bash

# Change to the parent directory where config files are located
cd "$(dirname "$0")/.."

# Run the example app
elixir examples/example_app.exs "$@"