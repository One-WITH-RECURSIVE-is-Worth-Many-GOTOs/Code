-- SELECT setseed(0.2);

-- Randomly create a width x height board with rewards and walls for the robot to move around on
\set width 10
\set height 10
\set inaccessible_squares 10
\set point_range Point(-2.0, 2.0) -- [x,y)

DROP FUNCTION IF EXISTS mdp();
DROP TABLE IF EXISTS actions CASCADE;
DROP TABLE IF EXISTS policy CASCADE;
DROP TABLE IF EXISTS states CASCADE;
DROP TABLE IF EXISTS utility CASCADE;

-- A state with a name and a reward
CREATE TABLE states (
  id INT PRIMARY KEY,
  name TEXT,
  r numeric
);

-- Each action is identified by its name and state it can be done from. The key, however, is an INT column "id"
CREATE TABLE actions (
  id SERIAL PRIMARY KEY,
  name TEXT,
  s_from INT REFERENCES states(id),
  s_to INT REFERENCES states(id),
  p numeric CHECK (actions.p BETWEEN 0.0 AND 1.0)
);

-- The policy describing the one action to do (by name) in a given state state_id
CREATE TABLE policy (
  state_id INT REFERENCES states(id),
  action_name TEXT
);

-- The utility holding the predicted reward v in a given state state_id
CREATE TABLE utility (
  state_id INT,
  v numeric
);

INSERT INTO states (
  SELECT ROW_NUMBER() OVER (),
    '(' || gs_x.v || ',' || gs_y.v || ')',
    FLOOR(random() * (ABS((:point_range)[0]) + ABS((:point_range)[1])) + ((:point_range)[0]))
  FROM generate_series(0, :width - 1) AS gs_x(v),
       generate_series(0, :height - 1) AS gs_y(v)
);

--UPDATE states AS s
--SET r = CASE WHEN random() < 0.5 THEN 1 ELSE -1 END
--WHERE s.r = 0;

DROP TABLE IF EXISTS walls CASCADE;
CREATE TEMP TABLE walls AS (
  SELECT s.id, s.name, NULL AS r
  FROM states AS s, (
    SELECT FLOOR(random() * (:width * :height)) + 1
    FROM generate_series(1, :inaccessible_squares) AS gs(v)
  ) AS inaccessible(id)
  WHERE s.id = inaccessible.id
);

DELETE FROM states
USING (
  SELECT w.id
  FROM walls AS w
) AS inaccessible(id)
WHERE inaccessible.id = states.id;

-- Initialize the actions and their possible outcomes.
-- Here: The robot can try to move either ↑, ↓, ← or →.
-- There is a 80% chance this succeeds.
-- Otherwise, it fails by steering either 90° to the left (10%) or 90° to the right (10%).
-- If the robot reaches 's', it stops there accumulating that field's reward indefinitely
INSERT INTO actions(name, s_from, s_to, p) (
  SELECT a.name, a.s_from, a.s_to, SUM(a.p) AS p
  FROM (
    SELECT d.v, current_s.id,
      CASE
      WHEN NOT EXISTS(
              SELECT NULL FROM states AS s WHERE s.name = '(' || (x.v + d.dx) || ',' || (y.v + d.dy) || ')'
      ) THEN current_s.id
        ELSE (SELECT s.id FROM states AS s WHERE s.name = '(' || (x.v + d.dx) || ',' || (y.v + d.dy) || ')')
    END, d.p
    FROM generate_series(0, :width - 1) AS x(v),
      generate_series(0, :height - 1) AS y(v),
      (VALUES
        ('↑', 0.8,0,-1),('↑', 0.1,-1,0),('↑', 0.1,+1,0),
        ('↓', 0.8,0,+1),('↓', 0.1,-1,0),('↓', 0.1,+1,0),
        ('←', 0.8,-1,0),('←', 0.1,0,-1),('←', 0.1,0,+1),
        ('→', 0.8,+1,0),('→', 0.1,0,-1),('→', 0.1,0,+1)
      ) AS d(v,p,dx,dy),
      LATERAL(
        SELECT s.id FROM states AS s WHERE s.name = '(' || x.v || ',' || y.v || ')'
      ) AS current_s
    ) AS a(name, s_from, s_to, p)
  GROUP BY a.s_from, a.name, a.s_to
);

-- Initialize policy
INSERT INTO policy (
  SELECT s.ID, '↑'
  FROM states AS s
);

