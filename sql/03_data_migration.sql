USE enterprise_supply_chain;

-- 1. Populate dim_customers (deduplicating customer records)
INSERT IGNORE INTO dim_customers (customer_id, first_name, last_name, customer_segment, city, state, country, zipcode)
SELECT 
    customer_id,
    MAX(customer_fname),
    MAX(customer_lname),
    MAX(customer_segment),
    MAX(customer_city),
    MAX(customer_state),
    MAX(customer_country),
    MAX(customer_zipcode)
FROM raw_dataco_staging
WHERE customer_id IS NOT NULL
GROUP BY customer_id;

-- 2. Populate dim_categories
INSERT IGNORE INTO dim_categories (category_id, category_name)
SELECT DISTINCT 
    category_id, 
    category_name
FROM raw_dataco_staging
WHERE category_id IS NOT NULL;

-- 3. Populate dim_products
INSERT IGNORE INTO dim_products (product_id, category_id, product_name, product_price)
SELECT 
    product_card_id,
    category_id,
    MAX(product_name),
    MAX(product_price)
FROM raw_dataco_staging
WHERE product_card_id IS NOT NULL
GROUP BY product_card_id, category_id;

-- 4. Populate fact_orders (handling date parsing formats)
INSERT IGNORE INTO fact_orders (
    order_id, 
    customer_id, 
    order_date, 
    shipping_date, 
    shipping_mode, 
    order_status, 
    delivery_status, 
    late_delivery_risk
)
SELECT 
    order_id,
    customer_id,
    STR_TO_DATE(order_date_raw, '%c/%e/%Y %k:%i'),
    STR_TO_DATE(shipping_date_raw, '%c/%e/%Y %k:%i'),
    shipping_mode,
    order_status,
    delivery_status,
    late_delivery_risk
FROM raw_dataco_staging
WHERE order_id IS NOT NULL
GROUP BY order_id, customer_id, order_date_raw, shipping_date_raw, shipping_mode, order_status, delivery_status, late_delivery_risk;

-- 5. Populate fact_order_items
INSERT IGNORE INTO fact_order_items (
    order_item_id, 
    order_id, 
    product_id, 
    order_item_quantity, 
    product_price, 
    sales_amount, 
    discount_amount, 
    profit_per_order
)
SELECT 
    order_item_id,
    order_id,
    product_card_id,
    order_item_quantity,
    order_item_product_price,
    sales,
    order_item_discount,
    order_profit_per_order
FROM raw_dataco_staging
WHERE order_item_id IS NOT NULL;

-- 6. Initialize fact_inventory with baseline stock data
-- Deterministic seed formula based on product ID to simulate realistic warehouse stock distribution
INSERT INTO fact_inventory (product_id, stock_on_hand, safety_stock)
SELECT 
    product_id,
    50 + MOD(product_id * 17, 450) AS stock_on_hand,
    30 AS safety_stock
FROM dim_products;

-- ensure all normalized tables are correctly populated
SELECT 'dim_customers' AS table_name, COUNT(*) AS total_records FROM dim_customers
UNION ALL
SELECT 'dim_categories', COUNT(*) FROM dim_categories
UNION ALL
SELECT 'dim_products', COUNT(*) FROM dim_products
UNION ALL
SELECT 'fact_orders', COUNT(*) FROM fact_orders
UNION ALL
SELECT 'fact_order_items', COUNT(*) FROM fact_order_items
UNION ALL
SELECT 'fact_inventory', COUNT(*) FROM fact_inventory;