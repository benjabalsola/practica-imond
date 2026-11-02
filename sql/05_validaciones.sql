-- =====================================================================
-- 05_validaciones.sql — Controles automáticos del data warehouse
-- =====================================================================
-- Cada fila de la tabla temporal "validaciones" es un control con el valor
-- esperado y el obtenido. Al final, si alguno no coincide, error() detiene
-- run_sql.py con un mensaje (y no se exporta un DW inconsistente).
-- La tabla es TEMP, así que no se exporta a dw/.
-- =====================================================================

CREATE TEMP TABLE validaciones (control VARCHAR, esperado DECIMAL(18, 2), obtenido DECIMAL(18, 2));

-- 1. Filas: cada hecho tiene una fila por registro de su tabla de origen
INSERT INTO validaciones
          SELECT 'filas fact_order = raw.sales_order',           (SELECT COUNT(*) FROM raw.sales_order),      (SELECT COUNT(*) FROM fact_order)
UNION ALL SELECT 'filas fact_sales = raw.sales_order_item',      (SELECT COUNT(*) FROM raw.sales_order_item), (SELECT COUNT(*) FROM fact_sales)
UNION ALL SELECT 'filas fact_payment = raw.payment',             (SELECT COUNT(*) FROM raw.payment),          (SELECT COUNT(*) FROM fact_payment)
UNION ALL SELECT 'filas fact_shipment = raw.shipment',           (SELECT COUNT(*) FROM raw.shipment),         (SELECT COUNT(*) FROM fact_shipment)
UNION ALL SELECT 'filas fact_web_session = raw.web_session',     (SELECT COUNT(*) FROM raw.web_session),      (SELECT COUNT(*) FROM fact_web_session)
UNION ALL SELECT 'filas fact_nps = raw.nps_response',            (SELECT COUNT(*) FROM raw.nps_response),     (SELECT COUNT(*) FROM fact_nps)
UNION ALL SELECT 'filas dim_customer = raw.customer + 1',        (SELECT COUNT(*) + 1 FROM raw.customer),     (SELECT COUNT(*) FROM dim_customer)
UNION ALL SELECT 'filas dim_address = raw.address + 1',          (SELECT COUNT(*) + 1 FROM raw.address),      (SELECT COUNT(*) FROM dim_address)
UNION ALL SELECT 'filas dim_product = raw.product + 1',          (SELECT COUNT(*) + 1 FROM raw.product),      (SELECT COUNT(*) FROM dim_product);

-- 2. Sumas: los montos del DW cierran con los de origen
INSERT INTO validaciones
          SELECT 'suma total_amount fact_order = raw',   (SELECT SUM(total_amount) FROM raw.sales_order),    (SELECT SUM(total_amount) FROM fact_order)
UNION ALL SELECT 'suma line_total fact_sales = raw',     (SELECT SUM(line_total) FROM raw.sales_order_item), (SELECT SUM(line_total) FROM fact_sales)
UNION ALL SELECT 'suma amount fact_payment = raw',       (SELECT SUM(amount) FROM raw.payment),              (SELECT SUM(amount) FROM fact_payment)
UNION ALL SELECT 'suma score fact_nps = raw',            (SELECT SUM(score) FROM raw.nps_response),          (SELECT SUM(score) FROM fact_nps)
UNION ALL SELECT 'subtotal = suma de line_total (pedidos con diferencia)', 0,
          (SELECT COUNT(*) FROM (SELECT o.order_id FROM fact_order AS o JOIN fact_sales AS s ON s.order_id = o.order_id
                                 GROUP BY o.order_id, o.subtotal HAVING o.subtotal <> SUM(s.line_total)));

-- 3. Claves: ninguna FK huérfana ni nula (debería ser imposible por NOT NULL + REFERENCES; se controla igual)
INSERT INTO validaciones
          SELECT 'huérfanas fact_order.date_key',            0, (SELECT COUNT(*) FROM fact_order f ANTI JOIN dim_date d ON d.date_key = f.date_key)
