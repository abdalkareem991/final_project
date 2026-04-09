// Professional English Comment: Root build file for Android project configuration using Kotlin DSL.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Logic: Redirect build directory to a shared location outside the android folder
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// ===========================================================================
// FIX FOR TELEPHONY & LEGACY LIBRARIES (NAMESPACE ISSUE)
// ===========================================================================
// Professional English Comment: This block resolves the 'Namespace not specified' 
// error by dynamically injecting a namespace into subprojects that lack one, 
// avoiding the 'afterEvaluate' lifecycle conflict.

subprojects {
    // We use dynamic configuration to apply settings as soon as the Android plugin is detected
    project.plugins.whenPluginAdded {
        val pluginName = this.toString()
        if (pluginName.contains("com.android.build.gradle.LibraryPlugin") || 
            pluginName.contains("com.android.build.gradle.AppPlugin")) {
            
            // Access the android extension using the BaseExtension type
            val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            if (android != null && android.namespace == null) {
                // Set the project group as the namespace fallback for libraries like 'telephony'
                android.namespace = project.group.toString()
            }
        }
    }
}