# AMap's location SDK loads these optional implementations reflectively when
# the corresponding vendor modules are present. They are not part of the
# release dependency set, so R8 must not treat their absence as a build error.
-dontwarn com.amap.ams.gnss.GnssSoftLocator
-dontwarn net.jafama.FastMath

# The AMap renderer loads its mapcore bridge by its original class name from
# the GL thread. R8 cannot see that lookup, so shrinking the release build
# removes `com.autonavi.base.amap.mapcore.ClassTools` and the first
# `AMapWidget` surface aborts the process. Keep the vendor runtime intact;
# the map SDK owns its reflection and native registration boundaries.
-keep class com.amap.** { *; }
-keep class com.autonavi.** { *; }
-dontwarn com.amap.**
-dontwarn com.autonavi.**
