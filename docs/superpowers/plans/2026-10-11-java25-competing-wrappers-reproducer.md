# Java 25 Competing Gradle Wrappers Reproducer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Mandrel Java 25 and Gradle 9.4.1 repository that compares nested-wrapper package discovery against competing outer and nested wrapper discovery.

**Architecture:** A non-Gradle Git root contains `ai-native-backend-jvm`, which owns an outer Gradle wrapper and includes a canary composite build. The canary owns a second wrapper and includes five wrapperless library builds. Two scan scripts run against the same commit and prebuilt outputs. Their only scan-scope difference is whether the outer wrapper is visible.

**Tech Stack:** Mandrel Java 25.0.2.0-Final, Gradle 9.4.1, Kotlin Gradle DSL, Bash, endorctl

**Spec:** `docs/superpowers/specs/2026-10-11-java25-competing-wrappers-reproducer-design.md`

## Global Constraints

- Keep all work inside `/Users/lmoreno/git/endor-internal/java-gradle-composite-scan`.
- Preserve the approved customer-derived directory and artifact names.
- Do not copy customer source code, proprietary build plugins, credentials, tenant values, or private dependencies.
- Do not add third-party Java dependencies.
- Do not run endorctl during implementation or local verification.
- Generate standard Gradle 9.4.1 wrappers through Gradle 9.4.1 itself.
- Verify both wrapper JARs against SHA-256 `55243ef57851f12b070ad14f7f5bb8302daceeebc5bce5ece5fa6edb23e1145c`.
- Verify the Gradle 9.4.1 binary ZIP against SHA-256 `2ab2958f2a1e51120c326cad6f385153bb11ee93b3c216c5fccebfdfbb7ec6cb`.
- Verify the Mandrel archive against SHA-256 `0b6d6c0ef85028b49080cba74c94090b73a281a01b1acf331990742ff8c6ea31`.
- Use Java source and bytecode compatibility 25.
- Leave all Gradle project versions unset so Gradle reports `unspecified`.
- Keep all five library builds wrapperless.
- Preserve exactly two wrappers and six selected manifests.
- Keep baseline and regression scan scripts identical except for the outer-wrapper include, detached ref, tag, and log name.

## Review Focus

- The baseline scope must include the nested wrapper but not the outer wrapper.
- The regression scope must include both wrappers.
- The outer and nested Gradle wrappers must be real 9.4.1 wrappers, not mixed-version wrapper JARs.
- The five libraries must remain independent composite builds with no wrapper.
- Scan scripts must stop before any API call when environment or runtime validation fails.
- No local verification command may invoke endorctl or write remote scan data.
- Mandrel and Gradle downloads, caches, build output, and scan logs must remain untracked.

---

### Task 1: Add the API-free fixture contract

**Files:**
- Create: `.gitignore`
- Create: `scripts/verify-fixture.sh`
- Test: `scripts/verify-fixture.sh`

**Interfaces:**
- Consumes: The topology and checksums defined in the approved spec.
- Produces: A local fixture contract with structure, wrapper, runtime, and build-output modes.

- [ ] **Step 1: Write the failing contract script**

Create `scripts/verify-fixture.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
outer_root="$repo_root/ai-native-backend-jvm"
canary_root="$outer_root/domains/deposits/deposits-transactions-core"
expected_wrapper_sha="55243ef57851f12b070ad14f7f5bb8302daceeebc5bce5ece5fa6edb23e1145c"

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
  java_output="$("$JAVA_HOME/bin/java" -version 2>&1)" ||
    fail "unable to run JAVA_HOME/bin/java"
  [[ "$java_output" == *"Mandrel"* ]] || fail "runtime is not Mandrel"
  [[ "$java_output" == *"25.0.2"* ]] || fail "runtime is not Mandrel 25.0.2"
fi

if [[ "$validate_build" == true ]]; then
  [[ -n "${JAVA_HOME:-}" ]] || fail "JAVA_HOME is required for --built"
  roots=(
    "$canary_root"
    "$canary_root/libraries/ach-pse"
    "$canary_root/libraries/credibanco-bre-b"
    "$canary_root/libraries/deposits-fraud"
    "$canary_root/libraries/deposits-transactions-core-sdk"
    "$canary_root/libraries/neurona"
  )
  for root in "${roots[@]}"; do
    artifact="$(
      find "$root" -type f \
        \( -path '*/build/libs/*.jar' -o \( -path '*/build/classes/*' -name '*.class' \) \) \
        -print -quit
    )"
    [[ -n "$artifact" ]] || fail "no JAR or class output under $root"
  done
fi

printf 'Fixture contract passed.\n'
```

