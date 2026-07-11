allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// receive_sharing_intent 1.9.0 applies only `com.android.library` and calls the
// `kotlin {}` DSL block without applying `kotlin-android` itself; the Flutter
// plugin loader applies it too late. Apply it here as soon as the library
// plugin is attached so the `kotlin {}` block resolves during configuration.
subprojects {
    plugins.withType(com.android.build.gradle.LibraryPlugin::class.java) {
        apply(plugin = "kotlin-android")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
