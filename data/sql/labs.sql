-- Blood lab results for the matched cohort's hospital admissions.

-- Requires the query parameters @subject_ids and @hadm_ids (ARRAY<INT64>), taken from the
-- matched (subject_id, hadm_id) pairs.
-- {version} in the table names is filled by run_query from template_params={'version': ...}.
--
-- Only fluid = 'Blood' items are kept:
-- Some labels have more than one blood itemid (e.g. chemistry vs blood gas), so
-- itemid and category are returned to tell them apart.

SELECT
    le.subject_id, le.hadm_id
    , le.labevent_id, le.specimen_id
    , le.itemid, d.label, d.fluid, d.category
    , le.charttime
    , le.value, le.valuenum, le.valueuom
    , le.ref_range_lower, le.ref_range_upper, le.flag
FROM `physionet-data.mimiciv_{version}_hosp.labevents` le
INNER JOIN `physionet-data.mimiciv_{version}_hosp.d_labitems` d
    ON le.itemid = d.itemid
WHERE le.subject_id IN UNNEST(@subject_ids)
    AND le.hadm_id IN UNNEST(@hadm_ids)
    AND d.fluid = 'Blood'
    AND d.label IN (
        'Hematocrit'
        , 'Platelet Count'
        , 'Creatinine'
        , 'Potassium'
        , 'Hemoglobin'
        , 'White Blood Cells'
        , 'MCHC'
        , 'Red Blood Cells'
        , 'MCV'
        , 'MCH'
        , 'RDW'
        , 'Urea Nitrogen'
        , 'Sodium'
        , 'Chloride'
        , 'Bicarbonate'
        , 'Anion Gap'
        , 'Glucose'
        , 'Magnesium'
        , 'Calcium, Total'
        , 'Phosphate'
        , 'INR(PT)'
        , 'PT'
        , 'PTT'
        , 'Basophils'
        , 'Neutrophils'
        , 'Monocytes'
        , 'Eosinophils'
        , 'Lymphocytes'
        , 'RDW-SD'
        , 'H'
        , 'L'
        , 'I'
        , 'Alanine Aminotransferase (ALT)'
        , 'Asparate Aminotransferase (AST)'
        , 'Lactate'
        , 'Alkaline Phosphatase'
        , 'Bilirubin, Total'
        , 'pH'
        , 'Albumin'
        , 'Base Excess'
        , 'pO2'
        , 'Calculated Total CO2'
        , 'pCO2'
        , 'Absolute Neutrophil Count'
        , 'Absolute Eosinophil Count'
        , 'Absolute Monocyte Count'
        , 'Absolute Basophil Count'
        , 'Absolute Lymphocyte Count'
        , 'Creatine Kinase (CK)'
        , 'Immature Granulocytes'
    )
