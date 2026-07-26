


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."wms_can_manage_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  select exists(
    select 1 from wms_staff s
    where lower(s.email)=lower(coalesce(auth.jwt()->>'email',''))
      and s.active
      and (s.role='admin' or (s.role='manager' and s.perms ? 'staff'))
  );
$$;


ALTER FUNCTION "public"."wms_can_manage_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."wms_health_check"() RETURNS TABLE("sort" integer, "check_key" "text", "category" "text", "title" "text", "hint" "text", "fail_count" bigint, "sample" "jsonb")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
with
bad_math as (
  select id, order_id, order_sku, ordered_qty, factor, required_base
  from wms_order_lines
  where required_base is distinct from ordered_qty * factor
),
factor_drift as (
  select ol.id, ol.order_sku, ol.factor as line_factor, s.factor as snapshot_factor
  from wms_order_lines ol
  join wms_sku_snapshot s on s.sku = ol.order_sku
  where ol.factor is distinct from s.factor
),
split_bad as (
  select ol.id, ol.order_id, o.order_number, ol.order_sku, ol.required_base,
         coalesce((select sum(ptl.assigned_base)
                     from wms_pick_task_lines ptl
                    where ptl.order_line_id = ol.id), 0) as assigned_sum
  from wms_order_lines ol
  join wms_orders o on o.id = ol.order_id
  where o.status in ('picking','packing','ready_to_close','closed')
    and exists (select 1 from wms_pick_tasks pt where pt.order_id = ol.order_id)
    and coalesce((select sum(ptl.assigned_base)
                    from wms_pick_task_lines ptl
                   where ptl.order_line_id = ol.id), 0)
        is distinct from ol.required_base
),
short_no_disc as (
  select ptl.id, ol.order_id, o.order_number, ol.order_sku,
         ptl.assigned_base, ptl.picked_base
  from wms_pick_task_lines ptl
  join wms_order_lines ol on ol.id = ptl.order_line_id
  join wms_orders o on o.id = ol.order_id
  where ptl.status = 'short'
    and not exists (
      select 1 from wms_discrepancies d
      where d.order_id = ol.order_id and d.sku = ol.order_sku
    )
),
pick_over as (
  select ptl.id, ptl.pick_task_id, ol.order_sku,
         ptl.assigned_base, ptl.picked_base
  from wms_pick_task_lines ptl
  join wms_order_lines ol on ol.id = ptl.order_line_id
  where ptl.picked_base > ptl.assigned_base
),
progress_leak as (
  select id, order_number, order_progress, status
  from wms_orders
  where order_progress is distinct from '2.Release to WMS'
    and status not in ('closed','voided')
),
dup_sale as (
  select cin7_sale_id, count(*) as cnt
  from wms_orders
  where cin7_sale_id is not null
  group by cin7_sale_id
  having count(*) > 1
),
finalize_recon as (
  select o.order_number, ol.order_sku, ol.required_base,
         coalesce(sum(ptl.picked_base), 0) as picked_base
  from wms_orders o
  join wms_order_lines ol on ol.order_id = o.id
  join wms_pick_task_lines ptl on ptl.order_line_id = ol.id
  where o.status = 'closed' and o.completion_type = 'clean'
  group by o.id, o.order_number, ol.order_sku, ol.required_base
  having coalesce(sum(ptl.picked_base), 0) is distinct from ol.required_base
),
orphan_pick as (
  select o.id, o.order_number, o.status, count(pt.id) as pick_tasks
  from wms_orders o
  join wms_pick_tasks pt on pt.order_id = o.id
  where o.status = 'pending'
  group by o.id, o.order_number, o.status
),
orphan_pack as (
  select pk.id as pack_task_id, pk.batch_label, o.order_number,
         pk.status as pack_status, pt.status as pick_status
  from wms_pack_tasks pk
  join wms_orders o on o.id = pk.order_id
  left join wms_pick_tasks pt on pt.id = pk.pick_task_id
  where pt.id is null                    -- pack with no paired pick batch at all
     or pt.status is distinct from 'completed'   -- or pick batch not finished yet
),
wave_state as (
  select w.id, w.label, w.status,
         count(pt.id) as member_batches,
         count(pt.id) filter (where pt.status = 'completed') as completed_batches
  from wms_waves w
  left join wms_pick_tasks pt on pt.wave_id = w.id
  group by w.id, w.label, w.status
  having count(pt.id) = 0
      or (w.status = 'completed'
          and count(pt.id) <> count(pt.id) filter (where pt.status = 'completed'))
      or (w.status <> 'completed'
          and count(pt.id) > 0
          and count(pt.id) = count(pt.id) filter (where pt.status = 'completed'))
),
last_import as (
  select max(imported_at) as last_at,
         round(extract(epoch from (now() - max(imported_at))) / 60)::int as minutes_ago
  from wms_orders
)
select 10, 'factor_math', 'critical', 'Factor arithmetic',
  'required_base must equal ordered_qty x factor. A row here means the base conversion was miscomputed at import.',
  (select count(*) from bad_math),
  (select jsonb_agg(t) from (select * from bad_math limit 8) t)
