allprojects {
    repositories {
        maven { url = uri("${rootProject.projectDir}/local_repo") }
        google()
        mavenCentral()
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
    }
    configurations.all {
        resolutionStrategy {
            force("androidx.lifecycle:lifecycle-livedata-core:2.8.7")
            force("androidx.lifecycle:lifecycle-viewmodel:2.8.7")
            force("androidx.lifecycle:lifecycle-common:2.8.7")
            force("androidx.lifecycle:lifecycle-runtime:2.8.7")
            force("com.google.android.gms:play-services-basement:18.9.0")
            force("androidx.browser:browser:1.8.0")
            force("androidx.annotation:annotation-experimental:1.4.1")
        }
    }
    buildscript {
        repositories {
            maven { url = uri("${rootProject.projectDir}/local_repo") }
            google()
            mavenCentral()
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
        }
        configurations.all {
            resolutionStrategy {
                force("com.android.tools.build:gradle:8.11.1")
            }
        }
    }

    // Restrict download.flutter.io to ONLY io.flutter artifacts so it never intercepts Google Play Services
    afterEvaluate {
        repositories.configureEach {
            if (this is MavenArtifactRepository && url.toString().contains("download.flutter.io")) {
                content {
                    includeGroup("io.flutter")
                    includeGroupByRegex("io\\.flutter\\..*")
                }
            }
        }
    }
}

extra["compileSdkVersion"] = 36

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
subprojects {
    plugins.withId("com.android.library") {
        val appExt = project(":app")
            .extensions
            .findByName("android")
            as? com.android.build.api.dsl.CommonExtension<*, *, *, *, *, *>
        val appNdk = appExt?.ndkVersion
        if (!appNdk.isNullOrBlank()) {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                ndkVersion = appNdk
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
