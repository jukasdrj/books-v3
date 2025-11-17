#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Install Xcode ---
# In a real CI environment, this would involve a more robust installation process.
# For this sandboxed environment, we'll assume xcodebuild is available if Xcode is installed.
if ! command -v xcodebuild &> /dev/null
then
    echo "xcodebuild could not be found. Please install Xcode."
    # On a real system you might use:
    # xcode-select --install
    # For now, we'll just exit.
    exit 1
else
    echo "Xcode command line tools are already installed."
fi

# --- Set up NVM and Node.js ---
# This function handles the installation and setup of Node.js using nvm.
setup_node() {
  export NVM_DIR="$HOME/.nvm"
  # Check if nvm is installed, and if not, install it.
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    echo "nvm not found, installing..."
    # Download and run the nvm installation script.
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi

  # Source nvm to make it available in this script's session.
  # The ' shellcheck disable=SC1091 ' is used to ignore the warning about the file not being found,
  # as it is created by the installation script.
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

  # Check if nvm command is now available.
  if ! command -v nvm &> /dev/null
  then
      echo "nvm command could not be found after installation. Something went wrong."
      exit 1
  fi

  # Use nvm to manage node versions.
  # The .nvmrc file in the root of the repository specifies the required version.
  if [ -f ".nvmrc" ]; then
    echo "Found .nvmrc, installing and using specified Node.js version..."
    nvm install
    nvm use
  else
    echo "No .nvmrc file found. Using default node version."
  fi
}

# Run the Node.js setup function.
setup_node

# --- Install ast-grep ---
echo "Installing ast-grep globally with npm..."
npm install -g @ast-grep/cli

echo "Setup complete."
