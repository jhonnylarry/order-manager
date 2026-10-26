package com.example.ordermanager.model;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("OrderItem - Pruebas unitarias del modelo")
class OrderItemTest {

    @Test
    @DisplayName("constructor: recorta el nombre y calcula el subtotal")
    void shouldCreateItemAndCalculateSubtotal() {
        OrderItem item = new OrderItem("  Cable USB  ", 3, new BigDecimal("2.50"));

        assertEquals("Cable USB", item.getProductName());
        assertEquals(3, item.getQuantity());
        assertEquals(0, new BigDecimal("7.50").compareTo(item.getSubtotal()));
    }

    @Test
    @DisplayName("constructor: rechaza nombre nulo o en blanco")
    void shouldRejectInvalidProductName() {
        assertThrows(IllegalArgumentException.class,
                () -> new OrderItem(null, 1, BigDecimal.ONE));
        assertThrows(IllegalArgumentException.class,
                () -> new OrderItem("  ", 1, BigDecimal.ONE));
    }

    @Test
    @DisplayName("constructor: rechaza cantidad menor o igual a cero")
    void shouldRejectNonPositiveQuantity() {
        assertThrows(IllegalArgumentException.class,
                () -> new OrderItem("Mouse", 0, BigDecimal.ONE));
        assertThrows(IllegalArgumentException.class,
                () -> new OrderItem("Mouse", -2, BigDecimal.ONE));
    }

    @Test
    @DisplayName("constructor: rechaza precio nulo o negativo y acepta cero")
    void shouldValidateUnitPrice() {
        assertThrows(IllegalArgumentException.class,
                () -> new OrderItem("Mouse", 1, null));
        assertThrows(IllegalArgumentException.class,
                () -> new OrderItem("Mouse", 1, new BigDecimal("-0.01")));

        OrderItem free = new OrderItem("Muestra", 1, BigDecimal.ZERO);
        assertEquals(0, BigDecimal.ZERO.compareTo(free.getSubtotal()));
    }

    @Test
    @DisplayName("setters: actualizan los valores del ítem")
    void shouldUpdateValuesThroughSetters() {
        OrderItem item = new OrderItem();

        item.setProductName("Monitor");
        item.setQuantity(2);
        item.setUnitPrice(new BigDecimal("100.00"));

        assertEquals("Monitor", item.getProductName());
        assertEquals(2, item.getQuantity());
        assertEquals(0, new BigDecimal("200.00").compareTo(item.getSubtotal()));
    }

    @Test
    @DisplayName("equals y hashCode: comparan nombre, cantidad y precio")
    void shouldCompareItemsByValue() {
        OrderItem base = new OrderItem("Mouse", 2, new BigDecimal("10.00"));
        OrderItem same = new OrderItem("Mouse", 2, new BigDecimal("10.00"));

        OrderItem sameReference = base;
        Object otherType = "no es un ítem";

        assertEquals(base, sameReference);
        assertEquals(base, same);
        assertEquals(base.hashCode(), same.hashCode());
        assertNotEquals(base, new OrderItem("Teclado", 2, new BigDecimal("10.00")));
        assertNotEquals(base, new OrderItem("Mouse", 3, new BigDecimal("10.00")));
        assertNotEquals(base, new OrderItem("Mouse", 2, new BigDecimal("11.00")));
        assertNotEquals(base, null);
        assertNotEquals(base, otherType);
    }
}
