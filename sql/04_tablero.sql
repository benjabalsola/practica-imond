-- =====================================================================
-- 04_tablero.sql — Marts del tablero (una tabla por visual o grupo de visuales)
-- =====================================================================
-- Cada mart es un hecho ya unido con sus dimensiones y AGREGADO por mes.
-- Todo el cálculo (JOIN, conteos distintos, reparto, ranking) se hace acá.
-- El tablero (docs/index.html) solo elige filas según los filtros, suma meses
-- y hace la división final de los cocientes (ticket, NPS, días promedio).
--
-- Para no sumar conteos distintos entre canales, provincias o productos,
-- cada mart trae también las filas "Todos" (GROUP BY CUBE / GROUPING SETS).
-- El tablero toma siempre la fila exacta del filtro elegido (ej. canal = 'Todos').
-- Sumar meses sí está permitido: un pedido, una respuesta o un envío pertenece a un solo mes.
-- =====================================================================


-- ---------------------------------------------------------------------
-- tablero_ventas: Total Ventas, Ticket Promedio, Ventas por mes,
-- Ventas por provincia y Ranking mensual por producto.
-- GRANO: mes × canal × provincia × producto (cada uno puede ser 'Todos').
--   ventas            = SUM(total_amount) de pedidos PAID o FULFILLED. Con un producto elegido,
--                       el total del pedido se reparte entre sus productos según line_total / subtotal.
--   pedidos           = pedidos distintos (con un producto elegido: pedidos que lo incluyen).
--   ventas_productos  = SUM(line_total), sin IVA ni envío (base del ranking).
--   puesto            = RANK() del producto dentro del mes, canal y provincia (vacío si producto = 'Todos').
-- ---------------------------------------------------------------------
CREATE TABLE tablero_ventas AS
WITH lineas AS (
    SELECT
        strftime(d.fecha, '%Y-%m') AS mes,
        c.code                     AS canal,
        pr.name                    AS provincia,
        p.name                     AS producto,
        s.order_id,
        s.line_total,
        o.total_amount * s.line_total / NULLIF(o.subtotal, 0) AS importe_total
    FROM fact_sales AS s
    JOIN fact_order       AS o  ON o.order_id          = s.order_id
    JOIN dim_date         AS d  ON d.date_key          = o.date_key
    JOIN dim_product      AS p  ON p.product_key       = s.product_key
    JOIN dim_channel      AS c  ON c.channel_key       = o.channel_key
    JOIN dim_province     AS pr ON pr.province_key     = o.province_key
    JOIN dim_order_status AS os ON os.order_status_key = o.order_status_key
    WHERE os.es_venta
),
agregado AS (
    SELECT
        mes,
        COALESCE(canal, 'Todos')     AS canal,
        COALESCE(provincia, 'Todos') AS provincia,
        COALESCE(producto, 'Todos')  AS producto,
        CAST(ROUND(SUM(importe_total), 2) AS DECIMAL(14, 2)) AS ventas,
        COUNT(DISTINCT order_id)     AS pedidos,
        SUM(line_total)              AS ventas_productos
    FROM lineas
    GROUP BY mes, CUBE (canal, provincia, producto)
)
SELECT
    *,
    CASE WHEN producto <> 'Todos' THEN
        RANK() OVER (PARTITION BY mes, canal, provincia, producto = 'Todos' ORDER BY ventas_productos DESC)
    END AS puesto
FROM agregado
ORDER BY mes, canal, provincia, producto;


-- ---------------------------------------------------------------------
-- tablero_usuarios: Usuarios Activos.
-- GRANO: un período (mes desde × mes hasta), con todos los períodos posibles.
-- Se calcula cada período completo porque los usuarios distintos no se pueden sumar entre meses.
--   usuarios_activos = clientes distintos con sesión + sesiones anónimas distintas (session_id).
-- Las sesiones web son del canal ONLINE; este KPI no tiene provincia ni producto.
-- ---------------------------------------------------------------------
CREATE TABLE tablero_usuarios AS
WITH meses AS (
    SELECT DISTINCT strftime(fecha, '%Y-%m') AS mes FROM dim_date WHERE date_key <> -1
),
periodos AS (
    SELECT a.mes AS desde, b.mes AS hasta
    FROM meses AS a JOIN meses AS b ON a.mes <= b.mes
),
sesiones AS (
    SELECT strftime(d.fecha, '%Y-%m') AS mes, w.customer_key, w.session_id
    FROM fact_web_session AS w
    JOIN dim_date AS d ON d.date_key = w.date_key
)
SELECT
    p.desde,
    p.hasta,
    COUNT(DISTINCT s.customer_key) FILTER (WHERE s.customer_key <> -1) AS clientes_identificados,
    COUNT(DISTINCT s.session_id)   FILTER (WHERE s.customer_key =  -1) AS sesiones_anonimas,
    clientes_identificados + sesiones_anonimas                         AS usuarios_activos
FROM periodos AS p
JOIN sesiones AS s ON s.mes BETWEEN p.desde AND p.hasta
GROUP BY p.desde, p.hasta
ORDER BY p.desde, p.hasta;


-- ---------------------------------------------------------------------
-- tablero_nps: NPS por período y canal.
-- GRANO: mes × canal (canal puede ser 'Todos'). Medidas sumables:
-- NPS = (promotores − detractores) / respuestas × 100, calculado después de sumar.
-- No tiene provincia ni producto (la encuesta no los registra).
-- ---------------------------------------------------------------------
CREATE TABLE tablero_nps AS
SELECT
    strftime(d.fecha, '%Y-%m')                    AS mes,
    COALESCE(c.code, 'Todos')                     AS canal,
    COUNT(*)                                      AS respuestas,
    COUNT(*) FILTER (WHERE s.grupo = 'Promotor')  AS promotores,
    COUNT(*) FILTER (WHERE s.grupo = 'Detractor') AS detractores
FROM fact_nps AS n
JOIN dim_date      AS d ON d.date_key    = n.date_key
JOIN dim_channel   AS c ON c.channel_key = n.channel_key
JOIN dim_nps_score AS s ON s.score_key   = n.score_key
GROUP BY GROUPING SETS ((strftime(d.fecha, '%Y-%m'), c.code), (strftime(d.fecha, '%Y-%m')))
ORDER BY 1, 2;


-- ---------------------------------------------------------------------
-- tablero_envios: días promedio de entrega (meta Mendoza).
-- GRANO: mes del pedido × canal × provincia (canal y provincia pueden ser 'Todos').
-- Solo envíos DELIVERED. Días promedio = dias_total / entregas, calculado después de sumar.
-- No tiene producto (el envío es del pedido completo).
-- ---------------------------------------------------------------------
CREATE TABLE tablero_envios AS
SELECT
    strftime(d.fecha, '%Y-%m')     AS mes,
    COALESCE(c.code, 'Todos')      AS canal,
    COALESCE(pr.name, 'Todos')     AS provincia,
    COUNT(*)                       AS entregas,
    SUM(s.days_to_deliver)         AS dias_total
FROM fact_shipment AS s
JOIN dim_date            AS d  ON d.date_key             = s.order_date_key
JOIN dim_channel         AS c  ON c.channel_key          = s.channel_key
JOIN dim_province        AS pr ON pr.province_key        = s.province_key
JOIN dim_shipment_status AS ss ON ss.shipment_status_key = s.shipment_status_key
WHERE ss.code = 'DELIVERED'
GROUP BY strftime(d.fecha, '%Y-%m'), CUBE (c.code, pr.name)
ORDER BY 1, 2, 3;
