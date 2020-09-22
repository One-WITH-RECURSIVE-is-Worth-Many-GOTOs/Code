
-- Robot walk setup
\set robots :invocations -- How many robots
\set success_at ( :iterations * (5.0/6)) :: int -- where success_at > 0
\set failure_at (-:iterations * (3.0/4)) :: int -- where failure_at < 0
\set max_steps :iterations

SELECT setseed(0.42);

\timing on
SELECT comp.result, COUNT(*)
FROM (
  SELECT
    i           AS robot,
    s.name      AS "start state name",
    s.id        AS "state id",
    :success_at AS "success at",
    :failure_at AS "failure at",
    CASE WHEN sign(steps) = 1 THEN 'success' WHEN sign(steps) = -1 THEN 'failure' ELSE 'draw' END AS result,
    CASE WHEN steps = 0 THEN :max_steps+1 ELSE abs(steps) END AS steps
  FROM (SELECT i, random() FROM generate_series(1,:robots) AS i) AS _(i, roll),
    LATERAL (
      SELECT s.name, s.id
      FROM   states AS s
      OFFSET floor(roll*(SELECT COUNT(*) from states))
      LIMIT  1
    ) AS s,
    LATERAL (SELECT s.id, :success_at, :failure_at, :max_steps) AS params(start_state, success_at, failure_at, max_steps),
    LATERAL
    (
    WITH :MODE run("rec?",
                   "res",
                   "curr_state",
                   "steps",
                   "total_reward") AS
    (
        SELECT True,
               NULL :: int4,
               "start_state" AS "curr_state_1",
               (SELECT 1 AS "?column?"),
               0 AS "total_reward_1"
          UNION ALL
        (SELECT "result".*
         FROM run AS "run"("rec?",
                           "res",
                           "curr_state",
                           "steps",
                           "total_reward"),
              LATERAL
              (SELECT "ifresult2".*
               FROM (LATERAL
                      (SELECT "steps" <= "max_steps" AS "pred_2") AS "let1"("pred_2")
                      LEFT OUTER JOIN
                      LATERAL
                      ((SELECT "ifresult8".*
                        FROM (LATERAL
                              (SELECT "RTE0"."action_name" AS "curr_action_4"
                                       FROM policy AS "RTE0"("state_id", "action_name"),
                                            states AS "RTE1"("id", "name", "r")
                                       WHERE ("curr_state" = "RTE1"."id"
                                              AND
                                              "RTE0"."state_id" = "RTE1"."id")
                              ) AS "let3"("curr_action_4")
                              LEFT OUTER JOIN
                              (LATERAL
                               (SELECT random() AS "roll_3") AS "let4"("roll_3")
                               LEFT OUTER JOIN
                               (LATERAL
                                (SELECT "subquery3"."s_to" AS "curr_state_4"
                                         FROM (SELECT "RTE2"."s_to" AS "s_to",
                                                      COALESCE(sum("RTE2"."p") OVER(ORDER BY ("RTE2"."id") ASC ROWS BETWEEN
                                                                                    UNBOUNDED PRECEDING
                                                                                    AND
                                                                                    1 PRECEDING),
                                                               0.0) AS "p_from",
                                                      sum("RTE2"."p") OVER(ORDER BY ("RTE2"."id") ASC RANGE UNBOUNDED PRECEDING) AS "p_to"
                                               FROM actions AS "RTE2"("id",
                                                                      "name",
                                                                      "s_from",
                                                                      "s_to",
                                                                      "p")
                                               WHERE ("curr_state" = "RTE2"."s_from"
                                                      AND
                                                      "curr_action_4" = "RTE2"."name")
                                              ) AS "subquery3"("s_to", "p_from", "p_to")
                                         WHERE (("subquery3"."p_from") <= "roll_3"
                                                AND
                                                "roll_3" < ("subquery3"."p_to"))
                                ) AS "let5"("curr_state_4")
                                LEFT OUTER JOIN
                                (LATERAL
                                 (SELECT ("total_reward")
                                         +
                                         ((SELECT "RTE4"."r" AS "r"
                                           FROM states AS "RTE4"("id", "name", "r")
                                           WHERE "curr_state_4" = "RTE4"."id")) AS "total_reward_4"
                                 ) AS "let6"("total_reward_4")
                                 LEFT OUTER JOIN
                                 (LATERAL
                                  (SELECT ("total_reward_4" >= "success_at" OR "total_reward_4" <= "failure_at") AS "q6_3"
                                  ) AS "let7"("q6_3")
                                  LEFT OUTER JOIN
                                  LATERAL
                                  ((SELECT False,
                                           ("steps") * (sign("total_reward_4")) :: int4 AS "result",
                                           "run"."curr_state",
                                           "run"."steps",
                                           "run"."total_reward" :: int4
                                    WHERE "q6_3")
                                     UNION ALL
                                   (SELECT True,
                                           NULL :: int4,
                                           "curr_state_4",
                                           "steps" + 1 AS "steps_5",
                                           "total_reward_4" :: int4
                                    WHERE NOT "q6_3")
                                  ) AS "ifresult8"
                                  ON True)
                                 ON True)
                                ON True)
                               ON True)
                              ON True)
                        WHERE "pred_2")
                         UNION ALL
                       (SELECT False,
                               0 :: int4 AS "result",
                               "run"."curr_state",
                               "run"."steps",
                               "run"."total_reward" :: int4
                        WHERE NOT "pred_2")
                      ) AS "ifresult2"
                      ON True)
              ) AS "result"
         WHERE "run"."rec?" = True)
    )
    SELECT "run"."res" AS "res"
    FROM run AS "run"
    WHERE "run"."rec?" = False
    ) AS __(steps)
) AS comp
GROUP BY comp.result
ORDER BY comp.result;
\timing off

