#!/bin/bash

# Install common tools on macOS using Homebrew

if ! command -v brew &>/dev/null; then
  echo "⚠️ Homebrew is not installed. Please install it from https://brew.sh"
  exit 1
fi

brew update

if ! command -v kubectl &>/dev/null; then
    echo "📦 kubectl is not installed. Installing with Homebrew..."
    brew install kubectl
fi
if ! command -v helm &>/dev/null; then
    echo "⚓ helm is not installed. Installing with Homebrew..."
    brew install helm
fi
# if ! command -v jq &>/dev/null; then
#     echo "🔧 jq is not installed. Installing with Homebrew..."
#     brew install jq
# fi
# if ! command -v yq &>/dev/null; then
#     echo "🔧 yq is not installed. Installing with Homebrew..."
#     brew install yq
# fi
if ! command -v openssl &>/dev/null; then
  echo "🔒 openssl is not installed. Installing with Homebrew..."
  brew install openssl
fi

echo "✅ All tools installed successfully."