-- Extracts ICD diagnoses for the matched cohort's hospital admissions and adds truncated code.
--
-- Requires the query parameters @subject_ids and @hadm_ids (ARRAY<INT64>), taken from the
-- matched (subject_id, hadm_id) pairs. hadm_id identifies a single subject, so filtering both
-- arrays returns exactly the diagnoses of those pairs.
-- {version} in the table names is filled by run_query from template_params={'version': ...}.
--
-- icd_code_truncated keeps the category plus one more character, with a dot:
-- N179 -> N17.9, I5033 -> I50.3, I10 -> I10 (nothing to truncate)
-- All codes in the cohort are ICD-10, which have the dot after the 3rd character.

SELECT
    dx.subject_id, dx.hadm_id, dx.seq_num
    , TRIM(dx.icd_code) AS icd_code
    , IF(
        LENGTH(TRIM(dx.icd_code)) > 3
        , CONCAT(SUBSTR(TRIM(dx.icd_code), 1, 3), '.', SUBSTR(TRIM(dx.icd_code), 4, 1))
        , TRIM(dx.icd_code)
    ) AS icd_code_truncated
    , dx.icd_version
    , d.long_title
FROM `physionet-data.mimiciv_{version}_hosp.diagnoses_icd` dx
LEFT JOIN `physionet-data.mimiciv_{version}_hosp.d_icd_diagnoses` d
    ON TRIM(d.icd_code) = TRIM(dx.icd_code) AND d.icd_version = dx.icd_version
WHERE dx.subject_id IN UNNEST(@subject_ids)
    AND dx.hadm_id IN UNNEST(@hadm_ids)
