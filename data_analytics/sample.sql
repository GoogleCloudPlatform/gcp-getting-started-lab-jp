# 分析1のクエリ
SELECT
    COUNT(DISTINCT station_id) as cnt
FROM
    `bigquery-public-data.new_york_citibike.citibike_stations`


# 分析2のクエリ
SELECT
    COUNT(station_id) as cnt
FROM
  `bigquery-public-data.new_york_citibike.citibike_stations`
WHERE
      is_installed = TRUE
     AND is_renting = TRUE
     AND is_returning = TRUE


# 分析3のクエリ
SELECT
    usertype,
    gender,
    COUNT(gender) AS cnt
FROM
 `bigquery-public-data.new_york_citibike.citibike_trips`
GROUP BY
    usertype,
    gender
ORDER BY
    cnt DESC


# 分析4のクエリ
SELECT
    start_station_name,
    end_station_name,
    COUNT(end_station_name) AS cnt
FROM
    `bigquery-public-data.new_york_citibike.citibike_trips`
GROUP BY
    start_station_name,
    end_station_name
ORDER BY
    cnt DESC
