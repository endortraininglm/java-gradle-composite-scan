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
native-image --version
```

The Java output must show 25.0.2. The native-image output must identify Mandrel 25.0.2.0-Final.

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
native-image --version
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