-- =====================================================================
-- 03_consultas.sql — Consultas para revisar el modelo y calcular KPIs
-- =====================================================================
-- Cada SELECT de este archivo se muestra en la terminal al ejecutar
-- run_sql.py. Usalo para:
--   * comprobar que las tablas se cargaron bien (cantidad de filas, nulos...)
--   * escribir las consultas clave de los KPIs que pide la consigna
--     (ventas, usuarios activos, ticket promedio, NPS, ventas por provincia,
--     ranking mensual por producto) usando las tablas del modelo estrella.
-- =====================================================================


-- Ejemplo: revisar la dimensión producto
SELECT product_key, name, category, family, list_price
FROM dim_product
ORDER BY product_key;


-- TU TURNO: agregá acá tus consultas.




-- Control: filas por tabla de hechos
SELECT 'fact_order' AS tabla, COUNT(*) AS filas FROM fact_order
UNION ALL SELECT 'fact_payment',  COUNT(*) FROM fact_payment
UNION ALL SELECT 'fact_shipment', COUNT(*) FROM fact_shipment;

-- KPI 1: Total Ventas ($M) por mes y canal
SELECT
    DATE_TRUNC('month', try_strptime(CAST(f.date_key AS VARCHAR), '%Y%m%d')) AS mes,
    c.code                              AS canal,
    ROUND(SUM(f.total_amount) / 1e6, 2) AS ventas_millones
FROM fact_order AS f
JOIN dim_channel AS c ON c.channel_key = f.channel_key
WHERE f.is_sale
GROUP BY mes, canal
ORDER BY mes, canal;

-- KPI 2: Ticket Promedio ($K) por mes
SELECT
    DATE_TRUNC('month', try_strptime(CAST(f.date_key AS VARCHAR), '%Y%m%d')) AS mes,
    ROUND(SUM(f.total_amount) / COUNT(*) / 1e3, 1) AS ticket_promedio_miles
FROM fact_order AS f
WHERE f.is_sale
GROUP BY mes
ORDER BY mes;

-- KPI 3: Ventas por Provincia
SELECT
    p.name                              AS provincia,
    ROUND(SUM(f.total_amount) / 1e6, 2) AS ventas_millones
FROM fact_order AS f
JOIN dim_province AS p ON p.province_key = f.province_key
WHERE f.is_sale
GROUP BY provincia
ORDER BY ventas_millones DESC;

-- KPI 4: Usuarios Activos (nK) por mes
SELECT
    DATE_TRUNC('month', try_strptime(CAST(w.date_key AS VARCHAR), '%Y%m%d')) AS mes,
    COUNT(DISTINCT w.customer_key) FILTER (WHERE w.customer_key <> -1) AS usuarios_activos
FROM fact_web_session AS w
GROUP BY mes
ORDER BY mes;

-- KPI 5: NPS por mes y canal = % promotores (9-10) - % detractores (0-6)
SELECT
    DATE_TRUNC('month', try_strptime(CAST(n.date_key AS VARCHAR), '%Y%m%d')) AS mes,
    c.code AS canal,
    ROUND(100.0 * (COUNT(*) FILTER (WHERE n.score >= 9)
                 - COUNT(*) FILTER (WHERE n.score <= 6)) / COUNT(*), 1) AS nps
FROM fact_nps AS n
JOIN dim_channel AS c ON c.channel_key = n.channel_key
GROUP BY mes, canal
ORDER BY mes, canal;

-- KPI 6: Ranking mensual por producto (solo pedidos PAID o FULFILLED)
SELECT
    DATE_TRUNC('month', try_strptime(CAST(o.date_key AS VARCHAR), '%Y%m%d')) AS mes,
    p.name            AS producto,
    SUM(s.line_total) AS ventas,
    RANK() OVER (PARTITION BY DATE_TRUNC('month', try_strptime(CAST(o.date_key AS VARCHAR), '%Y%m%d'))
                 ORDER BY SUM(s.line_total) DESC) AS puesto
FROM fact_sales AS s
JOIN fact_order  AS o ON o.order_id    = s.order_id
JOIN dim_product AS p ON p.product_key = s.product_key
WHERE o.is_sale
GROUP BY mes, producto
ORDER BY mes, puesto;

-- Extra (meta del trimestre): días promedio de entrega por provincia
SELECT
    p.name                           AS provincia,
    ROUND(AVG(s.days_to_deliver), 1) AS dias_promedio_entrega,
    COUNT(*)                         AS envios_entregados
FROM fact_shipment AS s
JOIN dim_province AS p ON p.province_key = s.province_key
WHERE s.status = 'DELIVERED'
GROUP BY provincia
ORDER BY dias_promedio_entrega DESC;