# Razorpay Standard Checkout (razorpay_flutter). Without these, R8 strips the
# checkout's reflective/JS-bridge classes and payments fail in release only.
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
# Google Pay / UPI intent classes referenced by the Razorpay SDK.
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.**
-keep class proguard.annotation.Keep
-keep class proguard.annotation.KeepClassMembers
-dontwarn proguard.annotation.**
