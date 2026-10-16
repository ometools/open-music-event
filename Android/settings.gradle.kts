// This gradle project is part of a conventional Skip app project.
pluginManagement {
    // Initialize the Skip plugin folder and perform a pre-build for non-Xcode builds
    val pluginPath = File.createTempFile("skip-plugin-path", ".tmp")

    fun shellQuote(value: String) = "'" + value.replace("'", "'\"'\"'") + "'"

    // overriding outputs for an Android IDE can be done by un-commenting and setting the Xcode path:
    //System.setProperty("BUILT_PRODUCTS_DIR", "${System.getProperty("user.home")}/Library/Developer/Xcode/DerivedData/MySkipProject-HASH/Build/Products/Debug-iphonesimulator")

    val skipCommand = System.getenv("SKIP_COMMAND_OVERRIDE") ?: "skip"
    val skipPluginPrebuildFlag = if ((System.getenv("SKIP_ANDROID_PREBUILD") ?: "1") == "0") "--no-prebuild" else "--prebuild"
    val skipPluginResult = providers.exec {
        commandLine("/bin/sh", "-c", "${shellQuote(skipCommand)} plugin ${skipPluginPrebuildFlag} --package-path ${shellQuote(settings.rootDir.parent)} --plugin-ref ${shellQuote(pluginPath.absolutePath)}")
        environment("OME_ANDROID_APP_BUILD", "1")
        environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
    }
    val skipPluginOutput = skipPluginResult.standardOutput.asText.get()
    print(skipPluginOutput)
    val skipPluginError = skipPluginResult.standardError.asText.get()
    print(skipPluginError)

    includeBuild(pluginPath.readText()) {
        name = "skip-plugins"
    }
}

plugins {
    id("skip-plugin") apply true
}
