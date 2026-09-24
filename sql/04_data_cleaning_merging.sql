-- ============================================================
-- 04_data_cleaning_merging.sql
-- Purpose: build master_transactions VIEW — one row per order item,
-- enriched with customer, product, seller, payment, and review data.
-- Used as the base for RFM, cohort, and category/regional analysis.
-- ============================================================

USE olist_ecommerce;

CREATE OR REPLACE VIEW master_transactions AS
WITH payments_agg AS (
    -- Collapse multiple payment rows per order into one summary row
    SELECT
        order_id,
        SUM(payment_value)                                              AS total_payment_value,
        COUNT(*)                                                        AS payment_count,
        MAX(payment_installments)                                       AS max_installments,
        SUBSTRING_INDEX(
            GROUP_CONCAT(payment_type ORDER BY payment_value DESC), ',', 1
        )                                                                AS primary_payment_type
    FROM payments
    GROUP BY order_id
),
reviews_dedup AS (
    -- Keep only the most recent review per order
    SELECT order_id, review_score, review_creation_date, review_answer_timestamp
    FROM (
        SELECT
            order_id,
            review_score,
            review_creation_date,
            review_answer_timestamp,
            ROW_NUMBER() OVER (
                PARTITION BY order_id
                ORDER BY review_answer_timestamp DESC, review_creation_date DESC
            ) AS rn
        FROM reviews
    ) ranked
    WHERE rn = 1
)
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,

    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,

    o.order_status,
    o.purchase_timestamp,
    o.approved_at,
    o.delivered_carrier_date,
    o.delivered_customer_date,
    o.estimated_delivery_date,

    p.product_category_name,
    ct.product_category_name_english,

    s.seller_city,
    s.seller_state,

    pa.total_payment_value,
    pa.payment_count,
    pa.max_installments,
    pa.primary_payment_type,

    rd.review_score,
    rd.review_creation_date

FROM order_items oi
JOIN orders    o  ON oi.order_id   = o.order_id
JOIN customers c  ON o.customer_id = c.customer_id
LEFT JOIN products p             ON oi.product_id = p.product_id
LEFT JOIN category_translation ct ON p.product_category_name = ct.product_category_name
LEFT JOIN sellers s               ON oi.seller_id = s.seller_id
LEFT JOIN payments_agg pa         ON oi.order_id = pa.order_id
LEFT JOIN reviews_dedup rd        ON oi.order_id = rd.order_id;




-- VERIFICATION :-

-- Should roughly match order_items row count (112,650)
SELECT COUNT(*) AS total_rows FROM master_transactions;

-- Should be 0 if the join didn't fan out unexpectedly
SELECT order_id, order_item_id, COUNT(*)
FROM master_transactions
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- Spot-check nulls from the LEFT JOINs
SELECT
    SUM(product_category_name_english IS NULL) AS missing_category,
    SUM(total_payment_value IS NULL) AS missing_payment,
    SUM(review_score IS NULL) AS missing_review
FROM master_transactions;