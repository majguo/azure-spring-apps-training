package com.example;

import io.micronaut.context.annotation.Factory;
import io.micronaut.context.event.BeanCreatedEventListener;
import io.micronaut.jdbc.DataSourceResolver;
import io.micronaut.runtime.Micronaut;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.instrumentation.jdbc.datasource.OpenTelemetryDataSource;

import jakarta.inject.Singleton;
import javax.sql.DataSource;

@Factory
public class Application {

    public static void main(String[] args) {
        Micronaut.run(Application.class, args);
    }

    @Singleton
    BeanCreatedEventListener<DataSource> otel(OpenTelemetry telemetry, DataSourceResolver resolver) {
        return event -> {
            DataSource dataSource = event.getBean();
            return new OpenTelemetryDataSource(
                    resolver.resolve(dataSource),
                    telemetry
            );
        };
    }
}