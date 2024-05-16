package com.example;

import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;

import java.util.List;

@Path("/")
public class CityResource {

    @GET
    @Path("cities")
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<List<City>> getCities() {
        return City.listAll();
    }
}
