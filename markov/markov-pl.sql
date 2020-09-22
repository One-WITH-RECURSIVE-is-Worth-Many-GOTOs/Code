
-- Robot walk setup
\set robots :invocations -- How many robots
\set success_at ( :iterations * (5.0/6)) :: int -- where success_at > 0
\set failure_at (-:iterations * (3.0/4)) :: int -- where failure_at < 0
\set max_steps :iterations

DROP FUNCTION walk(int, int, int, int);
CREATE FUNCTION walk(start_state int, success_at int, failure_at int, max_steps int)
RETURNS int AS $$
DECLARE
  total_reward int = 0;
  curr_state int = start_state;
  curr_action text = '';
  roll double precision;
BEGIN
  FOR steps in 1..max_steps LOOP
    -- Find the action the policy finds appropriate in the current state
    curr_action = (
      SELECT p.action_name
      FROM   policy AS p, states AS s
      WHERE  curr_state = s.id
      AND    p.state_id = s.id
    );
    -- Random number (double precision) roll ∈ [0.0, 1.0)
    roll = random();
    -- Find the state we actually reach. There may be a chance we end up in another state.
    curr_state = (
      SELECT possible_move.s_to
        FROM (
          SELECT a.s_to,
          COALESCE(SUM(a.p) OVER (ORDER BY a.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0.0) AS p_from,
          SUM(a.p) OVER (ORDER BY a.id) AS p_to
          FROM  actions AS a
          WHERE curr_state  = a.s_from
          AND   curr_action = a.name
        ) AS possible_move(s_to, p_from, p_to)
      WHERE possible_move.p_from <= roll AND roll < possible_move.p_to
    );
    -- Add the reward we receive by stepping on the state we actually reached
    total_reward = total_reward + (
      SELECT s.r
      FROM   states AS s
      WHERE  curr_state = s.id
    );
    IF total_reward >= success_at OR total_reward <= failure_at THEN
      RETURN steps * sign(total_reward);
    END IF;
  END LOOP;
  RETURN 0;
END
$$ LANGUAGE PLPGSQL;

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
    LATERAL (SELECT walk(s.id, :success_at, :failure_at, :max_steps)) AS __(steps)
) AS comp
GROUP BY comp.result
ORDER BY comp.result;
