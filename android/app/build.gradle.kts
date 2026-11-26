import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val releaseStoreFilePath: String? =
    System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty("storeFile")?.takeIf { it.isNotBlank() }
val hasReleaseSigning = releaseStoreFilePath != null

android {
    namespace = "vn.edu.aipms.ai_pms_mobile"
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "vn.edu.aipms.ai_pms_mobile"
        // Minimum SDK 23 required for flutter_secure_storage, livekit_client & Credential Manager.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        // Google Play requires targetSdk >= 35 for new releases.
        targetSdk = maxOf(flutter.targetSdkVersion, 35)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword =
                    System.getenv("ANDROID_KEYSTORE_PASSWORD")
                        ?: keystoreProperties.getProperty("storePassword")
                keyAlias =
                    System.getenv("ANDROID_KEY_ALIAS")
                        ?: keystoreProperties.getProperty("keyAlias")
                keyPassword =
                    System.getenv("ANDROID_KEY_PASSWORD")
                        ?: keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
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

    packaging {
        jniLibs {
            // Keep uncompressed aligned native libs for Android 15+ 16 KB page size compliance.
            useLegacyPackaging = false
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
