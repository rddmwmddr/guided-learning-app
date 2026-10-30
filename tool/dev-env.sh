#!/bin/sh
# Optional Homebrew shortcuts; standard Flutter/Android installations work without this file.
if command -v brew >/dev/null 2>&1; then
  task_brew_prefix="$(brew --prefix)"
  task_jdk="$task_brew_prefix/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  [ ! -d "$task_jdk" ] || export JAVA_HOME="$task_jdk"
  [ ! -d "$task_brew_prefix/share/android-commandlinetools" ] || export ANDROID_HOME="$task_brew_prefix/share/android-commandlinetools"
fi
if [ -n "${ANDROID_HOME:-}" ]; then
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export PATH="$ANDROID_HOME/platform-tools:$PATH"
fi
if [ -n "${JAVA_HOME:-}" ]; then export PATH="$JAVA_HOME/bin:$PATH"; fi
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
