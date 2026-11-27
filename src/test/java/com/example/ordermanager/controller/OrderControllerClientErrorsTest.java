package com.example.ordermanager.controller;

import com.example.ordermanager.service.OrderService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(OrderController.class)
@DisplayName("OrderController - Errores del cliente")
class OrderControllerClientErrorsTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private OrderService service;

    @Test
    @DisplayName("Un JSON mal escrito retorna 400")
    void shouldReturn400WhenJsonIsMalformed() throws Exception {
        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"customerName\":"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("El cuerpo de la solicitud no se puede leer"));
    }

    @Test
    @DisplayName("Un identificador que no es número retorna 400")
    void shouldReturn400WhenIdIsNotANumber() throws Exception {
        mockMvc.perform(get("/api/orders/abc"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Valor no válido para el parámetro 'id'"));
    }

    @Test
    @DisplayName("Una ruta que no existe retorna 404")
    void shouldReturn404WhenPathDoesNotExist() throws Exception {
        mockMvc.perform(get("/favicon.ico"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status").value(404));
    }

    @Test
    @DisplayName("Un método no permitido retorna 405 e indica los permitidos")
    void shouldReturn405WhenMethodIsNotAllowed() throws Exception {
        mockMvc.perform(patch("/api/orders/1"))
                .andExpect(status().isMethodNotAllowed())
                .andExpect(header().exists(HttpHeaders.ALLOW));
    }

    @Test
    @DisplayName("Un tipo de contenido no soportado retorna 415")
    void shouldReturn415WhenContentTypeIsNotSupported() throws Exception {
        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.TEXT_PLAIN)
                        .content("hola"))
                .andExpect(status().isUnsupportedMediaType());
    }
}