Create `.gitignore`:

```gitignore
.DS_Store
.tools/
.gradle/
**/.gradle/
**/build/
*.log
```

Make `scripts/verify-fixture.sh` executable.

- [ ] **Step 2: Verify RED**

Run:

```bash
./scripts/verify-fixture.sh
```

Expected: `FAIL: outer Gradle wrapper is missing or not executable`.

- [ ] **Step 3: Verify script syntax**

Run:

```bash
bash -n scripts/verify-fixture.sh
```

Expected: exit code 0.

### Task 2: Create the nested composite fixture

**Files:**
- Create: `ai-native-backend-jvm/settings.gradle.kts`
- Create: `ai-native-backend-jvm/build.gradle.kts`
- Create: `ai-native-backend-jvm/gradle.properties`
- Create: `ai-native-backend-jvm/domains/deposits/deposits-transactions-core/settings.gradle.kts`
- Create: `ai-native-backend-jvm/domains/deposits/deposits-transactions-core/build.gradle.kts`
- Create: `ai-native-backend-jvm/domains/deposits/deposits-transactions-core/gradle.properties`
- Create: five library `settings.gradle.kts` files
- Create: five library `build.gradle.kts` files
- Create: six Java source files
- Test: `scripts/verify-fixture.sh`

**Interfaces:**
- Consumes: The six-manifest and two-level composite contract.
- Produces: One canary source package and five direct composite-library dependencies.

- [ ] **Step 1: Create the outer build**

Create `ai-native-backend-jvm/settings.gradle.kts`:

```kotlin
rootProject.name = "ai-native-backend-jvm"

includeBuild("domains/deposits/deposits-transactions-core")
```

Create `ai-native-backend-jvm/build.gradle.kts`:

```kotlin
plugins {
    base
}

val transactionsCore = gradle.includedBuild("deposits-transactions-core")

tasks.register("buildAll") {
    group = "build"
    description = "Build the transaction-core composite and all included libraries."
    dependsOn(transactionsCore.task(":buildAll"))
}
```

Create `ai-native-backend-jvm/gradle.properties`:

```properties
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.warning.mode=all
```

- [ ] **Step 2: Create the canary composite build**

Create `domains/deposits/deposits-transactions-core/settings.gradle.kts`:

```kotlin
rootProject.name = "deposits-transactions-core-system"

includeBuild("libraries/ach-pse")
includeBuild("libraries/credibanco-bre-b")
includeBuild("libraries/deposits-fraud")
includeBuild("libraries/deposits-transactions-core-sdk")
includeBuild("libraries/neurona")
```

Create `domains/deposits/deposits-transactions-core/build.gradle.kts`:

```kotlin
plugins {
    application
}

group = "com.example.system"

java {
    sourceCompatibility = JavaVersion.VERSION_25
    targetCompatibility = JavaVersion.VERSION_25
}

application {
    mainClass.set("example.transactions.TransactionService")
}

dependencies {
    implementation("com.example.library:ach-pse-library:unspecified")
    implementation("com.example.library:credibanco-bre-b-library:unspecified")
    implementation("com.example.library:deposits-fraud-library:unspecified")
    implementation("com.example.library:deposits-transactions-core-sdk:unspecified")
    implementation("com.example.library:neurona-library:unspecified")
}

val achPse = gradle.includedBuild("ach-pse-library")
val credibanco = gradle.includedBuild("credibanco-bre-b-library")
val fraud = gradle.includedBuild("deposits-fraud-library")
val sdk = gradle.includedBuild("deposits-transactions-core-sdk")
val neurona = gradle.includedBuild("neurona-library")

tasks.register("buildAll") {
    group = "build"
    description = "Build the canary and all five included libraries."
    dependsOn(
        tasks.named("build"),
        achPse.task(":build"),
        credibanco.task(":build"),
        fraud.task(":build"),
        sdk.task(":build"),
        neurona.task(":build"),
    )
}
```

Create `gradle.properties`:

```properties
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.warning.mode=all
```

