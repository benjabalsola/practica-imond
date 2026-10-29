-- 04_tablero.sql: tablas planas para el tablero (una por tema).
-- Filtros comunes en todas: fecha, canal, provincia, producto.

-- Ventas: una fila por producto de cada pedido PAID o FULFILLED.
-- importe_total reparte el total del pedido entre sus productos.
CREATE TABLE tablero_ventas AS
SELECT
    CAST(try_strptime(CAST(o.date_key AS VARCHAR), '%Y%m%d') AS DATE) AS fecha,
    c.code AS canal,
    pr.name AS provincia,
    p.name AS producto,
    o.order_id AS pedido,
    s.line_total AS importe_productos,
    ROUND(o.total_amount * s.line_total / NULLIF(o.subtotal, 0), 2) AS importe_total
FROM fact_sales AS s
JOIN fact_order   AS o  ON o.order_id      = s.order_id
JOIN dim_product  AS p  ON p.product_key   = s.product_key
JOIN dim_channel  AS c  ON c.channel_key   = o.channel_key
JOIN dim_province AS pr ON pr.province_key = o.province_key
WHERE o.is_sale;

-- Usuarios activos: una fila por sesión web
CREATE TABLE tablero_usuarios AS
SELECT
    CAST(try_strptime(CAST(w.date_key AS VARCHAR), '%Y%m%d') AS DATE) AS fecha,
    'ONLINE' AS canal,
    CASE WHEN w.customer_key <> -1 THEN w.customer_key END AS cliente
FROM fact_web_session AS w;

-- NPS: una fila por respuesta
CREATE TABLE tablero_nps AS
SELECT
    CAST(try_strptime(CAST(n.date_key AS VARCHAR), '%Y%m%d') AS DATE) AS fecha,
    c.code AS canal,
    n.score AS puntaje,
    CASE WHEN n.score >= 9 THEN 1 ELSE 0 END AS promotor,
    CASE WHEN n.score <= 6 THEN 1 ELSE 0 END AS detractor
FROM fact_nps AS n
JOIN dim_channel AS c ON c.channel_key = n.channel_key;

-- Envíos entregados: para la meta de entregas en Mendoza
CREATE TABLE tablero_envios AS
SELECT
    CAST(try_strptime(CAST(s.order_date_key AS VARCHAR), '%Y%m%d') AS DATE) AS fecha,
    c.code AS canal,
    pr.name AS provincia,
    s.days_to_deliver AS dias_entrega
FROM fact_shipment AS s
JOIN dim_channel  AS c  ON c.channel_key   = s.channel_key
JOIN dim_province AS pr ON pr.province_key = s.province_key
WHERE s.status = 'DELIVERED';

-- Control: tiene que dar igual en las dos columnas
SELECT
    (SELECT ROUND(SUM(importe_total) / 1e6, 2) FROM tablero_ventas) AS ventas_tablero_M,
    (SELECT ROUND(SUM(total_amount) / 1e6, 2) FROM fact_order WHERE is_sale) AS ventas_fact_order_M;
