import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

val localPropertiesFile = rootProject.file("local.properties")
val localProperties = Properties()
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

fun String.toBuildConfigString(): String =
    "\"" + replace("\\", "\\\\").replace("\"", "\\\"") + "\""

val mapTilerApiKey =
    (project.findProperty("MAPTILER_API_KEY") as String?)
        ?: localProperties.getProperty("MAPTILER_API_KEY")
        ?: System.getenv("MAPTILER_API_KEY")
        ?: ""

val offlineTileUrlTemplateOverride =
    (project.findProperty("OFFLINE_TILE_URL_TEMPLATE") as String?)
        ?: localProperties.getProperty("OFFLINE_TILE_URL_TEMPLATE")
        ?: System.getenv("OFFLINE_TILE_URL_TEMPLATE")
        ?: ""
val offlineTileUrlTemplate =
    if (offlineTileUrlTemplateOverride.isNotBlank()) {
        offlineTileUrlTemplateOverride
    } else if (mapTilerApiKey.isNotBlank()) {
        "https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}@2x.jpg?key=$mapTilerApiKey"
    } else {
        ""
    }
val offlineTileSourceLabel =
    (project.findProperty("OFFLINE_TILE_SOURCE_LABEL") as String?)
        ?: localProperties.getProperty("OFFLINE_TILE_SOURCE_LABEL")
        ?: System.getenv("OFFLINE_TILE_SOURCE_LABEL")
        ?: if (offlineTileUrlTemplate.contains("api.maptiler.com")) {
            "MapTiler Hybrid tiles"
        } else {
            "Configured field imagery"
        }

val debugAbiFiltersRaw =
    (project.findProperty("DEBUG_ABI_FILTERS") as String?)
        ?: localProperties.getProperty("DEBUG_ABI_FILTERS")
        ?: System.getenv("DEBUG_ABI_FILTERS")
val debugAbiFilters =
    debugAbiFiltersRaw
        ?.split(",")
        ?.map { it.trim() }
        ?.filter { it.isNotEmpty() }
        ?: emptyList()

val isDebugOnlyGradleInvocation =
    gradle.startParameter.taskNames.any { it.contains("Debug", ignoreCase = true) } &&
        gradle.startParameter.taskNames.none { it.contains("Release", ignoreCase = true) }

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release", ignoreCase = true) } &&
        !keyPropertiesFile.exists()
    ) {
        throw GradleException(
            "Release builds require android/key.properties. Do not ship debug-signed release builds."
        )
    }
}

android {
    namespace = "grainright.wrkfarm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    if (keyPropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = keyProperties["storeFile"]?.let { file(it) }
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.wrkfarm.millets_now"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 29)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "GrainRight"
        buildConfigField("String", "MAPTILER_API_KEY", mapTilerApiKey.toBuildConfigString())
        buildConfigField(
            "String",
            "OFFLINE_TILE_URL_TEMPLATE",
            offlineTileUrlTemplate.toBuildConfigString()
        )
        buildConfigField(
            "String",
            "OFFLINE_TILE_SOURCE_LABEL",
            offlineTileSourceLabel.toBuildConfigString()
        )
        if (isDebugOnlyGradleInvocation && debugAbiFilters.isNotEmpty()) {
            ndk {
                abiFilters += debugAbiFilters
            }
        }
    }

    if (isDebugOnlyGradleInvocation && debugAbiFilters.isNotEmpty()) {
        val knownAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        val excludedAbis = knownAbis.filter { it !in debugAbiFilters }
        packaging {
            jniLibs {
                excludes += excludedAbis.map { "lib/$it/**" }
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "GrainRight Dev"
        }
        release {
            if (keyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
