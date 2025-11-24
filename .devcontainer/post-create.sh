#!/bin/bash
set -e

# get current git branch
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

URL_BRANCH="https://raw.githubusercontent.com/LMS-Community/slimserver-platforms/${BRANCH}/Docker/Slim-Utils-OS-Custom.pm"
URL_HEAD="https://raw.githubusercontent.com/LMS-Community/slimserver-platforms/HEAD/Docker/Slim-Utils-OS-Custom.pm"
TARGET_FILE="/workspaces/slimserver/Slim/Utils/OS/Custom.pm"

echo "Detected branch: ${BRANCH}"
echo "Trying branch-specific file..."

# Try downloading branch version
if curl -fSL "$URL_BRANCH" -o "$TARGET_FILE"; then
    echo "Downloaded branch version from: $URL_BRANCH"
else
    echo "Branch file not found, falling back to HEAD..."
    curl -fSL "$URL_HEAD" -o "$TARGET_FILE"
    echo "Downloaded latest version from: $URL_HEAD"
fi