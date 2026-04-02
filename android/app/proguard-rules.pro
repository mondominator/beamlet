# Gson
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.beamlet.android.data.api.** { *; }
-keep class com.beamlet.android.data.nearby.NearbyModels** { *; }

# Retrofit
-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
