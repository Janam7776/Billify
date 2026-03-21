// edit by dj
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")

    id("com.google.gms.google-services")  // ADD THIS by dj
}

android {
    namespace = "com.billify.app.billify"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.billify.app.billify"
        minSdk = flutter.minSdkVersion  // CHANGED
        targetSdk = 36  // CHANGED
        versionCode = 1  // CHANGED
        versionName = "1.0"  // CHANGED
        multiDexEnabled = true  // ADDED
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
