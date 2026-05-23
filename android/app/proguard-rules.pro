-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

-keep class * extends com.google.gson.reflect.TypeToken { *; }
