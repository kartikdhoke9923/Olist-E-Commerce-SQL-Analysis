create database if not exists EC ;
use EC;

SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = 'EC'
ORDER BY table_rows DESC;


# defining keys
-- Step 1: Add Primary Keys

ALTER TABLE customers
    MODIFY customer_id TEXT,
    ADD PRIMARY KEY (customer_id(50));

ALTER TABLE orders
    MODIFY order_id TEXT,
    ADD PRIMARY KEY (order_id(50));

ALTER TABLE products
    MODIFY product_id TEXT,
    ADD PRIMARY KEY (product_id(50));

ALTER TABLE sellers
    MODIFY seller_id TEXT,
    ADD PRIMARY KEY (seller_id(50));

-- Step 2: Add Foreign Keys



-- Convert columns to VARCHAR so foreign keys work

ALTER TABLE orders MODIFY customer_id VARCHAR(50);
ALTER TABLE customers MODIFY customer_id VARCHAR(50);
ALTER TABLE order_items MODIFY order_id VARCHAR(50);
ALTER TABLE order_items MODIFY product_id VARCHAR(50);
ALTER TABLE order_items MODIFY seller_id VARCHAR(50);
ALTER TABLE order_payments MODIFY order_id VARCHAR(50);
ALTER TABLE order_reviews MODIFY order_id VARCHAR(50);
ALTER TABLE products MODIFY product_id VARCHAR(50);
ALTER TABLE sellers MODIFY seller_id VARCHAR(50);
ALTER TABLE orders MODIFY order_id VARCHAR(50);

-- Now add Foreign Keys

ALTER TABLE orders
    ADD CONSTRAINT fk_orders_customers
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id);

ALTER TABLE order_items
    ADD CONSTRAINT fk_items_orders
    FOREIGN KEY (order_id) REFERENCES orders(order_id);

ALTER TABLE order_items
    ADD CONSTRAINT fk_items_products
    FOREIGN KEY (product_id) REFERENCES products(product_id);

ALTER TABLE order_items
    ADD CONSTRAINT fk_items_sellers
    FOREIGN KEY (seller_id) REFERENCES sellers(seller_id);

ALTER TABLE order_payments
    ADD CONSTRAINT fk_payments_orders
    FOREIGN KEY (order_id) REFERENCES orders(order_id);

ALTER TABLE order_reviews
    ADD CONSTRAINT fk_reviews_orders
    FOREIGN KEY (order_id) REFERENCES orders(order_id);
    
    
    
USE EC;

SELECT 
    TABLE_NAME,
    CONSTRAINT_NAME,
    CONSTRAINT_TYPE
FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = 'EC'
AND CONSTRAINT_TYPE = 'FOREIGN KEY';    