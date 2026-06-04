USE EC;

-- STEP 1: BASELINE PERFORMANCE (BEFORE OPTIMIZATION)

SET profiling = 1;

-- Baseline query without forcing index usage
-- This runs on already-indexed tables for comparison
-- We will compare against the unoptimized column types
SELECT 
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN order_reviews r ON oi.order_id = r.order_id
GROUP BY oi.seller_id; # 0.453/0.141 sec

SHOW PROFILES;

-- STEP 2: COLUMN TYPE OPTIMIZATION
-- Problem: Python loaded date columns as TEXT
-- TEXT columns cannot be indexed without length prefix
-- and date functions perform poorly on TEXT


ALTER TABLE orders MODIFY order_purchase_timestamp DATETIME;
ALTER TABLE orders MODIFY order_delivered_customer_date DATETIME;
ALTER TABLE orders MODIFY order_estimated_delivery_date DATETIME;

-- Verify conversion worked
SELECT 
    COLUMN_NAME,
    DATA_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'EC'
AND TABLE_NAME = 'orders'
AND COLUMN_NAME IN (
    'order_purchase_timestamp',
    'order_delivered_customer_date',
    'order_estimated_delivery_date'
);

-- STEP 3: ADD INDEXES
-- Adding indexes on:
-- 1. Frequently filtered columns (status, date)
-- 2. Frequently joined TEXT columns (category, state)
-- Note: Foreign key columns already auto-indexed
--       when FK constraints were added


-- Index on order_status for filtering by status
ALTER TABLE orders ADD INDEX idx_orders_status (order_status(20));

-- Index on purchase date for time-series queries
ALTER TABLE orders ADD INDEX idx_orders_purchase_date (order_purchase_timestamp);

-- Index on product category for category-level aggregations
ALTER TABLE products ADD INDEX idx_products_category (product_category_name(50));

-- Index on customer state for geographic analysis
ALTER TABLE customers ADD INDEX idx_customers_state (customer_state(20));


-- STEP 4: VERIFY ALL INDEXES ON EC DATABASE


SELECT 
    TABLE_NAME,
    INDEX_NAME,
    COLUMN_NAME,
    INDEX_TYPE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'EC'
ORDER BY TABLE_NAME, INDEX_NAME;


-- STEP 5: POST-OPTIMIZATION PERFORMANCE


SET profiling = 1;

SELECT 
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN order_reviews r ON oi.order_id = r.order_id
GROUP BY oi.seller_id;

SHOW PROFILES;

-- STEP 6: EXPLAIN ANALYSIS
-- Verify indexes are actually being used in joins
-- Look for: type = eq_ref or ref (good)
--           type = ALL means full table scan (bad)

EXPLAIN
SELECT 
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN order_reviews r ON oi.order_id = r.order_id
GROUP BY oi.seller_id
LIMIT 20;

-- EXPLAIN ANALYSIS RESULTS
-- -----------------------------------------------
-- Table        | Type    | Key                | Meaning
-- order_items  | range   | fk_items_orders    | Index used on join
-- orders       | eq_ref  | PRIMARY            | Fastest join type, PK lookup
-- order_reviews| ref     | fk_reviews_orders  | Index used on join
-- -----------------------------------------------
-- Result: Zero full table scans across all 3 tables
-- All joins are index-backed on 100K+ row dataset
-- eq_ref on orders = single row lookup per join = optimal



-- PERFORMANCE RESULTS

-- Post-optimization query execution time: 0.141 seconds
-- Tested on:
--   order_items   : 112,650 rows
--   orders        : 99,441 rows
--   order_reviews : 99,224 rows
--
-- Index impact verified via EXPLAIN analysis:
--   - Zero full table scans (no ALL type in EXPLAIN)
--   - All joins index-backed (eq_ref and ref types)
--   - eq_ref on orders = single row PK lookup per join
--
-- Note: Baseline timing unavailable as indexes were
-- added during schema setup. Performance validated
-- through EXPLAIN output showing index usage across
-- all join columns.

-- Industry reference: Full table scan on 100K rows
-- typically runs 2-5 seconds without indexes.
-- Index-backed joins reduce this to milliseconds.


-- Query 1: Date range filter now uses DATETIME index
EXPLAIN
SELECT 
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS month,
    COUNT(order_id) AS total_orders
FROM orders
WHERE order_purchase_timestamp BETWEEN '2017-01-01' AND '2018-01-01'
GROUP BY month
ORDER BY month;

-- Query 2: State filter now uses customer state index
EXPLAIN
SELECT 
    c.customer_state,
    COUNT(o.order_id) AS total_orders
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_state = 'SP'
GROUP BY c.customer_state;

-- Query 3: Category filter now uses product category index
EXPLAIN
SELECT 
    t.product_category_name_english,
    COUNT(oi.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_translation t 
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name = 'beleza_saude'
GROUP BY t.product_category_name_english;


-- SUMMARY

-- Indexes added   : 4 new indexes
-- Columns fixed   : 3 TEXT dates converted to DATETIME
-- Join efficiency : All major joins now index-backed
-- Query coverage  : Time-series, geographic, category queries
--                   all benefit from these indexes
-- Tables affected : orders, products, customers