union all
select 20, 'factor_drift', 'warn', 'Line factor vs snapshot',
  'Order-line factor differs from the current product snapshot. Often just a snapshot updated after import, but verify it is not a bad lookup.',
  (select count(*) from factor_drift),
  (select jsonb_agg(t) from (select * from factor_drift limit 8) t)
union all
select 30, 'split_sum', 'critical', 'Split assignment sum',
  'For split orders the assigned base across all batches must equal the line required_base. A gap means a concurrent split lost or double-counted units.',
  (select count(*) from split_bad),
  (select jsonb_agg(t) from (select * from split_bad limit 8) t)
union all
select 40, 'short_no_disc', 'critical', 'Short pick without discrepancy',
  'A pick line marked short with no matching discrepancy row - the shortfall vanished silently. Match key: order_id + order_sku; verify if unsure.',
  (select count(*) from short_no_disc),
  (select jsonb_agg(t) from (select * from short_no_disc limit 8) t)
union all
select 50, 'pick_over', 'warn', 'Picked exceeds assigned',
  'Picked base is greater than assigned at the pick level. Over-quantity should surface at pack, not pick.',
  (select count(*) from pick_over),
  (select jsonb_agg(t) from (select * from pick_over limit 8) t)
union all
select 60, 'progress_leak', 'warn', 'Order progress leak',
  'Active orders whose order_progress is not "2.Release to WMS". Watch for "Backordered" (shared field in Cin7). May also mean the order changed in Cin7 after import (case C).',
  (select count(*) from progress_leak),
  (select jsonb_agg(t) from (select * from progress_leak limit 8) t)
union all
select 70, 'dup_sale', 'critical', 'Duplicate Cin7 sale id',
  'Same cin7_sale_id imported more than once. The unique constraint should make this impossible - a row here means dedup or the constraint failed.',
  (select count(*) from dup_sale),
  (select jsonb_agg(t) from (select * from dup_sale limit 8) t)
union all
select 80, 'finalize_recon', 'critical', 'Finalize reconciliation',
  'Clean-finalized orders where total picked base does not equal required_base. End-to-end check: a row means a factor/pick error slipped through as clean.',
  (select count(*) from finalize_recon),
  (select jsonb_agg(t) from (select * from finalize_recon limit 8) t)
union all
select 90, 'orphan_pick', 'warn', 'Orphaned pick tasks',
  'Orders back at pending (pre-split) that still have pick tasks - an Undo Split rollback that did not clean up.',
  (select count(*) from orphan_pick),
  (select jsonb_agg(t) from (select * from orphan_pick limit 8) t)
union all
select 100, 'orphan_pack', 'warn', 'Orphaned pack tasks',
  'A pack batch whose paired pick batch is missing or not completed. (An order can be picking overall while some of its batches pack - that is normal and no longer flagged.)',
  (select count(*) from orphan_pack),
  (select jsonb_agg(t) from (select * from orphan_pack limit 8) t)
union all
select 110, 'wave_state', 'warn', 'Wave consistency',
  'A wave with no member batches, a completed wave with unfinished batches, or a wave whose batches are all done but the wave never closed (an interrupted finish).',
  (select count(*) from wave_state),
  (select jsonb_agg(t) from (select * from wave_state limit 8) t)
union all
select 200, 'last_import', 'info', 'Last order imported',
  'Newest imported_at - the true signal that polling saved an order. A long gap is normal if no new orders qualified.',
  0::bigint,
  (select jsonb_build_object('last_at', last_at, 'minutes_ago', minutes_ago) from last_import)
order by 1;
$$;


ALTER FUNCTION "public"."wms_health_check"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."wms_is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  select exists(
    select 1 from wms_staff s
    where lower(s.email)=lower(coalesce(auth.jwt()->>'email',''))
      and s.active and s.role='admin'
  );
$$;


ALTER FUNCTION "public"."wms_is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."wms_reap_stale_claims"() RETURNS "void"
    LANGUAGE "sql"
    AS $$
  update wms_pick_tasks
     set status = 'pending', assigned_to = null,
         started_at = null, heartbeat_at = null
   where status = 'in_progress'
     and work_started = false
     and coalesce(heartbeat_at, started_at, created_at) < now() - interval '3 minutes';
  update wms_pack_tasks
     set status = 'pending', assigned_to = null,
         started_at = null, heartbeat_at = null
   where status = 'in_progress'
     and work_started = false
     and coalesce(heartbeat_at, started_at, created_at) < now() - interval '3 minutes';
$$;


