#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
outer_root="$repo_root/ai-native-backend-jvm"
canary_root="$outer_root/domains/deposits/deposits-transactions-core"
expected_wrapper_sha="55243ef57851f12b070ad14f7f5bb8302daceeebc5bce5ece5fa6edb23e1145c"
expected_distribution_sha="2ab2958f2a1e51120c326cad6f385153bb11ee93b3c216c5fccebfdfbb7ec6cb"
expected_distribution_line="distributionSha256Sum=$expected_distribution_sha"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

validate_runtime=false
validate_build=false
for arg in "$@"; do
  case "$arg" in
    --runtime) validate_runtime=true ;;
    --built) validate_build=true ;;
    *) printf 'Usage: %s [--runtime] [--built]\n' "$0" >&2; exit 2 ;;
  esac
done

outer_wrapper="$outer_root/gradlew"
nested_wrapper="$canary_root/gradlew"

[[ -x "$outer_wrapper" ]] || fail "outer Gradle wrapper is missing or not executable"
[[ -x "$nested_wrapper" ]] || fail "nested Gradle wrapper is missing or not executable"

wrapper_count="$(
  find "$repo_root" -type f \( -name gradlew -o -name gradlew.bat \) -print |
    wc -l | tr -d ' '
)"
[[ "$wrapper_count" == "4" ]] || fail "expected two Unix and two Windows wrapper scripts, found $wrapper_count"

manifest_count="$(
  find "$canary_root" -name build.gradle.kts -type f -print |
    wc -l | tr -d ' '
)"
[[ "$manifest_count" == "6" ]] || fail "expected 6 canary manifests, found $manifest_count"

for library in \
  ach-pse \
  credibanco-bre-b \
  deposits-fraud \
  deposits-transactions-core-sdk \
  neurona
do
  library_root="$canary_root/libraries/$library"
  [[ -f "$library_root/build.gradle.kts" ]] || fail "missing manifest for $library"
  [[ -f "$library_root/settings.gradle.kts" ]] || fail "missing settings for $library"
  if find "$library_root" \( -name gradlew -o -name gradlew.bat \) -type f -print -quit | read -r _; then
    fail "library build $library must not contain a wrapper"
  fi
done

for root in "$outer_root" "$canary_root"; do
  properties="$root/gradle/wrapper/gradle-wrapper.properties"
  jar="$root/gradle/wrapper/gradle-wrapper.jar"
  [[ -f "$properties" ]] || fail "missing wrapper properties under $root"
  [[ -f "$jar" ]] || fail "missing wrapper JAR under $root"
  case "$(cat "$properties")" in
    *gradle-9.4.1-bin.zip*) ;;
    *) fail "wrapper under $root does not select Gradle 9.4.1" ;;
  esac
  distribution_line_count="$(grep -Fxc "$expected_distribution_line" "$properties" || true)"
  distribution_property_count="$(grep -Fc 'distributionSha256Sum' "$properties" || true)"
  [[ "$distribution_line_count" == "1" && "$distribution_property_count" == "1" ]] ||
    fail "Gradle distribution checksum mismatch under $root"
  actual_sha="$(shasum -a 256 "$jar" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_wrapper_sha" ]] ||
    fail "wrapper JAR checksum mismatch under $root"
done

for script in \
  setup-mandrel.sh \
  run-baseline.sh \
  run-regression.sh
do
  [[ -x "$repo_root/scripts/$script" ]] || fail "missing executable scripts/$script"
  bash -n "$repo_root/scripts/$script"
done

if [[ "$validate_runtime" == true ]]; then
  [[ -n "${JAVA_HOME:-}" ]] || fail "JAVA_HOME is required for --runtime"
  [[ -x "$JAVA_HOME/bin/java" ]] || fail "JAVA_HOME has no executable java"
  [[ -x "$JAVA_HOME/bin/native-image" ]] || fail "JAVA_HOME has no executable native-image"
  java_output="$("$JAVA_HOME/bin/java" -version 2>&1)" ||
    fail "unable to run JAVA_HOME/bin/java"
  mandrel_output="$("$JAVA_HOME/bin/native-image" --version 2>&1)" ||
    fail "unable to run JAVA_HOME/bin/native-image"
  [[ "$java_output" == *"25.0.2"* ]] || fail "runtime is not Java 25.0.2"
  [[ "$mandrel_output" == *"Mandrel-25.0.2.0-Final"* ]] ||
    fail "runtime is not Mandrel 25.0.2.0-Final"
fi

if [[ "$validate_build" == true ]]; then
  [[ -n "${JAVA_HOME:-}" ]] || fail "JAVA_HOME is required for --built"
  artifacts=(
    "$canary_root/build/classes/java/main/example/transactions/TransactionService.class"
    "$canary_root/libraries/ach-pse/build/classes/java/main/example/achpse/AchPseLibrary.class"
    "$canary_root/libraries/credibanco-bre-b/build/classes/java/main/example/credibanco/CredibancoLibrary.class"
    "$canary_root/libraries/deposits-fraud/build/classes/java/main/example/fraud/DepositsFraudLibrary.class"
    "$canary_root/libraries/deposits-transactions-core-sdk/build/classes/java/main/example/sdk/TransactionsCoreApi.class"
    "$canary_root/libraries/neurona/build/classes/java/main/example/neurona/NeuronaLibrary.class"
  )
  for artifact in "${artifacts[@]}"; do
    [[ -f "$artifact" ]] || fail "missing class output: $artifact"
  done
fi

printf 'Fixture contract passed.\n'
