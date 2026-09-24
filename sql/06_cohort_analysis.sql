- ============================================================
-- 06_cohort_analysis.sql
-- Purpose: monthly cohort retention — % of each cohort still
-- purchasing in subsequent months. Built on master_transactions.
-- ============================================================

USE olist_ecommerce;

CREATE OR REPLACE VIEW cohort_analysis AS
WITH filtered AS (
    SELECT *
    FROM master_transactions
    WHERE order_status = 'delivered'
),
customer_orders AS (
    SELECT DISTINCT
        customer_unique_id,
        order_id,
        DATE_FORMAT(purchase_timestamp, '%Y-%m-01') AS order_month
    FROM filtered
),
cohort AS (
    SELECT
        customer_unique_id,
        MIN(order_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_unique_id
),
joined AS (
    SELECT
        co.customer_unique_id,
        co.order_month,
        c.cohort_month,
        TIMESTAMPDIFF(MONTH, c.cohort_month, co.order_month) AS month_number
    FROM customer_orders co
    JOIN cohort c ON co.customer_unique_id = c.customer_unique_id
),
monthly_counts AS (
    SELECT
        cohort_month,
        month_number,
        COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM joined
    GROUP BY cohort_month, month_number
),
cohort_sizes AS (
    SELECT cohort_month, active_customers AS cohort_size
    FROM monthly_counts
    WHERE month_number = 0
),
-- NEW: build a complete grid of every cohort x every month_number
-- it could possibly reach, given how many months of data exist after it
max_month AS (
    SELECT TIMESTAMPDIFF(MONTH, MIN(cohort_month), MAX(order_month)) AS max_offset
    FROM joined
),
month_spine AS (
    SELECT n AS month_number
    FROM (
        SELECT ROW_NUMBER() OVER () - 1 AS n
        FROM information_schema.columns
        LIMIT 30   -- comfortably covers the dataset's ~25 month span
    ) nums
    WHERE n <= (SELECT max_offset FROM max_month)
),
full_grid AS (
    SELECT cs.cohort_month, ms.month_number, cs.cohort_size
    FROM cohort_sizes cs
    CROSS JOIN month_spine ms
)
SELECT
    fg.cohort_month,
    fg.month_number,
    COALESCE(mc.active_customers, 0) AS active_customers,
    fg.cohort_size,
    ROUND(COALESCE(mc.active_customers, 0) / fg.cohort_size * 100, 2) AS retention_rate
FROM full_grid fg
LEFT JOIN monthly_counts mc
    ON fg.cohort_month = mc.cohort_month AND fg.month_number = mc.month_number
ORDER BY fg.cohort_month, fg.month_number;






-- Now every cohort should show a continuous 0...N row range, no gaps
SELECT cohort_month, month_number, retention_rate
FROM cohort_analysis
WHERE cohort_month = '2017-01-01'
ORDER BY month_number;

-- 1. Make sure no cohort has a NULL cohort_size (would indicate a broken join)
SELECT COUNT(*) FROM cohort_analysis WHERE cohort_size IS NULL;

-- 2. Confirm every cohort's month_number range stops at the right place
-- (a cohort from late 2018 shouldn't have 24 months of data — there's no future data for it)
SELECT cohort_month, MAX(month_number) AS max_month_reached
FROM cohort_analysis
GROUP BY cohort_month
ORDER BY cohort_month DESC
LIMIT 5;

-- Sanity check: month_number=0 rows summed should ~= total unique customers (93358 from Stage 4)
SELECT SUM(active_customers) AS total_new_customers
FROM cohort_analysis
WHERE month_number = 0;

-- Retention should never exceed 100%
SELECT * FROM cohort_analysis WHERE retention_rate > 100;

-- The actual retention curve — this is the interesting part
SELECT cohort_month, month_number, retention_rate
FROM cohort_analysis
WHERE cohort_month = (SELECT MIN(cohort_month) FROM cohort_analysis)
ORDER BY month_number;