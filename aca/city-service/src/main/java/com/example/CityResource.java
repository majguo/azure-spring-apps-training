package com.example;

import io.smallrye.mutiny.Multi;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;

import java.util.List;

@Path("/")
public class CityResource {

    @GET
    @Path("cities")
    @Produces(MediaType.APPLICATION_JSON)
    public Multi<List<City>> getCities() {
        return City.streamAll().map(c -> (City)c).group().intoLists().of(20);
    }
}
