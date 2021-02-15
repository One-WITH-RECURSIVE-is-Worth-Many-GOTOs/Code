
DROP FUNCTION IF EXISTS count_items(INT8);
CREATE OR REPLACE FUNCTION count_items(catid INT8) RETURNS INT8 AS
$$
DECLARE
  totalcount INT8;
  curcat INT8;
  catitems INT8;
  subcat INT8;
  stack INT8[];
  catrec category;
BEGIN
  totalcount := 0 :: INT8;
  stack := ARRAY[catid];

  WHILE cardinality(stack) > 0 LOOP
    curcat := stack[1];
    stack := stack[2:];
    catitems := (SELECT count(P_PARTKEY)
                 FROM   item
                 WHERE category_id = curcat);
    totalcount := totalcount + catitems;
    stack := (SELECT array_agg(category_id :: INT8)
              FROM category
              WHERE parent_category = curcat) || stack;
  END LOOP;
  RETURN totalcount;
END
$$ LANGUAGE PLPGSQL;

DROP TABLE IF EXISTS category CASCADE;
CREATE TABLE category
( category_id SERIAL NOT NULL PRIMARY KEY
, parent_category INT
);

CREATE INDEX IDX_CATEGORY_PARENT_CATEGORY ON category(parent_category);

DROP TABLE IF EXISTS ITEM CASCADE;
CREATE TABLE ITEM  ( P_PARTKEY     INTEGER NOT NULL,
                          P_NAME        VARCHAR(55) NOT NULL,
                          P_MFGR        CHAR(25) NOT NULL,
                          P_BRAND       CHAR(10) NOT NULL,
                          P_TYPE        VARCHAR(25) NOT NULL,
                          P_SIZE        INTEGER NOT NULL,
                          P_CONTAINER   CHAR(10) NOT NULL,
                          P_RETAILPRICE DECIMAL(15,2) NOT NULL,
                          P_COMMENT     VARCHAR(23) NOT NULL,
                          category_id INT NOT NULL );

ALTER TABLE ITEM ADD PRIMARY KEY (P_PARTKEY);
ALTER TABLE ITEM ADD FOREIGN KEY (category_id) REFERENCES category(category_id);

CREATE INDEX IDX_ITEM_CATEGORY_KEY ON ITEM (category_id);

\set FANOUT 2
\set DEPTH  :invocations

SELECT setseed(0.425);

CREATE OR REPLACE FUNCTION make_hierarchy(fanout INT, depth INT) RETURNS VOID AS
$$
BEGIN
  DROP TABLE IF EXISTS leaves;
  CREATE TEMPORARY TABLE leaves(id INT);

  TRUNCATE category CASCADE;

  FOR i IN 1..depth LOOP
    WITH layer(id) AS (
    INSERT INTO category(parent_category)
      SELECT l.id
      FROM   leaves AS l FULL OUTER JOIN generate_series(1, fanout) AS _(x) ON TRUE
    RETURNING category_id
    ),
    d AS (
      DELETE FROM leaves
      RETURNING *
    )
    INSERT INTO leaves
    SELECT id
    FROM   layer AS l;
  END LOOP;
END
$$ LANGUAGE PLPGSQL;

SELECT make_hierarchy(:FANOUT, :DEPTH);

WITH catids(id_arr) AS
(
  SELECT array_agg(category_id)
  FROM   category
),
ins AS
(
  INSERT INTO ITEM
  SELECT P.*, (SELECT id_arr[floor(random()*array_length(id_arr, 1)+1)::int]
               FROM catids
               WHERE P.P_PARTKEY = 1 OR P.P_PARTKEY <> 1)
  FROM   PART AS P
  RETURNING *
) TABLE ins;

ANALYZE category; ANALYZE ITEM;
