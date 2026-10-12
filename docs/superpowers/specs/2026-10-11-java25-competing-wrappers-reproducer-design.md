# Java 25 Competing Gradle Wrappers Reproducer Design

## Purpose

Build a small standalone repository that reproduces a Java 25 Gradle composite-build coordinate-loss problem.

The repository must show whether adding an outer Gradle wrapper to the scan scope causes a package that resolves through a nested wrapper to lose its Maven coordinate. The fixture must not contain customer source code, private credentials, or private dependencies.

## Reproduction target

The fixture models a customer-reported `ai-native-backend-jvm` canary:

- The scan path is the Git repository root.
- The outer Gradle build is below that root in `ai-native-backend-jvm/`.
- The outer build has a Gradle 9.4.1 wrapper.
- The selected canary is a nested composite build.
- The selected canary has its own Gradle 9.4.1 wrapper.
- The canary includes five wrapperless library builds.
- The selected scope contains six `build.gradle.kts` manifests.
- The build and scan use Mandrel Java 25.0.2.0-Final.
- Baseline and regression scans use the same Git commit and prebuilt outputs.

The affected behavior appears only when the scan sees both the outer and nested wrappers.

## Repository layout

```text
java-gradle-composite-scan/
├── README.md
├── .gitignore
├── scripts/
│   ├── setup-mandrel.sh
│   ├── verify-fixture.sh
│   ├── run-baseline.sh
│   └── run-regression.sh
└── ai-native-backend-jvm/
    ├── build.gradle.kts
    ├── settings.gradle.kts
    ├── gradle.properties
    ├── gradlew
    ├── gradlew.bat
    ├── gradle/wrapper/
    │   ├── gradle-wrapper.jar
    │   └── gradle-wrapper.properties
    └── domains/deposits/deposits-transactions-core/
        ├── build.gradle.kts
        ├── settings.gradle.kts
        ├── gradle.properties
        ├── gradlew
        ├── gradlew.bat
        ├── gradle/wrapper/
        │   ├── gradle-wrapper.jar
        │   └── gradle-wrapper.properties
        ├── src/main/java/example/transactions/TransactionService.java
        └── libraries/
            ├── ach-pse/
            │   ├── build.gradle.kts
            │   ├── settings.gradle.kts
            │   └── src/main/java/example/achpse/AchPseLibrary.java
            ├── credibanco-bre-b/
            │   ├── build.gradle.kts
            │   ├── settings.gradle.kts
            │   └── src/main/java/example/credibanco/CredibancoLibrary.java
            ├── deposits-fraud/
            │   ├── build.gradle.kts
            │   ├── settings.gradle.kts
            │   └── src/main/java/example/fraud/DepositsFraudLibrary.java
            ├── deposits-transactions-core-sdk/
            │   ├── build.gradle.kts
            │   ├── settings.gradle.kts
            │   └── src/main/java/example/sdk/TransactionsCoreApi.java
            └── neurona/
                ├── build.gradle.kts
                ├── settings.gradle.kts
                └── src/main/java/example/neurona/NeuronaLibrary.java
```

## Gradle topology

`ai-native-backend-jvm/settings.gradle.kts` includes the canary build:

```text
domains/deposits/deposits-transactions-core
```

The canary `settings.gradle.kts` includes five independent library builds:

- `libraries/ach-pse`
- `libraries/credibanco-bre-b`
- `libraries/deposits-fraud`
- `libraries/deposits-transactions-core-sdk`
- `libraries/neurona`

Each library build has one `build.gradle.kts` and no Gradle wrapper.

The selected canary subtree therefore contains:

- One canary root manifest.
- Five wrapperless library manifests.
- One nested wrapper.

Adding `ai-native-backend-jvm/gradlew` gives the scanner two wrapper views of the canary root.

## Package identities

The canary root uses:

```text
group: com.example.system
artifact: deposits-transactions-core-system
version: unspecified
```

The five libraries use group `com.example.library` and these artifact names:

- `ach-pse-library`
- `credibanco-bre-b-library`
- `deposits-fraud-library`
- `deposits-transactions-core-sdk`
- `neurona-library`

Project versions remain unset so Gradle reports `unspecified`.

The canary declares direct dependencies on the five library coordinates. Gradle composite substitution resolves them from local source builds.

No third-party Java dependency is required.

## Build behavior

The outer build defines `buildAll`.

`buildAll` delegates to the canary build. The canary build delegates to its own package and the five included library builds.

The supported build command is:

```bash
./ai-native-backend-jvm/gradlew \
  -p ai-native-backend-jvm \
  buildAll
```

The build must retain JAR, class, and Gradle cache output in the same checkout used by endorctl.

## Java runtime

The fixture uses Mandrel 25.0.2.0-Final for macOS ARM:

```text
mandrel-java25-macos-aarch64-25.0.2.0-Final.tar.gz
```

`scripts/setup-mandrel.sh`:

1. Downloads the archive to a temporary file from the Mandrel GitHub release.
2. Verifies the archive checksum.
3. Extracts it under the ignored `.tools/` directory.
4. Deletes the temporary archive after successful extraction.
5. Removes the macOS quarantine attribute when `xattr` is available.
6. Prints the exact `JAVA_HOME`, `GRAALVM_HOME`, and `PATH` exports.

The runtime is not committed to Git.

## Gradle wrappers

