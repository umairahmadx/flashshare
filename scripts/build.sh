#!/bin/bash

set -e

echo "Installing Flutter..."

git clone https://github.com/flutter/flutter.git \
    --depth 1 \
    --branch stable \
    "$HOME/flutter"

export PATH="$HOME/flutter/bin:$PATH"

echo "Flutter version:"
flutter --version

echo "Enabling web..."
flutter config --enable-web

echo "Getting dependencies..."
flutter pub get

echo "Building Flutter Web..."
flutter build web --release

echo "Build completed!"
