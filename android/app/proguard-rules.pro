-keep class com.islandbridge.xposed.** { *; }
-keep class com.islandbridge.*Receiver { *; }
-keepclassmembers class com.islandbridge.** {
    @android.webkit.JavascriptInterface <methods>;
}
