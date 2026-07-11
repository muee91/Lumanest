import com.android.build.api.dsl.LibraryExtension

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

// amap_map 1.0.15 pins its Android library module to API 35, while its
// lifecycle dependency now requires API 36. Keep the override local to that
// third-party module instead of editing pub-cache files.
subprojects {
    afterEvaluate {
        if (name == "amap_map" && plugins.hasPlugin("com.android.library")) {
            extensions.configure<LibraryExtension>("android") {
                compileSdk = 36
            }
        }
    }
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
