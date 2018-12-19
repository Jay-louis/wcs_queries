
-- determine items that have a demand greater than the quantity available in the pickmod and insert into a temptable
SELECT m.item_number, m.shopify_product_variant_id as vid,  Coalesce(SUM(d.demand), 0) - Coalesce(SUM(t.total), 0) AS q INTO #TMP_REPLEN FROM t_item_master m with(NOLOCK)
LEFT OUTER JOIN(SELECT item_number, SUM(ord.qty) AS 'demand' FROM t_order_detail ord with(NOLOCK) INNER JOIN t_order orm with(NOLOCK) ON orm.order_number = ord.order_number WHERE orm.status IN('AUTOFAIL','IMPORTED','RATEFAIL','RATING','RELEASED')
--AND orm.order_date < '2018-12-10'
GROUP BY item_number) d
ON d.item_number = m.item_number
LEFT OUTER JOIN(SELECT item_number, SUM(actual_qty) AS 'total' FROM t_stored_item with(NOLOCK) WHERE type = '0' AND (location_id LIKE 'AA%' OR location_id LIKE 'AB%' OR location_id LIKE 'AC%') AND actual_qty > 0 AND status = 'A' GROUP BY item_number) t
ON m.item_number = t.item_number
GROUP BY m.item_master_id, m.item_number, m.shopify_product_variant_id
HAVING Coalesce(SUM(d.demand), 0) - Coalesce(SUM(t.total), 0) > 0
ORDER BY m.shopify_product_variant_id,m.item_master_id
--SELECT COUNT(*) FROM #TMP_REPLEN
--8217
--Using the list of items in the temptable to gather a list of all LP's in bulk for these items
 SELECT sto.location_id
	, sto.hu_id
	, sto.item_number
	, sto.actual_qty
    , itm.style
    , itm.color
    , itm.size
    , CASE WHEN sto.location_id LIKE 'BS%' THEN 'SFS'
            WHEN sto.location_id LIKE 'SC%' OR sto.location_id LIKE 'SV%' THEN 'SEVILLE'
            WHEN sto.location_id LIKE 'A-%' OR sto.location_id LIKE 'M-%' OR sto.location_id LIKE 'C-%' THEN 'VERNON'
            ELSE 'SEVILLE' END AS 'BUILDING'
    ,ROW_NUMBER ()
    OVER ( PARTITION BY sto.item_number ORDER BY sto.item_number DESC, sto.location_id ASC ) AS 'rowNumber'
    ,t.q AS 'totalNeed'
    INTO #TMP_REPLEN1
    FROM t_stored_item sto with(NOLOCK)
    INNER JOIN t_location loc with(NOLOCK) ON loc.location_id = sto.location_id
    INNER JOIN #TMP_REPLEN t ON t.item_number = sto.item_number
    LEFT OUTER JOIN t_item_master itm with(NOLOCK) ON itm.item_number = sto.item_number
    WHERE loc.type = 'M'
	AND loc.location_id <> 'T100'
	AND loc.location_id NOT LIKE 'Z%'
    AND sto.hu_id LIKE 'LP%'
    GROUP BY sto.item_number,  sto.actual_qty,sto.hu_id, sto.hu_id, itm.style, itm.color, itm.size, sto.location_id
     , CASE WHEN (sto.location_id LIKE 'BS%' OR sto.location_id LIKE 'REC%' OR sto.location_id LIKE 'RCV%' OR sto.location_id LIKE 'ITM%') THEN 'SFS'
            WHEN sto.location_id LIKE 'SC%' OR sto.location_id LIKE 'SV%' THEN 'SEVILLE'
            WHEN sto.location_id LIKE 'A-%' OR sto.location_id LIKE 'M-%' OR sto.location_id LIKE 'C-%' THEN 'VERNON' ELSE 'SEVILLE' END, t.q
    ORDER BY sto.item_number
    --SELECT * FROM #TMP_REPLEN1
  --SELECT COUNT(*) FROM #TMP_REPLEN1//6450
  --SELECT COUNT(DISTINCT item_number) FROM #TMP_REPLEN1 // 1937
--calculate running total
  SELECT *
    , SUM (actual_qty) OVER (PARTITION BY item_number ORDER BY rowNumber) AS runningTotal
    INTO #TMP_REPLEN2
    FROM #TMP_REPLEN1
  ORDER BY item_number, runningTotal
  --SELECT * FROM #TMP_REPLEN2 //6450
  --SELECT COUNT(DISTINCT item_number) FROM #TMP_REPLEN2 //1937
  --Calculate whether to PULL or DELETE LPN's
  SELECT *,
    CASE
        WHEN runningTotal <= totalNeed OR (rowNumber = 1 AND (runningTotal > (totalNeed))) THEN 'PULL'
        WHEN runningTotal > totalNeed THEN 'DELETE'
        ELSE 'DELETE' END AS 'replen'
  INTO #TMP_REPLEN3
  FROM #TMP_REPLEN2
  WHERE BUILDING <> 'VERNON'
  AND location_id NOT LIKE 'LOST%' AND location_id NOT LIKE 'RTV%'
  ORDER BY item_number,rowNumber
-- Use this as your replen sheet
SELECT * FROM #TMP_REPLEN3 WHERE replen = 'PULL'
DROP TABLE #TMP_REPLEN
DROP TABLE #TMP_REPLEN1
DROP TABLE #TMP_REPLEN2
DROP TABLE #TMP_REPLEN3