ALTER FUNCTION "public"."wms_reap_stale_claims"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."wms_discrepancies" (
    "id" bigint NOT NULL,
    "order_id" bigint,
    "order_number" "text" NOT NULL,
    "sku" "text" NOT NULL,
    "ordered_base" numeric,
    "actual_base" numeric,
    "reason" "text",
    "cin7_corrected" boolean DEFAULT false NOT NULL,
    "resolved_by" "text",
    "resolved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "responsible" "text",
    "source" "text",
    "po_number" "text",
    "receipt_id" bigint
);


ALTER TABLE "public"."wms_discrepancies" OWNER TO "postgres";


ALTER TABLE "public"."wms_discrepancies" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_discrepancies_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_drop_locations" (
    "id" bigint NOT NULL,
    "location_code" "text" NOT NULL,
    "name" "text",
    "warehouse" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wms_drop_locations" OWNER TO "postgres";


ALTER TABLE "public"."wms_drop_locations" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_drop_locations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_order_lines" (
    "id" bigint NOT NULL,
    "order_id" bigint NOT NULL,
    "cin7_line_id" "text",
    "order_sku" "text" NOT NULL,
    "base_sku" "text" NOT NULL,
    "factor" integer DEFAULT 1 NOT NULL,
    "ordered_qty" numeric NOT NULL,
    "required_base" numeric NOT NULL,
    "product_name" "text",
    "image_url" "text",
    "bin_location" "text",
    "zone" "text",
    "is_selling" boolean,
    "scannable_barcodes" "jsonb" DEFAULT '[]'::"jsonb",
    "line_flag" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wms_order_lines" OWNER TO "postgres";


ALTER TABLE "public"."wms_order_lines" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_order_lines_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_orders" (
    "id" bigint NOT NULL,
    "cin7_sale_id" "text" NOT NULL,
    "order_number" "text" NOT NULL,
    "customer_name" "text",
    "warehouse" "text",
    "location" "text",
    "ship_by" "date",
    "order_progress" "text",
    "cin7_status" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "completion_type" "text",
    "total_lines" integer DEFAULT 0,
    "total_required_base" numeric DEFAULT 0,
    "cin7_updated" timestamp with time zone,
    "imported_at" timestamp with time zone DEFAULT "now"(),
    "last_polled_at" timestamp with time zone,
    "notified_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "needs_review" boolean DEFAULT false,
    "fulfillment_type" "text",
    "finalized_by" "text",
    "finalized_at" timestamp with time zone,
    "comments" "text",
    "price_tier" "text",
    "mgr_reviewed" boolean DEFAULT false NOT NULL,
    "mgr_reviewed_by" "text",
    "mgr_reviewed_at" timestamp with time zone,
    "reference" "text",
    CONSTRAINT "wms_orders_completion_type_check" CHECK (("completion_type" = ANY (ARRAY['clean'::"text", 'flagged'::"text"]))),
    CONSTRAINT "wms_orders_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'picking'::"text", 'packing'::"text", 'ready_to_close'::"text", 'closed'::"text", 'voided'::"text"])))
);


ALTER TABLE "public"."wms_orders" OWNER TO "postgres";


