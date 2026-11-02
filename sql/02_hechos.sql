-- =====================================================================
-- 02_hechos.sql — Tablas de HECHOS del modelo estrella
-- =====================================================================
-- Este archivo se ejecuta después de 01_dimensiones.sql porque los hechos
-- apuntan a las dimensiones con FOREIGN KEY (REFERENCES).
--
-- Para cada tabla de hechos:
--   1. Definí el GRANO: ¿qué representa UNA fila?
--      (ej.: un producto dentro de un pedido, una sesión web, una respuesta NPS)
--   2. CREATE TABLE con:
--        - PRIMARY KEY
--        - una FOREIGN KEY por cada dimensión:  product_key INTEGER REFERENCES dim_product (product_key)
--        - las métricas (cantidades, importes, puntajes...)
--   3. INSERT INTO ... SELECT uniendo las tablas de origen (raw.) con las dimensiones
--      para obtener las claves.
--
-- Patrón para obtener la clave de una dimensión:
--
--   SELECT i.order_item_id, p.product_key, i.quantity, i.line_total
--   FROM raw.sales_order_item AS i
--   JOIN dim_product AS p ON p.product_id = i.product_id
--
-- Si una FOREIGN KEY apunta a una clave que no existe en la dimensión,
-- DuckDB rechaza la carga y run_sql.py te muestra el error.
-- =====================================================================


-- TU TURNO: creá acá las tablas de hechos.

-- Reglas comunes a todos los hechos:
--   * Todas las claves de dimensión son NOT NULL. Si falta el dato (cliente anónimo,
--     pedido online sin tienda, pago que todavía no se cobró) la clave es -1 ("Desconocido").
--   * Las claves de fecha tienen formato AAAAMMDD; -1 si la fecha no existe.
--   * order_id, payment_id, etc. son claves naturales del origen (BIGINT porque superan INTEGER).


-- ---------------------------------------------------------------------
-- fact_order
-- GRANO: un pedido (una fila por raw.sales_order).
-- Los montos son de cabecera: se suman solo en este hecho, nunca en fact_sales.
-- ---------------------------------------------------------------------
CREATE TABLE fact_order (
    order_id             BIGINT PRIMARY KEY,
    date_key             INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key         INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key          INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key            INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key         INTEGER NOT NULL REFERENCES dim_province (province_key),  -- provincia de envío
    shipping_address_key INTEGER NOT NULL REFERENCES dim_address (address_key),
    billing_address_key  INTEGER NOT NULL REFERENCES dim_address (address_key),
    order_status_key     INTEGER NOT NULL REFERENCES dim_order_status (order_status_key),
    subtotal             DECIMAL(12, 2),
    tax_amount           DECIMAL(12, 2),
    shipping_fee         DECIMAL(12, 2),
    total_amount         DECIMAL(12, 2)
);

INSERT INTO fact_order
SELECT
    o.order_id,
    COALESCE(CAST(strftime(o.order_date, '%Y%m%d') AS INTEGER), -1),
    COALESCE(cu.customer_key, -1),
    COALESCE(ch.channel_key, -1),
    COALESCE(st.store_key, -1),
    COALESCE(pr.province_key, -1),
    COALESCE(sa.address_key, -1),
    COALESCE(ba.address_key, -1),
    COALESCE(os.order_status_key, -1),
    o.subtotal, o.tax_amount, o.shipping_fee, o.total_amount
FROM raw.sales_order AS o
LEFT JOIN raw.address      AS a  ON a.address_id   = o.shipping_address_id
LEFT JOIN dim_province     AS pr ON pr.province_id = a.province_id
LEFT JOIN dim_address      AS sa ON sa.address_id  = o.shipping_address_id
LEFT JOIN dim_address      AS ba ON ba.address_id  = o.billing_address_id
LEFT JOIN dim_customer     AS cu ON cu.customer_id = o.customer_id
LEFT JOIN dim_channel      AS ch ON ch.channel_id  = o.channel_id
LEFT JOIN dim_store        AS st ON st.store_id    = o.store_id
LEFT JOIN dim_order_status AS os ON os.code        = o.status;