- [ ] **Step 3: Create five wrapperless library builds**

Create `libraries/ach-pse/settings.gradle.kts`:

```kotlin
rootProject.name = "ach-pse-library"
```

Create `libraries/credibanco-bre-b/settings.gradle.kts`:

```kotlin
rootProject.name = "credibanco-bre-b-library"
```

Create `libraries/deposits-fraud/settings.gradle.kts`:

```kotlin
rootProject.name = "deposits-fraud-library"
```

Create `libraries/deposits-transactions-core-sdk/settings.gradle.kts`:

```kotlin
rootProject.name = "deposits-transactions-core-sdk"
```

Create `libraries/neurona/settings.gradle.kts`:

```kotlin
rootProject.name = "neurona-library"
```

Create these five files with the exact shared content below:

```text
libraries/ach-pse/build.gradle.kts
libraries/credibanco-bre-b/build.gradle.kts
libraries/deposits-fraud/build.gradle.kts
libraries/deposits-transactions-core-sdk/build.gradle.kts
libraries/neurona/build.gradle.kts
```

```kotlin
plugins {
    `java-library`
}

group = "com.example.library"

java {
    sourceCompatibility = JavaVersion.VERSION_25
    targetCompatibility = JavaVersion.VERSION_25
}
```

Do not set `version` in any build.

- [ ] **Step 4: Add minimal Java source**

Create `TransactionService.java`:

```java
package example.transactions;

import example.achpse.AchPseLibrary;
import example.credibanco.CredibancoLibrary;
import example.fraud.DepositsFraudLibrary;
import example.neurona.NeuronaLibrary;
import example.sdk.TransactionsCoreApi;

public final class TransactionService {
    private TransactionService() {}

    public static void main(String[] args) {
        System.out.println(String.join(
            ",",
            AchPseLibrary.name(),
            CredibancoLibrary.name(),
            DepositsFraudLibrary.name(),
            TransactionsCoreApi.name(),
            NeuronaLibrary.name()
        ));
    }
}
```

Create `libraries/ach-pse/src/main/java/example/achpse/AchPseLibrary.java`:

```java
package example.achpse;

public final class AchPseLibrary {
    private AchPseLibrary() {}

    public static String name() {
        return "ach-pse";
    }
}
```

Create `libraries/credibanco-bre-b/src/main/java/example/credibanco/CredibancoLibrary.java`:

```java
package example.credibanco;

public final class CredibancoLibrary {
    private CredibancoLibrary() {}

    public static String name() {
        return "credibanco-bre-b";
    }
}
```

Create `libraries/deposits-fraud/src/main/java/example/fraud/DepositsFraudLibrary.java`:

```java
package example.fraud;

public final class DepositsFraudLibrary {
    private DepositsFraudLibrary() {}

    public static String name() {
        return "deposits-fraud";
    }
}
```

Create `libraries/deposits-transactions-core-sdk/src/main/java/example/sdk/TransactionsCoreApi.java`:

```java
package example.sdk;

public interface TransactionsCoreApi {
    static String name() {
        return "deposits-transactions-core-sdk";
    }
}
```

Create `libraries/neurona/src/main/java/example/neurona/NeuronaLibrary.java`:

```java
package example.neurona;

public final class NeuronaLibrary {
    private NeuronaLibrary() {}

    public static String name() {
        return "neurona";
    }
}
```

- [ ] **Step 5: Run the fixture contract and confirm the wrapper failure remains**

Run:

```bash
./scripts/verify-fixture.sh
```

Expected: `FAIL: outer Gradle wrapper is missing or not executable`.

### Task 3: Generate two official Gradle 9.4.1 wrappers

**Files:**
- Create: outer and nested `gradlew`
- Create: outer and nested `gradlew.bat`
- Create: outer and nested `gradle/wrapper/gradle-wrapper.jar`
- Create: outer and nested `gradle/wrapper/gradle-wrapper.properties`
- Test: `scripts/verify-fixture.sh`

**Interfaces:**
- Consumes: The two Gradle build roots from Task 2.
- Produces: Two official, checksum-verified Gradle 9.4.1 wrappers.

- [ ] **Step 1: Bootstrap the outer wrapper**

Create an isolated Gradle cache for wrapper generation:

