plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningEnvironment = listOf(
    "ANDROID_KEYSTORE_PATH",
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD",
).associateWith { providers.environmentVariable(it).orNull }
val releaseKeystoreFile = releaseSigningEnvironment["ANDROID_KEYSTORE_PATH"]
    ?.takeIf { it.isNotBlank() }
    ?.let { rootProject.file(it) }

val validateReleaseSigning by tasks.registering {
    group = "verification"
    description = "release用の署名資格情報を確認します。"
    doLast {
        val missingVariables = releaseSigningEnvironment.filterValues {
            it.isNullOrBlank()
        }.keys
        if (missingVariables.isNotEmpty()) {
            throw GradleException(
                "release署名に必要な環境変数が未設定です: " +
                    missingVariables.joinToString(", "),
            )
        }
        if (releaseKeystoreFile?.let { it.isFile && it.canRead() } != true) {
            throw GradleException(
                "ANDROID_KEYSTORE_PATHに読み込み可能な署名鍵ファイルを指定してください。",
            )
        }
    }
}

android {
    namespace = "io.github.yakitama5.marsterraforming"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.yakitama5.marsterraforming"
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
    }

    signingConfigs {
        create("release") {
            storeFile = releaseKeystoreFile
            storePassword = releaseSigningEnvironment["ANDROID_KEYSTORE_PASSWORD"]
            keyAlias = releaseSigningEnvironment["ANDROID_KEY_ALIAS"]
            keyPassword = releaseSigningEnvironment["ANDROID_KEY_PASSWORD"]
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// debugビルドでは署名資格情報を要求せず、releaseの成果物生成前に検証する。
tasks.configureEach {
    if (name == "preReleaseBuild" || name == "validateSigningRelease") {
        dependsOn(validateReleaseSigning)
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
