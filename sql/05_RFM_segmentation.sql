-- ============================================================
-- 05_rfm_segmentation.sql
-- Purpose: score each unique customer on Recency, Frequency, Monetary
-- and assign a behavioral segment label. Built on master_transactions.
-- ============================================================

CREATE OR REPLACE VIEW customer_rfm AS
WITH filtered AS (
    SELECT *
    FROM master_transactions
    WHERE order_status = 'delivered'
),
reference_date AS (
    SELECT DATE_ADD(MAX(purchase_timestamp), INTERVAL 1 DAY) AS ref_date
    FROM filtered
),
customer_agg AS (
    SELECT
        f.customer_unique_id,
        MAX(f.purchase_timestamp)  AS last_purchase_date,
        COUNT(DISTINCT f.order_id) AS frequency,
        SUM(f.price)               AS monetary
    FROM filtered f
    GROUP BY f.customer_unique_id
),
rfm_base AS (
    SELECT
        ca.customer_unique_id,
        DATEDIFF(rd.ref_date, ca.last_purchase_date) AS recency,
        ca.frequency,
        ca.monetary
    FROM customer_agg ca
    CROSS JOIN reference_date rd
),
rfm_scored AS (
    SELECT
        customer_unique_id,
        recency,
        frequency,
        monetary,
        NTILE(4) OVER (ORDER BY recency DESC) AS r_score,
        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 2
            WHEN frequency = 3 THEN 3
            ELSE 4
        END AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
)
SELECT
    customer_unique_id,
    recency,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, f_score, m_score) AS rfm_code,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Recent Customers'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score >= 3 THEN 'Cant Lose Them'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Lost'
        ELSE 'Needs Attention'
    END AS rfm_segment
FROM rfm_scored;





-- Should roughly match distinct customer_unique_id count in master_transactions
SELECT COUNT(*) FROM customer_rfm;

-- Sanity check: segment sizes should be reasonably distributed, not one giant bucket
SELECT rfm_segment, COUNT(*) AS customers, ROUND(AVG(monetary),2) AS avg_spend
FROM customer_rfm
GROUP BY rfm_segment
ORDER BY customers DESC;

-- Spot check a few real rows
SELECT * FROM customer_rfm ORDER BY monetary DESC LIMIT 10;