-- Make sure MySQL is configured to permit file imports by running
SHOW VARIABLES LIKE 'local_infile';
SET GLOBAL local_infile = 1;

-- 1. Create and select the database
CREATE DATABASE IF NOT EXISTS enterprise_supply_chain;
USE enterprise_supply_chain;

-- 2. Drop staging table if it already exists
DROP TABLE IF EXISTS raw_dataco_staging;

-- 3. Staging table matching the 53 columns of the Kaggle CSV
CREATE TABLE raw_dataco_staging(
	type VARCHAR(50),
    days_for_shipping_real INT,
    days_for_shipment_scheduled INT,
    benefit_per_order DECIMAL(10,2),
    sales_per_customer DECIMAL(10,2),
    delivery_status VARCHAR(50),
    late_delivery_risk INT,
    category_id INT,
    category_name VARCHAR(100),
    customer_city VARCHAR(100),
    customer_country VARCHAR(100),
    customer_email VARCHAR(100),
    customer_fname VARCHAR(100),
    customer_id INT,
    customer_lname VARCHAR(100),
    customer_password VARCHAR(100),
    customer_segment VARCHAR(50),
    customer_state VARCHAR(50),
    customer_street VARCHAR(150),
    customer_zipcode VARCHAR(20),
    department_id INT,
    department_name VARCHAR(100),
    latitude DECIMAL(10,6),
    longitude DECIMAL(10,6),
    market VARCHAR(50),
    order_city VARCHAR(100),
    order_country VARCHAR(100),
    order_customer_id INT,
    order_date_raw VARCHAR(50),
    order_id INT,
    order_item_cardprod_id INT,
    order_item_discount DECIMAL(10,2),
    order_item_discount_rate DECIMAL(5,2),
    order_item_id INT,
    order_item_product_price DECIMAL(10,2),
    order_item_profit_ratio DECIMAL(5,2),
    order_item_quantity INT,
    sales DECIMAL(10,2),
    order_item_total DECIMAL(10,2),
    order_profit_per_order DECIMAL(10,2),
    order_region VARCHAR(100),
    order_state VARCHAR(100),
    order_status VARCHAR(50),
    order_zipcode VARCHAR(20),
    product_card_id INT,
    product_category_id INT,
    product_description TEXT,
    product_image TEXT,
    product_name VARCHAR(255),
    product_price DECIMAL(10,2),
    product_status INT,
    shipping_date_raw VARCHAR(50),
    shipping_mode VARCHAR(50)
);

-- 4. Load The CSV File to my database
LOAD DATA LOCAL INFILE "D:/Enterprise-Slaes_Inventory-SQL-Analytics/data/raw/DataCoSupplyChainDataset.csv"
INTO TABLE raw_dataco_staging
CHARACTER SET latin1
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Check total row count (should be approximately 180,519 rows)
SELECT COUNT(*) AS total_rows_loaded FROM raw_dataco_staging;

-- Preview the top rows
SELECT 
    order_id, 
    customer_id, 
    product_name, 
    order_item_quantity, 
    sales, 
    order_status, 
    order_date_raw 
FROM raw_dataco_staging 
LIMIT 5;


















