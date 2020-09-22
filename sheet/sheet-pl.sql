
-- Evaluate cell c in sheet, respecting all of the cell's depedencies
DROP FUNCTION IF EXISTS eval_cell(cell);
CREATE FUNCTION eval_cell(c cell) RETURNS float AS
$$
  DECLARE
    deps          cell[];
    open          jsonb[];
    expr          jsonb;
    formulae      jsonb[];
    args          arguments;
    cells         cell[];
    dep           cell;
    intermediates contents[];
    e             jsonb;
    rpn           jsonb[];
    exprs         jsonb[];
    root          jsonb;
    stack         float[];
  BEGIN
    -- ➊ compute ordered array of dependencies for cell c
    deps := array[c];
    expr := (SELECT s.formula
             FROM   sheet AS s
             WHERE  s.cell = c);
    open := array[expr];
    WHILE cardinality(open) > 0 LOOP
      expr := open[1];
      open := open[2:];

      IF    expr->>'entry' = 'num' THEN CONTINUE;

      ELSIF expr->>'entry' = 'op'  THEN
        formulae := (SELECT array_agg(f)
                     FROM   jsonb_array_elements(expr->'args') AS f);
        open     := open || formulae;

      ELSIF expr->>'entry' = 'agg' THEN
       args := (SELECT (array_agg(s.cell), array_agg(s.formula)) :: arguments
                FROM   sheet AS s
                WHERE  s.cell BETWEEN (expr->>'from') :: cell AND (expr->>'to') :: cell);
       deps := args.cells || deps;
       open := open || args.formulae;

      ELSIF expr->>'entry' = 'cell' THEN
        c    := (expr->>'cell') :: cell;
        deps := c || deps;
        expr := (SELECT s.formula
                 FROM   sheet AS s
                 WHERE  s.cell = c);
        open := open || expr;
      END IF;
    END LOOP;

    -- intermediate cell contents found during evaluation
    intermediates := array[] :: contents[];

    -- ➋ evaluate all relevant cells in dependency-order
    FOREACH dep IN ARRAY deps LOOP
      -- do not recompute known results
      IF EXISTS(SELECT 1
                FROM   unnest(intermediates) AS i(c,v)
                WHERE  i.c = dep) THEN CONTINUE;
      END IF;

      e := (SELECT s.formula
            FROM   sheet AS s
            WHERE  s.cell = dep);
      -- ➋.➊ transform expression tree into post-order
      rpn   := array[e];
      exprs := array[] :: jsonb[];
      WHILE cardinality(rpn) > 0 LOOP
        root  := rpn[1];
        rpn   := rpn[2:];
        exprs := root || exprs;
        IF    root->>'entry' = 'num'  THEN CONTINUE;
        ELSIF root->>'entry' = 'op'   THEN
          rpn := (SELECT array_agg(f)
                  FROM   jsonb_array_elements(root->'args') AS f) || rpn;
        ELSIF root->>'entry' = 'agg'  THEN CONTINUE;
        ELSIF root->>'entry' = 'cell' THEN CONTINUE;
        END IF;
      END LOOP;

      -- ➋.➋ evaluate post-order expression
      stack := array[] :: float[];
      FOREACH e in ARRAY exprs LOOP
        IF    e->>'entry' = 'num' THEN stack := (e->>'num') :: float || stack;
        ELSIF e->>'entry' = 'op'  THEN
          IF    e->>'op' = '+' THEN stack := (stack[1] + stack[2]) || stack[3:];
          ELSIF e->>'op' = '-' THEN stack := (stack[1] - stack[2]) || stack[3:];
          ELSIF e->>'op' = '*' THEN stack := (stack[1] * stack[2]) || stack[3:];
          ELSIF e->>'op' = '/' THEN stack := (stack[1] / stack[2]) || stack[3:];
          END IF;
        ELSIF e->>'entry' = 'agg'  THEN
          stack := (SELECT CASE e->>'agg'
                             WHEN 'sum' THEN SUM(i.v)
                             WHEN 'avg' THEN AVG(i.v)
                             WHEN 'max' THEN MAX(i.v)
                             WHEN 'min' THEN MIN(i.v)
                           END
                    FROM   unnest(intermediates) AS i(c,v)
                    WHERE  i.c BETWEEN (e->>'from') :: cell AND (e->>'to') :: cell) || stack;
        ELSIF e->>'entry' = 'cell' THEN
          stack := (SELECT i.v
                    FROM   unnest(intermediates) AS i(c,v)
                    WHERE  i.c = (e->>'cell') :: cell) || stack;
        END IF;
      END LOOP;

      -- ➌ save resulting cell value as intermediate result
      intermediates := intermediates || (dep, stack[1]) :: contents;

    END LOOP;

    -- ➍ final cell value found in top of stack after formula evaluation
    RETURN stack[1];
  END;
$$
LANGUAGE PLPGSQL;


-- Simple spreadsheet
--
-- Formulæ in cells may refer to each other.  The code below finds
-- dependencies between cells and iteratively evaluates the individual
-- cell formulæ in proper dependency order.

-- # of sheet evaluations (~ invocations)
\set N :invocations

-- depth (# of rows) of sheet (~ iterations due to the inter-dependencies of cells)
\set R (1+sqrt(:iterations)) :: int


-- Evaluate entire sheet
-- SELECT s.cell, s.formula, eval_cell(s.cell) AS value
-- FROM   sheet AS s;

-- Evaluate lower-right cell (D,:R+1) which will trigger
-- evaluation of the entire sheet
\timing on

SELECT eval_cell(('D', :R+1) :: cell)
FROM   generate_series(1, :N) AS _;
