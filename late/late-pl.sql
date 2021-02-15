-- A PL/SQL re-implementation of TPC-H query Q21
-- (given a supplier, find the number of orders that were shipped late
--  because of this particular supplier)

DROP FUNCTION order_kept_waiting(int,int);
CREATE FUNCTION order_kept_waiting(suppkey int, orderkey int) RETURNS boolean AS
$$
  DECLARE
    lis   lineitem[];
    li    lineitem;
    blame boolean := false; -- is suppkey to blame?
    multi boolean := false; -- does this order have multiple suppliers?
  BEGIN
    lis := (SELECT array_agg(l)
            FROM   lineitem AS l
            WHERE  l.l_orderkey = orderkey);
    FOREACH li IN ARRAY lis LOOP
      multi := multi OR li.l_suppkey <> suppkey;
      IF li.l_receiptdate > li.l_commitdate THEN
          IF li.l_suppkey <> suppkey THEN
            RETURN false;
          ELSE
            blame := true;
          END IF;
      END IF;
    END LOOP;
    RETURN multi AND blame;
  END;
$$
LANGUAGE PLPGSQL;


\timing on

SELECT s.s_name, COUNT(*) AS numwait
FROM   supplier AS s, nation AS n, (SELECT *
                                    FROM orders
                                    WHERE o_orderstatus = 'F'
                                    ORDER BY o_orderkey
                                    LIMIT :invocations) AS o
WHERE  o.o_orderstatus = 'F'
AND    s.s_nationkey = n.n_nationkey AND n.n_name = 'GERMANY'
AND    order_kept_waiting(s.s_suppkey, o.o_orderkey)
GROUP BY s.s_name
ORDER BY numwait DESC, s_name;
