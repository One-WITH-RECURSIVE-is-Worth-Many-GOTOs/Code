
DROP FUNCTION IF EXISTS schedule(int);
CREATE FUNCTION schedule(orderkey int) RETURNS scheduled[] AS
$$
  DECLARE
    "order"        orders;
    details        order_details;
    schedule_start date;         -- production of order must happen
    schedule_end   date;         --   between these dates
    schedule       scheduled[];  -- constructed schedule
    busy           daterange[];  -- when are we busy already?
    lineitem       lineitem;     -- current lineitem to schedule
    item_start     date;         -- production of current lineitem
    item_end       date;         --   happens between these dates
  BEGIN
    -- access order, bail out if order does not exist
    "order" := (SELECT o
                FROM   orders AS o
                WHERE  o.o_orderkey = orderkey);
    IF "order" IS NULL THEN
      RETURN NULL;
    END IF;

    details := (SELECT (COUNT(*), MAX(l.l_shipdate)) :: order_details
                FROM   lineitem AS l
                WHERE  l.l_orderkey = orderkey);

    -- lineitems need to be produced between these dates
    schedule_end   := details.last_shipdate;
    schedule_start := "order".o_orderdate;

    -- start with an empty schedule
    schedule := array[] :: scheduled[];

    -- we're not busy yet
    busy := array[] :: daterange[];

    FOR prio IN 1..details.items LOOP
       -- grab lineitem with given priority (~ l_extendedprice)
       lineitem := (SELECT l.lineitem
                    FROM   (SELECT ROW_NUMBER() OVER (ORDER BY p.p_retailprice DESC) AS priority, l AS lineitem
                            FROM   lineitem AS l, part AS p
                            WHERE  l.l_orderkey = orderkey
                            AND    l.l_partkey  = p.p_partkey) AS l(priority, lineitem)
                    WHERE  l.priority = prio);

       -- initially, try to produce lineitem as late as possible
       item_end   := LEAST(lineitem.l_shipdate, schedule_end);
       item_start := item_end - lineitem.l_quantity :: int;

       -- move production forward until we find a non-busy period or
       -- we learn that we cannot schedule the item in the available date range :-/
       WHILE daterange(item_start, item_end) && ANY(busy) AND item_start >= schedule_start LOOP
         item_end   := (SELECT lower(b)
                        FROM   unnest(busy) AS b
                        WHERE  daterange(item_start, item_end) && b
                        ORDER BY b
                        LIMIT 1);
         item_start := item_end - lineitem.l_quantity :: int;
       END LOOP;

       IF item_start >= schedule_start THEN
         -- succeeded to schedule
         schedule := schedule || (lineitem.l_linenumber, item_start) :: scheduled;
         busy     := busy || daterange(item_start, item_end);
       END IF;

    END LOOP;

    -- order schedule by item start date
    IF cardinality(schedule) > 0 THEN
      schedule := (SELECT array_agg(s ORDER BY s."when")
                   FROM   unnest(schedule) AS s);
    END IF;

    RETURN schedule;
  END;
$$
LANGUAGE PLPGSQL;


\timing on
-- Try to schedule all open orders (and indicate whether we will miss the production deadline)
SELECT o.o_orderkey,
       cardinality(res) < (SELECT MAX(l.l_linenumber)
                                              FROM   lineitem AS l
                                              WHERE  l.l_orderkey = o.o_orderkey) AS "miss?",
       res AS schedule
FROM   (SELECT *
        FROM orders
        ORDER BY o_orderkey
        LIMIT :invocations) AS o, LATERAL (SELECT schedule(o.o_orderkey)) AS _(res)
WHERE  o.o_orderstatus = 'O';
