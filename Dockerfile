# Step 1: Use an official, lightweight Java 25 Runtime base image
FROM eclipse-temurin:25-jre-alpine

# Step 2: Establish a dedicated, unprivileged system user inside the container
RUN addgroup -S springgroup && adduser -S springuser -G springgroup
USER springuser

# Step 3: Define the container's isolated workspace
WORKDIR /home/springuser/app

# Step 4: Copy the compiled JAR binary into the container
COPY target/*.jar app.jar

# Step 5: Document the default port (overridden dynamically at runtime)
EXPOSE 8081

# Step 6: Execute the Java application
ENTRYPOINT ["java", "-jar", "app.jar"]
