
USE retail;

-- ======================================================================
-- Sanity check: row counts and sales totals (run after loading tables)
-- ======================================================================
SELECT
  (SELECT COUNT(*) FROM customers)   AS customers_n,
  (SELECT COUNT(*) FROM products)    AS products_n,
  (SELECT COUNT(*) FROM orders)      AS orders_n,
  (SELECT COUNT(*) FROM order_items) AS order_items_n,
  (SELECT ROUND(SUM(sales), 2) FROM order_raw)  AS raw_sales,
  (SELECT ROUND(SUM(sales), 2) FROM order_items) AS items_sales;


-- ======================================================================
-- Q1. Where do we make money? Profit and margin by region and category
-- Note: margin = SUM(profit) / SUM(sales), NOT an average of row margins.
-- ======================================================================

-- Q1a: by region
SELECT o.region,
       ROUND(SUM(oi.sales), 2)  AS total_sales,
       ROUND(SUM(oi.profit), 2) AS total_profit,
       ROUND(SUM(oi.profit) / SUM(oi.sales) * 100, 2) AS margin_pct
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
GROUP BY o.region
ORDER BY total_profit DESC;

-- Q1b: by category and sub-category
SELECT p.category, p.sub_category,
       ROUND(SUM(oi.sales), 2)  AS total_sales,
       ROUND(SUM(oi.profit), 2) AS total_profit,
       ROUND(SUM(oi.profit) / SUM(oi.sales) * 100, 2) AS margin_pct
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category, p.sub_category
ORDER BY total_profit DESC;


-- ======================================================================
-- Q2. How are sales trending? Month-over-month growth (CTE + LAG)
-- ======================================================================
WITH monthly AS (
  SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS ym,
         SUM(oi.sales) AS sales
  FROM order_items oi
  JOIN orders o ON oi.order_id = o.order_id
  GROUP BY ym
)
SELECT ym,
       ROUND(sales, 2) AS sales,
       ROUND((sales - LAG(sales) OVER (ORDER BY ym))
             / LAG(sales) OVER (ORDER BY ym) * 100, 1) AS mom_growth_pct
FROM monthly
ORDER BY ym;


-- ======================================================================
-- Q3. What loses money? Sub-categories with negative total profit (HAVING)
-- ======================================================================
SELECT p.category, p.sub_category,
       ROUND(SUM(oi.sales), 2)  AS total_sales,
       ROUND(SUM(oi.profit), 2) AS total_profit
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category, p.sub_category
HAVING SUM(oi.profit) < 0
ORDER BY total_profit;


-- ======================================================================
-- Q4. How does discounting affect profit? (CASE bands)
-- ======================================================================
SELECT CASE WHEN discount = 0     THEN '0%'
            WHEN discount <= 0.10 THEN '1-10%'
            WHEN discount <= 0.20 THEN '11-20%'
            WHEN discount <= 0.30 THEN '21-30%'
            ELSE '30%+' END AS discount_band,
       COUNT(*) AS line_items,
       ROUND(SUM(sales), 2)  AS total_sales,
       ROUND(SUM(profit), 2) AS total_profit,
       ROUND(SUM(profit) / SUM(sales) * 100, 2) AS margin_pct
FROM order_items
GROUP BY discount_band
ORDER BY MIN(discount);

-- Q4b: are the loss-making sub-categories the heavily discounted ones?
SELECT p.sub_category,
       ROUND(AVG(oi.discount) * 100, 1) AS avg_discount_pct,
       ROUND(SUM(oi.sales), 2)  AS total_sales,
       ROUND(SUM(oi.profit), 2) AS total_profit,
       ROUND(SUM(oi.profit) / SUM(oi.sales) * 100, 2) AS margin_pct
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.sub_category
ORDER BY avg_discount_pct DESC;


-- ======================================================================
-- Q5. Who are the best customers? (RANK + multi-table join)
-- ======================================================================

-- Q5a: top 10 customers by sales
SELECT c.customer_id, c.customer_name, c.segment,
       COUNT(DISTINCT o.order_id) AS orders_n,
       ROUND(SUM(oi.sales), 2)  AS total_sales,
       ROUND(SUM(oi.profit), 2) AS total_profit,
       RANK() OVER (ORDER BY SUM(oi.sales) DESC) AS sales_rank
FROM customers c
JOIN orders o       ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.customer_name, c.segment
ORDER BY sales_rank
LIMIT 10;

-- Q5b: repeat customers (more than one order over the whole period)
WITH cust AS (
  SELECT customer_id, COUNT(DISTINCT order_id) AS orders_n
  FROM orders
  GROUP BY customer_id
)
SELECT SUM(orders_n > 1) AS repeat_customers,
       COUNT(*) AS total_customers,
       ROUND(SUM(orders_n > 1) / COUNT(*) * 100, 1) AS repeat_pct
FROM cust;


-- ======================================================================
-- Q6. Which segment is weakest in which month?
-- ======================================================================

-- Q6a: sales, orders and profit by segment and month
SELECT c.segment,
       MONTH(o.order_date)     AS month_num,
       MONTHNAME(o.order_date) AS month_name,
       COUNT(DISTINCT o.order_id) AS orders_n,
       ROUND(SUM(oi.sales), 2)    AS total_sales,
       ROUND(SUM(oi.profit), 2)   AS total_profit
FROM order_items oi
JOIN orders o    ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.segment, MONTH(o.order_date), MONTHNAME(o.order_date)
ORDER BY c.segment, month_num;

-- Q6b: each segment's three weakest months (ROW_NUMBER + PARTITION BY)
WITH seg_month AS (
  SELECT c.segment,
         MONTH(o.order_date)     AS month_num,
         MONTHNAME(o.order_date) AS month_name,
         SUM(oi.sales)           AS total_sales
  FROM order_items oi
  JOIN orders o    ON oi.order_id = o.order_id
  JOIN customers c ON o.customer_id = c.customer_id
  GROUP BY c.segment, MONTH(o.order_date), MONTHNAME(o.order_date)
),
ranked AS (
  SELECT segment, month_name, total_sales,
         ROW_NUMBER() OVER (PARTITION BY segment ORDER BY total_sales) AS rn
  FROM seg_month
)
SELECT segment, month_name, ROUND(total_sales, 2) AS total_sales
FROM ranked
WHERE rn <= 3
ORDER BY segment, rn;
