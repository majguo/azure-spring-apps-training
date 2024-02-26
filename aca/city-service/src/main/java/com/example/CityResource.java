package com.example;

import io.quarkus.mongodb.panache.reactive.ReactivePanacheMongoEntityBase;
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;

@Path("/")
public class CityResource {

    @GET
    @Path("hello")
    @Produces(MediaType.TEXT_PLAIN)
    public String hello() {
        return "Hello from RESTEasy Reactive";
    }

    @GET
    @Path("cities")
    @Produces(MediaType.APPLICATION_JSON)
    public Multi<List<City>> getCities() {
        return City.streamAll().map(c -> (City)c).group().intoLists().of(20);
    }

    @POST
    @Path("cities")
    @Consumes(MediaType.APPLICATION_JSON)
    public Uni<Response> addCity(City city) {
        return city.<City>persist().map(v ->
                Response.created(URI.create("/cities/" + URLEncoder.encode(v.name, StandardCharsets.UTF_8).replace("+", "%20")))
                        .entity(city).build());
    }

    @GET
    @Path("cities/{name}")
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<City> getCity(@PathParam("name") String name) {
        return City.find("name", name).firstResult();
    }

    @DELETE
    @Path("cities/{name}")
    public Uni<Void> deleteCity(@PathParam("name") String name) {
        return City.find("name", name).firstResult().call(ReactivePanacheMongoEntityBase::delete).map(v -> null);
    }
}