Both wrappers use Gradle 9.4.1.

The implementation must generate and commit standard wrapper scripts, properties, and wrapper JARs. It must verify both wrapper JARs against the official Gradle 9.4.1 wrapper checksum.

Wrapper generation must use a temporary Gradle user home. The implementation deletes that cache before it downloads Mandrel so both large toolchains do not occupy disk at the same time.

The five library builds must not contain wrappers.

## Baseline scan

The baseline scan includes only the nested canary subtree:

```bash
endorctl scan \
  --namespace "$ENDOR_NAMESPACE" \
  --api "$ENDOR_API" \
  --path "$REPO_ROOT" \
  --dependencies \
  --languages=java,kotlin \
  --include-path='ai-native-backend-jvm/domains/deposits/deposits-transactions-core/**' \
  --detached-ref-name='java25-gradle941-nested-wrapper-baseline' \
  --tags='java25,gradle941,nested-wrapper,baseline' \
  --verbose
```

This scope contains the nested wrapper but not the outer wrapper.

The baseline contract requires:

- At least one source package.
- A nonempty Maven coordinate for the canary root.
- One full dependency analysis for the canary root.
- Debug output showing the nested wrapper used for the canary root.

The five wrapperless libraries can remain missing or external in the baseline. Their behavior is evidence, but it is not the A/B pass criterion.

## Regression scan

The regression scan adds the outer wrapper:

```bash
endorctl scan \
  --namespace "$ENDOR_NAMESPACE" \
  --api "$ENDOR_API" \
  --path "$REPO_ROOT" \
  --dependencies \
  --languages=java,kotlin \
  --include-path='ai-native-backend-jvm/gradlew' \
  --include-path='ai-native-backend-jvm/domains/deposits/deposits-transactions-core/**' \
  --detached-ref-name='java25-gradle941-competing-wrappers-regression' \
  --tags='java25,gradle941,competing-wrappers,regression' \
  --verbose
```

This scope contains the outer and nested wrappers.

The issue is reproduced when:

- The baseline canary coordinate disappears.
- The package count changes from at least one to zero.
- The canary root becomes an unnamed unresolved dependency.
- The final CLI summary reports zero failures despite dependency-scanning warnings.

## Scan scripts

`run-baseline.sh` and `run-regression.sh`:

- Require explicit `ENDOR_NAMESPACE`, `ENDOR_API`, and `JAVA_HOME`.
- Verify that `JAVA_HOME` reports Mandrel Java 25.0.2.
- Verify both wrappers report Gradle 9.4.1.
- Prebuild once before each scan.
- Enable `ENDOR_LOG_LEVEL=debug`.
- Enable `ENDOR_SCAN_GRADLE_PRINT_DEBUG=true`.
- Save complete output to separate ignored log files.
- Never set a default namespace or credential.

The scripts do not query or delete existing scan data.

## Local validation

`scripts/verify-fixture.sh` must validate without calling endorctl:

1. The outer and nested wrappers exist and are executable.
2. Both wrappers select Gradle 9.4.1.
3. Exactly two wrappers exist in the repository.
4. Exactly six canary manifests exist.
5. The five library builds contain no wrapper.
6. Mandrel reports Java 25.0.2 when `--runtime` is requested.
7. Both Gradle builds complete.
8. JAR or class output exists for the canary and all five libraries.
9. Compiled classes use Java 25 bytecode.

## Evidence output

The README instructs the user to record:

- Git commit.
- endorctl version.
- Mandrel version.
- Both Gradle wrapper versions.
- Baseline and regression scan result UUIDs.
- Baseline and regression package counts.
- Wrapper commands selected during project discovery.
- Maven coordinates emitted for the canary root.
- Scan status, exit code, and failure count.

## Expected fixed behavior

A fixed endorctl version must preserve the baseline canary package when the outer wrapper becomes visible.

Specifically:

- Package identity must not depend on wrapper discovery order.
- Project name, build file, Gradle home, and runner must come from one consistent project structure.
- The nested wrapper must remain the effective runner for its canary build.
- The regression package count must be no lower than the baseline package count.
- Empty package names must create visible failures or increment `scan_failures`.

## Safety

- No customer source code or credentials are committed.
- No token, namespace, or API endpoint is hardcoded.
- Mandrel archives, Gradle caches, build outputs, and scan logs are ignored.
- Scan scripts stop before any API call when required variables are absent or invalid.
- The README directs users to an isolated test namespace.

## Out of scope

- The Java 11 wrapper-propagation defect.
- A product fix in endorctl.
- CI automation.
- Main-branch or PR policy behavior.
- Container, SAST, secrets, or AI SAST scanning.
- Maven Local publication.
- Private package registries.

## Success criteria

The repository is ready when:

1. A clean clone builds with Mandrel Java 25.0.2 and Gradle 9.4.1.
2. The canary subtree has one wrapper and six manifests.
3. The repository has exactly two wrappers.
4. Baseline and regression scripts differ only by the outer-wrapper include and detached-ref metadata.
5. API-free verification passes.
6. The baseline and regression commands are ready for explicit user execution.
7. No customer source, credential, private dependency, cache, build output, runtime archive, or scan log is tracked.

Built by endor-lmoreno's AI harness (harness v1.7.1179-3-g1e74dc3873-dirty - gpt-5.6-sol - default)