ALTER TABLE "public"."wms_orders" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_orders_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_pack_task_lines" (
    "id" bigint NOT NULL,
    "pack_task_id" bigint NOT NULL,
    "order_line_id" bigint NOT NULL,
    "expected_base" numeric NOT NULL,
    "verified_base" numeric DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "verification_method" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "verified_at" timestamp with time zone,
    CONSTRAINT "wms_pack_task_lines_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_progress'::"text", 'verified'::"text", 'mismatch'::"text"]))),
    CONSTRAINT "wms_pack_task_lines_verification_method_check" CHECK (("verification_method" = ANY (ARRAY['scanned_variant'::"text", 'scanned_base'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."wms_pack_task_lines" OWNER TO "postgres";


ALTER TABLE "public"."wms_pack_task_lines" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_pack_task_lines_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_pack_tasks" (
    "id" bigint NOT NULL,
    "order_id" bigint NOT NULL,
    "pick_task_id" bigint NOT NULL,
    "batch_label" "text",
    "assigned_to" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "heartbeat_at" timestamp with time zone,
    "work_started" boolean DEFAULT false NOT NULL,
    "held_by" "text",
    CONSTRAINT "wms_pack_tasks_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_progress'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."wms_pack_tasks" OWNER TO "postgres";


ALTER TABLE "public"."wms_pack_tasks" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_pack_tasks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_pallet_items" (
    "id" bigint NOT NULL,
    "pallet_id" bigint NOT NULL,
    "pack_task_id" bigint,
    "order_id" bigint,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "order_line_id" bigint,
    "order_sku" "text",
    "product_name" "text",
    "qty_base" integer,
    "from_drop" "text"
);


ALTER TABLE "public"."wms_pallet_items" OWNER TO "postgres";


ALTER TABLE "public"."wms_pallet_items" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_pallet_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_pallets" (
    "id" bigint NOT NULL,
    "status" "text" DEFAULT 'building'::"text" NOT NULL,
    "weight_note" "text",
    "height_note" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "completed_at" timestamp with time zone,
    "unit_type" "text" DEFAULT 'pallet'::"text",
    "order_id" bigint,
    "label" "text",
    "parent_id" bigint,
    "created_by" "text",
    CONSTRAINT "wms_pallets_status_check" CHECK (("status" = ANY (ARRAY['building'::"text", 'completed'::"text"]))),
    CONSTRAINT "wms_pallets_unit_type_check" CHECK (("unit_type" = ANY (ARRAY['pallet'::"text", 'box'::"text"])))
);


ALTER TABLE "public"."wms_pallets" OWNER TO "postgres";


ALTER TABLE "public"."wms_pallets" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_pallets_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_pick_task_lines" (
    "id" bigint NOT NULL,
    "pick_task_id" bigint NOT NULL,
    "order_line_id" bigint NOT NULL,
    "assigned_base" numeric NOT NULL,
    "picked_base" numeric DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "verification_method" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "picked_at" timestamp with time zone,
    CONSTRAINT "wms_pick_task_lines_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_progress'::"text", 'picked'::"text", 'short'::"text"]))),
    CONSTRAINT "wms_pick_task_lines_verification_method_check" CHECK (("verification_method" = ANY (ARRAY['scanned_variant'::"text", 'scanned_base'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."wms_pick_task_lines" OWNER TO "postgres";


ALTER TABLE "public"."wms_pick_task_lines" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_pick_task_lines_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_pick_tasks" (
    "id" bigint NOT NULL,
    "order_id" bigint NOT NULL,
    "batch_label" "text",
    "assigned_to" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "drop_location" "text",
    "created_by" "text",
    "heartbeat_at" timestamp with time zone,
    "work_started" boolean DEFAULT false NOT NULL,
    "wave_id" bigint,
    "tote_no" integer,
    "held_by" "text",
    CONSTRAINT "wms_pick_tasks_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_progress'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."wms_pick_tasks" OWNER TO "postgres";


ALTER TABLE "public"."wms_pick_tasks" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_pick_tasks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_receipt_lines" (
    "id" bigint NOT NULL,
    "receipt_id" bigint NOT NULL,
    "cin7_po_line_id" "text",
    "order_sku" "text",
    "base_sku" "text",
    "product_name" "text",
    "expected_base" numeric DEFAULT 0 NOT NULL,
    "received_base" numeric DEFAULT 0 NOT NULL,
    "exported_base" numeric DEFAULT 0 NOT NULL,
    "putaway_bin" "text",
    "zone" "text",
    "putaway_done" boolean DEFAULT false NOT NULL,
    "is_off_po" boolean DEFAULT false NOT NULL,
    "needs_approval" boolean DEFAULT false NOT NULL,
    "approved_by" "text",
    "approved_at" timestamp with time zone,
    "verification_method" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wms_receipt_lines_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'received'::"text"])))
);


ALTER TABLE "public"."wms_receipt_lines" OWNER TO "postgres";


ALTER TABLE "public"."wms_receipt_lines" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."wms_receipt_lines_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_receipts" (
    "id" bigint NOT NULL,
    "po_number" "text" NOT NULL,
    "cin7_purchase_id" "text",
    "supplier_name" "text",
    "warehouse" "text" DEFAULT 'toronto'::"text" NOT NULL,
    "status" "text" DEFAULT 'in_progress'::"text" NOT NULL,
    "received_by" "text",
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "source_type" "text" DEFAULT 'po'::"text" NOT NULL,
    "applied_at" timestamp with time zone,
    "applied_by" "text",
    "apply_note" "text",
    CONSTRAINT "wms_receipts_source_type_check" CHECK (("source_type" = ANY (ARRAY['po'::"text", 'transfer'::"text"]))),
    CONSTRAINT "wms_receipts_status_check" CHECK (("status" = ANY (ARRAY['in_progress'::"text", 'held'::"text", 'partial'::"text", 'completed'::"text"]))),
    CONSTRAINT "wms_receipts_warehouse_check" CHECK (("warehouse" = ANY (ARRAY['toronto'::"text", 'edmonton'::"text"])))
);


ALTER TABLE "public"."wms_receipts" OWNER TO "postgres";


ALTER TABLE "public"."wms_receipts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."wms_receipts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_refresh_requests" (
    "id" bigint NOT NULL,
    "requested_by" "text",
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "started_at" timestamp with time zone,
    "finished_at" timestamp with time zone,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "note" "text"
);


ALTER TABLE "public"."wms_refresh_requests" OWNER TO "postgres";


