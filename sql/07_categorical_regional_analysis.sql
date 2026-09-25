-- ============================================================
-- Stage 6: Category & Regional Performance Analysis
-- Grain: one row per category (or per state) — aggregated from
-- master_transactions, which is at order_items grain.
-- ============================================================

-- 1. CATEGORY PERFORMANCE
-- Plain language: for each product category, add up all the money
-- it brought in, count how many order-line-items it appeared in,
-- work out the average amount customers spent per line item, and
-- average what customers rated those orders.
CREATE OR REPLACE VIEW category_performance AS
SELECT
    product_category_name_english AS category,
    COUNT(*) AS total_order_items,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(SUM(price), 2) AS total_revenue,
    ROUND(AVG(price), 2) AS avg_item_price,
    ROUND(AVG(review_score), 2) AS avg_review_score,
    ROUND(SUM(freight_value), 2) AS total_freight_cost,
    ROUND(AVG(freight_value), 2) AS avg_freight_per_item
FROM master_transactions
WHERE product_category_name_english IS NOT NULL
GROUP BY product_category_name_english
ORDER BY total_revenue DESC;


-- 2. REGIONAL PERFORMANCE
-- Plain language: step 1 shrinks master_transactions down to one row
-- per order_id, picking each order's state, payment, freight, review,
-- and delivery dates. This removes the item-level duplication. Step 2
-- then aggregates that clean, one-row-per-order data by state.
CREATE OR REPLACE VIEW regional_performance AS
WITH order_level AS (
    SELECT
        order_id,
        customer_state,
        customer_unique_id,
        MAX(total_payment_value) AS order_payment_value,   -- same value repeated per row, so MAX just picks it once
        SUM(freight_value) AS order_freight_value,          -- freight IS per item, so this one correctly sums
        MAX(review_score) AS order_review_score,
        MAX(purchase_timestamp) AS purchase_timestamp,
        MAX(delivered_customer_date) AS delivered_customer_date,
        MAX(estimated_delivery_date) AS estimated_delivery_date
    FROM master_transactions
    GROUP BY order_id, customer_state, customer_unique_id
)
SELECT
    customer_state AS state,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_unique_id) AS unique_customers,
    ROUND(SUM(order_payment_value), 2) AS total_revenue,
    ROUND(AVG(order_payment_value), 2) AS avg_order_value,
    ROUND(AVG(order_freight_value), 2) AS avg_freight_cost,
    ROUND(AVG(order_review_score), 2) AS avg_review_score,
    ROUND(AVG(DATEDIFF(delivered_customer_date, purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(estimated_delivery_date, delivered_customer_date)), 1) AS avg_days_early_or_late
FROM order_level
WHERE delivered_customer_date IS NOT NULL
GROUP BY customer_state
ORDER BY total_revenue DESC;

-- 3. TOP CATEGORY PER REGION (optional, good for a dashboard slicer)
-- Plain language: for each state, find its single best-selling
-- category by revenue. Uses a window function to rank categories
-- within each state, then keeps only rank 1.
CREATE OR REPLACE VIEW top_category_by_region AS
SELECT state, category, total_revenue
FROM (
    SELECT
        customer_state AS state,
        product_category_name_english AS category,
        SUM(price) AS total_revenue,
        RANK() OVER (PARTITION BY customer_state ORDER BY SUM(price) DESC) AS rnk
    FROM master_transactions
    WHERE product_category_name_english IS NOT NULL
    GROUP BY customer_state, product_category_name_english
) ranked
WHERE rnk = 1
ORDER BY total_revenue DESC;




-- Total revenue across all states should be in the same ballpark
-- as total payments across all orders in the raw payments table.
SELECT SUM(total_revenue) AS regional_total FROM regional_performance;
SELECT SUM(payment_value) AS raw_payments_total FROM payments;

-- Order count check
SELECT SUM(total_orders) AS sum_across_states FROM regional_performance;

-- Category performance — order item count check
SELECT SUM(total_order_items) AS sum_across_categories FROM category_performance;


-- Manual version for one state, avoiding the view entirely
SELECT
    COUNT(DISTINCT order_id) AS manual_order_count,
    ROUND(SUM(DISTINCT_payment), 2) AS manual_revenue
FROM (
    SELECT DISTINCT order_id, total_payment_value AS DISTINCT_payment
    FROM master_transactions
    WHERE customer_state = 'SP'
      AND delivered_customer_date IS NOT NULL
) t;

-- avg_review_score should be between 1 and 5 for every row
SELECT * FROM category_performance WHERE avg_review_score NOT BETWEEN 1 AND 5;
SELECT * FROM regional_performance WHERE avg_review_score NOT BETWEEN 1 AND 5;

-- avg_delivery_days should be positive and roughly sane (few days to a couple months)
SELECT * FROM regional_performance WHERE avg_delivery_days < 0 OR avg_delivery_days > 100;


SELECT * FROM regional_performance WHERE state = 'SP';



