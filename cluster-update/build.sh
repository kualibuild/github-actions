#!/usr/bin/env bash
# Copyright © 2020-2025 Kuali, Inc. - All Rights Reserved
echo "Building ${PWD##*/} for linux/amd64..."
env GOOS=linux GOARCH=amd64 go build -o ${PWD##*/}-linux-amd64 .
echo "Building ${PWD##*/} for linux/arm64..."
env GOOS=linux GOARCH=arm64 go build -o ${PWD##*/}-linux-arm64 .
echo "Building ${PWD##*/} for darwin/amd64..."
env GOOS=darwin GOARCH=arm64 go build -o ${PWD##*/}-darwin-amd64 .
echo "Building ${PWD##*/} for darwin/arm64..."
env GOOS=darwin GOARCH=arm64 go build -o ${PWD##*/}-darwin-arm64 .
