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
if ! command -v skaffold &>/dev/null; then
    echo "🚧 skaffold is not installed. Installing with Homebrew..."
    brew install skaffold
fi

echo "✅ All tools installed successfully."