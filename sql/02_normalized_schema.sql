USE enterprise_supply_chain;

-- Drop dependent tables first to avoid foreign key conflicts
DROP TABLE IF EXISTS fact_inventory;
DROP TABLE IF EXISTS fact_order_items;
DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS dim_products;
DROP TABLE IF EXISTS dim_categories;
DROP TABLE IF EXISTS dim_customers;

-- 1. Dimension: Customers
CREATE TABLE dim_customers (
    customer_id INT PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    customer_segment VARCHAR(50),
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(100),
    zipcode VARCHAR(20)
);

-- 2. Dimension: Categories
CREATE TABLE dim_categories (
    category_id INT PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL
);

-- 3. Dimension: Products
CREATE TABLE dim_products (
    product_id INT PRIMARY KEY,
    category_id INT NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    product_price DECIMAL(10,2) NOT NULL,
    reorder_threshold INT DEFAULT 50,
    lead_time_days INT DEFAULT 7,
    FOREIGN KEY (category_id) REFERENCES dim_categories(category_id)
);

-- 4. Fact: Orders (Header Level)
CREATE TABLE fact_orders (
    order_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    order_date DATETIME NOT NULL,
    shipping_date DATETIME,
    shipping_mode VARCHAR(50),
    order_status VARCHAR(50),
    delivery_status VARCHAR(50),
    late_delivery_risk INT,
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id)
);

-- 5. Fact: Order Items (Line Item Level)
CREATE TABLE fact_order_items (
    order_item_id INT PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    order_item_quantity INT NOT NULL,
    product_price DECIMAL(10,2) NOT NULL,
    sales_amount DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) NOT NULL,
    profit_per_order DECIMAL(10,2),
    FOREIGN KEY (order_id) REFERENCES fact_orders(order_id),
    FOREIGN KEY (product_id) REFERENCES dim_products(product_id),
    CONSTRAINT chk_quantity CHECK (order_item_quantity > 0)
);

-- 6. Fact: Inventory Snapshot (Warehouse Tracking)
CREATE TABLE fact_inventory (
    product_id INT PRIMARY KEY,
    stock_on_hand INT NOT NULL,
    safety_stock INT DEFAULT 30,
    FOREIGN KEY (product_id) REFERENCES dim_products(product_id)
);