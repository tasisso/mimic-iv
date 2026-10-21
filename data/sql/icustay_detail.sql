-- This query returns ICU stays with patient, hospital and ICU level factors.
-- Also derives ethnicity_grouped and age_grouped columns as categorical variables.
--
-- Requires the query parameter @subject_ids (ARRAY<INT64>), taken from the waveform record metadata.
-- Returns all hospital admission and ICU stays those subjects.
-- {version} in the table names is filled by run_query from template_params={'version': ...}.

WITH t AS (
    SELECT ie.subject_id, ie.hadm_id, ie.stay_id

        -- patient level factors
        , pat.gender, pat.dod

        -- hospital level factors
        , adm.admittime, adm.dischtime
        , DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital
        -- calculate the age as anchor_age (60) plus difference between
        -- admit year and the anchor year.
        -- the noqa retains the extra long line so the 
        -- convert to postgres bash script works
        , pat.anchor_age + DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) AS admission_age -- noqa: L016
        , adm.race
        -- grouped race/ethnicity: WHITE, BLACK, HISPANIC/LATINO, ASIAN, OTHER, UNKNOWN
        , CASE
            WHEN adm.race = 'WHITE' OR adm.race LIKE 'WHITE - %'
                OR adm.race = 'PORTUGUESE' THEN 'WHITE'
            WHEN adm.race LIKE 'BLACK/%' THEN 'BLACK'
            WHEN adm.race LIKE 'HISPANIC%'
                OR adm.race = 'SOUTH AMERICAN' THEN 'HISPANIC/LATINO'
            WHEN adm.race = 'ASIAN' OR adm.race LIKE 'ASIAN - %' THEN 'ASIAN'
            WHEN adm.race IS NULL
                OR adm.race IN ('UNKNOWN', 'PATIENT DECLINED TO ANSWER', 'UNABLE TO OBTAIN')
                THEN 'UNKNOWN'
            ELSE 'OTHER' END AS ethnicity_grouped
        , adm.hospital_expire_flag
        , DENSE_RANK() OVER (
            PARTITION BY adm.subject_id ORDER BY adm.admittime
        ) AS hospstay_seq
        , CASE
            WHEN
                DENSE_RANK() OVER (
                    PARTITION BY adm.subject_id ORDER BY adm.admittime
                ) = 1 THEN TRUE
            ELSE FALSE END AS first_hosp_stay

        -- icu level factors
        , ie.intime AS icu_intime, ie.outtime AS icu_outtime
        , ROUND(
            CAST(DATETIME_DIFF(ie.outtime, ie.intime, HOUR) / 24.0 AS NUMERIC), 2
        ) AS los_icu
        , DENSE_RANK() OVER (
            PARTITION BY ie.hadm_id ORDER BY ie.intime
        ) AS icustay_seq

        -- first ICU stay *for the current hospitalization*
        , CASE
            WHEN
                DENSE_RANK() OVER (
                    PARTITION BY ie.hadm_id ORDER BY ie.intime
                ) = 1 THEN TRUE
            ELSE FALSE END AS first_icu_stay

    FROM `physionet-data.mimiciv_{version}_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_{version}_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_{version}_hosp.patients` pat
        ON ie.subject_id = pat.subject_id
    WHERE ie.subject_id IN UNNEST(@subject_ids)
)

SELECT
    t.subject_id
    , t.hadm_id
    , t.stay_id
    , t.gender
    , t.dod
    , t.admittime
    , t.dischtime
    , t.los_hospital
    , t.hospital_expire_flag
    , t.hospstay_seq
    , t.first_hosp_stay
    , t.admission_age
    , ['<46', '46-55', '56-65', '66-75', '76+'][OFFSET(
        RANGE_BUCKET(t.admission_age, [46, 56, 66, 76]) -- right-inclusive edges
    )] AS age_grouped
    , t.race
    , t.ethnicity_grouped
    , t.icu_intime
    , t.icu_outtime
    , t.los_icu
    , t.icustay_seq
    , t.first_icu_stay
FROM t