-- ---------------------------------------------------------------------
-- fact_sales
-- GRANO: un producto dentro de un pedido (una fila por raw.sales_order_item).
-- Solo tiene montos de línea (line_total). Las claves del pedido se copian de fact_order.
-- ---------------------------------------------------------------------
CREATE TABLE fact_sales (
    order_item_id    BIGINT PRIMARY KEY,
    order_id         BIGINT NOT NULL,          -- dimensión degenerada
    date_key         INTEGER NOT NULL REFERENCES dim_date (date_key),
    product_key      INTEGER NOT NULL REFERENCES dim_product (product_key),
    customer_key     INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key      INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key        INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key     INTEGER NOT NULL REFERENCES dim_province (province_key),  -- provincia de envío
    order_status_key INTEGER NOT NULL REFERENCES dim_order_status (order_status_key),
    quantity         INTEGER,
    unit_price       DECIMAL(12, 2),
    discount_amount  DECIMAL(12, 2),
    line_total       DECIMAL(12, 2)
);

INSERT INTO fact_sales
SELECT
    i.order_item_id,
    i.order_id,
    f.date_key,
    COALESCE(p.product_key, -1),
    f.customer_key,
    f.channel_key,
    f.store_key,
    f.province_key,
    f.order_status_key,
    i.quantity,
    i.unit_price,
    i.discount_amount,
    i.line_total
FROM raw.sales_order_item AS i
JOIN fact_order           AS f ON f.order_id   = i.order_id
LEFT JOIN dim_product     AS p ON p.product_id = i.product_id;


-- ---------------------------------------------------------------------
-- fact_payment
-- GRANO: un pago (una fila por raw.payment). Canal y cliente se copian del pedido.
-- ---------------------------------------------------------------------
CREATE TABLE fact_payment (
    payment_id         BIGINT PRIMARY KEY,
    order_id           BIGINT NOT NULL,      -- dimensión degenerada
    order_date_key     INTEGER NOT NULL REFERENCES dim_date (date_key),
    paid_date_key      INTEGER NOT NULL REFERENCES dim_date (date_key),   -- -1 si no se cobró
    customer_key       INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key        INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    payment_method_key INTEGER NOT NULL REFERENCES dim_payment_method (payment_method_key),
    payment_status_key INTEGER NOT NULL REFERENCES dim_payment_status (payment_status_key),
    amount             DECIMAL(12, 2)
);

INSERT INTO fact_payment
SELECT
    p.payment_id,
    p.order_id,
    f.date_key,
    COALESCE(CAST(strftime(p.paid_at, '%Y%m%d') AS INTEGER), -1),
    f.customer_key,
    f.channel_key,
    COALESCE(pm.payment_method_key, -1),
    COALESCE(ps.payment_status_key, -1),
    p.amount
FROM raw.payment AS p
JOIN fact_order              AS f  ON f.order_id = p.order_id
LEFT JOIN dim_payment_method AS pm ON pm.code    = p.method
LEFT JOIN dim_payment_status AS ps ON ps.code    = p.status;


-- ---------------------------------------------------------------------
-- fact_shipment
-- GRANO: un envío por correo (una fila por raw.shipment).
-- Provincia, canal y cliente se copian del pedido. Los días se cuentan como
-- cambios de fecha calendario (date_diff 'day') desde el pedido.
-- ---------------------------------------------------------------------
CREATE TABLE fact_shipment (
    shipment_id         BIGINT PRIMARY KEY,
    order_id            BIGINT NOT NULL,     -- dimensión degenerada
    order_date_key      INTEGER NOT NULL REFERENCES dim_date (date_key),
    shipped_date_key    INTEGER NOT NULL REFERENCES dim_date (date_key),   -- -1 si no salió
    delivered_date_key  INTEGER NOT NULL REFERENCES dim_date (date_key),   -- -1 si no llegó
    customer_key        INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    province_key        INTEGER NOT NULL REFERENCES dim_province (province_key),
    channel_key         INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    carrier_key         INTEGER NOT NULL REFERENCES dim_carrier (carrier_key),
    shipment_status_key INTEGER NOT NULL REFERENCES dim_shipment_status (shipment_status_key),
    days_to_ship        INTEGER,   -- vacío si no salió
    days_to_deliver     INTEGER    -- vacío si no llegó
);

