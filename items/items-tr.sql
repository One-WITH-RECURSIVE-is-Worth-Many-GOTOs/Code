
\timing on

SELECT *
FROM category, LATERAL (SELECT category_id AS catid) AS _(catid)
WHERE
  (WITH :MODE run("rec?", "res", "catid", "stack", "totalcount") AS
    (
        SELECT True, NULL :: int8, "catid", ARRAY["catid"] :: int8[] AS "stack_1", 0 :: INT8 AS "totalcount_1"
          UNION ALL
        (SELECT "result".*
         FROM run AS "run"("rec?", "res", "catid", "stack", "totalcount"),
              LATERAL
              (SELECT "ifresult4".*
               FROM (LATERAL
                     (SELECT (cardinality("stack")) > 0 AS "pred_2") AS "let3"("pred_2")
                     LEFT OUTER JOIN
                     LATERAL
                     ((SELECT True,
                              NULL :: int8,
                              "catid",
                              (SELECT array_agg(("RTE1"."category_id") :: int8) AS "array_agg"
                                           FROM category AS "RTE1"("category_id", "parent_category")
                                           WHERE "RTE1"."parent_category" = "curcat_3") || "stack_4" AS "stack_5",
                              "totalcount" + "catitems_3" AS "totalcount_4"
                       FROM (LATERAL
                             (SELECT ("stack")[1] AS "curcat_3") AS "let5"("curcat_3")
                             LEFT OUTER JOIN
                             (LATERAL (SELECT ("stack")[2:] AS "stack_4") AS "let6"("stack_4")
                              LEFT OUTER JOIN
                              LATERAL
                               (SELECT count("RTE0"."p_partkey") AS "count"
                                FROM item AS "RTE0"
                                WHERE "RTE0"."category_id" = "curcat_3") AS "let7"("catitems_3")
                              ON True)
                             ON True)
                       WHERE NOT "pred_2" IS DISTINCT FROM True)
                        UNION ALL
                      (SELECT False,
                              "totalcount" AS "result",
                              "run"."catid",
                              "run"."stack",
                              "run"."totalcount"
                       WHERE "pred_2" IS DISTINCT FROM True)
                     ) AS "ifresult4"
                     ON True)
              ) AS "result"
         WHERE "run"."rec?")
    )
    SELECT "run"."res" AS "res"
    FROM run AS "run"
    WHERE NOT "run"."rec?"
    ) > 1;