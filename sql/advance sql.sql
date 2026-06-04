use ec;
# Delivery Delay vs Review Score Correlation

SELECT 
    CASE 
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) < 0 
            THEN 'Early'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) = 0 
            THEN 'On Time'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) BETWEEN 1 AND 3 
            THEN '1-3 Days Late'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) BETWEEN 4 AND 7 
            THEN '4-7 Days Late'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) BETWEEN 8 AND 14 
            THEN '8-14 Days Late'
        ELSE 'Over 14 Days Late'
    END AS delivery_status,
    COUNT(o.order_id) AS total_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status
ORDER BY avg_review_score DESC;

# best finding:

-- Early delivery = 4.29 avg score — customers reward speed significantly
-- On time = 4.03 — good but not exceptional
-- 1-3 days late = 3.29 — one star drop just from being slightly late
-- 4-7 days late = 2.10 — severe drop
-- 8-14 days and 14+ days = basically the same (~1.7) — after 8 days late, customers are equally unhappy regardless of how much later it gets
-- The critical threshold is 3 days. Beyond that, review scores collapse. Olist should prioritize getting late orders delivered within 3 days of estimate, not just "eventually." 


# Customer Cohort Retention
WITH first_order AS (
    SELECT 
        c.customer_unique_id,
        MIN(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')) AS cohort_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
),
order_months AS (
    SELECT 
        c.customer_unique_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
),
cohort_data AS (
    SELECT 
        f.cohort_month,
        om.order_month,
        COUNT(DISTINCT f.customer_unique_id) AS customers
    FROM first_order f
    JOIN order_months om ON f.customer_unique_id = om.customer_unique_id
    GROUP BY f.cohort_month, om.order_month
)
SELECT 
    cohort_month,
    order_month,
    customers
FROM cohort_data
ORDER BY cohort_month, order_month
LIMIT 50;

-- The data confirms what most e-commerce businesses fear:
-- Jan 2017 cohort: 764 customers first month → only 6 returned in Jan 2018
-- Feb 2017 cohort: 1,752 first month → single digits returning in subsequent months
-- Retention rate is roughly 0.5-1% — extremely low repeat purchase rate


# RFM Segmentation
WITH rfm_base AS (
    SELECT 
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_order_date,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.price), 2) AS monetary
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT *,
        DATEDIFF('2018-09-01', last_order_date) AS recency_days,
        NTILE(4) OVER (ORDER BY DATEDIFF('2018-09-01', last_order_date) ASC) AS r_score,
        NTILE(4) OVER (ORDER BY frequency DESC) AS f_score,
        NTILE(4) OVER (ORDER BY monetary DESC) AS m_score
    FROM rfm_base
)
SELECT 
    CASE 
        WHEN r_score = 4 AND f_score >= 3 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score <= 2 THEN 'Potential Loyalists'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
        WHEN r_score = 1 AND f_score = 1 THEN 'Lost'
        ELSE 'Needs Attention'
    END AS customer_segment,
    COUNT(customer_unique_id) AS total_customers,
    ROUND(AVG(monetary), 2) AS avg_spend,
    ROUND(AVG(recency_days), 0) AS avg_days_since_order
FROM rfm_scores
GROUP BY customer_segment
ORDER BY total_customers DESC;

 -- Needs Attention is the largest segment (34,989 customers) — this is a problem
-- Champions and Loyal Customers combined: ~39,000 customers but avg spend nearly identical to Needs Attention (139 BRL)
-- Lost customers (4,198) actually have the highest avg spend (159 BRL) — your best spenders left. This is a critical finding
-- Potential Loyalists and At Risk have identical count (7,493) — interesting split 

# High-value customers are churning. The Lost segment spending 159 BRL
# average vs Champions at 139 BRL means Olist is losing its best customers, not its worst

# Seller Health Score -- 
WITH seller_metrics AS (
    SELECT 
        oi.seller_id,
        s.seller_state,
        COUNT(DISTINCT oi.order_id) AS total_orders,
        ROUND(SUM(oi.price), 2) AS total_revenue,
        ROUND(AVG(r.review_score), 2) AS avg_review,
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date 
            THEN 1 ELSE 0 END) AS late_deliveries,
        ROUND(SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date 
            THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT oi.order_id), 2) AS late_pct
    FROM order_items oi
    JOIN sellers s ON oi.seller_id = s.seller_id
    JOIN orders o ON oi.order_id = o.order_id
    JOIN order_reviews r ON oi.order_id = r.order_id
    WHERE o.order_delivered_customer_date IS NOT NULL
    GROUP BY oi.seller_id, s.seller_state
    HAVING total_orders > 30
),
ranked AS (
    SELECT *,
        RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
        RANK() OVER (ORDER BY avg_review DESC) AS review_rank,
        RANK() OVER (ORDER BY late_pct ASC) AS delivery_rank
    FROM seller_metrics
)
SELECT 
    seller_id,
    seller_state,
    total_orders,
    total_revenue,
    avg_review,
    late_pct,
    ROUND((revenue_rank + review_rank + delivery_rank) / 3.0, 1) AS health_score_rank
FROM ranked
ORDER BY health_score_rank ASC
LIMIT 20;

# Late delivery rate is a stronger predictor of seller health than revenue
--  or review score. A seller can have mediocre reviews but still rank well if they
--  deliver on time. But no seller with high late rates appears in the top health rankings regardless of revenue