INSERT INTO fact_shipment
SELECT
    s.shipment_id,
    s.order_id,
    f.date_key,
    COALESCE(CAST(strftime(s.shipped_at,   '%Y%m%d') AS INTEGER), -1),
    COALESCE(CAST(strftime(s.delivered_at, '%Y%m%d') AS INTEGER), -1),
    f.customer_key,
    f.province_key,
    f.channel_key,
    COALESCE(ca.carrier_key, -1),
    COALESCE(ss.shipment_status_key, -1),
    date_diff('day', o.order_date, s.shipped_at),
    date_diff('day', o.order_date, s.delivered_at)
FROM raw.shipment AS s
JOIN raw.sales_order          AS o  ON o.order_id = s.order_id
JOIN fact_order               AS f  ON f.order_id = s.order_id
LEFT JOIN dim_carrier         AS ca ON ca.name    = s.carrier
LEFT JOIN dim_shipment_status AS ss ON ss.code    = s.status;


-- ---------------------------------------------------------------------
-- fact_web_session
-- GRANO: una visita a la web (una fila por raw.web_session). Sin cliente = anónima (-1).
-- ---------------------------------------------------------------------
CREATE TABLE fact_web_session (
    session_id       BIGINT PRIMARY KEY,
    date_key         INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key     INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    web_source_key   INTEGER NOT NULL REFERENCES dim_web_source (web_source_key),
    device_key       INTEGER NOT NULL REFERENCES dim_device (device_key),
    duration_minutes DECIMAL(10, 2)
);

INSERT INTO fact_web_session
SELECT
    w.session_id,
    COALESCE(CAST(strftime(w.started_at, '%Y%m%d') AS INTEGER), -1),
    COALESCE(c.customer_key, -1),
    COALESCE(ws.web_source_key, -1),
    COALESCE(d.device_key, -1),
    date_diff('second', w.started_at, w.ended_at) / 60.0
FROM raw.web_session AS w
LEFT JOIN dim_customer   AS c  ON c.customer_id = w.customer_id
LEFT JOIN dim_web_source AS ws ON ws.code       = w.source
LEFT JOIN dim_device     AS d  ON d.code        = w.device;


-- ---------------------------------------------------------------------
-- fact_nps
-- GRANO: una respuesta a la encuesta NPS (una fila por raw.nps_response).
-- comment es texto libre de la respuesta (atributo degenerado, no se agrupa por él).
-- ---------------------------------------------------------------------
CREATE TABLE fact_nps (
    nps_id       BIGINT PRIMARY KEY,
    date_key     INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key  INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    score_key    INTEGER NOT NULL REFERENCES dim_nps_score (score_key),
    score        INTEGER,
    comment      VARCHAR
);

INSERT INTO fact_nps
SELECT
    n.nps_id,
    COALESCE(CAST(strftime(n.responded_at, '%Y%m%d') AS INTEGER), -1),
    COALESCE(c.customer_key, -1),   -- anónimos van a "Desconocido"
    COALESCE(ch.channel_key, -1),
    COALESCE(sc.score_key, -1),
    n.score,
    n.comment
FROM raw.nps_response AS n
LEFT JOIN dim_customer  AS c  ON c.customer_id = n.customer_id
LEFT JOIN dim_channel   AS ch ON ch.channel_id = n.channel_id
LEFT JOIN dim_nps_score AS sc ON sc.score      = n.score;
