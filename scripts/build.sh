#!/bin/bash

# Copyright (c) 2021 InSeven Limited
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -e
set -o pipefail
set -x
set -u

SCRIPTS_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

ROOT_DIRECTORY="${SCRIPTS_DIRECTORY}/.."
BUILD_DIRECTORY="${ROOT_DIRECTORY}/build"
TEMPORARY_DIRECTORY="${ROOT_DIRECTORY}/temp"

PROJECT_PATH="${ROOT_DIRECTORY}/macos/Multifolder.xcodeproj"
KEYCHAIN_PATH="${TEMPORARY_DIRECTORY}/temporary.keychain"
ARCHIVE_PATH="${BUILD_DIRECTORY}/Multifolder.xcarchive"
FASTLANE_ENV_PATH="${ROOT_DIRECTORY}/fastlane/.env"

CHANGES_SCRIPT="${SCRIPTS_DIRECTORY}/changes/changes"
BUILD_TOOLS_SCRIPT="${SCRIPTS_DIRECTORY}/build-tools/build-tools"

# Process the command line arguments.
POSITIONAL=()
NOTARIZE=true
RELEASE=false
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -N|--skip-notarize)
        NOTARIZE=false
        shift
        ;;
        -r|--release)
        RELEASE=true
        shift
        ;;
        *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
done

# Generate a random string to secure the local keychain.
export TEMPORARY_KEYCHAIN_PASSWORD=`openssl rand -base64 14`

# Source the Fastlane .env file if it exists to make local development easier.
if [ -f "$FASTLANE_ENV_PATH" ] ; then
    echo "Sourcing .env..."
    source "$FASTLANE_ENV_PATH"
fi

function build_scheme {
    # Disable code signing for the build server.
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$1" \
        clean \
        build \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO | xcpretty
}

cd "$ROOT_DIRECTORY"

# List the available schemes
xcodebuild -project "$PROJECT_PATH" -list

# Smoke test builds.

build_scheme "Multifolder"

# Build the macOS archive.

# Clean up the build directory.
if [ -d "$BUILD_DIRECTORY" ] ; then
    rm -r "$BUILD_DIRECTORY"
fi
mkdir -p "$BUILD_DIRECTORY"

# Create the a new keychain.
if [ -d "$TEMPORARY_DIRECTORY" ] ; then
    rm -rf "$TEMPORARY_DIRECTORY"
fi
mkdir -p "$TEMPORARY_DIRECTORY"
echo "$TEMPORARY_KEYCHAIN_PASSWORD" | "$BUILD_TOOLS_SCRIPT" create-keychain "$KEYCHAIN_PATH" --password

function cleanup {
    # Cleanup the temporary files and keychain.
    cd "$ROOT_DIRECTORY"
    "$BUILD_TOOLS_SCRIPT" delete-keychain "$KEYCHAIN_PATH"
    rm -rf "$TEMPORARY_DIRECTORY"
}

trap cleanup EXIT

# Determine the version and build number.
VERSION_NUMBER=`"$CHANGES_SCRIPT" --scope macOS current-version`
GIT_COMMIT=`git rev-parse --short HEAD`
TIMESTAMP=`date +%s`
BUILD_NUMBER="${GIT_COMMIT}.${TIMESTAMP}"

# Import the certificates into our dedicated keychain.
fastlane import_certificates keychain:"$KEYCHAIN_PATH"

# Archive and export the build.
xcodebuild -project "$PROJECT_PATH" -scheme "Multifolder" -config Release -archivePath "$ARCHIVE_PATH"  OTHER_CODE_SIGN_FLAGS="--keychain=\"${KEYCHAIN_PATH}\"" BUILD_NUMBER=$BUILD_NUMBER MARKETING_VERSION=$VERSION_NUMBER archive | xcpretty
xcodebuild -archivePath "$ARCHIVE_PATH" -exportArchive -exportPath "$BUILD_DIRECTORY" -exportOptionsPlist "macos/ExportOptions.plist"

APP_BASENAME="Multifolder.app"
APP_PATH="$BUILD_DIRECTORY/$APP_BASENAME"

# Show the code signing details.
codesign -dvv "$APP_PATH"

# Notarize the release build.
if $NOTARIZE ; then
    fastlane notarize_release package:"$APP_PATH"
fi

# Archive the results.
pushd "$BUILD_DIRECTORY"
ZIP_BASENAME="Multifolder-${VERSION_NUMBER}.zip"
zip -r --symlinks "$ZIP_BASENAME" "$APP_BASENAME"
"$BUILD_TOOLS_SCRIPT" verify-notarized-zip "$ZIP_BASENAME"
rm -r "$APP_BASENAME"
zip -r "Artifacts.zip" "."
popd

# Attempt to create a version tag and publish a GitHub release.
# This fails quietly if there's no release to be made.
if $RELEASE || $TRY_RELEASE ; then
    # List the current tags just to check GitHub has them.
    git tag
    "$CHANGES_SCRIPT" --scope macOS release --skip-if-empty --push --command 'scripts/release.sh'
fi