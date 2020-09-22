-- Optimize the supply chain for the given order
DROP FUNCTION IF EXISTS savings(int);
CREATE FUNCTION savings(orderkey int) RETURNS savings AS
$$
  DECLARE
    "order"          orders;
    items            int;
    lineitem         lineitem;
    partsupp         partsupp;
    min_supplycost   numeric(15,2);
    new_supplier     int;
    new_suppliers    supplier_change[];
    total_supplycost numeric(15,2);
    new_supplycost   numeric(15,2);
  BEGIN
    "order" := (SELECT o
                FROM   orders AS o
                WHERE  o.o_orderkey = orderkey);
    IF "order" IS NULL THEN
      RETURN NULL;
    END IF;

    -- # of lineitems (= parts) in order
    items := (SELECT COUNT(*)
              FROM   lineitem AS l
              WHERE  l.l_orderkey = orderkey);

    total_supplycost := 0.0;
    new_supplycost   := 0.0;
    new_suppliers    := array[] :: supplier_change[];

    -- iterate over all lineitems in order
    FOR item IN 1..items LOOP
      -- pick current lineitem in order
      lineitem := (SELECT l
                   FROM   lineitem AS l
                   WHERE  l.l_orderkey = orderkey AND l.l_linenumber = item);
      -- find current supplier for lineitem's part
      partsupp := (SELECT ps
                   FROM   partsupp AS ps
                   WHERE  lineitem.l_partkey = ps.ps_partkey AND lineitem.l_suppkey = ps.ps_suppkey);

      -- find minimum supplycost (for ANY supplier that has sufficient stock) for the lineitem's part
      min_supplycost := (SELECT MIN(ps.ps_supplycost)
                         FROM   partsupp AS ps
                         WHERE  ps.ps_partkey = lineitem.l_partkey
                         AND    ps.ps_availqty >= lineitem.l_quantity);

      -- new supplier with minimum supplycost
      new_supplier := (SELECT MIN(ps.ps_suppkey)
                       FROM   partsupp AS ps
                       WHERE  ps.ps_supplycost = min_supplycost
                       AND    ps.ps_partkey = lineitem.l_partkey);

      -- record whether supplier has changed (part, old, new)
      IF new_supplier <> partsupp.ps_suppkey THEN
        new_suppliers := (lineitem.l_partkey, partsupp.ps_suppkey, new_supplier) :: supplier_change || new_suppliers;
      END IF;

      -- total supplycost of original and new supplier
      total_supplycost := total_supplycost + partsupp.ps_supplycost * lineitem.l_quantity;
      new_supplycost   := new_supplycost   + min_supplycost         * lineitem.l_quantity;
    END LOOP;

    RETURN ((1.0 - new_supplycost / total_supplycost) * 100.0, new_suppliers) :: savings;
  END;
$$
LANGUAGE PLPGSQL;


\timing on

-- Optimize the supply chain for all open orders
SELECT o.o_orderkey, savings(o.o_orderkey) AS "supply chain changes"
FROM   (SELECT *
        FROM orders
        ORDER BY o_orderkey
        LIMIT :invocations) AS o
WHERE  o.o_orderstatus = 'O';
