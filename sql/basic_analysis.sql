-- Monthly order volume trend-- 
select 
date_format(order_purchase_timestamp, '%Y-%m') as month,
count(order_id) as total_orders 
from orders 
group by month 
order by month;
-- Growth from 4 orders in Sep 2016 to 7,500+ by Nov 2017 — roughly 100x growth in 14 months
-- November 2017 spike (7,544) — almost certainly Black Friday. Note this explicitly
-- 2018-09 and 2018-10 show only 16 and 4 orders — this is data cutoff, not business decline. Mention this in your README so you don't look like you missed it
-- Consistent plateau around 6,000-7,000 orders/month in early 2018 — business matured


#  Order status breakdown -- 
SELECT 
    order_status,
    COUNT(order_id) AS total_orders,
    ROUND(COUNT(order_id) * 100.0 / SUM(COUNT(order_id)) OVER(), 2) AS percentage
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;

-- 97% delivered — operationally healthy on the surface
-- 625 cancelled orders (0.63%) — dig into this later. Which categories cancel most?
-- 609 unavailable — these are orders that could never be fulfilled. Worth flagging 


# Top 10 product categories by revenue -- 
SELECT 
    t.product_category_name_english AS category,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    COUNT(DISTINCT oi.order_id) AS total_orders
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_translation t ON p.product_category_name = t.product_category_name
GROUP BY category
ORDER BY total_revenue DESC
LIMIT 10;

-- Health & Beauty is #1 by revenue (1.25M) but NOT #1 by order count
-- Bed Bath Table has the most orders (9,417) but only 3rd in revenue — lower average order value
-- This gap between volume and revenue is your insight: high volume ≠ high value
-- Computers & Accessories: 6,689 orders but 911K revenue — high ticket items 


# Average delivery time in days -- 
SELECT 
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(order_estimated_delivery_date, order_purchase_timestamp)), 1) AS avg_estimated_days
FROM orders
WHERE order_delivered_customer_date IS NOT NULL;

-- Actual avg: 12.5 days, Estimated avg: 24.4 days
-- Olist is delivering nearly 12 days faster than promised on average
-- This is a strong positive insight — under-promise, over-deliver strategy working
 
 
# Revenue by payment type
SELECT 
    payment_type,
    COUNT(order_id) AS total_orders,
    ROUND(SUM(payment_value), 2) AS total_revenue,
    ROUND(AVG(payment_value), 2) AS avg_order_value
FROM order_payments
GROUP BY payment_type
ORDER BY total_revenue DESC;

-- Credit card dominates — 76,795 orders, avg 163 BRL
-- Voucher users spend significantly less (avg 65 BRL) — likely discount-driven buyers
-- Boleto (Brazilian bank slip) — 19,784 orders, close avg value to credit card — significant payment method, not just fallback 


# On-time vs late delivery by state
SELECT 
    c.customer_state,
    COUNT(o.order_id) AS total_orders,
    SUM(CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date 
        THEN 1 ELSE 0 END) AS on_time,
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date 
        THEN 1 ELSE 0 END) AS late,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date 
        THEN 1 ELSE 0 END) * 100.0 / COUNT(o.order_id), 2) AS late_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY late_pct DESC;

-- AL (Alagoas) is worst — 23.9% late delivery rate
-- Northern/northeastern states dominate the late list — AL, MA, PI, CE, SE, BA
-- SP (São Paulo) only 5.89% late despite being the highest volume state (40K orders)
-- Clear pattern: distance from SP warehouse = higher late rate. Brazil's logistics infrastructure problem, not seller problem 


# Average review score by product category
SELECT 
    t.product_category_name_english AS category,
    ROUND(AVG(r.review_score), 2) AS avg_review,
    COUNT(r.review_id) AS total_reviews
FROM order_reviews r
JOIN order_items oi ON r.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_translation t ON p.product_category_name = t.product_category_name
GROUP BY category
HAVING total_reviews > 100
ORDER BY avg_review ASC
LIMIT 10;

-- Office furniture is the worst rated (3.49) — likely due to assembly complaints and damage in transit
-- Bed Bath Table appears here (3.90) despite being top revenue category — volume doesn't equal satisfaction
-- Computers & Accessories (3.93) with 7,849 reviews — high volume, mediocre satisfaction. Risk area 


# Sellers ranked by revenue and order count
SELECT 
    oi.seller_id,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM order_items oi
JOIN sellers s ON oi.seller_id = s.seller_id
JOIN order_reviews r ON oi.order_id = r.order_id
GROUP BY oi.seller_id, s.seller_state
HAVING total_orders > 50
ORDER BY total_revenue DESC
LIMIT 20;

# Top seller (SP) doing 228K BRL revenue — but review score only 4.12, not exceptional
-- Seller 7c67e1448b... — 976 orders, 188K revenue but 3.35 review score — this is a problem seller. High volume, poor quality
-- Almost all top sellers are in SP — confirms geography drives seller success too
-- BA seller in position 2 (220K revenue, 4.08 score) — notable outlier outside SP

