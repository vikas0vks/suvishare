import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live outside the repo (see android/key.properties,
// which is gitignored). Release tasks fail closed when they are unavailable.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val releaseKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val hasReleaseKeystore = releaseKeys.all {
    (keystoreProperties[it] as String?)?.isNotBlank() == true
} && file(keystoreProperties["storeFile"] as? String ?: "missing").exists()
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseRequested && !hasReleaseKeystore) {
    throw GradleException(
        "Release signing is not configured. Add android/key.properties and a valid keystore.",
    )
}

android {
    namespace = "com.suvishare.suvi_share"
    // Keep the compile SDK on the current stable Android platform so clean
    // release runners can reproduce the build.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time — needs desugaring on
        // minSdk < 26.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.suvishare.suvi_share"
        minSdk = flutter.minSdkVersion
        // Stay on 36 until the Android 17 ACCESS_LOCAL_NETWORK runtime-permission
        // flow is built; targeting 37
        // blocks all LAN sockets until that permission is granted.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                // minSdk 24 supports v2; v3 covers modern Android.
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
