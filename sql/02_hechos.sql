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


CREATE TABLE fact_sales (
    order_item_id   BIGINT PRIMARY KEY,
    order_id        BIGINT NOT NULL,          -- dimensión degenerada
    date_key        INTEGER REFERENCES dim_date (date_key),
    product_key     INTEGER REFERENCES dim_product (product_key),
    customer_key    INTEGER REFERENCES dim_customer (customer_key),
    channel_key     INTEGER REFERENCES dim_channel (channel_key),
    store_key       INTEGER REFERENCES dim_store (store_key),
    province_key    INTEGER REFERENCES dim_province (province_key),  -- provincia de envío
    order_status    VARCHAR,
    quantity        INTEGER,
    unit_price      DECIMAL(12, 2),
    discount_amount DECIMAL(12, 2),
    line_total      DECIMAL(12, 2)
);

INSERT INTO fact_sales
SELECT
    i.order_item_id,
    o.order_id,
    CAST(strftime(o.order_date, '%Y%m%d') AS INTEGER) AS date_key,
    p.product_key,
    COALESCE(c.customer_key, -1),
    COALESCE(ch.channel_key, -1),
    COALESCE(s.store_key, -1),
    COALESCE(pr.province_key, -1),
    o.status,
    i.quantity,
    i.unit_price,
    i.discount_amount,
    i.line_total
FROM raw.sales_order_item AS i
JOIN raw.sales_order      AS o  ON o.order_id = i.order_id
JOIN dim_product          AS p  ON p.product_id = i.product_id
LEFT JOIN dim_customer    AS c  ON c.customer_id = o.customer_id
LEFT JOIN dim_channel     AS ch ON ch.channel_id = o.channel_id
LEFT JOIN dim_store       AS s  ON s.store_id = o.store_id
LEFT JOIN raw.address     AS a  ON a.address_id = o.shipping_address_id
LEFT JOIN dim_province    AS pr ON pr.province_id = a.province_id;

CREATE TABLE fact_nps (
    nps_id       BIGINT PRIMARY KEY,
    date_key     INTEGER REFERENCES dim_date (date_key),
    customer_key INTEGER REFERENCES dim_customer (customer_key),
    channel_key  INTEGER REFERENCES dim_channel (channel_key),
    score        INTEGER,
    nps_group    VARCHAR,     -- Promotor / Neutro / Detractor
    comment      VARCHAR
);

INSERT INTO fact_nps
SELECT
    n.nps_id,
    CAST(strftime(n.responded_at, '%Y%m%d') AS INTEGER),
    COALESCE(c.customer_key, -1),   -- anónimos van a "Desconocido"
    COALESCE(ch.channel_key, -1),
    n.score,
    CASE WHEN n.score >= 9 THEN 'Promotor'
         WHEN n.score >= 7 THEN 'Neutro'
         ELSE 'Detractor' END,
    n.comment
FROM raw.nps_response AS n
LEFT JOIN dim_customer AS c  ON c.customer_id = n.customer_id
LEFT JOIN dim_channel  AS ch ON ch.channel_id = n.channel_id;


CREATE TABLE fact_web_session (
    session_id       BIGINT PRIMARY KEY,
    date_key         INTEGER REFERENCES dim_date (date_key),
    customer_key     INTEGER REFERENCES dim_customer (customer_key),
    source           VARCHAR,
    device           VARCHAR,
    duration_minutes DECIMAL(10, 2)
);

INSERT INTO fact_web_session
SELECT
    w.session_id,
    CAST(strftime(w.started_at, '%Y%m%d') AS INTEGER),
    COALESCE(c.customer_key, -1),
    w.source,
    w.device,
    date_diff('second', w.started_at, w.ended_at) / 60.0
FROM raw.web_session AS w
LEFT JOIN dim_customer AS c ON c.customer_id = w.customer_id;

CREATE TABLE fact_order (
    order_id      BIGINT PRIMARY KEY,
    date_key      INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key  INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key   INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key     INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key  INTEGER NOT NULL REFERENCES dim_province (province_key),  -- provincia de envío
    status        VARCHAR NOT NULL,
    is_sale       BOOLEAN NOT NULL,      -- TRUE si es PAID o FULFILLED
    subtotal      DECIMAL(12, 2),
    tax_amount    DECIMAL(12, 2),
    shipping_fee  DECIMAL(12, 2),
    total_amount  DECIMAL(12, 2)
);

INSERT INTO fact_order
SELECT
    o.order_id,
    CAST(strftime(o.order_date, '%Y%m%d') AS INTEGER),
    COALESCE(cu.customer_key, -1),
    COALESCE(ch.channel_key, -1),
    COALESCE(st.store_key, -1),
    COALESCE(pr.province_key, -1),
    o.status,
    o.status IN ('PAID', 'FULFILLED'),
    o.subtotal, o.tax_amount, o.shipping_fee, o.total_amount
FROM raw.sales_order AS o
LEFT JOIN raw.address  AS a  ON a.address_id   = o.shipping_address_id
LEFT JOIN dim_customer AS cu ON cu.customer_id = o.customer_id
LEFT JOIN dim_channel  AS ch ON ch.channel_id  = o.channel_id
LEFT JOIN dim_store    AS st ON st.store_id    = o.store_id
LEFT JOIN dim_province AS pr ON pr.province_id = a.province_id;


CREATE TABLE fact_payment (
    payment_id     BIGINT PRIMARY KEY,
    order_id       BIGINT NOT NULL,
    order_date_key INTEGER NOT NULL REFERENCES dim_date (date_key),
    paid_date_key  INTEGER REFERENCES dim_date (date_key),  -- vacío si no se pagó
    channel_key    INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    method         VARCHAR NOT NULL,
    status         VARCHAR NOT NULL,
    amount         DECIMAL(12, 2)
);

INSERT INTO fact_payment
SELECT
    p.payment_id, p.order_id, f.date_key,
    CAST(strftime(p.paid_at, '%Y%m%d') AS INTEGER),
    f.channel_key, p.method, p.status, p.amount
FROM raw.payment AS p
JOIN fact_order AS f ON f.order_id = p.order_id;


CREATE TABLE fact_shipment (
    shipment_id        BIGINT PRIMARY KEY,
    order_id           BIGINT NOT NULL,
    order_date_key     INTEGER NOT NULL REFERENCES dim_date (date_key),
    shipped_date_key   INTEGER REFERENCES dim_date (date_key),  -- vacío si no salió
    delivered_date_key INTEGER REFERENCES dim_date (date_key),  -- vacío si no llegó
    province_key       INTEGER NOT NULL REFERENCES dim_province (province_key),
    channel_key        INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    carrier            VARCHAR,
    status             VARCHAR NOT NULL,
    days_to_ship       INTEGER,   -- días del pedido a la salida
    days_to_deliver    INTEGER    -- días del pedido a la entrega
);

INSERT INTO fact_shipment
SELECT
    s.shipment_id, s.order_id, f.date_key,
    CAST(strftime(s.shipped_at,   '%Y%m%d') AS INTEGER),
    CAST(strftime(s.delivered_at, '%Y%m%d') AS INTEGER),
    f.province_key, f.channel_key, s.carrier, s.status,
    date_diff('day', o.order_date, s.shipped_at),
    date_diff('day', o.order_date, s.delivered_at)
FROM raw.shipment AS s
JOIN raw.sales_order AS o ON o.order_id = s.order_id
JOIN fact_order      AS f ON f.order_id = s.order_id;