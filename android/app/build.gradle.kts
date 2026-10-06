import java.util.Properties

plugins {
    id("com.android.application")

    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Google Maps SDK for Android key ──
// Never committed. Resolved, first match wins, from:
//   1. -PTIRVONA_ANDROID_MAPS_KEY=... (Gradle property, e.g. CI)
//   2. the TIRVONA_ANDROID_MAPS_KEY environment variable
//   3. android/secrets.properties (git-ignored; see secrets.properties.example)
// The key is restricted in Google Cloud to package com.tirvona.ride + the
// signing SHA-1s, and to the Maps SDK for Android API only.
val mapsApiKeyName = "TIRVONA_ANDROID_MAPS_KEY"
val mapsApiKey: String = run {
    val secrets = Properties()
    val secretsFile = rootProject.file("secrets.properties")
    if (secretsFile.isFile) secretsFile.inputStream().use { secrets.load(it) }
    listOf(
        providers.gradleProperty(mapsApiKeyName).orNull,
        providers.environmentVariable(mapsApiKeyName).orNull,
        secrets.getProperty(mapsApiKeyName),
    ).firstOrNull { !it.isNullOrBlank() }?.trim() ?: ""
}

// ── Release signing (Google Play upload key) ──
// android/key.properties (git-ignored; see key.properties.example) names the
// upload keystore. Without it, `bundleRelease` (the Play Store artifact) fails
// on purpose, and `assembleRelease` / `flutter run --release` fall back to the
// debug key so a release build can still be tried on a phone — never upload
// that one: Play rejects debug-signed bundles.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.isFile) file.inputStream().use { load(it) }
}
val hasUploadKeystore = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keystoreProperties.getProperty(it).isNullOrBlank() }

// Debug builds still run without a key (the map renders blank and logcat
// says "Authorization failure"); release builds must not ship without one.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (buildsRelease && mapsApiKey.isEmpty()) {
        throw GradleException(
            "$mapsApiKeyName is not set. Add it to android/secrets.properties " +
                "or export it as an environment variable before a release build.",
        )
    }
    val buildsBundle = allTasks.any { it.project == project && it.name.startsWith("bundle") && it.name.endsWith("Release") }
    if (buildsBundle && !hasUploadKeystore) {
        throw GradleException(
            "No upload keystore: create android/key.properties (see key.properties.example) " +
                "before building the Play Store bundle.",
        )
    }
    if (buildsRelease && !hasUploadKeystore) {
        logger.warn("w: android/key.properties is missing — this release build is signed with the DEBUG key. Do not upload it.")
    }
    if (mapsApiKey.isEmpty()) {
        logger.warn("w: $mapsApiKeyName is not set — Google Maps will not load tiles.")
    }
}

android {
    namespace = "com.tirvona.ride"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tirvona.ride"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Substituted into AndroidManifest.xml (com.google.android.geo.API_KEY).
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
    }

    signingConfigs {
        if (hasUploadKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 shrinks and obfuscates the Java/Kotlin side, resources are
            // trimmed; the keep rules below protect the Razorpay checkout.
            isMinifyEnabled = true
            isShrinkResources = true
            // Native debug symbols go into the bundle so Play Console can
            // symbolicate native crashes and ANRs.
            ndk { debugSymbolLevel = "SYMBOL_TABLE" }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
