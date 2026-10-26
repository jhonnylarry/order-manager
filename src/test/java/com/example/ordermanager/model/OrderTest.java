package com.example.ordermanager.model;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Order - Pruebas unitarias del modelo")
class OrderTest {

    @Test
    @DisplayName("constructor: recorta el nombre y deja estado PENDING con total 0")
    void shouldInitializeWithDefaults() {
        Order order = new Order("  Juan  ");

        assertEquals("Juan", order.getCustomerName());
        assertEquals(OrderStatus.PENDING, order.getStatus());
        assertEquals(BigDecimal.ZERO, order.getTotalAmount());
        assertTrue(order.getItems().isEmpty());
    }

    @Test
    @DisplayName("constructor: rechaza nombre nulo o en blanco")
    void shouldRejectInvalidCustomerName() {
        assertThrows(IllegalArgumentException.class, () -> new Order(null));
        assertThrows(IllegalArgumentException.class, () -> new Order("   "));
    }

    @Test
    @DisplayName("addItem: agrega ítems y recalcula el total")
    void shouldRecalculateTotalWhenAddingItems() {
        Order order = new Order("Ana");

        order.addItem(new OrderItem("Mouse", 2, new BigDecimal("10.50")));
        order.addItem(new OrderItem("Teclado", 1, new BigDecimal("30.00")));

        assertEquals(2, order.getItems().size());
        assertEquals(0, new BigDecimal("51.00").compareTo(order.getTotalAmount()));
    }

    @Test
    @DisplayName("canBeModified: solo es verdadero en estado PENDING")
    void shouldAllowModificationOnlyWhenPending() {
        Order order = new Order("Ana");
        assertTrue(order.canBeModified());

        order.setStatus(OrderStatus.CONFIRMED);
        assertFalse(order.canBeModified());
    }

    @Test
    @DisplayName("onCreate: completa fecha, estado y total por defecto")
    void shouldFillDefaultsOnCreate() {
        Order order = new Order();

        order.onCreate();

        assertNotNull(order.getCreatedAt());
        assertEquals(OrderStatus.PENDING, order.getStatus());
        assertEquals(BigDecimal.ZERO, order.getTotalAmount());
    }

    @Test
    @DisplayName("onCreate: conserva estado y total ya definidos")
    void shouldKeepExistingValuesOnCreate() {
        Order order = new Order();
        order.setStatus(OrderStatus.SHIPPED);
        order.setTotalAmount(BigDecimal.TEN);

        order.onCreate();

        assertEquals(OrderStatus.SHIPPED, order.getStatus());
        assertEquals(BigDecimal.TEN, order.getTotalAmount());
    }

    @Test
    @DisplayName("getters y setters: guardan y devuelven los valores")
    void shouldStoreValuesThroughAccessors() {
        Order order = new Order();
        LocalDateTime now = LocalDateTime.now();
        List<OrderItem> items = new ArrayList<>();

        order.setId(7L);
        order.setCustomerName("Luis");
        order.setCreatedAt(now);
        order.setItems(items);

        assertEquals(7L, order.getId());
        assertEquals("Luis", order.getCustomerName());
        assertEquals(now, order.getCreatedAt());
        assertSame(items, order.getItems());
    }

    @Test
    @DisplayName("equals y hashCode: se basan en el id")
    void shouldCompareOrdersById() {
        Order first = new Order("A");
        first.setId(1L);
        Order sameId = new Order("B");
        sameId.setId(1L);
        Order otherId = new Order("A");
        otherId.setId(2L);

        Order sameReference = first;
        Object otherType = "no es un pedido";

        assertEquals(first, sameReference);
        assertEquals(first, sameId);
        assertEquals(first.hashCode(), sameId.hashCode());
        assertNotEquals(first, otherId);
        assertNotEquals(first, null);
        assertNotEquals(first, otherType);
    }
}
