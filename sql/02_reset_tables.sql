-- truncating all the tables
TRUNCATE TABLE customers;
TRUNCATE TABLE geolocation;
TRUNCATE TABLE orders;
TRUNCATE TABLE order_items;
TRUNCATE TABLE payments;
TRUNCATE TABLE reviews;
TRUNCATE TABLE products;
TRUNCATE TABLE sellers;
TRUNCATE TABLE category_translation;

-- chcking if all the tables are empty or no
SELECT COUNT(*) FROM customers;