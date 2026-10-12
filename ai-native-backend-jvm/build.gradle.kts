plugins {
    base
}

val transactionsCore = gradle.includedBuild("deposits-transactions-core")

tasks.register("buildAll") {
    group = "build"
    description = "Build the transaction-core composite and all included libraries."
    dependsOn(transactionsCore.task(":buildAll"))
}