ALTER TABLE "public"."wms_refresh_requests" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_refresh_requests_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_reports" (
    "id" bigint NOT NULL,
    "order_id" bigint,
    "order_number" "text",
    "sku" "text",
    "kind" "text" NOT NULL,
    "note" "text",
    "reported_by" "text",
    "source" "text",
    "resolved_by" "text",
    "resolved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."wms_reports" OWNER TO "postgres";


ALTER TABLE "public"."wms_reports" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."wms_reports_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_rollback_log" (
    "id" bigint NOT NULL,
    "order_id" bigint,
    "order_number" "text",
    "action" "text" NOT NULL,
    "from_stage" "text",
    "to_stage" "text",
    "performed_by" "text",
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "batch_label" "text",
    "original_worker" "text"
);


ALTER TABLE "public"."wms_rollback_log" OWNER TO "postgres";


ALTER TABLE "public"."wms_rollback_log" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."wms_rollback_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_sku_bins" (
    "id" bigint NOT NULL,
    "sku" "text" NOT NULL,
    "warehouse" "text",
    "warehouse_raw" "text",
    "bin" "text" NOT NULL,
    "zone" "text",
    "on_hand" numeric DEFAULT 0,
    "available" numeric DEFAULT 0,
    "is_current" boolean DEFAULT true,
    "synced_at" timestamp with time zone DEFAULT "now"(),
    "last_seen" "date"
);


ALTER TABLE "public"."wms_sku_bins" OWNER TO "postgres";


ALTER TABLE "public"."wms_sku_bins" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_sku_bins_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_sku_snapshot" (
    "sku" "text" NOT NULL,
    "base_sku" "text",
    "is_variant" boolean DEFAULT false,
    "factor" integer DEFAULT 1,
    "product_name" "text",
    "barcode" "text",
    "is_selling" boolean,
    "image_url" "text",
    "scannable_barcodes" "jsonb" DEFAULT '[]'::"jsonb",
    "synced_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wms_sku_snapshot" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wms_staff" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "warehouse_access" "text" DEFAULT 'toronto'::"text" NOT NULL,
    "role" "text" DEFAULT 'worker'::"text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "email" "text",
    "perms" "jsonb" DEFAULT '["split", "admin", "staff"]'::"jsonb" NOT NULL,
    CONSTRAINT "wms_staff_role_check" CHECK (("role" = ANY (ARRAY['worker'::"text", 'manager'::"text", 'admin'::"text"]))),
    CONSTRAINT "wms_staff_warehouse_access_check" CHECK (("warehouse_access" = ANY (ARRAY['toronto'::"text", 'edmonton'::"text", 'both'::"text"])))
);


ALTER TABLE "public"."wms_staff" OWNER TO "postgres";


ALTER TABLE "public"."wms_staff" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_staff_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_waves" (
    "id" bigint NOT NULL,
    "label" "text" NOT NULL,
    "warehouse" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "assigned_to" "text",
    "created_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "started_at" timestamp with time zone,
    "heartbeat_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "held_by" "text"
);


ALTER TABLE "public"."wms_waves" OWNER TO "postgres";


ALTER TABLE "public"."wms_waves" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_waves_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wms_zone_sequence" (
    "id" bigint NOT NULL,
    "warehouse" "text" NOT NULL,
    "zone" "text" NOT NULL,
    "sequence_order" integer NOT NULL,
    "center_x" numeric,
    "center_y" numeric,
    "active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."wms_zone_sequence" OWNER TO "postgres";


ALTER TABLE "public"."wms_zone_sequence" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."wms_zone_sequence_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."wms_discrepancies"
    ADD CONSTRAINT "wms_discrepancies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_drop_locations"
    ADD CONSTRAINT "wms_drop_locations_location_code_key" UNIQUE ("location_code");



ALTER TABLE ONLY "public"."wms_drop_locations"
    ADD CONSTRAINT "wms_drop_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_order_lines"
    ADD CONSTRAINT "wms_order_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_orders"
    ADD CONSTRAINT "wms_orders_cin7_sale_id_key" UNIQUE ("cin7_sale_id");



ALTER TABLE ONLY "public"."wms_orders"
    ADD CONSTRAINT "wms_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_pack_task_lines"
    ADD CONSTRAINT "wms_pack_task_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_pack_tasks"
    ADD CONSTRAINT "wms_pack_tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_pallet_items"
    ADD CONSTRAINT "wms_pallet_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_pallets"
    ADD CONSTRAINT "wms_pallets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_pick_task_lines"
    ADD CONSTRAINT "wms_pick_task_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_pick_tasks"
    ADD CONSTRAINT "wms_pick_tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_receipt_lines"
    ADD CONSTRAINT "wms_receipt_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_receipts"
    ADD CONSTRAINT "wms_receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_refresh_requests"
    ADD CONSTRAINT "wms_refresh_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_reports"
    ADD CONSTRAINT "wms_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_rollback_log"
    ADD CONSTRAINT "wms_rollback_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_sku_bins"
    ADD CONSTRAINT "wms_sku_bins_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_sku_snapshot"
    ADD CONSTRAINT "wms_sku_snapshot_pkey" PRIMARY KEY ("sku");



