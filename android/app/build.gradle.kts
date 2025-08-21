// build.gradle.kts (Module: android/app)
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    // Flutter Gradle Plugin은 Android/Kotlin 뒤에 와야 함
    id("dev.flutter.flutter-gradle-plugin")
}

// keystore 읽기
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}

android {
    namespace = "com.justpixel.studio"

    compileSdk = 35

    defaultConfig {
        applicationId = "com.justpixel.studio"
        minSdk = 23
        targetSdk = 35

        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // JDK/Desugaring
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    ndkVersion = "27.0.12077973"

    signingConfigs {
        create("release") {
            // key.properties가 없으면 CI 등에서 빌드 실패 방지
            if (!keystoreProps.isEmpty) {
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        // debug 설정을 따로 건드릴 필요 없으면 생략 가능
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Java 8+ API desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
