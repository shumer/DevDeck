#!/bin/bash
# Sourced by build.sh, run-tests.sh and smoke-test.sh: picks the SDK to build against.
#
# The Command Line Tools point their default SDK symlink at whatever they shipped with, which
# after an update can be a beta SDK for the *next* macOS. In that SDK SwiftUI's `@State` is a
# macro, and the macro plugin that expands it ships with Xcode, not with the Command Line
# Tools, so every card fails to compile with "plugin for module 'SwiftUIMacros' not found".
# Building against the SDK that matches the running macOS is what worked before the update
# and keeps working after it.
#
# Does nothing when SDKROOT is already set, or when the tools are Xcode's (CI), whose SDK is
# always the right one.
if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs ]; then
  major="$(sw_vers -productVersion | cut -d. -f1)"
  sdk="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX"${major}".*.sdk 2>/dev/null | sort -V | tail -1)"
  if [ -n "$sdk" ]; then
    export SDKROOT="$sdk"
  fi
fi
