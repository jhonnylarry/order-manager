package com.example.ordermanager.controller;

import com.example.ordermanager.exception.InvalidOrderStateException;
import com.example.ordermanager.model.Order;
import com.example.ordermanager.model.OrderStatus;
import com.example.ordermanager.service.OrderService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(OrderController.class)
@DisplayName("OrderController - Filtros, ítems y transiciones de estado")
class OrderControllerTransitionsTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private OrderService service;

    private Order orderWithStatus(OrderStatus status) {
        Order order = new Order("Juan");
        order.setId(1L);
        order.setStatus(status);
        return order;
    }

    @Test
    @DisplayName("GET /api/orders/status/{status}: filtra por estado")
    void shouldFilterOrdersByStatus() throws Exception {
        when(service.getOrdersByStatus(OrderStatus.PENDING))
                .thenReturn(List.of(orderWithStatus(OrderStatus.PENDING)));

        mockMvc.perform(get("/api/orders/status/PENDING"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].status").value("PENDING"));
    }

    @Test
    @DisplayName("POST /api/orders/{id}/items: retorna 200 con ítem válido")
    void shouldAddItem() throws Exception {
        when(service.addItem(eq(1L), any()))
                .thenReturn(orderWithStatus(OrderStatus.PENDING));

        String body = "{\"productName\":\"Mouse\",\"quantity\":2,\"unitPrice\":10.50}";

        mockMvc.perform(post("/api/orders/1/items")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1));
    }

    @Test
    @DisplayName("POST /api/orders/{id}/items: retorna 400 si la cantidad es inválida")
    void shouldReturn400WhenItemQuantityInvalid() throws Exception {
        String body = "{\"productName\":\"Mouse\",\"quantity\":0,\"unitPrice\":10.50}";

        mockMvc.perform(post("/api/orders/1/items")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fields.quantity").exists());

        verify(service, never()).addItem(any(), any());
    }

    @Test
    @DisplayName("PUT /api/orders/{id}/ship: retorna 200 con estado SHIPPED")
    void shouldShipOrder() throws Exception {
        when(service.shipOrder(1L)).thenReturn(orderWithStatus(OrderStatus.SHIPPED));

        mockMvc.perform(put("/api/orders/1/ship"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("SHIPPED"));
    }

    @Test
    @DisplayName("PUT /api/orders/{id}/deliver: retorna 200 con estado DELIVERED")
    void shouldDeliverOrder() throws Exception {
        when(service.deliverOrder(1L)).thenReturn(orderWithStatus(OrderStatus.DELIVERED));

        mockMvc.perform(put("/api/orders/1/deliver"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DELIVERED"));
    }

    @Test
    @DisplayName("PUT /api/orders/{id}/cancel: retorna 200 con estado CANCELLED")
    void shouldCancelOrder() throws Exception {
        when(service.cancelOrder(1L)).thenReturn(orderWithStatus(OrderStatus.CANCELLED));

        mockMvc.perform(put("/api/orders/1/cancel"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("CANCELLED"));
    }

    @Test
    @DisplayName("PUT /api/orders/{id}/ship: retorna 409 si el estado no lo permite")
    void shouldReturn409WhenShipIsNotAllowed() throws Exception {
        when(service.shipOrder(1L)).thenThrow(
                new InvalidOrderStateException("PENDING", "SHIPPED"));

        mockMvc.perform(put("/api/orders/1/ship"))
                .andExpect(status().isConflict());
    }

    @Test
    @DisplayName("POST /api/orders: retorna 400 si el servicio lanza IllegalArgumentException")
    void shouldReturn400WhenServiceRejectsArgument() throws Exception {
        when(service.createOrder(any())).thenThrow(new IllegalArgumentException("dato inválido"));

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"customerName\":\"Juan\",\"items\":[]}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("dato inválido"));
    }

    @Test
    @DisplayName("GET /api/orders: retorna 500 ante un error inesperado")
    void shouldReturn500OnUnexpectedError() throws Exception {
        when(service.getAllOrders()).thenThrow(new RuntimeException("falla interna"));

        mockMvc.perform(get("/api/orders"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.status").value(500));
    }
}
