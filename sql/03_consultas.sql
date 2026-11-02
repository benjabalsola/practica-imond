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



-- Venta = pedido con estado PAID o FULFILLED (dim_order_status.es_venta).
-- El mes sale de dim_date (fecha).

-- Control: filas por tabla de hechos
SELECT 'fact_order' AS tabla, COUNT(*) AS filas FROM fact_order
UNION ALL SELECT 'fact_sales',       COUNT(*) FROM fact_sales
UNION ALL SELECT 'fact_payment',     COUNT(*) FROM fact_payment
UNION ALL SELECT 'fact_shipment',    COUNT(*) FROM fact_shipment
UNION ALL SELECT 'fact_web_session', COUNT(*) FROM fact_web_session
UNION ALL SELECT 'fact_nps',         COUNT(*) FROM fact_nps;

-- KPI 1: Total Ventas ($M) por mes y canal
SELECT
    strftime(d.fecha, '%Y-%m')          AS anio_mes,
    c.code                              AS canal,
    ROUND(SUM(f.total_amount) / 1e6, 2) AS ventas_millones
FROM fact_order AS f
JOIN dim_date         AS d  ON d.date_key          = f.date_key
JOIN dim_channel      AS c  ON c.channel_key       = f.channel_key
JOIN dim_order_status AS os ON os.order_status_key = f.order_status_key
WHERE os.es_venta
GROUP BY anio_mes, canal
ORDER BY anio_mes, canal;

-- KPI 2: Ticket Promedio ($K) por mes = SUM(total_amount) / COUNT(*)
SELECT
    strftime(d.fecha, '%Y-%m') AS anio_mes,
    ROUND(SUM(f.total_amount) / COUNT(*) / 1e3, 1) AS ticket_promedio_miles
FROM fact_order AS f
JOIN dim_date         AS d  ON d.date_key          = f.date_key
JOIN dim_order_status AS os ON os.order_status_key = f.order_status_key
WHERE os.es_venta
GROUP BY anio_mes
ORDER BY anio_mes;

-- KPI 3: Ventas por Provincia (provincia de la dirección de envío)
SELECT
    p.name                              AS provincia,
    ROUND(SUM(f.total_amount) / 1e6, 2) AS ventas_millones
FROM fact_order AS f
JOIN dim_province     AS p  ON p.province_key      = f.province_key
JOIN dim_order_status AS os ON os.order_status_key = f.order_status_key
WHERE os.es_venta
GROUP BY provincia
ORDER BY ventas_millones DESC;

-- KPI 4: Usuarios Activos por mes
-- Clientes identificados: COUNT(DISTINCT customer). Visitas anónimas: COUNT(DISTINCT session_id).
SELECT
    strftime(d.fecha, '%Y-%m') AS anio_mes,
    COUNT(DISTINCT w.customer_key) FILTER (WHERE w.customer_key <> -1) AS clientes_identificados,
    COUNT(DISTINCT w.session_id)   FILTER (WHERE w.customer_key =  -1) AS sesiones_anonimas,
    clientes_identificados + sesiones_anonimas                         AS usuarios_activos
FROM fact_web_session AS w
JOIN dim_date AS d ON d.date_key = w.date_key
GROUP BY anio_mes
ORDER BY anio_mes;

-- KPI 5: NPS por mes y canal = (% promotores 9-10 − % detractores 0-6) × 100
SELECT
    strftime(d.fecha, '%Y-%m') AS anio_mes,
    c.code AS canal,
    ROUND(100.0 * (COUNT(*) FILTER (WHERE s.grupo = 'Promotor')
                 - COUNT(*) FILTER (WHERE s.grupo = 'Detractor')) / COUNT(*), 1) AS nps
FROM fact_nps AS n
JOIN dim_date      AS d ON d.date_key    = n.date_key
JOIN dim_channel   AS c ON c.channel_key = n.channel_key
JOIN dim_nps_score AS s ON s.score_key   = n.score_key
GROUP BY anio_mes, canal
ORDER BY anio_mes, canal;

-- KPI 6: Ranking mensual por producto (top N, acá N = 5) según line_total
SELECT *
FROM (
    SELECT
        strftime(d.fecha, '%Y-%m') AS anio_mes,
        p.name                     AS producto,
        SUM(s.line_total)          AS ventas,
        RANK() OVER (PARTITION BY strftime(d.fecha, '%Y-%m') ORDER BY SUM(s.line_total) DESC) AS puesto
    FROM fact_sales AS s
    JOIN dim_date         AS d  ON d.date_key          = s.date_key
    JOIN dim_product      AS p  ON p.product_key       = s.product_key
    JOIN dim_order_status AS os ON os.order_status_key = s.order_status_key
    WHERE os.es_venta
    GROUP BY anio_mes, producto
)
WHERE puesto <= 5
ORDER BY anio_mes, puesto;

-- Extra (meta del trimestre): días promedio de entrega por provincia
SELECT
    p.name                           AS provincia,
    ROUND(AVG(s.days_to_deliver), 1) AS dias_promedio_entrega,
    COUNT(*)                         AS envios_entregados
FROM fact_shipment AS s
JOIN dim_province        AS p  ON p.province_key        = s.province_key
JOIN dim_shipment_status AS ss ON ss.shipment_status_key = s.shipment_status_key
WHERE ss.code = 'DELIVERED'
GROUP BY provincia
ORDER BY dias_promedio_entrega DESC;
