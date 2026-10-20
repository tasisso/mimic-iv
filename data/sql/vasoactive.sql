-- This query combines all vasoactive drug administrations in a single table
-- and calculates norepinphrine equivalent based on:
-- "An updated 'norepinephrine equivalent' score in intensive care:
-- as a marker of shock severity" by Kotani et al. 2023.
--
-- Of the included drugs, dobutamine and milrinone are NOT used to calculated neq,
-- but are still used downstream to represent vasoactive windows.
-- 
-- Requires the query parameter @stay_ids (ARRAY<INT64>).
-- {version} in the table names is filled by run_query from template_params={'version': ...}.

WITH dobutamine AS (
    SELECT
        stay_id, linkorderid
        -- all rows in mcg/kg/min
        , rate AS vaso_rate
        , amount AS vaso_amount
        , starttime
        , endtime
    FROM `physionet-data.mimiciv_{version}_icu.inputevents`
    WHERE itemid = 221653 -- dobutamine
        AND stay_id IN UNNEST(@stay_ids)
)

, dopamine AS (
    SELECT
        stay_id, linkorderid
        -- all rows in mcg/kg/min
        , rate AS vaso_rate
        , amount AS vaso_amount
        , starttime
        , endtime
    FROM `physionet-data.mimiciv_{version}_icu.inputevents`
    WHERE itemid = 221662 -- dopamine
        AND stay_id IN UNNEST(@stay_ids)
)

, epinephrine AS (
    SELECT
        stay_id, linkorderid
        -- all rows in mcg/kg/min
        , rate AS vaso_rate
        , amount AS vaso_amount
        , starttime
        , endtime
    FROM `physionet-data.mimiciv_{version}_icu.inputevents`
    WHERE itemid = 221289 -- epinephrine
        AND stay_id IN UNNEST(@stay_ids)
)

, norepinephrine AS (
    SELECT
        stay_id, linkorderid
        , CASE WHEN rateuom = 'mg/kg/min' AND patientweight = 1 THEN rate
            WHEN rateuom = 'mg/kg/min' THEN rate * 1000.0
            ELSE rate END AS vaso_rate
        , amount AS vaso_amount
        , starttime
        , endtime
    FROM `physionet-data.mimiciv_{version}_icu.inputevents`
    WHERE itemid = 221906 -- norepinephrine
        AND stay_id IN UNNEST(@stay_ids)
)

, phenylephrine AS (
    SELECT
        stay_id, linkorderid
        , CASE WHEN rateuom = 'mcg/min' THEN rate / patientweight
            ELSE rate END AS vaso_rate
        , amount AS vaso_amount
        , starttime
        , endtime
    FROM `physionet-data.mimiciv_{version}_icu.inputevents`
    WHERE itemid = 221749 -- phenylephrine
        AND stay_id IN UNNEST(@stay_ids)
)

, vasopressin AS (
    SELECT
        stay_id, linkorderid
        -- three rows in units/min, rest in units/hour
        -- convert all rows to units/min
        , CASE WHEN rateuom = 'units/hour' THEN rate / 60.0
            ELSE rate END AS vaso_rate
        , amount AS vaso_amount
        , starttime
        , endtime
    FROM `physionet-data.mimiciv_{version}_icu.inputevents`
    WHERE itemid = 222315 -- vasopressin
        AND stay_id IN UNNEST(@stay_ids)
)

, milrinone AS (
    SELECT
        stay_id, linkorderid
        -- all rows in mcg/kg/min
        , rate AS vaso_rate
        , amount AS vaso_amount
        , starttime
        , endtime
    FROM `physionet-data.mimiciv_{version}_icu.inputevents`
    WHERE itemid = 221986 -- milrinone
        AND stay_id IN UNNEST(@stay_ids)
)

-- angiotensin II rate in ng/kg/min; also used to calculate the norepinephrine equivalent rate
, angiotensin_ii AS (
    SELECT
        stay_id, linkorderid
        -- itemid 229709 is in mcg/kg/min, 229764 is in ng/kg/min
        -- convert all rows to ng/kg/min
        , CASE WHEN itemid = 229709 THEN rate * 1000.0
            ELSE rate END AS vaso_rate
        , starttime
        , endtime
    FROM `physionet-data.mimiciv_{version}_icu.inputevents`
    WHERE itemid IN (229709, 229764) -- angiotensin II
        AND stay_id IN UNNEST(@stay_ids)
)

