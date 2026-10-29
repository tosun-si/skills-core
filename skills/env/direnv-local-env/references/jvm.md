# Java / Kotlin (JVM)

```bash
# SDKMAN-managed JDK (preferred — per-project JDK switching).
export JAVA_HOME="$HOME/.sdkman/candidates/java/21.0.5-tem"
PATH_add "$JAVA_HOME/bin"

# Or system-managed on macOS:
# export JAVA_HOME="$(/usr/libexec/java_home -v 21)"

# Gradle: cap memory + disable the daemon for CI-like behaviour locally.
export GRADLE_OPTS="-Xmx2g -Dorg.gradle.daemon=false"

# Kotlin compiler (rarely needed if using Gradle).
# export KOTLIN_HOME="$HOME/.sdkman/candidates/kotlin/current"
```
