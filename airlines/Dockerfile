# Step 1: Use an official Gradle image to build the application
FROM gradle:8.3.0-jdk17 AS build

# Set the working directory inside the container
WORKDIR /app

# Copy the entire project to the container
COPY . .

# Build the application
RUN gradle clean bootJar

# Download the OpenTelemetry Java agent (auto-instruments Spring Boot, no code changes).
# Version matches opentelemetryInstrumentationVersion in build.gradle.
RUN curl -fsSL -o /opentelemetry-javaagent.jar \
    https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.13.3/opentelemetry-javaagent.jar

# Download the Pyroscope Java agent (previously a manual, gitignored airlines/instrumentation/pyroscope.jar)
RUN curl -fsSL -o /pyroscope.jar \
    https://github.com/grafana/pyroscope-java/releases/download/v2.9.2/pyroscope.jar

# Step 2: Use a lightweight JDK image for running the app
FROM eclipse-temurin:17-jdk-alpine

# Set the working directory for the runtime container
WORKDIR /app

# Copy the JAR file from the build stage
COPY --from=build /app/build/libs/*.jar app.jar

# Copy the OpenTelemetry Java agent
COPY --from=build /opentelemetry-javaagent.jar opentelemetry-javaagent.jar

# Expose the port the application runs on
EXPOSE 8080

# Copy the Pyroscope JAR file
COPY --from=build /pyroscope.jar pyroscope.jar

# set up javaagent
ENV JAVA_TOOL_OPTIONS='-javaagent:/app/opentelemetry-javaagent.jar -javaagent:/app/pyroscope.jar'

# Set the command to run the application
ENTRYPOINT ["java", "-jar", "app.jar"]