ALTER TABLE ONLY "public"."wms_staff"
    ADD CONSTRAINT "wms_staff_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."wms_staff"
    ADD CONSTRAINT "wms_staff_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_waves"
    ADD CONSTRAINT "wms_waves_label_key" UNIQUE ("label");



ALTER TABLE ONLY "public"."wms_waves"
    ADD CONSTRAINT "wms_waves_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_zone_sequence"
    ADD CONSTRAINT "wms_zone_sequence_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wms_zone_sequence"
    ADD CONSTRAINT "wms_zone_sequence_warehouse_zone_key" UNIQUE ("warehouse", "zone");



CREATE INDEX "idx_disc_unresolved" ON "public"."wms_discrepancies" USING "btree" ("cin7_corrected") WHERE ("cin7_corrected" = false);



CREATE INDEX "idx_lines_base_sku" ON "public"."wms_order_lines" USING "btree" ("base_sku");



CREATE INDEX "idx_lines_order" ON "public"."wms_order_lines" USING "btree" ("order_id");



CREATE INDEX "idx_lines_zone" ON "public"."wms_order_lines" USING "btree" ("zone");



CREATE INDEX "idx_orders_finalized" ON "public"."wms_orders" USING "btree" ("finalized_at" DESC) WHERE ("finalized_at" IS NOT NULL);



CREATE INDEX "idx_orders_progress" ON "public"."wms_orders" USING "btree" ("order_progress");



CREATE INDEX "idx_orders_status" ON "public"."wms_orders" USING "btree" ("status");



CREATE INDEX "idx_packlines_task" ON "public"."wms_pack_task_lines" USING "btree" ("pack_task_id");



CREATE INDEX "idx_packtasks_lease" ON "public"."wms_pack_tasks" USING "btree" ("status", "heartbeat_at") WHERE ("status" = 'in_progress'::"text");



CREATE INDEX "idx_packtasks_order" ON "public"."wms_pack_tasks" USING "btree" ("order_id");



CREATE INDEX "idx_packtasks_pick" ON "public"."wms_pack_tasks" USING "btree" ("pick_task_id");



CREATE INDEX "idx_palletitems_pallet" ON "public"."wms_pallet_items" USING "btree" ("pallet_id");



CREATE INDEX "idx_picktasks_assignee" ON "public"."wms_pick_tasks" USING "btree" ("assigned_to");



CREATE INDEX "idx_picktasks_lease" ON "public"."wms_pick_tasks" USING "btree" ("status", "heartbeat_at") WHERE ("status" = 'in_progress'::"text");



CREATE INDEX "idx_picktasks_order" ON "public"."wms_pick_tasks" USING "btree" ("order_id");



CREATE INDEX "idx_picktasks_wave" ON "public"."wms_pick_tasks" USING "btree" ("wave_id") WHERE ("wave_id" IS NOT NULL);



CREATE INDEX "idx_pticklines_orderline" ON "public"."wms_pick_task_lines" USING "btree" ("order_line_id");



CREATE INDEX "idx_pticklines_task" ON "public"."wms_pick_task_lines" USING "btree" ("pick_task_id");



CREATE INDEX "idx_receipt_lines_base" ON "public"."wms_receipt_lines" USING "btree" ("base_sku");



CREATE INDEX "idx_receipt_lines_export" ON "public"."wms_receipt_lines" USING "btree" ("receipt_id") WHERE ("received_base" > "exported_base");



CREATE INDEX "idx_receipt_lines_receipt" ON "public"."wms_receipt_lines" USING "btree" ("receipt_id");



CREATE INDEX "idx_receipts_po" ON "public"."wms_receipts" USING "btree" ("po_number");



CREATE INDEX "idx_receipts_status" ON "public"."wms_receipts" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_reports_open" ON "public"."wms_reports" USING "btree" ("created_at" DESC) WHERE ("resolved_at" IS NULL);



CREATE INDEX "idx_reports_order" ON "public"."wms_reports" USING "btree" ("order_id");



CREATE INDEX "idx_rollback_created" ON "public"."wms_rollback_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_rollback_order" ON "public"."wms_rollback_log" USING "btree" ("order_id");



CREATE INDEX "idx_sku_bins_recommend" ON "public"."wms_sku_bins" USING "btree" ("sku", "warehouse", "is_current" DESC, "last_seen" DESC);



CREATE INDEX "idx_skubins_sku" ON "public"."wms_sku_bins" USING "btree" ("sku");



CREATE INDEX "idx_skubins_wh_zone" ON "public"."wms_sku_bins" USING "btree" ("warehouse", "zone");



CREATE INDEX "idx_snapshot_base" ON "public"."wms_sku_snapshot" USING "btree" ("base_sku");