```bash
wrapper_gradle_home="$(mktemp -d)"
export GRADLE_USER_HOME="$wrapper_gradle_home"
```

Run:

```bash
gradle \
  -p ai-native-backend-jvm \
  wrapper \
  --gradle-version 9.4.1 \
  --distribution-type bin
```

This first command can use the installed Gradle version only to create a bootstrap wrapper.

- [ ] **Step 2: Regenerate the outer wrapper through Gradle 9.4.1**

Run:

```bash
./ai-native-backend-jvm/gradlew \
  -p ai-native-backend-jvm \
  wrapper \
  --gradle-version 9.4.1 \
  --distribution-type bin
```

- [ ] **Step 3: Generate the nested wrapper through Gradle 9.4.1**

Run:

```bash
./ai-native-backend-jvm/gradlew \
  -p ai-native-backend-jvm/domains/deposits/deposits-transactions-core \
  wrapper \
  --gradle-version 9.4.1 \
  --distribution-type bin
```

- [ ] **Step 4: Verify wrapper distribution and JAR checksums**

Run:

```bash
for root in \
  ai-native-backend-jvm \
  ai-native-backend-jvm/domains/deposits/deposits-transactions-core
do
  shasum -a 256 "$root/gradle/wrapper/gradle-wrapper.jar"
  cat "$root/gradle/wrapper/gradle-wrapper.properties"
done
```

Expected for each wrapper JAR:

```text
55243ef57851f12b070ad14f7f5bb8302daceeebc5bce5ece5fa6edb23e1145c
```

Expected distribution:

```text
gradle-9.4.1-bin.zip
```

- [ ] **Step 5: Remove the temporary Gradle distribution**

Run:

```bash
rm -rf "$wrapper_gradle_home"
unset GRADLE_USER_HOME
```

Expected: the temporary Gradle cache and downloaded 9.4.1 distribution are removed before Mandrel setup.

- [ ] **Step 6: Run the fixture contract**

Run:

```bash
./scripts/verify-fixture.sh
```

Expected: failure because the remaining scripts do not exist yet.

### Task 4: Add verified Mandrel setup

**Files:**
- Create: `scripts/setup-mandrel.sh`
- Test: `scripts/setup-mandrel.sh`

**Interfaces:**
- Consumes: GitHub release `mandrel-25.0.2.0-Final`.
- Produces: A checksum-verified local Mandrel installation path on stdout.

- [ ] **Step 1: Write the Mandrel setup script**

Create `scripts/setup-mandrel.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_root="$repo_root/.tools"
install_root="$tools_root/mandrel-java25-25.0.2.0-Final"
java_home="$install_root/Contents/Home"
url="https://github.com/graalvm/mandrel/releases/download/mandrel-25.0.2.0-Final/mandrel-java25-macos-aarch64-25.0.2.0-Final.tar.gz"
expected_sha="0b6d6c0ef85028b49080cba74c94090b73a281a01b1acf331990742ff8c6ea31"
archive=""

cleanup() {
  if [[ -n "$archive" ]]; then
    rm -f "$archive"
  fi
}
trap cleanup EXIT

[[ "$(uname -s)" == "Darwin" ]] || {
  printf 'This setup script supports macOS only.\n' >&2
  exit 2
}
[[ "$(uname -m)" == "arm64" ]] || {
  printf 'This setup script supports macOS ARM64 only.\n' >&2
  exit 2
}

mkdir -p "$tools_root"

if [[ ! -x "$java_home/bin/java" ]]; then
  archive="$(mktemp)"
  printf 'Downloading Mandrel 25.0.2.0-Final...\n' >&2
  curl -fL "$url" -o "$archive"

  actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || {
    printf 'Mandrel SHA-256 mismatch.\nExpected: %s\nActual:   %s\n' \
      "$expected_sha" "$actual_sha" >&2
    exit 1
  }

  rm -rf "$install_root"
  tar -xzf "$archive" -C "$tools_root"
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -c -r "$install_root"
fi

[[ -x "$java_home/bin/java" ]] || {
  printf 'Mandrel extraction did not create %s\n' "$java_home" >&2
  exit 1
}

printf '%s\n' "$java_home"
```

Make it executable.

- [ ] **Step 2: Validate Mandrel setup**

Run:

```bash
export JAVA_HOME="$(./scripts/setup-mandrel.sh)"
export GRAALVM_HOME="$JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

java -version
```

