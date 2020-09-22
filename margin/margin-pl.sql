
-- find trade that will yield the best possible margin
-- for the part partkey
DROP FUNCTION IF EXISTS margin(int);
CREATE FUNCTION margin(partkey int) RETURNS trade AS
$$
  DECLARE
    this_order dated_order;
    buy            int           := NULL;
    sell           int           := NULL;
    margin         numeric(15,2) := NULL;
    cheapest       numeric(15,2) := NULL;
    cheapest_order int;
    price          numeric(15,2);
    profit         numeric(15,2);
  BEGIN
    -- ➊ first order for the given part
    this_order := (SELECT (o.o_orderkey, o.o_orderdate) :: dated_order
                   FROM   lineitem AS l, orders AS o
                   WHERE  l.l_orderkey = o.o_orderkey
                   AND    l.l_partkey  = partkey
                   ORDER BY o.o_orderdate
                   LIMIT 1);

    -- hunt for the best margin while there are more orders to consider
    WHILE this_order IS NOT NULL LOOP
      -- ➋ price of part in this order
      price := (SELECT MIN(l.l_extendedprice * (1 - l.l_discount) * (1 + l.l_tax))
                FROM   lineitem AS l
                WHERE  l.l_orderkey = this_order.orderkey
                AND    l.l_partkey  = partkey);

      -- if this the new cheapest price, remember it
      cheapest := COALESCE(cheapest, price);
      IF price <= cheapest THEN
        cheapest       := price;
        cheapest_order := this_order.orderkey;
      END IF;
      -- compute current obtainable margin
      profit := price - cheapest;
      margin := COALESCE(margin, profit);
      IF profit >= margin THEN
        buy    := cheapest_order;
        sell   := this_order.orderkey;
        margin := profit;
      END IF;

      -- ➌ find next order (if any) that traded the part
      this_order := (SELECT (o.o_orderkey, o.o_orderdate) :: dated_order
                     FROM   lineitem AS l, orders AS o
                     WHERE  l.l_orderkey = o.o_orderkey
                     AND    l.l_partkey  = partkey
                     AND    o.o_orderdate > this_order.orderdate
                     ORDER BY o.o_orderdate
                     LIMIT 1);
    END LOOP;

    RETURN (buy, sell, margin) :: trade;
  END;
$$
LANGUAGE PLPGSQL;


\timing on

-- compute margins for these parts in the TPC-H instance
SELECT p.p_partkey, p.p_name, margin(p.p_partkey) AS margin
FROM   (SELECT * FROM part ORDER BY p_partkey ASC
        LIMIT :invocations) AS p
;