-- Initialize utility
INSERT INTO utility
SELECT s.id, s.r + res.sum
FROM states AS s, (
  SELECT a.s_from, SUM(a.p * s_to.r) AS sum
  FROM states AS s_from, states AS s_to, actions AS a, policy AS p
  WHERE s_from.id = a.s_from
  AND   s_from.id = p.state_id
  AND   a.name = p.action_name
  AND   s_to.id = a.s_to
  GROUP BY a.s_from
) AS res(s_from, sum)
WHERE s.id = res.s_from;

-- Original function (policy iteration variant)
CREATE FUNCTION mdp() RETURNS void AS $$
DECLARE
  done boolean = false;
BEGIN
  DROP TABLE IF EXISTS prev_policy CASCADE;
  CREATE TEMP TABLE prev_policy (
    state_id INT PRIMARY KEY,
    action_name TEXT
  );

  INSERT INTO prev_policy (TABLE policy);

  LOOP
    -- Keep current policy
    UPDATE prev_policy AS p
    SET action_name = p_.action_name
    FROM policy AS p_
    WHERE p.state_id = p_.state_id;

    -- Calculate the new utility from the given current policy and utility.
    --
    -- This is the value determination in the modified policy iteration [Puterman & Shin, 1978].
    -- Specifically: Fixed number approximation with n = 1.
    -- Alternatively: Write a fixed number approximation with n > 1,
    -- dynamic number approximation or stabilizing utility values.
    UPDATE utility AS u
    SET v = u_.v
    FROM (
      SELECT s.id, s.r + res.sum
      FROM states AS s, (
        SELECT a.s_from, SUM(a.p * u.v) AS sum
        FROM states AS s_from, states AS s_to, actions AS a, policy AS p, utility AS u
        WHERE s_from.id = a.s_from
        AND   s_from.id = u.state_id
        AND   a.name = p.action_name
        AND   s_to.id = a.s_to
        AND   u.state_id = a.s_to
        GROUP BY a.s_from
      ) AS res(s_from, sum)
      WHERE s.id = res.s_from
    ) AS u_(state_id, v)
    WHERE u.state_id = u_.state_id;

    -- Update policy based on the new utilities
    UPDATE policy AS p
    SET action_name = p_.action_name
    FROM (
      SELECT s.id, next_actions.name
      FROM (SELECT * FROM states) AS s, LATERAL (
        SELECT ar.name
        FROM (
          SELECT a.name, SUM(a.p * u.v) AS v
          FROM actions AS a, utility AS u
          WHERE    s.id = a.s_from
          AND      u.state_id = a.s_to
          GROUP BY a.s_from, a.name
        ) AS ar
        ORDER BY ar.v DESC
        LIMIT 1
      ) AS next_actions
    ) AS p_(state_id, action_name)
    WHERE p.state_id = p_.state_id;

    -- If previous policy is the same as the current policy, the approximation of the most optimal policy is done.
    EXIT WHEN NOT EXISTS (TABLE prev_policy EXCEPT TABLE policy);
  END LOOP;

END $$ LANGUAGE PLPGSQL;

SELECT mdp(); -- Calculate markov decision process

-- Print the rewards in each square
SELECT (mdp.s_name :: Point)[1] AS " ", array_to_string(ARRAY_AGG(mdp.r ORDER BY (mdp.s_name :: Point)[0]), '|', ' #') AS rewards
FROM (
  SELECT s.id AS "state id", s.name AS "state name", lpad(s.r :: TEXT, '2', ' ')
  FROM states AS s
    UNION
  SELECT w.id, w.name, NULL
  FROM walls AS w
) AS mdp(id, s_name, r)
GROUP BY (mdp.s_name :: Point)[1]
  UNION
SELECT NULL AS row, STRING_AGG(lpad(gs.v :: TEXT, '2', ' '), ' ')
FROM generate_series(0,:width - 1) AS gs(v)
ORDER BY " " NULLS FIRST;

-- Print policy in a grid
SELECT (mdp.s_name :: Point)[1] AS " ", array_to_string(ARRAY_AGG(mdp.a_name ORDER BY (mdp.s_name :: Point)[0]), '|', '#') AS policy
FROM (
  SELECT s.id AS "state id", s.name AS "state name", p.action_name AS "optimal action"
  FROM policy AS p, states AS s
  WHERE p.state_id = s.id
    UNION
  SELECT w.id, w.name, NULL
  FROM walls AS w
) AS mdp(id, s_name, a_name)
GROUP BY (mdp.s_name :: Point)[1]
  UNION
SELECT NULL AS row, STRING_AGG(gs.v :: TEXT, ' ')
FROM generate_series(0,:width - 1) AS gs(v)
ORDER BY " " NULLS FIRST;
