-- =====================================================================
-- 01_dimensiones.sql — Tablas de DIMENSIONES del modelo estrella
-- =====================================================================
-- Para cada dimensión:
--   1. CREATE TABLE con sus columnas, tipos y PRIMARY KEY.
--   2. INSERT INTO ... SELECT para cargarla desde las tablas de origen.
--
-- Las tablas de origen (los CSV de raw/) están en el esquema raw:
--     FROM raw.product
-- Para ver qué columnas y tipos tiene una:  DESCRIBE raw.product;
-- Para explorarlas antes de escribir nada:  python run_sql.py --explorar
-- =====================================================================


-- ---------------------------------------------------------------------
-- EJEMPLO RESUELTO: dimensión producto
-- ---------------------------------------------------------------------
-- En raw/ la categoría está en otra tabla y tiene jerarquía
-- (Bottles -> Classic / Sport). En la dimensión la "aplanamos":
-- cada producto queda en una sola fila con su categoría y su familia.
--
-- product_key es la clave SUBROGADA: un número propio del data warehouse.
-- product_id es la clave NATURAL: el ID que viene del sistema de origen.
-- Las tablas de hechos usan product_key; product_id sirve para encontrarla.

CREATE TABLE dim_product (
    product_key INTEGER PRIMARY KEY,
    product_id  INTEGER,
    sku         VARCHAR NOT NULL,
    name        VARCHAR NOT NULL,
    category    VARCHAR,             -- Classic / Sport
    family      VARCHAR,             -- Bottles
    list_price  DECIMAL(12, 2)
);

INSERT INTO dim_product VALUES (-1, NULL, 'N/A', 'Desconocido', NULL, NULL, NULL);

INSERT INTO dim_product
SELECT
    ROW_NUMBER() OVER (ORDER BY p.product_id) AS product_key,
    p.product_id,
    p.sku,
    p.name,
    c.name AS category,
    f.name AS family,
    p.list_price
FROM raw.product AS p
LEFT JOIN raw.product_category AS c ON c.category_id = p.category_id   -- categoría
LEFT JOIN raw.product_category AS f ON f.category_id = c.parent_id;    -- familia (categoría padre)


-- ---------------------------------------------------------------------
-- TU TURNO: el resto de las dimensiones
-- ---------------------------------------------------------------------
-- Pensá qué preguntas tiene que responder el dashboard (por fecha, canal,
-- provincia, producto, cliente, tienda...) y creá una dimensión para cada una.
--
-- Tips:
--   * Generar todas las fechas entre dos días:
--       SELECT CAST(range AS DATE) AS fecha
--       FROM range(DATE '2024-01-01', DATE '2025-10-01', INTERVAL 1 DAY);
--   * Partes de una fecha: year(fecha), month(fecha), monthname(fecha), dayname(fecha)
--   * Clave numérica para una fecha (ej. 20240131):
--       CAST(strftime(fecha, '%Y%m%d') AS INTEGER)
--   * Si algo puede venir vacío (ej. NPS anónimos, sin cliente), podés agregar
--     una fila "Desconocido" con clave -1 y usar COALESCE(clave, -1) en los hechos.


CREATE TABLE dim_date (
    date_key     INTEGER PRIMARY KEY,   -- ej. 20240131; -1 = fecha desconocida o que todavía no ocurrió
    fecha        DATE,
    anio         INTEGER,
    trimestre    INTEGER,
    mes          INTEGER,
    nombre_mes   VARCHAR,
    dia          INTEGER,
    nombre_dia   VARCHAR,
    es_fin_de_semana BOOLEAN
);

INSERT INTO dim_date VALUES (-1, NULL, NULL, NULL, NULL, 'Desconocido', NULL, 'Desconocido', NULL);

INSERT INTO dim_date
SELECT
    CAST(strftime(fecha, '%Y%m%d') AS INTEGER) AS date_key,
    fecha,
    year(fecha),
    quarter(fecha),
    month(fecha),
    monthname(fecha),
    day(fecha),
    dayname(fecha),
    dayofweek(fecha) IN (0, 6)
FROM (
    SELECT CAST(range AS DATE) AS fecha
    FROM range(DATE '2024-01-01', DATE '2025-10-01', INTERVAL 1 DAY)
);


CREATE TABLE dim_province (
    province_key INTEGER PRIMARY KEY,
    province_id  INTEGER,
    name         VARCHAR NOT NULL,
    code         VARCHAR
);

