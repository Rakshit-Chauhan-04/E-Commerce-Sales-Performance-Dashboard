-- Verification queries: confirm row counts match expected values after MySQL load
SELECT
    (SELECT COUNT(*) FROM customers) AS customers,
    (SELECT COUNT(*) FROM geolocation) AS geolocation,
    (SELECT COUNT(*) FROM orders) AS orders,
    (SELECT COUNT(*) FROM order_items) AS order_items,
    (SELECT COUNT(*) FROM payments) AS payments,
    (SELECT COUNT(*) FROM reviews) AS reviews,
    (SELECT COUNT(*) FROM products) AS products,
    (SELECT COUNT(*) FROM sellers) AS sellers,
    (SELECT COUNT(*) FROM category_translation) AS category_translation;


-- spot-check queries
    SELECT order_id, purchase_timestamp, delivered_customer_date
FROM orders
LIMIT 5;

SELECT product_id, product_name_length, product_description_length
FROM products
LIMIT 5;