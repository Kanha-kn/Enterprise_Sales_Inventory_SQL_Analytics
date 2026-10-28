USE enterprise_supply_chain;

-- 1. Drop existing views cleanly
DROP VIEW IF EXISTS view_inventory_telemetry;
DROP VIEW IF EXISTS view_monthly_sales_trajectory;

-- 2. Create view_inventory_telemetry
CREATE VIEW view_inventory_telemetry AS
WITH max_date_cte AS (
    SELECT MAX(order_date) AS anchor_date FROM fact_orders
),
trailing_demand AS (
    SELECT 
        oi.product_id,
        SUM(oi.order_item_quantity) AS trailing_units,
        ROUND(SUM(oi.order_item_quantity) / 90.0, 2) AS daily_burn_rate
    FROM fact_order_items oi
    JOIN fact_orders o ON oi.order_id = o.order_id
    CROSS JOIN max_date_cte md
    WHERE o.order_date >= md.anchor_date - INTERVAL 90 DAY
      AND o.order_status NOT IN ('CANCELED', 'SUSPECTED_FRAUD')
    GROUP BY oi.product_id
)
SELECT 
    p.product_id,
    p.product_name,
    c.category_name,
    inv.stock_on_hand,
    inv.safety_stock,
    COALESCE(td.daily_burn_rate, 0) AS daily_burn_rate,
    -- Days of Inventory Remaining (DOIR)
    CASE 
        WHEN COALESCE(td.daily_burn_rate, 0) = 0 THEN 999.0 
        ELSE ROUND(inv.stock_on_hand / td.daily_burn_rate, 1)
    END AS days_inventory_remaining,
    -- Dynamic Reorder Point: (Daily Burn * Lead Time) + Safety Stock
    ROUND((COALESCE(td.daily_burn_rate, 0) * p.lead_time_days) + inv.safety_stock, 0) AS dynamic_reorder_point,
    -- Operational Status:
    -- <= 25 days runway triggers URGENT REORDER
    -- 25 to 40 days runway triggers MONITOR BUFFER
    -- > 40 days runway triggers OPTIMAL STOCK
    CASE 
        WHEN COALESCE(td.daily_burn_rate, 0) = 0 THEN 'DEAD STOCK'
        WHEN (inv.stock_on_hand / NULLIF(td.daily_burn_rate, 0)) <= 25.0 THEN 'URGENT REORDER'
        WHEN (inv.stock_on_hand / NULLIF(td.daily_burn_rate, 0)) <= 40.0 THEN 'MONITOR BUFFER'
        ELSE 'OPTIMAL STOCK'
    END AS replenishment_status,
    -- Recommended Restock Quantity to maintain a 45-day operational runway
    CASE 
        WHEN (inv.stock_on_hand / NULLIF(td.daily_burn_rate, 0)) <= 40.0
        THEN GREATEST(0, ROUND((td.daily_burn_rate * 45) - inv.stock_on_hand, 0))
        ELSE 0 
    END AS recommended_reorder_qty
FROM dim_products p
JOIN dim_categories c ON p.category_id = c.category_id
JOIN fact_inventory inv ON p.product_id = inv.product_id
LEFT JOIN trailing_demand td ON p.product_id = td.product_id;

-- 3. Create view_monthly_sales_trajectory
CREATE VIEW view_monthly_sales_trajectory AS
WITH monthly_sales_summary AS (
    SELECT 
        DATE_FORMAT(o.order_date, '%Y-%m-01') AS sales_month,
        ROUND(SUM(oi.sales_amount), 2) AS monthly_revenue,
        COUNT(DISTINCT o.order_id) AS total_monthly_orders
    FROM fact_orders o
    JOIN fact_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('CANCELED', 'SUSPECTED_FRAUD')
    GROUP BY DATE_FORMAT(o.order_date, '%Y-%m-01')
)
SELECT 
    sales_month,
    monthly_revenue,
    total_monthly_orders,
    LAG(monthly_revenue, 1) OVER (ORDER BY sales_month) AS prior_month_revenue,
    ROUND(
        (monthly_revenue - LAG(monthly_revenue, 1) OVER (ORDER BY sales_month)) 
        / LAG(monthly_revenue, 1) OVER (ORDER BY sales_month) * 100, 
        2
    ) AS mom_growth_pct,
    CASE 
        WHEN LAG(monthly_revenue, 1) OVER (ORDER BY sales_month) IS NULL THEN 'Baseline'
        WHEN monthly_revenue >= LAG(monthly_revenue, 1) OVER (ORDER BY sales_month) THEN 'Expansion'
        ELSE 'Contraction'
    END AS sales_trajectory
FROM monthly_sales_summary;


SELECT * FROM view_inventory_telemetry;