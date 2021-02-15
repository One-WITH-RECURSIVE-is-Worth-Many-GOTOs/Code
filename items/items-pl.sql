
\timing on

SELECT *
FROM category
WHERE count_items(category_id) > 1;