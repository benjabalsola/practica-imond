# EcoBottle AR: data warehouse y tablero comercial

Trabajo práctico de **Introducción al Marketing Online y los Negocios Digitales**.

Se armó un modelo estrella (metodología Kimball) a partir de los datos de ventas online y offline de EcoBottle AR, y un tablero para el área comercial con los KPIs: **Ventas, Usuarios Activos, Ticket Promedio, NPS, Ventas por Provincia y Ranking Mensual por Producto**.

- Datos de origen: carpeta `raw/` (una foto del sistema al 30/09/2025, pedidos del 01/01/2024 al 30/09/2025, montos en pesos argentinos).
- Data warehouse: carpeta `dw/` (un CSV por tabla, generados por `run_sql.py`).
- Tablero: LookerStudio → _pegar acá el enlace_ · versión HTML: `tablero.html` · capturas en `capturas/`.

## Cómo ejecutarlo

Requisitos: Python 3.9 o más nuevo y Git.

```bash
git clone https://github.com/benjabalsola/practica-imond.git
cd practica-imond
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python run_sql.py                # arma warehouse.duckdb y exporta las tablas a dw/
```

Opcional: `python run_sql.py --ui` abre DuckDB en el navegador para explorar las tablas.

### Archivos SQL (se ejecutan en este orden)

| Archivo | Qué hace |
|---|---|
| `sql/01_dimensiones.sql` | Crea y carga las 6 dimensiones |
| `sql/02_hechos.sql` | Crea y carga las 6 tablas de hechos, con sus `FOREIGN KEY` |
| `sql/03_consultas.sql` | Controles y consultas de los KPIs |
| `sql/04_tablero.sql` | Tablas planas (`tablero_*`) que usa el tablero |

## Modelo estrella

El diagrama completo, con claves y relaciones, está en [`dw/modelo_estrella.md`](dw/modelo_estrella.md).

- **Dimensiones:** `dim_date`, `dim_channel`, `dim_province`, `dim_product`, `dim_store`, `dim_customer`.
- **Hechos:** `fact_sales`, `fact_order`, `fact_payment`, `fact_shipment`, `fact_web_session`, `fact_nps`.

## Supuestos

1. **Venta** = pedido con estado `PAID` o `FULFILLED` (columna `is_sale`). `CREATED`, `CANCELLED` y `REFUNDED` no cuentan.
2. **Total Ventas** usa `total_amount` (subtotal + IVA 21 % + envío), como pide la consigna.
3. **Provincia de una venta** = provincia de la dirección de envío. En compras en tienda es la provincia de la tienda.
4. **Fecha de una venta** = `order_date` del pedido.
5. **Usuarios activos** = clientes distintos que visitaron la web en el período. Las visitas anónimas no se cuentan, porque no se puede saber si son la misma persona.
6. **NPS** = % de promotores (9 y 10) − % de detractores (0 a 6). Las respuestas anónimas sí se cuentan.
7. Cuando un dato no existe (cliente anónimo, pedido online sin tienda), la clave apunta a la fila **-1 "Desconocido"** de la dimensión.
8. Las fechas de pago, despacho y entrega quedan **vacías** si todavía no ocurrieron.
9. Los IDs del sistema de origen se guardan como `BIGINT`, porque superan el rango de `INTEGER`.
10. Las claves de fecha tienen formato `AAAAMMDD` (ej. `20240131`).
11. La consigna menciona scripts en Python. Las transformaciones están escritas en SQL y las ejecuta el script de Python `run_sql.py`.

## Diccionario de datos

### Dimensiones

| Tabla | Grano | Columnas |
|---|---|---|
| `dim_date` | un día (01/01/2024 a 30/09/2025) | `date_key` PK (AAAAMMDD), `fecha`, `anio`, `trimestre`, `mes`, `nombre_mes`, `dia`, `nombre_dia`, `es_fin_de_semana` |
| `dim_channel` | un canal de venta | `channel_key` PK, `channel_id` (origen), `code` (`ONLINE` / `OFFLINE`), `name` |
| `dim_province` | una provincia | `province_key` PK, `province_id`, `name`, `code` |
| `dim_product` | un producto | `product_key` PK, `product_id`, `sku`, `name`, `category` (Classic / Sport), `family` (Bottles), `list_price` |
| `dim_store` | una tienda física | `store_key` PK, `store_id`, `name`, `city`, `province` |
| `dim_customer` | un cliente | `customer_key` PK, `customer_id`, `full_name`, `email`, `status` (`A` activo / `I` baja), `created_at` |

`_key` es la clave subrogada del data warehouse y `_id` es la clave natural del sistema de origen. Todas las dimensiones tienen la fila `-1` "Desconocido".

### Hechos

