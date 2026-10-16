import java.io.File
import org.gradle.api.Project
import org.gradle.kotlin.dsl.withGroovyBuilder

val packageDeclaration = Regex("""^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)""")

fun packageName(file: File): String? = file.useLines { lines ->
    lines.mapNotNull { packageDeclaration.find(it)?.groupValues?.get(1) }.firstOrNull()
}

fun Project.inferredAndroidNamespace(): String {
    val declaredPackage = sequenceOf(
        projectDir.resolve("src/main/kotlin"),
        projectDir.resolve("src/main/java"),
    )
        .filter(File::isDirectory)
        .flatMap { sourceRoot ->
            sourceRoot.walkTopDown()
                .filter { source -> source.isFile && source.extension in setOf("kt", "java") }
                .mapNotNull(::packageName)
        }
        .firstOrNull()

    if (declaredPackage != null) {
        return if (declaredPackage == rootProject.name) "$declaredPackage.module" else declaredPackage
    }

    val fallbackName = name.replace(Regex("[^A-Za-z0-9_]"), "_")
    return "skip.generated.$fallbackName"
}

gradle.beforeProject {
    pluginManager.withPlugin("com.android.library") {
        val inferredNamespace = inferredAndroidNamespace()
        extensions.getByName("android").withGroovyBuilder {
            setProperty("namespace", inferredNamespace)
        }
        logger.lifecycle("Configured generated Android namespace for $path: $inferredNamespace")
    }
}
