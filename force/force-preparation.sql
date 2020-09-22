-- PL/SQL-based Barnes-Hut N-Body Simulation
-- (for a static set of bodies, separated by walls)
--
-- Uses SQL (WITH RECURSIVE) to compute the Barnes-Hut quad-tree
-- in table barneshut(node,bbox,parent,mass,center)
-- in which each quadrant is decorated with is total mass (mass)
-- and center point of mass (center). Points on opposite sides
-- of a wall do not affect each other.
--
-- Define aggregates, operations, comparisons on PostgreSQL points
\i points.sql


-- Overall containing area for all bodies
\set area box(point(0,0), point(1000,1000))


-- Number of bodies
\set N :iterations

-- Populate area with N random bodies
SELECT setseed(0.42);

DROP TABLE IF EXISTS bodies CASCADE;
CREATE TABLE bodies (pos point, mass float);

INSERT INTO bodies(pos, mass)
  SELECT point(width(:area) * random(),
               width(:area) * random()) AS pos,
         GREATEST(1.0, 10 * random()) AS mass
  FROM   generate_series(1, :N);

-- Number of walls
\set W :N / 100

-- Populate area with W random walls
SELECT setseed(0.42);

DROP TABLE IF EXISTS walls CASCADE;
CREATE TABLE walls (wall line);

INSERT INTO walls(wall)
  SELECT line(point(width(:area) * random(), width(:area) * random()),
              point(width(:area) * random(), width(:area) * random()))
  FROM   generate_series(1, :W);



-- Table barneshut(node, bbox, parent, mass, center) stores
-- the quad-tree.  Leaf nodes represent the bodies themselves.
--
-- node                     id of internal quad-tree node (NULL for bodies ≡ leaves)
-- bbox (box)               bounding box enclosed by this node (leaf: encloses body only)
-- parent (int)             parent node
-- mass (float)             aggregate mass of subtree below node (leaf: mass of body)
-- center (point)           weigthed center of mass of subtree below node (leaf: body position)

DROP TABLE IF EXISTS barneshut;
CREATE TABLE barneshut AS
  -- Build complete quad-tree for :area
  WITH RECURSIVE
    -- ➊ Construct inner nodes of quad-tree (top-down, starting from the root)
    skeleton(node, bbox, parent) AS (
      SELECT 0 AS node, :area AS bbox, NULL :: int AS parent
        UNION ALL
      SELECT n.*
      FROM   skeleton AS s,
             LATERAL (VALUES (center(s.bbox), width(s.bbox) / 2)) AS _(c,w),
             LATERAL (VALUES (s.node * 4 + 1, box(c, c + point( w, w)), s.node),
                             (s.node * 4 + 2, box(c, c + point(-w, w)), s.node),
                             (s.node * 4 + 3, box(c, c + point( w,-w)), s.node),
                             (s.node * 4 + 4, box(c, c + point(-w,-w)), s.node)) AS n(node,bbox,parent)
      -- create quad-tree node only if it indeed hosts more than one body
      WHERE (SELECT COUNT(*) FROM bodies AS b WHERE b.pos <@ n.bbox) >= 2
    ),
    -- ➋ Add bodies as quad-tree leaves (hanging off the inner nodes covering minimal area)
    quadtree(node, bbox, parent, mass) AS (
      SELECT s.node, s.bbox, s.parent, NULL :: float AS mass
      FROM   skeleton AS s
        UNION ALL                                           -- ⚠️ not recursive
      SELECT NULL AS node, box(b.pos, b.pos) AS bbox,
             (SELECT s.node
              FROM   skeleton AS s
              WHERE  b.pos <@ s.bbox
              -- if two bounding boxes overlap, place body b in node s with smaller ID
              ORDER BY area(s.bbox), s.node
              LIMIT 1) AS parent,
             b.mass AS mass
      FROM   bodies AS b
    ),
    -- ➌ Annotate all quad-tree nodes with their total mass and centre of mass (bottom-up)
    barneshut(node, bbox, parent, mass, center) AS (
      SELECT q.node, q.bbox, q.parent,
             q.mass,
             center(q.bbox) AS center
      FROM   quadtree AS q
      WHERE  q.node IS NULL      -- ≡ is q a leaf?
        UNION ALL
      SELECT DISTINCT ON (q.node) q.node, q.bbox, q.parent,
             SUM(b.mass) OVER (PARTITION BY q.node) AS mass,  -- ─────────────────────────────────── ≡ mass
             SUM(b.mass * b.center) OVER (PARTITION BY q.node) / SUM(b.mass) OVER (PARTITION BY q.node) AS center -- ⧆
      FROM   quadtree AS q, barneshut AS b
      WHERE  q.node = b.parent
    )
    SELECT b.node, b.bbox, b.parent,
           SUM(b.mass) AS mass,
           SUM(b.mass * b.center) / SUM(b.mass) AS center -- ⧆
    FROM   barneshut AS b
    GROUP BY b.node, b.bbox, b.parent, center(b.bbox);
    --                                      🠵
    --              additional grouping criterion to differentiate
    --              between leaf bounding boxes below the same parent
    --              (PostgreSQL considers any two boxes of width 0
    --               to be equal, no matter what their center point is)

-----------------------------------------------------------------------

DROP INDEX IF EXISTS barneshut_parent;
CREATE INDEX barneshut_parent ON barneshut USING btree (parent);
ANALYZE barneshut;