Expected output contains:

```text
Mandrel
25.0.2
```

- [ ] **Step 3: Verify checksum-failure handling**

Run:

```bash
corrupt_copy="$(mktemp)"
printf 'not-a-valid-mandrel-archive' > "$corrupt_copy"

set +e
actual_sha="$(shasum -a 256 "$corrupt_copy" | awk '{print $1}')"
test "$actual_sha" = "0b6d6c0ef85028b49080cba74c94090b73a281a01b1acf331990742ff8c6ea31"
status=$?
set -e

rm -f "$corrupt_copy"
test "$status" -ne 0
```

Expected: the comparison rejects the modified archive.

### Task 5: Add baseline and regression scan scripts

**Files:**
- Create: `scripts/run-baseline.sh`
- Create: `scripts/run-regression.sh`
- Test: both scripts in guard-only mode

**Interfaces:**
- Consumes: Explicit `ENDOR_NAMESPACE`, `ENDOR_API`, and Mandrel `JAVA_HOME`.
- Produces: Two controlled scan commands and separate debug log files.

- [ ] **Step 1: Write the baseline script**

Create `scripts/run-baseline.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || {
    printf 'Required environment variable is not set: %s\n' "$name" >&2
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

[[ -x "$java_bin" ]] || {
  printf 'JAVA_HOME has no executable java: %s\n' "$java_bin" >&2
  exit 2
}

java_output="$("$java_bin" -version 2>&1)" || {
  printf 'Unable to run Java from JAVA_HOME.\n' >&2
  exit 2
}
[[ "$java_output" == *"Mandrel"* && "$java_output" == *"25.0.2"* ]] || {
  printf 'JAVA_HOME must point to Mandrel 25.0.2. Current output:\n%s\n' \
    "$java_output" >&2
  exit 2
}

command -v endorctl >/dev/null 2>&1 || {
  printf 'endorctl is not available on PATH.\n' >&2
  exit 2
}

export PATH="$JAVA_HOME/bin:$PATH"

"$outer_root/gradlew" -p "$outer_root" --version
"$canary_root/gradlew" -p "$canary_root" --version
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
```

Make it executable.

- [ ] **Step 2: Write the regression script**

Copy `scripts/run-baseline.sh` to `scripts/run-regression.sh`.

Make only these changes:

```text
log file:
  java25-gradle941-competing-wrappers-regression.log

ref environment variable:
  REGRESSION_REF

default ref:
  java25-gradle941-competing-wrappers-regression

tags:
  java25,gradle941,competing-wrappers,regression

additional scan argument before the canary include:
  --include-path='ai-native-backend-jvm/gradlew'
```

Make it executable.

- [ ] **Step 3: Verify guard failures before external writes**

For each script, run:

```bash
env -u ENDOR_NAMESPACE -u ENDOR_API -u JAVA_HOME ./scripts/run-baseline.sh
env -u ENDOR_NAMESPACE -u ENDOR_API -u JAVA_HOME ./scripts/run-regression.sh
```

Expected: exit code 2 before endorctl.

Run both scripts with:

- Nonexistent `JAVA_HOME`.
- A non-Mandrel Java 25 runtime.
- Mandrel with a version other than 25.0.2.

Expected: each invalid runtime exits 2 before endorctl.

- [ ] **Step 4: Verify the A/B command delta**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

baseline = Path("scripts/run-baseline.sh").read_text().splitlines()
regression = Path("scripts/run-regression.sh").read_text().splitlines()

def normalize(lines):
    ignored_fragments = (
        "java25-gradle941-nested-wrapper-baseline.log",
        "java25-gradle941-competing-wrappers-regression.log",
        "BASELINE_REF",
        "REGRESSION_REF",
        "nested-wrapper,baseline",
        "competing-wrappers,regression",
        "--include-path='ai-native-backend-jvm/gradlew'",
    )
    result = []
    for line in lines:
        if any(fragment in line for fragment in ignored_fragments):
            continue
        result.append(line)
    return result

