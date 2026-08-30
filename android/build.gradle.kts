import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        // AGP 9.0.1 ships KGP 2.2.10 for built-in Kotlin, while Flutter
        // 3.47.1 requires at least 2.2.20. Override only the KGP runtime
        // dependency; do not re-apply org.jetbrains.kotlin.android.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

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

gradle.projectsEvaluated {
    allprojects {
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Pinned bundletool is used only by release artifact verification.
val releaseBundletool by configurations.creating

dependencies {
    add(releaseBundletool.name, "com.android.tools.build:bundletool:1.18.3")
}

tasks.register<JavaExec>("dumpReleaseBundleManifestAttribute") {
    group = "verification"
    description = "Print one Android App Bundle manifest attribute using bundletool."
    classpath = releaseBundletool
    mainClass.set("com.android.tools.build.bundletool.BundleToolMain")
    doFirst {
        val bundleFile = providers.gradleProperty("bundleFile").orNull
            ?: throw GradleException("-PbundleFile is required")
        val manifestXpath = providers.gradleProperty("manifestXpath").orNull
            ?: throw GradleException("-PmanifestXpath is required")
        args(
            "dump",
            "manifest",
            "--bundle=$bundleFile",
            "--xpath=$manifestXpath",
        )
    }
}