INSERT INTO dim_province VALUES (-1, NULL, 'Desconocido', NULL);

INSERT INTO dim_province
SELECT
    ROW_NUMBER() OVER (ORDER BY province_id) AS province_key,
    province_id,
    name,
    code
FROM raw.province;


CREATE TABLE dim_channel (
    channel_key INTEGER PRIMARY KEY,
    channel_id  INTEGER,
    code        VARCHAR,
    name        VARCHAR NOT NULL
);

INSERT INTO dim_channel VALUES (-1, NULL, NULL, 'Desconocido');

INSERT INTO dim_channel
SELECT
    ROW_NUMBER() OVER (ORDER BY channel_id) AS channel_key,
    channel_id,
    code,
    name
FROM raw.channel;


CREATE TABLE dim_store (
    store_key  INTEGER PRIMARY KEY,
    store_id   INTEGER,
    name       VARCHAR NOT NULL,
    city       VARCHAR,
    province   VARCHAR
);

INSERT INTO dim_store VALUES (-1, NULL, 'Sin tienda', NULL, NULL);

INSERT INTO dim_store
SELECT
    ROW_NUMBER() OVER (ORDER BY s.store_id) AS store_key,
    s.store_id,
    s.name,
    a.city,
    pr.name AS province
FROM raw.store AS s
LEFT JOIN raw.address  AS a  ON a.address_id   = s.address_id
LEFT JOIN raw.province AS pr ON pr.province_id = a.province_id;


CREATE TABLE dim_customer (
    customer_key INTEGER PRIMARY KEY,
    customer_id  INTEGER,
    full_name    VARCHAR NOT NULL,
    email        VARCHAR,
    status       VARCHAR,
    created_at   TIMESTAMP
);

INSERT INTO dim_customer VALUES (-1, NULL, 'Desconocido', NULL, NULL, NULL);

INSERT INTO dim_customer
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_key,
    customer_id,
    first_name || ' ' || last_name AS full_name,
    email,
    status,
    created_at
FROM raw.customer;


-- ---------------------------------------------------------------------
-- Dirección (de envío y de facturación de los pedidos)
-- ---------------------------------------------------------------------
CREATE TABLE dim_address (
    address_key  INTEGER PRIMARY KEY,
    address_id   BIGINT,
    city         VARCHAR,
    postal_code  VARCHAR,
    province     VARCHAR,
    country_code VARCHAR
);

INSERT INTO dim_address VALUES (-1, NULL, 'Desconocido', NULL, 'Desconocido', NULL);

INSERT INTO dim_address
SELECT
    ROW_NUMBER() OVER (ORDER BY a.address_id) AS address_key,
    a.address_id,
    a.city,
    CAST(a.postal_code AS VARCHAR),
    pr.name AS province,
    a.country_code
FROM raw.address AS a
LEFT JOIN raw.province AS pr ON pr.province_id = a.province_id;


-- ---------------------------------------------------------------------
-- Dimensiones chicas para los atributos descriptivos
-- (estados, medios de pago, transportista, origen de la visita, dispositivo, puntaje NPS).
-- Se cargan con los valores que aparecen en raw/, así no queda texto suelto en los hechos.
-- ---------------------------------------------------------------------
CREATE TABLE dim_order_status (
    order_status_key INTEGER PRIMARY KEY,
    code             VARCHAR NOT NULL,   -- CREATED / PAID / FULFILLED / CANCELLED / REFUNDED
    descripcion      VARCHAR,
    es_venta         BOOLEAN NOT NULL    -- TRUE si es PAID o FULFILLED (definición de venta de la consigna)
);

INSERT INTO dim_order_status VALUES (-1, 'N/A', 'Desconocido', FALSE);

INSERT INTO dim_order_status
SELECT
    ROW_NUMBER() OVER (ORDER BY status),
    status,
    CASE status WHEN 'CREATED'   THEN 'Creado'
                WHEN 'PAID'      THEN 'Pagado'
                WHEN 'FULFILLED' THEN 'Entregado'
                WHEN 'CANCELLED' THEN 'Cancelado'
                WHEN 'REFUNDED'  THEN 'Devuelto' END,
    status IN ('PAID', 'FULFILLED')
FROM (SELECT DISTINCT status FROM raw.sales_order);


CREATE TABLE dim_payment_method (
    payment_method_key INTEGER PRIMARY KEY,
    code               VARCHAR NOT NULL,   -- CARD / CASH / GATEWAY / TRANSFER
    descripcion        VARCHAR
);