assert normalize(baseline) == normalize(regression)
print("A/B command delta is limited to approved fields.")
PY
```

Expected: no other differences between `run-baseline.sh` and `run-regression.sh`.

### Task 6: Build and validate with Mandrel Java 25

**Files:**
- Modify only if validation reveals an implementation defect.
- Test: Gradle builds, fixture contract, bytecode

**Interfaces:**
- Consumes: Tasks 1 through 5.
- Produces: API-free evidence that the fixture and both wrappers are valid.

- [ ] **Step 1: Configure Mandrel**

Run:

```bash
export JAVA_HOME="$(./scripts/setup-mandrel.sh)"
export GRAALVM_HOME="$JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
java -version
```

- [ ] **Step 2: Build through the outer wrapper**

Run:

```bash
./ai-native-backend-jvm/gradlew \
  -p ai-native-backend-jvm \
  clean buildAll
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Validate fixture, runtime, and artifacts**

Run:

```bash
./scripts/verify-fixture.sh --runtime --built
```

Expected:

```text
Fixture contract passed.
```

- [ ] **Step 4: Verify Java 25 bytecode**

Run:

```bash
"$JAVA_HOME/bin/javap" -verbose \
  ai-native-backend-jvm/domains/deposits/deposits-transactions-core/build/classes/java/main/example/transactions/TransactionService.class
```

Expected output contains:

```text
major version: 69
```

- [ ] **Step 5: Confirm generated files remain ignored**

Run:

```bash
git status --short
```

Expected: no `.tools`, `.gradle`, `build`, archive, or log path appears.

### Task 7: Document use and interpretation

**Files:**
- Modify: `README.md`
- Test: documentation commands against the completed fixture

**Interfaces:**
- Consumes: The completed fixture and scripts.
- Produces: Public setup, A/B scan, evidence, interpretation, and cleanup instructions.

- [ ] **Step 1: Replace the README**

Replace `README.md` with:

````markdown
# Java 25 competing Gradle wrappers reproducer

This repository reproduces an endorctl package-coordinate regression in a nested Gradle composite build.

The Git repository root is not a Gradle root. `ai-native-backend-jvm` has an outer Gradle 9.4.1 wrapper. Its selected `deposits-transactions-core` build has a second Gradle 9.4.1 wrapper and five wrapperless library builds.

Two scans use the same commit and prebuilt output:

- Baseline: only the nested canary wrapper is visible.
- Regression: the outer and nested wrappers are visible.

## Requirements

- macOS on Apple Silicon
- `curl`, `tar`, `shasum`, and `xattr`
- endorctl
- Access to an isolated test namespace

Do not use a customer namespace for this experiment.

## Install Mandrel 25

```bash
export JAVA_HOME="$(./scripts/setup-mandrel.sh)"
export GRAALVM_HOME="$JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

java -version
```

The output must identify Mandrel 25.0.2.

## Verify the fixture

```bash
./scripts/verify-fixture.sh --runtime
```

This validation does not call endorctl.

## Build

```bash
./ai-native-backend-jvm/gradlew \
  -p ai-native-backend-jvm \
  clean buildAll

./scripts/verify-fixture.sh --runtime --built
```

Both wrappers use Gradle 9.4.1. The five library builds contain no wrapper.

## Configure an isolated namespace

Each scan writes data to the selected namespace. Get approval before running either scan.

```bash
test -n "${ENDOR_NAMESPACE:?Set ENDOR_NAMESPACE to an isolated test namespace}"
export ENDOR_API="https://api.endorlabs.com"
```

## Run the baseline

```bash
./scripts/run-baseline.sh
```

The baseline includes only:

```text
ai-native-backend-jvm/domains/deposits/deposits-transactions-core/**
```

This subtree contains the nested wrapper but not the outer wrapper.

## Run the competing-wrapper regression

```bash
./scripts/run-regression.sh
```

The regression adds:

```text
ai-native-backend-jvm/gradlew
```

The repository source, commit, runtime, and build output remain unchanged.

## Compare results

Record:

```bash
git rev-parse HEAD
endorctl --version
java -version
./ai-native-backend-jvm/gradlew -p ai-native-backend-jvm --version
./ai-native-backend-jvm/domains/deposits/deposits-transactions-core/gradlew \
  -p ai-native-backend-jvm/domains/deposits/deposits-transactions-core \
  --version
```

Also record:

- Baseline scan result UUID
- Regression scan result UUID
- Package counts
- Full dependency-analysis counts
- Wrapper commands used during project discovery
- Maven coordinate emitted for the canary root
- Scan status, exit code, and failure count

