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

val achPse = gradle.includedBuild("ach-pse")
val credibanco = gradle.includedBuild("credibanco-bre-b")
val fraud = gradle.includedBuild("deposits-fraud")
val sdk = gradle.includedBuild("deposits-transactions-core-sdk")
val neurona = gradle.includedBuild("neurona")

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