CREATE INDEX "idx_staff_active" ON "public"."wms_staff" USING "btree" ("active");



CREATE INDEX "idx_waves_status" ON "public"."wms_waves" USING "btree" ("status");



CREATE UNIQUE INDEX "uq_disc_receipt_sku" ON "public"."wms_discrepancies" USING "btree" ("receipt_id", "sku") WHERE ("receipt_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_packtasks_pick" ON "public"."wms_pack_tasks" USING "btree" ("pick_task_id");



ALTER TABLE ONLY "public"."wms_discrepancies"
    ADD CONSTRAINT "wms_discrepancies_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."wms_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wms_order_lines"
    ADD CONSTRAINT "wms_order_lines_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."wms_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wms_pack_task_lines"
    ADD CONSTRAINT "wms_pack_task_lines_order_line_id_fkey" FOREIGN KEY ("order_line_id") REFERENCES "public"."wms_order_lines"("id");



ALTER TABLE ONLY "public"."wms_pack_task_lines"
    ADD CONSTRAINT "wms_pack_task_lines_pack_task_id_fkey" FOREIGN KEY ("pack_task_id") REFERENCES "public"."wms_pack_tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wms_pack_tasks"
    ADD CONSTRAINT "wms_pack_tasks_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."wms_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wms_pack_tasks"
    ADD CONSTRAINT "wms_pack_tasks_pick_task_id_fkey" FOREIGN KEY ("pick_task_id") REFERENCES "public"."wms_pick_tasks"("id");



ALTER TABLE ONLY "public"."wms_pallet_items"
    ADD CONSTRAINT "wms_pallet_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."wms_orders"("id");



ALTER TABLE ONLY "public"."wms_pallet_items"
    ADD CONSTRAINT "wms_pallet_items_order_line_id_fkey" FOREIGN KEY ("order_line_id") REFERENCES "public"."wms_order_lines"("id");



ALTER TABLE ONLY "public"."wms_pallet_items"
    ADD CONSTRAINT "wms_pallet_items_pack_task_id_fkey" FOREIGN KEY ("pack_task_id") REFERENCES "public"."wms_pack_tasks"("id");



ALTER TABLE ONLY "public"."wms_pallet_items"
    ADD CONSTRAINT "wms_pallet_items_pallet_id_fkey" FOREIGN KEY ("pallet_id") REFERENCES "public"."wms_pallets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wms_pallets"
    ADD CONSTRAINT "wms_pallets_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."wms_orders"("id");



ALTER TABLE ONLY "public"."wms_pallets"
    ADD CONSTRAINT "wms_pallets_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."wms_pallets"("id");



ALTER TABLE ONLY "public"."wms_pick_task_lines"
    ADD CONSTRAINT "wms_pick_task_lines_order_line_id_fkey" FOREIGN KEY ("order_line_id") REFERENCES "public"."wms_order_lines"("id");



ALTER TABLE ONLY "public"."wms_pick_task_lines"
    ADD CONSTRAINT "wms_pick_task_lines_pick_task_id_fkey" FOREIGN KEY ("pick_task_id") REFERENCES "public"."wms_pick_tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wms_pick_tasks"
    ADD CONSTRAINT "wms_pick_tasks_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."wms_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wms_pick_tasks"
    ADD CONSTRAINT "wms_pick_tasks_wave_id_fkey" FOREIGN KEY ("wave_id") REFERENCES "public"."wms_waves"("id");



ALTER TABLE ONLY "public"."wms_receipt_lines"
    ADD CONSTRAINT "wms_receipt_lines_receipt_id_fkey" FOREIGN KEY ("receipt_id") REFERENCES "public"."wms_receipts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wms_reports"
    ADD CONSTRAINT "wms_reports_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."wms_orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."wms_rollback_log"
    ADD CONSTRAINT "wms_rollback_log_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."wms_orders"("id") ON DELETE SET NULL;



CREATE POLICY "auth_all" ON "public"."wms_discrepancies" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_order_lines" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_orders" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_pack_task_lines" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_pack_tasks" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_pallet_items" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_pallets" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_pick_task_lines" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_pick_tasks" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_receipt_lines" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_receipts" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_refresh_requests" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_reports" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_rollback_log" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_sku_bins" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_sku_snapshot" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_waves" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "auth_all" ON "public"."wms_zone_sequence" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "staff_delete" ON "public"."wms_staff" FOR DELETE TO "authenticated" USING (("public"."wms_is_admin"() OR ("public"."wms_can_manage_staff"() AND ("role" = 'worker'::"text"))));



CREATE POLICY "staff_insert" ON "public"."wms_staff" FOR INSERT TO "authenticated" WITH CHECK ("public"."wms_can_manage_staff"());



CREATE POLICY "staff_select" ON "public"."wms_staff" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "staff_update" ON "public"."wms_staff" FOR UPDATE TO "authenticated" USING (("public"."wms_can_manage_staff"() AND (("role" <> 'admin'::"text") OR "public"."wms_is_admin"()))) WITH CHECK (("public"."wms_can_manage_staff"() AND (("role" <> 'admin'::"text") OR "public"."wms_is_admin"())));



ALTER TABLE "public"."wms_discrepancies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_drop_locations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_order_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_pack_task_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_pack_tasks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_pallet_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_pallets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_pick_task_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_pick_tasks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_receipt_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_receipts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_refresh_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_rollback_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_sku_bins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_sku_snapshot" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_staff" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_waves" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wms_zone_sequence" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";












GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";











































































































































































GRANT ALL ON FUNCTION "public"."wms_can_manage_staff"() TO "anon";
GRANT ALL ON FUNCTION "public"."wms_can_manage_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."wms_can_manage_staff"() TO "service_role";



GRANT ALL ON FUNCTION "public"."wms_health_check"() TO "anon";
GRANT ALL ON FUNCTION "public"."wms_health_check"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."wms_health_check"() TO "service_role";



GRANT ALL ON FUNCTION "public"."wms_is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."wms_is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."wms_is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."wms_reap_stale_claims"() TO "anon";
GRANT ALL ON FUNCTION "public"."wms_reap_stale_claims"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."wms_reap_stale_claims"() TO "service_role";
























GRANT ALL ON TABLE "public"."wms_discrepancies" TO "anon";
GRANT ALL ON TABLE "public"."wms_discrepancies" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_discrepancies" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_discrepancies_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_discrepancies_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_discrepancies_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_drop_locations" TO "anon";
GRANT ALL ON TABLE "public"."wms_drop_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_drop_locations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_drop_locations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_drop_locations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_drop_locations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_order_lines" TO "anon";
GRANT ALL ON TABLE "public"."wms_order_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_order_lines" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_order_lines_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_order_lines_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_order_lines_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_orders" TO "anon";
GRANT ALL ON TABLE "public"."wms_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_orders" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_orders_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_orders_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_orders_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_pack_task_lines" TO "anon";
GRANT ALL ON TABLE "public"."wms_pack_task_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_pack_task_lines" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_pack_task_lines_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_pack_task_lines_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_pack_task_lines_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_pack_tasks" TO "anon";
GRANT ALL ON TABLE "public"."wms_pack_tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_pack_tasks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_pack_tasks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_pack_tasks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_pack_tasks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_pallet_items" TO "anon";
GRANT ALL ON TABLE "public"."wms_pallet_items" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_pallet_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_pallet_items_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_pallet_items_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_pallet_items_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_pallets" TO "anon";
GRANT ALL ON TABLE "public"."wms_pallets" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_pallets" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_pallets_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_pallets_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_pallets_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_pick_task_lines" TO "anon";
GRANT ALL ON TABLE "public"."wms_pick_task_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_pick_task_lines" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_pick_task_lines_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_pick_task_lines_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_pick_task_lines_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_pick_tasks" TO "anon";
GRANT ALL ON TABLE "public"."wms_pick_tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_pick_tasks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_pick_tasks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_pick_tasks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_pick_tasks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_receipt_lines" TO "anon";
GRANT ALL ON TABLE "public"."wms_receipt_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_receipt_lines" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_receipt_lines_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_receipt_lines_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_receipt_lines_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_receipts" TO "anon";
GRANT ALL ON TABLE "public"."wms_receipts" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_receipts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_receipts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_receipts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_receipts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_refresh_requests" TO "anon";
GRANT ALL ON TABLE "public"."wms_refresh_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_refresh_requests" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_refresh_requests_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_refresh_requests_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_refresh_requests_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_reports" TO "anon";
GRANT ALL ON TABLE "public"."wms_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_reports" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_reports_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_reports_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_reports_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_rollback_log" TO "anon";
GRANT ALL ON TABLE "public"."wms_rollback_log" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_rollback_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_rollback_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_rollback_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_rollback_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_sku_bins" TO "anon";
GRANT ALL ON TABLE "public"."wms_sku_bins" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_sku_bins" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_sku_bins_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_sku_bins_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_sku_bins_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_sku_snapshot" TO "anon";
GRANT ALL ON TABLE "public"."wms_sku_snapshot" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_sku_snapshot" TO "service_role";



GRANT ALL ON TABLE "public"."wms_staff" TO "anon";
GRANT ALL ON TABLE "public"."wms_staff" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_staff" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_staff_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_staff_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_staff_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_waves" TO "anon";
GRANT ALL ON TABLE "public"."wms_waves" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_waves" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_waves_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_waves_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_waves_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wms_zone_sequence" TO "anon";
GRANT ALL ON TABLE "public"."wms_zone_sequence" TO "authenticated";
GRANT ALL ON TABLE "public"."wms_zone_sequence" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wms_zone_sequence_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wms_zone_sequence_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wms_zone_sequence_id_seq" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