-- collect all vasopressor administration times
-- create a single table with these as start/stop times
, tm AS (
    SELECT stay_id, starttime AS vasotime FROM dobutamine
    UNION DISTINCT
    SELECT stay_id, starttime AS vasotime FROM dopamine
    UNION DISTINCT
    SELECT stay_id, starttime AS vasotime FROM epinephrine
    UNION DISTINCT
    SELECT stay_id, starttime AS vasotime FROM norepinephrine
    UNION DISTINCT
    SELECT stay_id, starttime AS vasotime FROM phenylephrine
    UNION DISTINCT
    SELECT stay_id, starttime AS vasotime FROM vasopressin
    UNION DISTINCT
    SELECT stay_id, starttime AS vasotime FROM milrinone
    UNION DISTINCT
    SELECT stay_id, starttime AS vasotime FROM angiotensin_ii
    UNION DISTINCT
    -- combine end times from the same tables
    SELECT stay_id, endtime AS vasotime FROM dobutamine
    UNION DISTINCT
    SELECT stay_id, endtime AS vasotime FROM dopamine
    UNION DISTINCT
    SELECT stay_id, endtime AS vasotime FROM epinephrine
    UNION DISTINCT
    SELECT stay_id, endtime AS vasotime FROM norepinephrine
    UNION DISTINCT
    SELECT stay_id, endtime AS vasotime FROM phenylephrine
    UNION DISTINCT
    SELECT stay_id, endtime AS vasotime FROM vasopressin
    UNION DISTINCT
    SELECT stay_id, endtime AS vasotime FROM milrinone
    UNION DISTINCT
    SELECT stay_id, endtime AS vasotime FROM angiotensin_ii
)

-- create starttime/endtime from all possible times collected
, tm_lag AS (
    SELECT stay_id
        , vasotime AS starttime
        -- note: the last row for each partition (stay_id) will have
        -- a NULL endtime. we can drop this row later, as we know that no
        -- vasopressor will start at this time (otherwise, we would have
        -- a later end time, which would mean it's not the last row!)
        , LEAD(
            vasotime, 1
        ) OVER (PARTITION BY stay_id ORDER BY vasotime) AS endtime
    FROM tm
)

-- left join to raw data tables to combine doses
SELECT t.stay_id, t.starttime, t.endtime
    -- inopressors/vasopressors
    , dop.vaso_rate AS dopamine -- mcg/kg/min
    , epi.vaso_rate AS epinephrine -- mcg/kg/min
    , nor.vaso_rate AS norepinephrine -- mcg/kg/min
    , phe.vaso_rate AS phenylephrine -- mcg/kg/min
    , vas.vaso_rate AS vasopressin -- units/min
    , ang.vaso_rate AS angiotensin_ii -- ng/kg/min
    -- inodialators
    , dob.vaso_rate AS dobutamine -- mcg/kg/min
    , mil.vaso_rate AS milrinone -- mcg/kg/min
    -- Only these factors appear in MetaVision - Angiotensin II rare
    -- Norepinephrine   - 1:1 ug/kg/min
    -- Epinephrine      - 1:1 ug/kg/min
    -- Dopamine         - 1:0.01 ug/kg/min
    -- Phenylephrine    - 1:0.06 ug/kg/min
    -- Vasopressin      - 1:2.5 units/min
    -- Angiotensin II   - 1:0.0025 ng/kg/min
    , COALESCE(nor.vaso_rate, 0)
        + COALESCE(epi.vaso_rate, 0)
        + 0.01 * COALESCE(dop.vaso_rate, 0)
        + 0.06 * COALESCE(phe.vaso_rate, 0)
        + 2.5 * COALESCE(vas.vaso_rate, 0)
        + 0.0025 * COALESCE(ang.vaso_rate, 0) AS neq -- mcg/kg/min

FROM tm_lag t
LEFT JOIN dobutamine dob
    ON t.stay_id = dob.stay_id
        AND t.starttime >= dob.starttime
        AND t.endtime <= dob.endtime
LEFT JOIN dopamine dop
    ON t.stay_id = dop.stay_id
        AND t.starttime >= dop.starttime
        AND t.endtime <= dop.endtime
LEFT JOIN epinephrine epi
    ON t.stay_id = epi.stay_id
        AND t.starttime >= epi.starttime
        AND t.endtime <= epi.endtime
LEFT JOIN norepinephrine nor
    ON t.stay_id = nor.stay_id
        AND t.starttime >= nor.starttime
        AND t.endtime <= nor.endtime
LEFT JOIN phenylephrine phe
    ON t.stay_id = phe.stay_id
        AND t.starttime >= phe.starttime
        AND t.endtime <= phe.endtime
LEFT JOIN vasopressin vas
    ON t.stay_id = vas.stay_id
        AND t.starttime >= vas.starttime
        AND t.endtime <= vas.endtime
LEFT JOIN milrinone mil
    ON t.stay_id = mil.stay_id
        AND t.starttime >= mil.starttime
        AND t.endtime <= mil.endtime
LEFT JOIN angiotensin_ii ang
    ON t.stay_id = ang.stay_id
        AND t.starttime >= ang.starttime
        AND t.endtime <= ang.endtime
-- remove the final row for each stay_id
-- it will not have any infusions associated with it
WHERE t.endtime IS NOT NULL;
