package com.example;

import io.quarkus.runtime.StartupEvent;
import io.vertx.ext.consul.ServiceOptions;
import io.vertx.mutiny.ext.consul.ConsulClient;
import io.vertx.ext.consul.ConsulClientOptions;
import io.vertx.mutiny.core.Vertx;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

@ApplicationScoped
public class Registration {

    @ConfigProperty(name = "consul.host", defaultValue = "localhost") String host;
    @ConfigProperty(name = "consul.port", defaultValue = "8500") int port;

    @ConfigProperty(name = "quarkus.http.port", defaultValue = "8080") int httpPort;
    @ConfigProperty(name = "consul.app.address", defaultValue = "localhost") String address;

    /**
     * Register city-service in Consul.
     *
     * Note: this method is called on a worker thread, and so it is allowed to block.
     */
    public void init(@Observes StartupEvent ev, Vertx vertx) {
        ConsulClient client = ConsulClient.create(vertx, new ConsulClientOptions().setHost(host).setPort(port));

        client.registerServiceAndAwait(
                new ServiceOptions().setPort(httpPort).setAddress(address).setName("city-service"));
    }
}
