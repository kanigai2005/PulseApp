plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.autonap"
    compileSdk = 36 // Hardcoded for stability
    ndkVersion = "26.1.10909125"

    compileOptions {
        // This is the line the error is looking for
        isCoreLibraryDesugaringEnabled = true 
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.autonap"
        targetSdk = 34 
        // minSdk 21 is required for the notification library
        minSdk = flutter.minSdkVersion 
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // MultiDex is required when using many libraries
        multiDexEnabled = true 
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // This library handles the "Desugaring"
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}
