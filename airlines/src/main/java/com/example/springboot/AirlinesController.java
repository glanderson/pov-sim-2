package com.example.springboot;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.bind.annotation.CrossOrigin;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.baggage.Baggage;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.metrics.LongCounter;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.opentelemetry.instrumentation.annotations.SpanAttribute;
import io.opentelemetry.instrumentation.annotations.WithSpan;

import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Random;

@RestController
@CrossOrigin(origins = "*") // Allow requests from React app
public class AirlinesController {

	private static final Meter meter = GlobalOpenTelemetry.getMeter("airlines");
	private static final LongCounter requestsCounter =
      meter
          .counterBuilder("app.airlines.requests")
          .setDescription("Counts requests by request and response type")
		  .setUnit("1")
          .build();
	private static final Logger logger = LogManager.getLogger(AirlinesController.class);

	private static String[] airlines = { "AA", "DL", "UA" };

	@Operation(summary = "Index", description = "No-op hello world")
	@GetMapping("/")
	public String index() {
		return "Greetings from Spring Boot!";
	}

	@Operation(summary = "Health check", description = "Performs a simple health check")
	@GetMapping("/health")
	public String health() {
		return "Health check passed!";
	}

	@GetMapping("/airlines")
	@Operation(summary = "Get airlines", description = "Fetch a list of airlines")
	public String getUserById(
			@Parameter(description = "Optional flag - set raise to true to raise an exception") 
			@RequestParam(value = "raise", required = false, defaultValue = "false") boolean raise) {
		if (raise) {
			throw new RuntimeException("Exception raised");
		}
		// otel trace/span
		Span span = Span.current();
		span.setAttribute("testAttribute1", "test123");
		span.setAttribute("testAttribute2", "test456");

		// metric
		requestsCounter.add(1);

		// log
		Random random = new Random();
		int randomNumber = random.nextInt();
		logger.info("here's a random number: " + String.valueOf(randomNumber));
		
		return String.join(", ", airlines);
	}
}
