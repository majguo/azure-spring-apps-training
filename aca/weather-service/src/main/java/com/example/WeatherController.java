package com.example;

import com.example.domain.Weather;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.annotation.QueryValue;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;

import jakarta.validation.constraints.NotBlank;
import java.util.Optional;

@ExecuteOn(TaskExecutors.BLOCKING)
@Controller("/weather")
public class WeatherController {

    protected final WeatherRepository weatherRepository;

    public WeatherController(WeatherRepository weatherRepository) {
        this.weatherRepository = weatherRepository;
    }

    @Get("/city")
    public Optional<Weather> show(@QueryValue("name") @NotBlank String cityName) {
        return weatherRepository.findById(cityName);
    }

}