INSERT INTO dim_payment_method VALUES (-1, 'N/A', 'Desconocido');

INSERT INTO dim_payment_method
SELECT
    ROW_NUMBER() OVER (ORDER BY method),
    method,
    CASE method WHEN 'CARD'     THEN 'Tarjeta'
                WHEN 'CASH'     THEN 'Efectivo'
                WHEN 'GATEWAY'  THEN 'Pasarela de pago'
                WHEN 'TRANSFER' THEN 'Transferencia' END
FROM (SELECT DISTINCT method FROM raw.payment);


CREATE TABLE dim_payment_status (
    payment_status_key INTEGER PRIMARY KEY,
    code               VARCHAR NOT NULL,   -- PENDING / PAID / FAILED / REFUNDED
    descripcion        VARCHAR
);

INSERT INTO dim_payment_status VALUES (-1, 'N/A', 'Desconocido');

INSERT INTO dim_payment_status
SELECT
    ROW_NUMBER() OVER (ORDER BY status),
    status,
    CASE status WHEN 'PENDING'  THEN 'Pendiente'
                WHEN 'PAID'     THEN 'Pagado'
                WHEN 'FAILED'   THEN 'Rechazado'
                WHEN 'REFUNDED' THEN 'Reintegrado' END
FROM (SELECT DISTINCT status FROM raw.payment);


CREATE TABLE dim_shipment_status (
    shipment_status_key INTEGER PRIMARY KEY,
    code                VARCHAR NOT NULL,   -- READY / SHIPPED / DELIVERED / CANCELLED
    descripcion         VARCHAR
);

INSERT INTO dim_shipment_status VALUES (-1, 'N/A', 'Desconocido');

INSERT INTO dim_shipment_status
SELECT
    ROW_NUMBER() OVER (ORDER BY status),
    status,
    CASE status WHEN 'READY'     THEN 'Listo para despachar'
                WHEN 'SHIPPED'   THEN 'En camino'
                WHEN 'DELIVERED' THEN 'Entregado'
                WHEN 'CANCELLED' THEN 'Cancelado' END
FROM (SELECT DISTINCT status FROM raw.shipment);


CREATE TABLE dim_carrier (
    carrier_key INTEGER PRIMARY KEY,
    name        VARCHAR NOT NULL
);

INSERT INTO dim_carrier VALUES (-1, 'Desconocido');

INSERT INTO dim_carrier
SELECT ROW_NUMBER() OVER (ORDER BY carrier), carrier
FROM (SELECT DISTINCT carrier FROM raw.shipment WHERE carrier IS NOT NULL);


CREATE TABLE dim_web_source (
    web_source_key INTEGER PRIMARY KEY,
    code           VARCHAR NOT NULL,   -- ads / direct / organic / referral
    descripcion    VARCHAR
);

INSERT INTO dim_web_source VALUES (-1, 'N/A', 'Desconocido');

INSERT INTO dim_web_source
SELECT
    ROW_NUMBER() OVER (ORDER BY source),
    source,
    CASE source WHEN 'ads'      THEN 'Publicidad'
                WHEN 'direct'   THEN 'Directo'
                WHEN 'organic'  THEN 'Búsqueda orgánica'
                WHEN 'referral' THEN 'Referido' END
FROM (SELECT DISTINCT source FROM raw.web_session);


CREATE TABLE dim_device (
    device_key INTEGER PRIMARY KEY,
    code       VARCHAR NOT NULL   -- desktop / mobile / tablet
);

INSERT INTO dim_device VALUES (-1, 'Desconocido');

INSERT INTO dim_device
SELECT ROW_NUMBER() OVER (ORDER BY device), device
FROM (SELECT DISTINCT device FROM raw.web_session);


-- Puntaje NPS: una fila por puntaje posible (0 a 10) con su grupo.
CREATE TABLE dim_nps_score (
    score_key INTEGER PRIMARY KEY,   -- igual al puntaje; -1 = desconocido
    score     INTEGER,
    grupo     VARCHAR NOT NULL       -- Promotor (9-10) / Neutro (7-8) / Detractor (0-6)
);

INSERT INTO dim_nps_score VALUES (-1, NULL, 'Desconocido');

INSERT INTO dim_nps_score
SELECT
    score,
    score,
    CASE WHEN score >= 9 THEN 'Promotor'
         WHEN score >= 7 THEN 'Neutro'
         ELSE 'Detractor' END
FROM range(0, 11) AS t(score);
