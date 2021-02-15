-- Decide whether a given order has to endure long-distance shipping
-- (since its parts stem from different regions of the world)
--
-- This is equivalent to a SQL query of the following form:
--
--   SELECT l.l_orderkey, COUNT(DISTINCT n.n_regionkey) > 1 AS "long_distance?"
--   FROM   lineitem AS l, supplier AS s, nation AS n
--   WHERE  l.l_suppkey = s.s_suppkey AND s.s_nationkey = n.n_nationkey
--   GROUP BY l.l_orderkey;

DROP FUNCTION IF EXISTS long_distance(int);
CREATE FUNCTION long_distance(orderkey int) RETURNS boolean AS
$$
  DECLARE
    regions int[];
    region  int;
  BEGIN
    regions := (SELECT array_agg(n.n_regionkey)
                FROM   lineitem AS l, supplier AS s, nation AS n
                WHERE  l.l_orderkey = orderkey
                AND    l.l_suppkey  = s.s_suppkey AND s.s_nationkey = n.n_nationkey);

    FOREACH region IN ARRAY regions LOOP
      IF region <> regions[1] THEN RETURN true;
      END IF;
    END LOOP;

    RETURN false;
  END;
$$
LANGUAGE PLPGSQL;

\timing on
-- Check long-distance shipping requirements for all line items
SELECT l.l_orderkey, long_distance(l.l_orderkey) "long_distance?"
FROM   (SELECT *
        FROM   lineitem
        ORDER BY l_orderkey
        LIMIT :invocations) AS l
GROUP  BY l.l_orderkey;