Attach these ignored files to the engineering issue:

```text
java25-gradle941-nested-wrapper-baseline.log
java25-gradle941-competing-wrappers-regression.log
```

## Expected affected behavior

- Baseline creates at least one named source package.
- Regression loses the canary package or returns six unnamed manifests.
- The CLI can report zero failures despite dependency-scanning warnings.

## Expected fixed behavior

- The canary package survives when the outer wrapper becomes visible.
- Project identity does not depend on wrapper discovery order.
- The nested wrapper remains the runner for the nested build.
- Empty package names create visible failures or increment `scan_failures`.

This fixture tests the Java 25 competing-wrapper case. It does not prove the separate Java 11 wrapper-propagation case.

## Cleanup

```bash
find ai-native-backend-jvm -type d -name .gradle -prune -exec rm -rf {} +
find ai-native-backend-jvm -type d -name build -prune -exec rm -rf {} +
rm -rf .tools
rm -f java25-gradle941-*.log
```
````

- [ ] **Step 2: Document evidence collection**

In the README, instruct users to capture:

```bash
git rev-parse HEAD
endorctl --version
java -version
./ai-native-backend-jvm/gradlew -p ai-native-backend-jvm --version
./ai-native-backend-jvm/domains/deposits/deposits-transactions-core/gradlew \
  -p ai-native-backend-jvm/domains/deposits/deposits-transactions-core \
  --version
```

Also record both scan result UUIDs and attach both ignored log files to the engineering issue.

- [ ] **Step 3: Document cleanup**

Include:

```bash
find ai-native-backend-jvm -type d -name .gradle -prune -exec rm -rf {} +
find ai-native-backend-jvm -type d -name build -prune -exec rm -rf {} +
rm -rf .tools
rm -f java25-gradle941-*.log
```

### Task 8: Run final local gates

**Files:**
- Review all source, wrapper, script, and documentation files.

**Interfaces:**
- Consumes: The complete repository.
- Produces: A clean implementation handoff without any remote scan.

- [ ] **Step 1: Run shell and fixture checks**

Run:

```bash
bash -n scripts/setup-mandrel.sh
bash -n scripts/verify-fixture.sh
bash -n scripts/run-baseline.sh
bash -n scripts/run-regression.sh
./scripts/verify-fixture.sh --runtime --built
```

- [ ] **Step 2: Run both Gradle builds**

Run:

```bash
./ai-native-backend-jvm/gradlew -p ai-native-backend-jvm clean buildAll
./ai-native-backend-jvm/domains/deposits/deposits-transactions-core/gradlew \
  -p ai-native-backend-jvm/domains/deposits/deposits-transactions-core \
  clean buildAll
```

Expected: both builds pass under Mandrel 25.0.2.

- [ ] **Step 3: Verify checksums**

Run:

```bash
for root in \
  ai-native-backend-jvm \
  ai-native-backend-jvm/domains/deposits/deposits-transactions-core
do
  shasum -a 256 "$root/gradle/wrapper/gradle-wrapper.jar"
done
```

Expected: both hashes equal:

```text
55243ef57851f12b070ad14f7f5bb8302daceeebc5bce5ece5fa6edb23e1145c
```

- [ ] **Step 4: Sweep for sensitive and generated files**

Run:

```bash
git grep --untracked -ni -I -E \
  'ENDOR_TOKEN=|password[[:space:]]*=|BEGIN [A-Z ]*PRIVATE KEY' \
  -- .

git status --short
```

Expected:

- The sensitive-value search returns no matches.
- No runtime, archive, cache, build output, log, credential, or token file is tracked.

- [ ] **Step 5: Confirm no endorctl scan ran**

Verify that neither scan log exists:

```bash
test ! -e java25-gradle941-nested-wrapper-baseline.log
test ! -e java25-gradle941-competing-wrappers-regression.log
```

## Execution handoff

Use one `code-writer` agent for all tasks because wrapper generation, composite substitution, Mandrel setup, scan scripts, and README commands must remain consistent. Then use one fresh correctness reviewer focused on A/B fidelity, wrapper count, package identities, checksum validation, external-write guards, and public-repository safety.

---
🥷 harness `v1.7.1179-3-g1e74dc3873-dirty` · `gpt-5.6-sol` · `default` · `@main` · `/brainstorming` · `/writing-plans`
