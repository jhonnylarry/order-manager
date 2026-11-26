package com.example.ordermanager.observability;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.allOf;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureObservability
@DisplayName("Observabilidad - Métricas para Prometheus")
class MetricsEndpointTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("GET /actuator/prometheus: publica métricas de peticiones, memoria, CPU y logs")
    void shouldExposePrometheusMetrics() throws Exception {
        mockMvc.perform(get("/api/orders")).andExpect(status().isOk());

        mockMvc.perform(get("/actuator/prometheus"))
                .andExpect(status().isOk())
                .andExpect(content().string(allOf(
                        containsString("http_server_requests_seconds_bucket"),
                        containsString("jvm_memory_used_bytes"),
                        containsString("process_cpu_usage"),
                        containsString("logback_events_total"),
                        containsString("application=\"order-manager\""))));
    }
}