UNION ALL SELECT 'huérfanas fact_order.customer_key',        0, (SELECT COUNT(*) FROM fact_order f ANTI JOIN dim_customer d ON d.customer_key = f.customer_key)
UNION ALL SELECT 'huérfanas fact_order.channel_key',         0, (SELECT COUNT(*) FROM fact_order f ANTI JOIN dim_channel d ON d.channel_key = f.channel_key)
UNION ALL SELECT 'huérfanas fact_order.store_key',           0, (SELECT COUNT(*) FROM fact_order f ANTI JOIN dim_store d ON d.store_key = f.store_key)
UNION ALL SELECT 'huérfanas fact_order.province_key',        0, (SELECT COUNT(*) FROM fact_order f ANTI JOIN dim_province d ON d.province_key = f.province_key)
UNION ALL SELECT 'huérfanas fact_order.shipping_address_key',0, (SELECT COUNT(*) FROM fact_order f ANTI JOIN dim_address d ON d.address_key = f.shipping_address_key)
UNION ALL SELECT 'huérfanas fact_order.billing_address_key', 0, (SELECT COUNT(*) FROM fact_order f ANTI JOIN dim_address d ON d.address_key = f.billing_address_key)
UNION ALL SELECT 'huérfanas fact_order.order_status_key',    0, (SELECT COUNT(*) FROM fact_order f ANTI JOIN dim_order_status d ON d.order_status_key = f.order_status_key)
UNION ALL SELECT 'huérfanas fact_sales.product_key',         0, (SELECT COUNT(*) FROM fact_sales f ANTI JOIN dim_product d ON d.product_key = f.product_key)
UNION ALL SELECT 'huérfanas fact_sales.date_key',            0, (SELECT COUNT(*) FROM fact_sales f ANTI JOIN dim_date d ON d.date_key = f.date_key)
UNION ALL SELECT 'huérfanas fact_payment.paid_date_key',     0, (SELECT COUNT(*) FROM fact_payment f ANTI JOIN dim_date d ON d.date_key = f.paid_date_key)
UNION ALL SELECT 'huérfanas fact_payment.payment_method_key',0, (SELECT COUNT(*) FROM fact_payment f ANTI JOIN dim_payment_method d ON d.payment_method_key = f.payment_method_key)
UNION ALL SELECT 'huérfanas fact_payment.payment_status_key',0, (SELECT COUNT(*) FROM fact_payment f ANTI JOIN dim_payment_status d ON d.payment_status_key = f.payment_status_key)
UNION ALL SELECT 'huérfanas fact_shipment.shipped_date_key', 0, (SELECT COUNT(*) FROM fact_shipment f ANTI JOIN dim_date d ON d.date_key = f.shipped_date_key)
UNION ALL SELECT 'huérfanas fact_shipment.delivered_date_key',0,(SELECT COUNT(*) FROM fact_shipment f ANTI JOIN dim_date d ON d.date_key = f.delivered_date_key)
UNION ALL SELECT 'huérfanas fact_shipment.carrier_key',      0, (SELECT COUNT(*) FROM fact_shipment f ANTI JOIN dim_carrier d ON d.carrier_key = f.carrier_key)
UNION ALL SELECT 'huérfanas fact_shipment.shipment_status_key',0,(SELECT COUNT(*) FROM fact_shipment f ANTI JOIN dim_shipment_status d ON d.shipment_status_key = f.shipment_status_key)
UNION ALL SELECT 'huérfanas fact_web_session.customer_key',  0, (SELECT COUNT(*) FROM fact_web_session f ANTI JOIN dim_customer d ON d.customer_key = f.customer_key)
UNION ALL SELECT 'huérfanas fact_web_session.web_source_key',0, (SELECT COUNT(*) FROM fact_web_session f ANTI JOIN dim_web_source d ON d.web_source_key = f.web_source_key)
UNION ALL SELECT 'huérfanas fact_web_session.device_key',    0, (SELECT COUNT(*) FROM fact_web_session f ANTI JOIN dim_device d ON d.device_key = f.device_key)
UNION ALL SELECT 'huérfanas fact_nps.score_key',             0, (SELECT COUNT(*) FROM fact_nps f ANTI JOIN dim_nps_score d ON d.score_key = f.score_key)
UNION ALL SELECT 'huérfanas fact_nps.channel_key',           0, (SELECT COUNT(*) FROM fact_nps f ANTI JOIN dim_channel d ON d.channel_key = f.channel_key);

-- 4. Marts: cierran contra los hechos
INSERT INTO validaciones
          SELECT 'tablero_ventas (Todos) = ventas de fact_order',
                 (SELECT SUM(o.total_amount) FROM fact_order o JOIN dim_order_status s USING (order_status_key) WHERE s.es_venta),
                 (SELECT SUM(ventas) FROM tablero_ventas WHERE canal = 'Todos' AND provincia = 'Todos' AND producto = 'Todos')
UNION ALL SELECT 'tablero_ventas (Todos) pedidos = pedidos de venta',
                 (SELECT COUNT(*) FROM fact_order o JOIN dim_order_status s USING (order_status_key) WHERE s.es_venta),
                 (SELECT SUM(pedidos) FROM tablero_ventas WHERE canal = 'Todos' AND provincia = 'Todos' AND producto = 'Todos')
UNION ALL SELECT 'tablero_ventas: provincias suman el total',
                 (SELECT SUM(ventas) FROM tablero_ventas WHERE canal = 'Todos' AND provincia = 'Todos' AND producto = 'Todos'),
                 (SELECT SUM(ventas) FROM tablero_ventas WHERE canal = 'Todos' AND provincia <> 'Todos' AND producto = 'Todos')
UNION ALL SELECT 'tablero_nps (Todos) = filas de fact_nps',
                 (SELECT COUNT(*) FROM fact_nps), (SELECT SUM(respuestas) FROM tablero_nps WHERE canal = 'Todos')
UNION ALL SELECT 'tablero_usuarios período completo = cálculo directo',
                 (SELECT COUNT(DISTINCT customer_key) FILTER (WHERE customer_key <> -1)
                       + COUNT(DISTINCT session_id) FILTER (WHERE customer_key = -1) FROM fact_web_session),
                 (SELECT usuarios_activos FROM tablero_usuarios WHERE desde = '2024-01' AND hasta = '2025-09')
UNION ALL SELECT 'tablero_envios (Todos) = envíos entregados',
                 (SELECT COUNT(*) FROM fact_shipment f JOIN dim_shipment_status s USING (shipment_status_key) WHERE s.code = 'DELIVERED'),
                 (SELECT SUM(entregas) FROM tablero_envios WHERE canal = 'Todos' AND provincia = 'Todos');

-- Resultado de los controles
SELECT control, esperado, obtenido, esperado = obtenido AS ok
FROM validaciones
ORDER BY ok, control;

-- Si algún control falla, se detiene la ejecución
SELECT CASE WHEN COUNT(*) FILTER (WHERE esperado IS DISTINCT FROM obtenido) = 0
            THEN 'Todos los controles OK (' || COUNT(*) || ')'
            ELSE error('Fallaron ' || COUNT(*) FILTER (WHERE esperado IS DISTINCT FROM obtenido) || ' controles: revisá la tabla de arriba')
       END AS resultado
FROM validaciones;
