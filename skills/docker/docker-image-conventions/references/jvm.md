# JVM (Java / Kotlin) — Maven build, JRE runtime

> **Not yet proven on a GroupBees project.** A starting point, not a
> convention: validate it on the first real project, then remove this note.

```dockerfile
# ---- builder ----
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /usr/local/src/app
# Deps first — cached as long as pom.xml doesn't change.
COPY mvnw pom.xml ./
COPY .mvn ./.mvn
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -q dependency:go-offline
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -q package -DskipTests \
 && cp target/*.jar /tmp/app.jar

# ---- runtime: JRE-only image, non-root ----
FROM eclipse-temurin:21-jre-alpine AS runtime
ARG APP_DIR=/usr/local/src/app
ENV APP_DIR=${APP_DIR}
WORKDIR ${APP_DIR}
RUN addgroup -S app && adduser -S -G app -h ${APP_DIR} -s /sbin/nologin app
COPY --from=builder --chown=app:app /tmp/app.jar ${APP_DIR}/app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

- Use the Maven wrapper (`mvnw` + `.mvn/`, committed) so the build does not
  depend on the Maven version of the image. Tests run in CI, hence
  `-DskipTests` in the image build.
- `target/*.jar` must match one jar: with a multi-module build, copy the
  module's jar explicitly.
- If your app needs ICU (i18n, full Unicode collation) or specific locales,
  switch the runtime to `eclipse-temurin:21-jre-jammy` — alpine ships only the
  POSIX locale by default.

## Gradle variant

Replace the builder's dependency and build steps:

```dockerfile
COPY gradlew build.gradle.kts settings.gradle.kts ./
COPY gradle ./gradle
RUN ./gradlew --no-daemon dependencies
COPY src ./src
RUN ./gradlew --no-daemon bootJar && cp build/libs/*.jar /tmp/app.jar
```

With Spring Boot, disable the plain jar (`tasks.jar { enabled = false }`) so
`build/libs/` holds a single jar.
