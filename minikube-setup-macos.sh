#!/bin/bash

# Script to install minikube on macOS using Homebrew
DOCKER_HOST="unix://${HOME}/.colima/docker.sock" 
num_cpus=$((($(sysctl -n hw.ncpu) + 1) / 2))
mem_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
available_mem_gb=16

# Check if there is less than double the available memory
if [ "$mem_gb" -lt $((available_mem_gb * 2)) ]; then
  echo "❌ This system only has $mem_gb GB of RAM. At least $((available_mem_gb * 2)) GB is required."
  exit 1
fi

check_colima_memory() {
  # Check if Colima is running
  if ! colima status -e -j >/dev/null 2>&1; then
      echo "⚠️ Colima is not running"
      return 1
  fi
  
  # Get current memory configured in Colima
  current_mem_bytes=$(colima status -e -j | grep -o '"memory":[0-9]*' | cut -d':' -f2)
  current_mem_gb=$((current_mem_bytes / 1024 / 1024 / 1024))
  
  echo "💾 Current Colima memory: ${current_mem_gb}GB"
  echo "🎯 Required memory: ${available_mem_gb}GB"
  
  # Return 0 if memory needs adjustment, 1 if correct
  if [ "$current_mem_gb" -eq "$available_mem_gb" ]; then
      echo "✅ Memory is correctly configured"
      return 1
  else
      echo "⚙️ Memory needs adjustment"
      return 0
  fi
}

chmod +x tools-macos.sh
./tools-macos.sh

if ! command -v docker &>/dev/null; then
  echo "🐳 Docker is not installed. Installing with Homebrew..."
  brew install docker
fi

if ! command -v minikube &>/dev/null; then
  echo "🚢 Minikube is not installed. Attempting to install with Homebrew..."
  brew install minikube
  if [ $? -ne 0 ]; then
    echo "❌ Error installing Minikube. Please check the error messages."
    exit 1
  fi
else
  echo "✅ Minikube is already installed."
fi

# Install colima to manage docker in macos 
if ! command -v colima &>/dev/null; then
  echo "🐳 Colima is not installed. Attempting to install with Homebrew..."
  brew install colima
fi

# Manage Colima
if ! colima status >/dev/null 2>&1; then
    echo "🐳 Starting Colima with ${available_mem_gb}GB of RAM..."
    colima start --cpu $num_cpus --memory $available_mem_gb --runtime docker
elif check_colima_memory; then
    echo "🔄 Restarting Colima to adjust memory to ${available_mem_gb}GB..."
    colima stop
    colima start --cpu $num_cpus --memory $available_mem_gb --runtime docker
else
    echo "✅ Colima is already running with correct memory configuration"
fi

docker context use colima

# Check if Minikube is already running
if minikube status >/dev/null 2>&1; then
    echo "🛑 Minikube is already running. Stopping it..."
    minikube stop
fi

# Start Minikube with specified configuration
echo "🚀 Starting Minikube..."

minikube start \
  --memory=$(($available_mem_gb - 1))g \
  --cpus=$num_cpus \
  --driver=docker \
  --kubernetes-version=v1.32.0 \
  --cache-images=true \
  --disable-driver-mounts \
  --extra-config=kubelet.cgroup-driver=systemd

echo "✨ Minikube enabled."

minikube addons enable storage-provisioner
minikube addons enable default-storageclass

echo "✨ Minikube prepared successfully."