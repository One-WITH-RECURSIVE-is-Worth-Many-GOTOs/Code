-- PL/SQL function that find's a good packing of an order's lineitems
-- into containers of specified size.  Assumes a TPC-H database instance.
-- Uses bit sets to represents sets of lineitems in a pack.

DROP DOMAIN IF EXISTS linenumber CASCADE;
CREATE DOMAIN linenumber AS int;

-- Pack the lineitems of order orderkey into several packs of which each
-- has a maximum size of capacity:
DROP FUNCTION IF EXISTS pack(int, int);
CREATE FUNCTION pack(orderkey int, capacity int) RETURNS linenumber[][] AS
$$
  DECLARE
    n          int;            -- # of lineitems in order
    items      int;            -- set of lineitems still to pack
    size       int;            -- current pack size
    subset     int;            -- current subset of lineitems considered for a pack
    max_size   int;            -- maximum pack size found so far
    max_subset int;            -- pack subset of maximum size found so far
    pack       linenumber[];   -- current pack
    packs      linenumber[][]; -- current pack of packs
  BEGIN
    -- # of lineitems in order
    n := (SELECT COUNT(*)
          FROM   lineitem AS l
          WHERE  l.l_orderkey = orderkey);
    -- order key not found?
    IF n = 0 THEN
      RETURN array[] :: int[][];
    END IF;

    -- container capacity sufficient to hold largest part?
    IF capacity < (SELECT MAX(p.p_size)
                   FROM   lineitem AS l, part AS p
                   WHERE  l.l_orderkey = orderkey
                   AND    l.l_partkey = p.p_partkey) THEN
      RETURN array[] :: int[][];
    END IF;

    -- initialize empty pack of packs
    packs := array[] :: linenumber[][];
    -- create full set of linenumbers {1,2,...,n}
    items := 2^n - 1;

    -- as long as there are still lineitems to pack...
    WHILE items <> 0 LOOP
      max_size   := 0;
      max_subset := 0;  -- ∅
      -- iterate through all non-empty subsets of items
      subset := items & -items;
      LOOP
         -- find size of current lineitem subset o
         size := (SELECT SUM(p.p_size)
                  FROM   lineitem AS l, part AS p
                  WHERE  l.l_orderkey = orderkey
                  AND    subset & (1 << l.l_linenumber - 1) <> 0
                  AND    l.l_partkey = p.p_partkey);

         if size <= capacity AND size > max_size THEN
           max_size   := size;
           max_subset := subset;
         END IF;
         -- exit if iterated through all lineitem subsets ...
         IF subset = items THEN
           EXIT;
         ELSE
           -- ... else, consider next lineitem subset
           subset := items & (subset - items);
         END IF;
      END LOOP;

      -- convert bit set max_subset into set of linenumbers
      pack := array[] :: linenumber[];
      FOR linenumber IN 1..n LOOP
        IF max_subset & (1 << linenumber - 1) <> 0 THEN
          pack := pack || linenumber :: linenumber;
        ELSE
          pack := pack || 0 :: linenumber; -- 0 ≡ lineitem not in set
        END IF;
      END LOOP;
      -- add pack to current packing
      packs := packs || array[pack];

      -- we've selected lineitems in set max_subset,
      -- update items to remove these lineitems
      items := items & ~max_subset;
    END LOOP;

    RETURN packs;
  END;
$$
LANGUAGE PLPGSQL;


-- maximum size of one pack
\set CAPACITY 60

\timing on
-- pack all finished orders
SELECT o.o_orderkey, pack(o.o_orderkey, :CAPACITY) AS packs
FROM   (SELECT *
        FROM orders
        ORDER BY o_orderkey
        LIMIT :invocations ) AS o
WHERE  o.o_orderstatus = 'F';
