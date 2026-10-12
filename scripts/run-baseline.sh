#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || {
    printf 'Required environment variable is not set: %s\n' "$name" >&2
    exit 2
  }
}

require_gradle_version() {
  local label="$1"
  local wrapper="$2"
  local project_root="$3"
  local output

  output="$("$wrapper" -p "$project_root" --version 2>&1)" || {
    printf 'Unable to run the %s Gradle wrapper.\n' "$label" >&2
    exit 2
  }
  printf '%s\n' "$output" | grep -Fqx 'Gradle 9.4.1' || {
    printf 'The %s Gradle wrapper must report Gradle 9.4.1. Current output:\n%s\n' \
      "$label" "$output" >&2
    exit 2
  }
}

require_env ENDOR_NAMESPACE
require_env ENDOR_API
require_env JAVA_HOME

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
outer_root="$repo_root/ai-native-backend-jvm"
canary_root="$outer_root/domains/deposits/deposits-transactions-core"
log_file="$repo_root/java25-gradle941-nested-wrapper-baseline.log"
ref_name="${BASELINE_REF:-java25-gradle941-nested-wrapper-baseline}"
java_bin="$JAVA_HOME/bin/java"
native_image_bin="$JAVA_HOME/bin/native-image"

[[ -x "$java_bin" ]] || {
  printf 'JAVA_HOME has no executable java: %s\n' "$java_bin" >&2
  exit 2
}
[[ -x "$native_image_bin" ]] || {
  printf 'JAVA_HOME has no executable native-image: %s\n' "$native_image_bin" >&2
  exit 2
}

java_output="$("$java_bin" -version 2>&1)" || {
  printf 'Unable to run Java from JAVA_HOME.\n' >&2
  exit 2
}
mandrel_output="$("$native_image_bin" --version 2>&1)" || {
  printf 'Unable to run native-image from JAVA_HOME.\n' >&2
  exit 2
}
[[ "$java_output" == *"25.0.2"* &&
  "$mandrel_output" == *"Mandrel-25.0.2.0-Final"* ]] || {
  printf 'JAVA_HOME must point to Mandrel 25.0.2.0-Final. Current output:\n%s\n%s\n' \
    "$java_output" "$mandrel_output" >&2
  exit 2
}

command -v endorctl >/dev/null 2>&1 || {
  printf 'endorctl is not available on PATH.\n' >&2
  exit 2
}

export PATH="$JAVA_HOME/bin:$PATH"

require_gradle_version "outer" "$outer_root/gradlew" "$outer_root"
require_gradle_version "nested" "$canary_root/gradlew" "$canary_root"
"$outer_root/gradlew" -p "$outer_root" buildAll

artifact="$(
  find "$canary_root" -type f \
    \( -path '*/build/libs/*.jar' -o \( -path '*/build/classes/*' -name '*.class' \) \) \
    -print -quit
)"
[[ -n "$artifact" ]] || {
  printf 'Prebuild produced no canary JAR or class output.\n' >&2
  exit 2
}

export ENDOR_LOG_LEVEL=debug
export ENDOR_SCAN_GRADLE_PRINT_DEBUG=true

endorctl scan \
  --namespace "$ENDOR_NAMESPACE" \
  --api "$ENDOR_API" \
  --path "$repo_root" \
  --dependencies \
  --languages=java,kotlin \
  --include-path='ai-native-backend-jvm/domains/deposits/deposits-transactions-core/**' \
  --detached-ref-name="$ref_name" \
  --tags='java25,gradle941,nested-wrapper,baseline' \
  --verbose \
  2>&1 | tee "$log_file"
