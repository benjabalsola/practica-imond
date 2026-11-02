# Modelo estrella

Generado por `run_sql.py` a partir de las tablas de `warehouse.duckdb`.

```mermaid
erDiagram
    dim_address ||--o{ fact_order : "billing_address_key"
    dim_address ||--o{ fact_order : "shipping_address_key"
    dim_carrier ||--o{ fact_shipment : "carrier_key"
    dim_channel ||--o{ fact_nps : "channel_key"
    dim_channel ||--o{ fact_order : "channel_key"
    dim_channel ||--o{ fact_payment : "channel_key"
    dim_channel ||--o{ fact_sales : "channel_key"
    dim_channel ||--o{ fact_shipment : "channel_key"
    dim_customer ||--o{ fact_nps : "customer_key"
    dim_customer ||--o{ fact_order : "customer_key"
    dim_customer ||--o{ fact_payment : "customer_key"
    dim_customer ||--o{ fact_sales : "customer_key"
    dim_customer ||--o{ fact_shipment : "customer_key"
    dim_customer ||--o{ fact_web_session : "customer_key"
    dim_date ||--o{ fact_nps : "date_key"
    dim_date ||--o{ fact_order : "date_key"
    dim_date ||--o{ fact_payment : "order_date_key"
    dim_date ||--o{ fact_payment : "paid_date_key"
    dim_date ||--o{ fact_sales : "date_key"
    dim_date ||--o{ fact_shipment : "delivered_date_key"
    dim_date ||--o{ fact_shipment : "order_date_key"
    dim_date ||--o{ fact_shipment : "shipped_date_key"
    dim_date ||--o{ fact_web_session : "date_key"
    dim_device ||--o{ fact_web_session : "device_key"
    dim_nps_score ||--o{ fact_nps : "score_key"
    dim_order_status ||--o{ fact_order : "order_status_key"
    dim_order_status ||--o{ fact_sales : "order_status_key"
    dim_payment_method ||--o{ fact_payment : "payment_method_key"
    dim_payment_status ||--o{ fact_payment : "payment_status_key"
    dim_product ||--o{ fact_sales : "product_key"
    dim_province ||--o{ fact_order : "province_key"
    dim_province ||--o{ fact_sales : "province_key"
    dim_province ||--o{ fact_shipment : "province_key"
    dim_shipment_status ||--o{ fact_shipment : "shipment_status_key"
    dim_store ||--o{ fact_order : "store_key"
    dim_store ||--o{ fact_sales : "store_key"
    dim_web_source ||--o{ fact_web_session : "web_source_key"
    dim_address {
        INTEGER address_key PK
        BIGINT address_id
        VARCHAR city
        VARCHAR postal_code
        VARCHAR province
        VARCHAR country_code
    }
    dim_carrier {
        INTEGER carrier_key PK
        VARCHAR name
    }
    dim_channel {
        INTEGER channel_key PK
        INTEGER channel_id
        VARCHAR code
        VARCHAR name
    }
    dim_customer {
        INTEGER customer_key PK
        INTEGER customer_id
        VARCHAR full_name
        VARCHAR email
        VARCHAR status
        TIMESTAMP created_at
    }
    dim_date {
        INTEGER date_key PK
        DATE fecha
        INTEGER anio
        INTEGER trimestre
        INTEGER mes
        VARCHAR nombre_mes
        INTEGER dia
        VARCHAR nombre_dia
        BOOLEAN es_fin_de_semana
    }
    dim_device {
        INTEGER device_key PK
        VARCHAR code
    }
    dim_nps_score {
        INTEGER score_key PK
        INTEGER score
        VARCHAR grupo
    }
    dim_order_status {
        INTEGER order_status_key PK
        VARCHAR code
        VARCHAR descripcion
        BOOLEAN es_venta
    }
    dim_payment_method {
        INTEGER payment_method_key PK
        VARCHAR code
        VARCHAR descripcion
    }
    dim_payment_status {
        INTEGER payment_status_key PK
        VARCHAR code
        VARCHAR descripcion
    }
    dim_product {
        INTEGER product_key PK
        INTEGER product_id
        VARCHAR sku
        VARCHAR name
        VARCHAR category
        VARCHAR family
        DECIMAL list_price
    }
    dim_province {
        INTEGER province_key PK
        INTEGER province_id
        VARCHAR name
        VARCHAR code
    }
    dim_shipment_status {
        INTEGER shipment_status_key PK
        VARCHAR code
        VARCHAR descripcion
    }
    dim_store {
        INTEGER store_key PK
        INTEGER store_id
        VARCHAR name
        VARCHAR city
        VARCHAR province
    }
    dim_web_source {
        INTEGER web_source_key PK
        VARCHAR code
        VARCHAR descripcion
    }
    fact_nps {
        BIGINT nps_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER score_key FK
        INTEGER score
        VARCHAR comment
    }
    fact_order {
        BIGINT order_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        INTEGER shipping_address_key FK
        INTEGER billing_address_key FK
        INTEGER order_status_key FK
        DECIMAL subtotal
        DECIMAL tax_amount
        DECIMAL shipping_fee
        DECIMAL total_amount
    }
    fact_payment {
        BIGINT payment_id PK
        BIGINT order_id
        INTEGER order_date_key FK
        INTEGER paid_date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER payment_method_key FK
        INTEGER payment_status_key FK
        DECIMAL amount
    }
    fact_sales {
        BIGINT order_item_id PK
        BIGINT order_id
        INTEGER date_key FK
        INTEGER product_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        INTEGER order_status_key FK
        INTEGER quantity
        DECIMAL unit_price
        DECIMAL discount_amount
        DECIMAL line_total
    }
    fact_shipment {
        BIGINT shipment_id PK
        BIGINT order_id
        INTEGER order_date_key FK
        INTEGER shipped_date_key FK
        INTEGER delivered_date_key FK
        INTEGER customer_key FK
        INTEGER province_key FK
        INTEGER channel_key FK
        INTEGER carrier_key FK
        INTEGER shipment_status_key FK
        INTEGER days_to_ship
        INTEGER days_to_deliver
    }
    fact_web_session {
        BIGINT session_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER web_source_key FK
        INTEGER device_key FK
        DECIMAL duration_minutes
    }
    tablero_envios {
        VARCHAR mes
        VARCHAR canal
        VARCHAR provincia
        BIGINT entregas
        HUGEINT dias_total
    }
    tablero_nps {
        VARCHAR mes
        VARCHAR canal
        BIGINT respuestas
        BIGINT promotores
        BIGINT detractores
    }
    tablero_usuarios {
        VARCHAR desde
        VARCHAR hasta
        BIGINT clientes_identificados
        BIGINT sesiones_anonimas
        BIGINT usuarios_activos
    }
    tablero_ventas {
        VARCHAR mes
        VARCHAR canal
        VARCHAR provincia
        VARCHAR producto
        DECIMAL ventas
        BIGINT pedidos
        DECIMAL ventas_productos
        BIGINT puesto
    }
```