| Tabla | Grano | Claves (FK) | Métricas y atributos |
|---|---|---|---|
| `fact_sales` | un producto dentro de un pedido | `date_key`, `product_key`, `customer_key`, `channel_key`, `store_key`, `province_key` | `order_item_id` PK, `order_id`, `order_status`, `quantity`, `unit_price`, `discount_amount`, `line_total` (= cantidad × precio − descuento) |
| `fact_order` | un pedido | `date_key`, `customer_key`, `channel_key`, `store_key`, `province_key` | `order_id` PK, `status`, `is_sale`, `subtotal`, `tax_amount`, `shipping_fee`, `total_amount` |
| `fact_payment` | un pago | `order_date_key`, `paid_date_key`, `channel_key` | `payment_id` PK, `order_id`, `method` (CASH / CARD / TRANSFER / GATEWAY), `status` (PENDING / PAID / FAILED / REFUNDED), `amount` |
| `fact_shipment` | un envío por correo | `order_date_key`, `shipped_date_key`, `delivered_date_key`, `province_key`, `channel_key` | `shipment_id` PK, `order_id`, `carrier`, `status` (READY / SHIPPED / DELIVERED / CANCELLED), `days_to_ship`, `days_to_deliver` |
| `fact_web_session` | una visita a la web | `date_key`, `customer_key` | `session_id` PK, `source` (ads / direct / referral / organic), `device`, `duration_minutes` |
| `fact_nps` | una respuesta de la encuesta | `date_key`, `customer_key`, `channel_key` | `nps_id` PK, `score` (0 a 10), `nps_group` (promotor / pasivo / detractor), `comment` |

`order_id` en pagos y envíos es una **dimensión degenerada**: el número de pedido, sin tabla propia.

### Tablas para el tablero

| Tabla | Grano | Columnas |
|---|---|---|
| `tablero_ventas` | un producto de un pedido que es venta | `fecha`, `canal`, `provincia`, `producto`, `pedido`, `importe_productos`, `importe_total` (total del pedido repartido entre sus productos) |
| `tablero_usuarios` | una visita web | `fecha`, `canal`, `cliente` (vacío si es anónimo) |
| `tablero_nps` | una respuesta NPS | `fecha`, `canal`, `puntaje`, `promotor` (1/0), `detractor` (1/0) |
| `tablero_envios` | un envío entregado | `fecha`, `canal`, `provincia`, `dias_entrega` |

## KPIs y consultas clave

| KPI | Definición | Fórmula en el tablero |
|---|---|---|
| Total Ventas ($M) | `SUM(total_amount)` de pedidos `PAID`/`FULFILLED` | `SUM(importe_total)` |
| Usuarios Activos (nK) | clientes distintos con sesión web | `COUNT_DISTINCT(cliente)` |
| Ticket Promedio ($K) | ventas / cantidad de pedidos | `SUM(importe_total) / COUNT_DISTINCT(pedido)` |
| NPS | (% 9-10 − % 0-6) × 100 | `(SUM(promotor) - SUM(detractor)) / COUNT(puntaje) * 100` |
| Ventas por provincia | ventas por provincia de envío | `SUM(importe_total)` por `provincia` |
| Ranking mensual por producto | `SUM(line_total)` por producto y mes | `SUM(importe_productos)` por mes y `producto` |

Ejemplo, Total Ventas por mes y canal (el resto está en `sql/03_consultas.sql`):

```sql
SELECT
    DATE_TRUNC('month', try_strptime(CAST(f.date_key AS VARCHAR), '%Y%m%d')) AS mes,
    c.code AS canal,
    ROUND(SUM(f.total_amount) / 1e6, 2) AS ventas_millones
FROM fact_order AS f
JOIN dim_channel AS c ON c.channel_key = f.channel_key
WHERE f.is_sale
GROUP BY mes, canal
ORDER BY mes, canal;
```

Ranking mensual por producto:

```sql
SELECT
    DATE_TRUNC('month', try_strptime(CAST(o.date_key AS VARCHAR), '%Y%m%d')) AS mes,
    p.name AS producto,
    SUM(s.line_total) AS ventas,
    RANK() OVER (PARTITION BY DATE_TRUNC('month', try_strptime(CAST(o.date_key AS VARCHAR), '%Y%m%d'))
                 ORDER BY SUM(s.line_total) DESC) AS puesto
FROM fact_sales AS s
JOIN fact_order  AS o ON o.order_id    = s.order_id
JOIN dim_product AS p ON p.product_key = s.product_key
WHERE o.is_sale
GROUP BY mes, producto
ORDER BY mes, puesto;
```

## Hallazgos

- **Ventas totales: $382,4M.** Enero a septiembre de 2025 vendió $170,6M, un **16,6 % más** que el mismo período de 2024 ($146,3M).
- **ONLINE vende más que OFFLINE** ($227,0M contra $155,4M), con un ticket parecido (unos $35K).
- **Sport B** es el producto que más vende ($162,7M contra $147,2M de Classic A), aunque en varios meses lo supera Classic A.
- **Buenos Aires** concentra la mayor parte de las ventas ($142,7M). Le siguen Córdoba ($89,5M) y Santa Fe ($87,6M), y Mendoza queda última ($62,6M).
- **Meta Córdoba (+15 %):** en el 3.er trimestre de 2025 vendió $12,3M, un **25 % más** que en el mismo trimestre de 2024 ($9,8M). Pero cayó un 5 % contra el 2.º trimestre de 2025 ($12,9M), así que hay que seguirlo.
- **Meta Mendoza (tiempos de entrega):** el promedio bajó de **6,2 días en 2024 a 5,3 días en 2025**. Aun así, Mendoza sigue más lenta que Buenos Aires (3,5 días).
- **NPS:** las tiendas físicas tienen mejor NPS (**40,9**) que la web (**24,0**). Una posible causa son los tiempos de entrega del canal online, que conviene analizar junto con los comentarios de la encuesta.

### Ideas para sumar al tablero

- Tasa de conversión: pedidos online / sesiones web, por origen de la visita (`source`).
- Pagos rechazados por método de pago (`fact_payment`).
- Pedidos cancelados y devueltos por mes.
- Ventas de Córdoba contra la meta de +15 %, como indicador de semáforo.
