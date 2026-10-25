# ============================================================
# Order Manager - imagen multi-stage
#   Etapa 1 (build):   compila el JAR con Maven y JDK 17
#   Etapa 2 (runtime): ejecuta el JAR con un JRE liviano (Alpine)
# Solo la etapa 2 forma parte de la imagen final.
# ============================================================

# ---------- Etapa 1: construcción ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Se copia primero solo el pom.xml para reutilizar la capa de
# dependencias mientras el pom no cambie
COPY pom.xml .
RUN mvn -B dependency:go-offline

COPY src ./src

# Las pruebas ya se ejecutan en el pipeline, por eso se omiten aquí
RUN mvn -B clean package -DskipTests

# ---------- Etapa 2: ejecución ----------
FROM bellsoft/liberica-openjre-alpine:17
WORKDIR /app

# Usuario sin privilegios: el contenedor no corre como root
RUN addgroup -S spring && adduser -S spring -G spring

COPY --from=build --chown=spring:spring /app/target/*.jar app.jar

USER spring

EXPOSE 8098

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:8098/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
