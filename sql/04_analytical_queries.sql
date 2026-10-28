USE enterprise_supply_chain;

-- =====================================================================================
-- QUERY 1: Top 3 Revenue-Generating Products per Category using DENSE_RANK()
-- Business Purpose: Identify category revenue drivers and assess product concentration.
-- =====================================================================================

WITH category_product_sales AS (
    SELECT 
        c.category_id,
        c.category_name,
        p.product_id,
        p.product_name,
        ROUND(SUM(oi.sales_amount), 2) AS total_revenue,
        SUM(oi.order_item_quantity) AS total_units_sold,
        DENSE_RANK() OVER (
            PARTITION BY c.category_id 
            ORDER BY SUM(oi.sales_amount) DESC
        ) AS category_revenue_rank
    FROM dim_categories c
    JOIN dim_products p ON c.category_id = p.category_id
    JOIN fact_order_items oi ON p.product_id = oi.product_id
    JOIN fact_orders o ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('CANCELED', 'SUSPECTED_FRAUD')
    GROUP BY c.category_id, c.category_name, p.product_id, p.product_name
)
SELECT 
    category_name,
    category_revenue_rank,
    product_name,
    total_revenue,
    total_units_sold
FROM category_product_sales
WHERE category_revenue_rank <= 3
ORDER BY category_name, category_revenue_rank;


-- =====================================================================================
-- QUERY 2: Month-over-Month (MoM) Revenue Growth & Trajectory using LAG()
-- Business Purpose: Detect financial acceleration, plateauing, or seasonal contraction.
-- =====================================================================================

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
    -- Determine trend trajectory
    CASE 
        WHEN LAG(monthly_revenue, 1) OVER (ORDER BY sales_month) IS NULL THEN 'Baseline'
        WHEN monthly_revenue >= LAG(monthly_revenue, 1) OVER (ORDER BY sales_month) THEN 'Expansion'
        ELSE 'Contraction'
    END AS sales_trajectory
FROM monthly_sales_summary
ORDER BY sales_month;


-- =====================================================================================
-- QUERY 3: 7-Day & 30-Day Moving Averages of Daily Unit Demand
-- Business Purpose: Smooth out weekly demand volatility to discern true inventory burn.
-- =====================================================================================

WITH daily_order_velocity AS (
    SELECT 
        DATE(o.order_date) AS order_day,
        SUM(oi.order_item_quantity) AS daily_units_shipped,
        ROUND(SUM(oi.sales_amount), 2) AS daily_gross_sales
    FROM fact_orders o
    JOIN fact_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('CANCELED', 'SUSPECTED_FRAUD')
    GROUP BY DATE(o.order_date)
)
SELECT 
    order_day,
    daily_units_shipped,
    daily_gross_sales,
    -- 7-Day Moving Average
    ROUND(
        AVG(daily_units_shipped) OVER (
            ORDER BY order_day 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS rolling_7d_avg_units,
    -- 30-Day Moving Average
    ROUND(
        AVG(daily_units_shipped) OVER (
            ORDER BY order_day 
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ), 2
    ) AS rolling_30d_avg_units
FROM daily_order_velocity
ORDER BY order_day DESC;


-- =====================================================================================
-- QUERY 4: Stock Depletion Velocity, Days of Inventory Remaining (DOIR), & Reorder Logic
-- Business Purpose: Dynamic stock replenishment triggers preventing stockouts & dead capital.
-- =====================================================================================

USE enterprise_supply_chain;

WITH max_date_cte AS (
    SELECT MAX(order_date) AS anchor_date FROM fact_orders
),
trailing_demand AS (
    -- Trailing 90-day demand window to capture full catalog sales velocity
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
    -- Dynamic Reorder Point: (Daily Demand * Lead Time) + Safety Stock
    ROUND((COALESCE(td.daily_burn_rate, 0) * p.lead_time_days) + inv.safety_stock, 0) AS dynamic_reorder_point,
    -- Calibrated Operational Status
    CASE 
        WHEN COALESCE(td.daily_burn_rate, 0) = 0 THEN 'DEAD STOCK'
        WHEN inv.stock_on_hand <= (COALESCE(td.daily_burn_rate, 0) * p.lead_time_days) + inv.safety_stock 
             OR (inv.stock_on_hand / NULLIF(td.daily_burn_rate, 0)) <= 15 THEN 'URGENT REORDER'
        WHEN inv.stock_on_hand <= p.reorder_threshold 
             OR (inv.stock_on_hand / NULLIF(td.daily_burn_rate, 0)) <= 30 THEN 'MONITOR BUFFER'
        ELSE 'OPTIMAL STOCK'
    END AS replenishment_status,
    -- Recommended replenishment quantity to maintain a 45-day operational runway
    CASE 
        WHEN inv.stock_on_hand <= (COALESCE(td.daily_burn_rate, 0) * p.lead_time_days) + inv.safety_stock 
             OR (inv.stock_on_hand / NULLIF(td.daily_burn_rate, 0)) <= 15
        THEN GREATEST(0, ROUND((td.daily_burn_rate * 45) - inv.stock_on_hand, 0))
        ELSE 0 
    END AS recommended_reorder_qty
FROM dim_products p
JOIN dim_categories c ON p.category_id = c.category_id
JOIN fact_inventory inv ON p.product_id = inv.product_id
LEFT JOIN trailing_demand td ON p.product_id = td.product_id
ORDER BY days_inventory_remaining ASC;