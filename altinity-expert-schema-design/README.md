 read files and help me convert pg schema to clickhouse.  tune ch schema to optimize slow query.  use dictionaries for dimensional tables.  create fact and dimension
    as for star schema, give prefixes fact_ and dim_ to tables. use materialized views and aggregated tables as needed. ask questions propose plan to discuss before
  implementing
 
 replicated, latest clickhouse. 100-200M rows in biggest tables. latest snapshot only. use dictGet. wrap all dictGet into UDF getter. leave fixed values as-is, but
  place into WITH expressions for clear. Yes, leave region codes as-is

use macro {cluster} for cluster name. database=pp

You don't need to specify ZK path for ON CLUSTER, ENGINE = ReplicatedMergeTree is enough.  remove all ZK path from table defintion.  CREATE FUNCTION IF NOT EXISTS
  pp.asin_dim thats wrong.  use CREATE OR REPLACE FUNCTION getAsin AS (product_id,key) -> dictGet('pp.dict_dim_asin', key, product_id), no default, no tuples. Make
  single sql file per each fact and dimenion.  place dictionary and related UDFs to the same file as dimension create table.  rewrite slow query for clickhouse using
  new schema
