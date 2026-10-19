--Power BI works best with a star schema — one central “fact” table with the actual transactions/numbers, surrounded by small “dimension” tables (lookup tables) that describe things like dates, products, customers, and locations. This is different from master_transactions, which is a flat, wide table — great for SQL analysis, but not ideal for Power BI’s relationship model and DAX measures.


-- ============================================================
-- Stage 7 (Part A): Star Schema for Power BI
-- Builds 3 dimension tables + 2 fact tables from master_transactions.
-- Run top to bottom. Safe to re-run (each table is dropped first).
-- ============================================================


-- ------------------------------------------------------------
-- 1. dim_date: one row per calendar day
-- Why: Power BI needs a proper date table for time analysis
-- (month-over-month, year-over-year, weekday vs weekend, etc.)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim_date;

-- A recursive query can only repeat a limited number of times by
-- default. We have ~2 years of days, so we raise that limit first.
SET SESSION cte_max_recursion_depth = 3000;

CREATE TABLE dim_date AS
WITH RECURSIVE date_range AS (
    -- Start from the first order date...
    SELECT MIN(DATE(purchase_timestamp)) AS date_value
    FROM master_transactions
    UNION ALL
    -- ...and keep adding 1 day until we reach the last order date
    SELECT DATE_ADD(date_value, INTERVAL 1 DAY)
    FROM date_range
    WHERE date_value < (SELECT MAX(DATE(purchase_timestamp)) FROM master_transactions)
)
SELECT
    date_value                          AS date_key,      -- the date itself, used to link to fact tables
    YEAR(date_value)                    AS year,
    QUARTER(date_value)                 AS quarter,
    MONTH(date_value)                   AS month_number,
    MONTHNAME(date_value)               AS month_name,
    DAY(date_value)                     AS day_of_month,
    DAYNAME(date_value)                 AS day_name,
    WEEK(date_value)                    AS week_number,
    CASE WHEN DAYOFWEEK(date_value) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend  -- 1 = Sat/Sun
FROM date_range;


-- ------------------------------------------------------------
-- 2. dim_product: one row per product category
-- Why: lookup table so charts can filter/group by category.
-- product_key is a simple numeric ID for each category.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim_product;

CREATE TABLE dim_product AS
SELECT DISTINCT
    product_category_name_english AS category
FROM master_transactions
WHERE product_category_name_english IS NOT NULL;   -- skip items with no category name

-- Add an auto-numbered ID column as the first column
ALTER TABLE dim_product
    ADD COLUMN product_key INT AUTO_INCREMENT PRIMARY KEY FIRST;


-- ------------------------------------------------------------
-- 3. dim_location: one row per customer state
-- Why: lookup table so charts can filter/group by state.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim_location;

CREATE TABLE dim_location AS
SELECT DISTINCT
    customer_state AS state
FROM master_transactions
WHERE customer_state IS NOT NULL;

ALTER TABLE dim_location
    ADD COLUMN location_key INT AUTO_INCREMENT PRIMARY KEY FIRST;


-- ------------------------------------------------------------
-- 4. fact_orders: ONE ROW PER ORDER
-- Why: main table for order-level questions (revenue, reviews,
-- delivery time). It has NO product_key on purpose: an order can
-- contain several categories, and including product_key would split
-- one order into several rows and double-count its payment
-- (this was the bug we found and fixed).
-- ------------------------------------------------------------
DROP TABLE IF EXISTS fact_orders;

CREATE TABLE fact_orders AS
SELECT
    mt.order_id,
    DATE(MAX(mt.purchase_timestamp))   AS date_key,        -- links to dim_date
    dl.location_key,                                       -- links to dim_location
    mt.customer_unique_id,
    MAX(mt.total_payment_value)        AS order_revenue,   -- same value repeated on each item row, so MAX picks it once
    SUM(mt.freight_value)              AS order_freight,   -- freight is per item, so SUM is correct
    MAX(mt.review_score)               AS review_score,
    DATEDIFF(MAX(mt.delivered_customer_date),
             MAX(mt.purchase_timestamp)) AS delivery_days  -- NULL if the order was never delivered
FROM master_transactions mt
LEFT JOIN dim_location dl ON mt.customer_state = dl.state
GROUP BY mt.order_id, dl.location_key, mt.customer_unique_id;


-- ------------------------------------------------------------
-- 5. fact_order_items: ONE ROW PER ITEM
-- Why: used for category-level questions. Price and freight are
-- genuinely per item, so summing them here is safe.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS fact_order_items;

CREATE TABLE fact_order_items AS
SELECT
    mt.order_id,
    mt.order_item_id,
    DATE(mt.purchase_timestamp) AS date_key,       -- links to dim_date
    dp.product_key,                                -- links to dim_product
    dl.location_key,                               -- links to dim_location
    mt.price,
    mt.freight_value
FROM master_transactions mt
LEFT JOIN dim_product  dp ON mt.product_category_name_english = dp.category
LEFT JOIN dim_location dl ON mt.customer_state = dl.state;


-- ============================================================
-- VERIFICATION QUERIES (run after the build)
-- ============================================================

-- Row counts for all 5 tables
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL SELECT 'dim_product',     COUNT(*) FROM dim_product
UNION ALL SELECT 'dim_location',    COUNT(*) FROM dim_location
UNION ALL SELECT 'fact_orders',     COUNT(*) FROM fact_orders
UNION ALL SELECT 'fact_order_items', COUNT(*) FROM fact_order_items;

-- fact_orders must be one row per order: both numbers should be identical (98,666)
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT order_id) AS distinct_orders FROM fact_orders;

-- Total revenue: should be about $15.85M (just under the raw payments total of about $16.0M)
SELECT ROUND(SUM(order_revenue), 2) AS fact_revenue FROM fact_orders;

-- Item count: should be close to 112,650
SELECT COUNT(*) AS item_rows FROM fact_order_items;