buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.2.2")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22")
        classpath("com.google.gms:google-services:4.4.0")
    }
}

// Set property to ignore NDK version mismatches
System.setProperty("android.overrideNdkVersion", "true")

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// This is critical - DO NOT remove or change these lines
// They prevent path conflicts between plugins and your app
rootProject.layout.buildDirectory.set(rootProject.projectDir.resolve("build"))

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
} 