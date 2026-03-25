#!/bin/bash

# Ensure the SSH directory exists with correct permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Function to safely create a key file from user input
setup_key_file() {
    local file_path=$1
    local description=$2
    
    echo "Please paste your $description below (Press Ctrl+D when finished):"
    cat > "$file_path"
}

# Setup Private and Public keys
setup_key_file "$HOME/.ssh/id_ed25519" "PRIVATE KEY"
setup_key_file "$HOME/.ssh/id_ed25519.pub" "PUBLIC KEY"

# Set strict permissions for the private key
chmod 600 ~/.ssh/id_ed25519

# Start ssh-agent and add the key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# --- Git Auth & GPG Signing Configuration ---

# Configure Git to use SSH for signing
git config --global gpg.format ssh
git config --global user.signingkey "$HOME/.ssh/id_ed25519.pub"
git config --global commit.gpgsign true

# Set up the allowed_signers file for local verification
ALLOWED_SIGNERS_FILE="$HOME/.ssh/allowed_signers"
touch "$ALLOWED_SIGNERS_FILE"

# Append the current git email and public key to allowed_signers
USER_EMAIL=$(git config --get user.email)
PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)

echo "$USER_EMAIL $PUB_KEY" >> "$ALLOWED_SIGNERS_FILE"

# Point Git to the allowed_signers file
git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS_FILE"

echo "Setup complete! Your Git commits will now be signed using your SSH key."
