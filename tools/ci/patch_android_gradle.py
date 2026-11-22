#!/usr/bin/env python3
"""Applies release signing + optional minSdk override to a Flutter
android/app/build.gradle.kts (used for the freshly generated legacy project)."""
import re
import sys

p = sys.argv[1]
s = open(p).read()
if 'hasReleaseKey' not in s:
    s = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + s
    s = s.replace('android {', '''val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
fun signingValue(env: String, prop: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keyProps.getProperty(prop)
val releaseStoreFile = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val hasReleaseKey = releaseStoreFile != null && file(releaseStoreFile).exists()

android {''', 1)
    s = re.sub(r'minSdk = flutter\.minSdkVersion',
               'minSdk = (project.findProperty("legacyMinSdk") as String?)?.toInt() ?: flutter.minSdkVersion', s)
    s = re.sub(r'applicationId = "[^"]*"', 'applicationId = "io.github.gmwester.universal_translator"', s)
    s = re.sub(r'namespace = "[^"]*"', 'namespace = "io.github.gmwester.universal_translator"', s)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")', '''signingConfig = if (hasReleaseKey) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")''')
    s = s.replace('    buildTypes {', '''    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {''', 1)
s = s.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 36')
s = s.replace('ndkVersion = flutter.ndkVersion', 'ndkVersion = "27.0.12077973"')
open(p, 'w').write(s)
print('patched', p)
