----------------------------------------------------------------------------------------------------------------
-- Date:        January 2025
-- Author:      Eva Vasques
-- Reviewer:    Tiago Salvado
-- Description:
--
-- Fix problem introduced by MNT-24137, the CrCHelper logic has been changed in ACS 23.3.2 and 23.4.0 causing
-- duplicated records in the database tables below:
--
--    - alf_prop_class
--    - alf_prop_string_value
--    - alf_prop_value
--    - alf_prop_unique_ctx
--    - alf_prop_link
--    - alf_audit_app
--    - alf_audit_entry
--
-- The goal of this SQL script is to fix the duplicated records and update all the references accordingly.
----------------------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- alf_prop_class
----------------------------------------------------------
--
-- Type:    TEMP TABLE
--
-- Table:   alf_prop_class_duplicated_temp
--
-- Description:
--
--        Contains the mapping between property classes that have been duplicated after migration. The goal
--        is to maintain the correspondence between the class id used before migration and the id created after.
--
-- Example:
--
--        Given 'alf_prop_class' table (after migration):
--
--        -------------------------------------------------------------------------------------
--        | id  | java_class_name        | java_class_name_short     | java_class_name_crc    |
--        -------------------------------------------------------------------------------------
--        | 1   | "java.lang.String"     | "java.lang.string"        | 2004016611             |
--        | 21  | "java.lang.String"     | "java.lang.String"        | 2004016611             |
--        -------------------------------------------------------------------------------------
--
--        The table 'alf_prop_class_duplicated_temp' will be created as follows:
--
--        -------------------------------------------------------------------------------
--        | java_class_name       | before_problem_type_id    | after_problem_type_id   |
--        -------------------------------------------------------------------------------
--        |  "java.lang.String"   | 1                         | 21                      |
--        -------------------------------------------------------------------------------
--
create table alfresco.alf_prop_class_duplicated_temp as
select *
from (
        select
            java_class_name,
            (
                select min(id)
                from alfresco.alf_prop_class p
                where
                    t.java_class_name = p.java_class_name
            ) as before_problem_type_id,
            (
                select max(id)
                from alfresco.alf_prop_class p
                where
                    t.java_class_name = p.java_class_name
            ) as after_problem_type_id
        from alfresco.alf_prop_class t
        group by
            java_class_name
    ) alf_prop_class_before_after_ids
where
    before_problem_type_id <> after_problem_type_id;

----------------------------------------------------------
-- alf_prop_string_value
----------------------------------------------------------

--
-- Type:    TEMP TABLE
--
-- Table:   alf_prop_string_value_duplicated_temp
--
-- Description:
--
--        Contains the mapping between property string values that have been duplicated after migration. The goal
--        is to maintain the correspondence between the property string value id used before migration and the id created after.
--
-- Example:
--
--        Given 'alf_prop_string_value' table (after migration):
--
--        ------------------------------------------------------------------
--        | id    | string_value    | string_end_lower     | string_crc    |
--        ------------------------------------------------------------------
--        | 37    | ".sharedIds"    | ".sharedids"         | 1096111251    |
--        | 918   | ".sharedIds"    | ".sharedIds"         | 1096111251    |
--        ------------------------------------------------------------------
--
--
--        The table 'alf_prop_string_value_duplicated_temp' will be created as follows:
--
--        ---------------------------------------------------------------------------------------
--        | string_value    | before_problem_sv_id    | after_problem_sv_id    | crc            |
--        ---------------------------------------------------------------------------------------
--        | ".sharedIds"    | 37                      | 918                    | 1096111251     |
--        ---------------------------------------------------------------------------------------
--
create table alfresco.alf_prop_string_value_duplicated_temp as
select
    string_value,
    before_problem_sv_id,
    after_problem_sv_id,
    string_crc
from (
        select
            string_value,
            string_crc,
            count(id) as duplicates,
            min(id) as before_problem_sv_id,
            max(id) as after_problem_sv_id
        from alfresco.alf_prop_string_value t
        group by
            string_value,
            string_crc
    ) alf_prop_string_value_before_after_ids
where
    duplicates > 1;
--
-- Type:    UPDATE
--
-- Table:   alf_prop_string_value
--
-- Description:
--
--        Updates all records where 'string_end_lower' column is not lowercase
--
--
update alfresco.alf_prop_string_value
set
    string_end_lower = lower(string_end_lower)
where
    id in (
        select id
        from alfresco.alf_prop_string_value
        where
            lower(string_end_lower) != string_end_lower
            and string_value not in (
                select string_value
                from alfresco.alf_prop_string_value_duplicated_temp
            )
    );

----------------------------------------------------------
-- alf_prop_value
----------------------------------------------------------

--
-- Type:    UPDATE

-- Table:   alf_prop_value
--
-- Description:
--
--        Fix duplicated string values by replacing the 'long_value' column with the
--        original 'alf_prop_string_value.id' (before migration)
--

update alfresco.alf_prop_value apv
set
    long_value = (
        select apsvdt.before_problem_sv_id
        from alfresco.alf_prop_string_value_duplicated_temp apsvdt
        where
            apsvdt.after_problem_sv_id = apv.long_value
    )
where
    apv.actual_type_id in (
        select max(id)
        from alfresco.alf_prop_class apc
        where
            java_class_name = 'java.lang.String'
    )
    and exists (
        select 1
        from alfresco.alf_prop_string_value_duplicated_temp apsvdt
        where
            apsvdt.after_problem_sv_id = apv.long_value
    );
--
-- Type:    TEMP TABLE
--
-- Table:   alf_prop_value_duplicated_temp
--
-- Description:
--
--        Contains the records from 'alf_prop_value' table that cannot have the 'actual_type_id' column
--        updated with value from 'alf_prop_class_duplicated_temp.before_problem_type_id', otherwise, the
--         index 'idx_alf_propv_act' (actual_type_id, long_value) would be violated since it is not possible
--         to have duplicated combinations.
--
--        The goal is to have a correspondence between property values that have been duplicated after
--        migration and the correspondent prop value that existed prior to migration. This way all the tables
--        that reference 'alf_prop_value.id' column can be updated accordingly.
--
-- Example:
--
--        Given 'alf_prop_value' table (after migration):
--
--        ----------------------------------------------------------
--        | id   | actual_type_id | persisted_type | long_value    |
--        ----------------------------------------------------------
--        | 2    | 1              | 3              | 2             |
--        ----------------------------------------------------------
--        | 73   | 1              | 3              | 59            |
--        ----------------------------------------------------------
--        | 82   | 1              | 3              | 65            |
--        ----------------------------------------------------------
--        | 878  | 21             | 3              | 2             |
--        ----------------------------------------------------------
--        | 883  | 21             | 3              | 59            |
--        ----------------------------------------------------------
--        | 914  | 21             | 3              | 65            |
--        ----------------------------------------------------------
--
--        The table 'alf_prop_value_duplicated_temp' will be created as follows:
--
--        ----------------------------------------------------------------------------------------------------------------------
--        | after_problem_id  | before_problem_id   | actual_type_id    | actual_type_id_before_problem     |    long_value    |
--        ----------------------------------------------------------------------------------------------------------------------
--        | 878               | 2                   | 21                | 1                                 |                  |
--        ----------------------------------------------------------------------------------------------------------------------
--        | 883               | 73                  | 21                | 1                                 |                  |
--        ----------------------------------------------------------------------------------------------------------------------
--        | 914               | 82                  | 21                | 1                                 |                  |
--        ----------------------------------------------------------------------------------------------------------------------
--
create table alfresco.alf_prop_value_duplicated_temp as
select
    apv.id after_problem_id,
    (
        select id
        from alfresco.alf_prop_value apv2
        where
            apv2.actual_type_id = apcdt.before_problem_type_id
            and apv2.long_value = apv.long_value
    ) before_problem_id,
    apv.actual_type_id,
    apcdt.before_problem_type_id actual_type_id_before_problem,
    apv.long_value
from alfresco.alf_prop_value apv, alfresco.alf_prop_class_duplicated_temp apcdt
where
    apv.actual_type_id = apcdt.after_problem_type_id
    and (
        apcdt.before_problem_type_id,
        apv.long_value
    ) in (
        select actual_type_id, long_value
        from alfresco.alf_prop_value
    );

--
-- Type:    TEMP TABLE
--
-- Table:   alf_prop_value_not_duplicated_temp
--
-- Description:
--
--        Contains the records from 'alf_prop_value' table that can have the 'actual_type_id' column updated with
--        value from 'alf_prop_class_duplicated_temp.before_problem_type_id' which means these records were not
--        duplicated after migration.
--
create table alfresco.alf_prop_value_not_duplicated_temp as
select
    apv.id after_problem_id,
    apv.actual_type_id,
    apcdt.before_problem_type_id actual_type_id_before_problem,
    apv.long_value
from alfresco.alf_prop_value apv, alfresco.alf_prop_class_duplicated_temp apcdt
where
    apv.actual_type_id = apcdt.after_problem_type_id
    and (
        apcdt.before_problem_type_id,
        apv.long_value
    ) not in (
        select actual_type_id, long_value
        from alfresco.alf_prop_value
    );

--
-- Type:    UPDATE
--
-- Table:   alf_prop_value
--
-- Description:
--
--        Fix the 'alf_prop_value.actual_type_id' column of non-duplicated records by using
--        'alf_prop_value_not_duplicated_temp.actual_type_id_before_problem' column
--

merge into alfresco.alf_prop_value apv using alfresco.alf_prop_value_not_duplicated_temp apvndt on (
    apv.id = apvndt.after_problem_id
) when matched then
update
set
    apv.actual_type_id = apvndt.actual_type_id_before_problem;

----------------------------------------------------------
-- alf_prop_unique_ctx
----------------------------------------------------------

--
-- Type:    TEMP TABLE
--
-- Table:   alf_prop_unique_ctx_map_values_temp
--
-- Description:
--
--        Creates a mapping for columns value1_prop_id, value2_prop_id and value3_prop_id columns before and after migration.
--
-- Example:
--
--        Given 'alf_prop_unique_ctx' table:
--
--        -----------------------------------------------------------------------------------------------
--        | id    | version  | value1_prop_id    | value2_prop_id    | value3_prop_id  | prop1_id       |
--        -----------------------------------------------------------------------------------------------
--        | 38    | 0        | 81                | 86                | 3               | 49             |
--        -----------------------------------------------------------------------------------------------
--        | 71    | 0        | 913               | 916               | 879             | 685            |
--        -----------------------------------------------------------------------------------------------
--
--        We will have 'alf_prop_unique_ctx_map_values_temp' table as follows:
--
--        -----------------------------------------------------------------------------------------------------------------------------------------------------------------------
--        | id    | value1_after_problem | value2_after_problem | value3_after_problem  | value1_before_problem   | value2_before_problem | value3_before_problem | prop1_id    |
--        -----------------------------------------------------------------------------------------------------------------------------------------------------------------------
--        | 38    | 81                   | 86                   | 3                     | null                    | null                  | null                  | 49          |
--        -----------------------------------------------------------------------------------------------------------------------------------------------------------------------
--        | 71    | 913                  | 916                  | 879                   | 81                      | 86                    | 3                     | 685         |
--        -----------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
create table alfresco.alf_prop_unique_ctx_map_values_temp as
select
    apuc.id,
    apuc.value1_prop_id value1_after_problem,
    apuc.value2_prop_id value2_after_problem,
    apuc.value3_prop_id value3_after_problem,
    (
        select t1.before_problem_id
        from alfresco.alf_prop_value_duplicated_temp t1
        where
            t1.after_problem_id = apuc.value1_prop_id
    ) value1_before_problem,
    (
        select t1.before_problem_id
        from alfresco.alf_prop_value_duplicated_temp t1
        where
            t1.after_problem_id = apuc.value2_prop_id
    ) value2_before_problem,
    (
        select t1.before_problem_id
        from alfresco.alf_prop_value_duplicated_temp t1
        where
            t1.after_problem_id = apuc.value3_prop_id
    ) value3_before_problem,
    prop1_id prop1_id_after_problem
from alfresco.alf_prop_unique_ctx apuc;

--
-- Type:    TEMP TABLE
--
-- Table:   alf_prop_unique_ctx_duplicated_values_temp
--
-- Description:
--
--        Contains only the records that cannot have both value1_prop_id, value2_prop_id and value3_prop_id columns
--        updated at once, otherwise, the index 'idx_alf_propuctx' would be violated.
--
-- Example:
--
--        Given 'alf_prop_unique_ctx' table:
--
--        -------------------------------------------------------------------------------------------
--        | id    | version  | value1_prop_id    | value2_prop_id | value3_prop_id    | prop1_id    |
--        -------------------------------------------------------------------------------------------
--        | 38    | 0        | 81                | 86             | 3                 | 49          |
--        -------------------------------------------------------------------------------------------
--        | 71    | 0        | 913               | 916            | 879               | 685         |
--        -------------------------------------------------------------------------------------------
--
--        We will have 'alf_prop_unique_ctx_duplicated_values_temp' table as follows:
--
--        --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--        | after_problem_id  | before_problem_id | value1_after_problem | value2_after_problem | value3_after_problem | value1_before_problem | value2_before_problem | value3_before_problem |
--        --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--        | 71                | 38                | 913                  | 916                  | 879                  | 81                    | 86                    | 3                     |
--        --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
create table alfresco.alf_prop_unique_ctx_duplicated_values_temp as
select
    apucmvt.id after_problem_id,
    apuc.id before_problem_id,
    apucmvt.value1_after_problem,
    apucmvt.value2_after_problem,
    apucmvt.value3_after_problem,
    apucmvt.value1_before_problem,
    apucmvt.value2_before_problem,
    apucmvt.value3_before_problem,
    apucmvt.prop1_id_after_problem
from alfresco.alf_prop_unique_ctx_map_values_temp apucmvt, alfresco.alf_prop_unique_ctx apuc
where
    apucmvt.value1_before_problem is not null
    and apucmvt.value2_before_problem is not null
    and apucmvt.value3_before_problem is not null
    and apuc.value1_prop_id = apucmvt.value1_before_problem
    and apuc.value2_prop_id = apucmvt.value2_before_problem
    and apuc.value3_prop_id = apucmvt.value3_before_problem;

--
-- Type:    UPDATE
--
-- Table:   alf_prop_unique_ctx
--
-- Description:
--
--        Fix 'value1_prop_id' column with id used before problem
--
update alfresco.alf_prop_unique_ctx apuc
set
    apuc.value1_prop_id = (
        select apucmvt.value1_before_problem
        from alfresco.alf_prop_unique_ctx_map_values_temp apucmvt
        where
            apuc.value1_prop_id = apucmvt.value1_after_problem
            and apucmvt.value1_before_problem is not null
            and apucmvt.prop1_id_after_problem = apuc.prop1_id
            and (
                apucmvt.value1_before_problem,
                apuc.value2_prop_id,
                apuc.value3_prop_id
            ) not in (
                select
                    value1_before_problem,
                    value2_before_problem,
                    value3_before_problem
                from alfresco.alf_prop_unique_ctx_duplicated_values_temp
            )
    )
where
    exists (
        select 1
        from alfresco.alf_prop_unique_ctx_map_values_temp apucmvt
        where
            apuc.value1_prop_id = apucmvt.value1_after_problem
            and apucmvt.value1_before_problem is not null
            and apucmvt.prop1_id_after_problem = apuc.prop1_id
            and (
                apucmvt.value1_before_problem,
                apuc.value2_prop_id,
                apuc.value3_prop_id
            ) not in (
                select
                    value1_before_problem,
                    value2_before_problem,
                    value3_before_problem
                from alfresco.alf_prop_unique_ctx_duplicated_values_temp
            )
    );

--
-- Type:    UPDATE
--
-- Table:   alf_prop_unique_ctx
--
-- Description:
--
--        Fix 'value2_prop_id' column with id used before problem
--
update alfresco.alf_prop_unique_ctx apuc
set
    apuc.value2_prop_id = (
        select apucmvt.value2_before_problem
        from alfresco.alf_prop_unique_ctx_map_values_temp apucmvt
        where
            apuc.value2_prop_id = apucmvt.value2_after_problem
            and apucmvt.value2_before_problem is not null
            and apucmvt.prop1_id_after_problem = apuc.prop1_id
            and (
                apuc.value1_prop_id,
                apucmvt.value2_before_problem,
                apuc.value3_prop_id
            ) not in (
                select
                    value1_before_problem,
                    value2_before_problem,
                    value3_before_problem
                from alfresco.alf_prop_unique_ctx_duplicated_values_temp
            )
    )
where
    exists (
        select 1
        from alfresco.alf_prop_unique_ctx_map_values_temp apucmvt
        where
            apuc.value2_prop_id = apucmvt.value2_after_problem
            and apucmvt.value2_before_problem is not null
            and apucmvt.prop1_id_after_problem = apuc.prop1_id
            and (
                apuc.value1_prop_id,
                apucmvt.value2_before_problem,
                apuc.value3_prop_id
            ) not in (
                select
                    value1_before_problem,
                    value2_before_problem,
                    value3_before_problem
                from alfresco.alf_prop_unique_ctx_duplicated_values_temp
            )
    );

--
-- Type:    UPDATE
--
-- Tabl:    alf_prop_unique_ctx
--
-- Description:
--
--        Fix 'value3_prop_id' column with id used before problem
--
update alfresco.alf_prop_unique_ctx apuc
set
    apuc.value3_prop_id = (
        select apucmvt.value3_before_problem
        from alfresco.alf_prop_unique_ctx_map_values_temp apucmvt
        where
            apuc.value3_prop_id = apucmvt.value3_after_problem
            and apucmvt.value3_before_problem is not null
            and apucmvt.prop1_id_after_problem = apuc.prop1_id
            and (
                apuc.value1_prop_id,
                apuc.value2_prop_id,
                apucmvt.value3_before_problem
            ) not in (
                select
                    value1_before_problem,
                    value2_before_problem,
                    value3_before_problem
                from alfresco.alf_prop_unique_ctx_duplicated_values_temp
            )
    )
where
    exists (
        select 1
        from alfresco.alf_prop_unique_ctx_map_values_temp apucmvt
        where
            apuc.value3_prop_id = apucmvt.value3_after_problem
            and apucmvt.value3_before_problem is not null
            and apucmvt.prop1_id_after_problem = apuc.prop1_id
            and (
                apuc.value1_prop_id,
                apuc.value2_prop_id,
                apucmvt.value3_before_problem
            ) not in (
                select
                    value1_before_problem,
                    value2_before_problem,
                    value3_before_problem
                from alfresco.alf_prop_unique_ctx_duplicated_values_temp
            )
    );

----------------------------------------------------------
-- alf_prop_link
----------------------------------------------------------

--
-- Type:    UPDATE
--
-- Table:   alf_prop_link
--
-- Description:
--
--        Fix 'alf_prop_link.key_prop_id' column with id before migration.
--
update alfresco.alf_prop_link apl
set
    apl.key_prop_id = (
        select apvdt.before_problem_id
        from alfresco.alf_prop_value_duplicated_temp apvdt
        where
            apl.key_prop_id = apvdt.after_problem_id
    )
where
    exists (
        select 1
        from alfresco.alf_prop_value_duplicated_temp apvdt
        where
            apl.key_prop_id = apvdt.after_problem_id
    );

--
-- Type:    UPDATE
--
-- Table: alf_prop_link
--
-- Description:
--
--        Fix 'alf_prop_link.key_prop_id' column with id before migration.
--
update alfresco.alf_prop_link apl
set
    apl.value_prop_id = (
        select apvdt.before_problem_id
        from alfresco.alf_prop_value_duplicated_temp apvdt
        where
            apl.value_prop_id = apvdt.after_problem_id
    )
where
    exists (
        select 1
        from alfresco.alf_prop_value_duplicated_temp apvdt
        where
            apl.value_prop_id = apvdt.after_problem_id
    );

----------------------------------------------------------
-- alf_audit_app
----------------------------------------------------------

--
-- Type:    TEMP TABLE
--
-- Table:   alf_audit_app_duplicated_temp
--
-- Description:
--
--        Contains the relationship between audit app ids that have been duplicated and the
--        id that was used before migration.
--
-- Example:
--
--        Given 'alf_audit_app' table:
--
--        ----------------------------------------------------------------------
--        | id   | version  | app_name_id | audit_model_id | disabled_paths_id |
--        ----------------------------------------------------------------------
--        | 1    | 0        | 5           | 3              | 2                 |
--        ----------------------------------------------------------------------
--        | 2    | 0        | 72          | 1              | 34                |
--        ----------------------------------------------------------------------
--        | 3    | 0        | 73          | 2              | 35                |
--        ----------------------------------------------------------------------
--        | 4    | 0        | 74          | 4              | 36                |
--        ----------------------------------------------------------------------
--        | 5    | 0        | 881         | 1              | 669               |
--        ----------------------------------------------------------------------
--        | 6    | 0        | 883         | 2              | 670               |
--        ----------------------------------------------------------------------
--        | 7    | 0        | 884         | 3              | 671               |
--        ----------------------------------------------------------------------
--        | 8    | 0        | 885         | 4              | 672               |
--        ----------------------------------------------------------------------
--
--        We will have 'alf_audit_app_duplicated_temp' table as follows:
--
--        ----------------------------------------------
--        | after_problem_aa_id | before_problem_aa_id |
--        ----------------------------------------------
--        | 5                   | 2                    |
--        ----------------------------------------------
--        | 6                   | 3                    |
--        ----------------------------------------------
--        | 7                   | 1                    |
--        ----------------------------------------------
--        | 8                   | 4                    |
--        ----------------------------------------------
--
create table alfresco.alf_audit_app_duplicated_temp as
select
    aaa.id after_problem_aa_id,
    (
        select id
        from alfresco.alf_audit_app aaa2
        where
            aaa2.app_name_id = apvdt.before_problem_id
    ) before_problem_aa_id
from alfresco.alf_audit_app aaa, alfresco.alf_prop_value_duplicated_temp apvdt
where
    aaa.app_name_id = apvdt.after_problem_id;

----------------------------------------------------------
-- alf_audit_entry
----------------------------------------------------------

--
-- Type:    UPDATE
--
-- Table:   alf_audit_entry
--
-- Description:
--
--        Fix 'alf_audit_entry.audit_app_id' with 'alf_audit_app.id' that was used before the migration.
--
update alfresco.alf_audit_entry aae
set
    aae.audit_app_id = (
        select aaadt.before_problem_aa_id
        from alfresco.alf_audit_app_duplicated_temp aaadt
        where
            aae.audit_app_id = aaadt.after_problem_aa_id
    )
where
    exists (
        select 1
        from alfresco.alf_audit_app_duplicated_temp aaadt
        where
            aae.audit_app_id = aaadt.after_problem_aa_id
    );

--
-- Type:    UPDATE
--
-- Table:   alf_audit_entry
--
-- Description:
--
--        Fix 'alf_audit_entry.audit_user_id' with id from 'alf_prop_value' table that was used before migration.
--

update alfresco.alf_audit_entry aae
set
    aae.audit_user_id = (
        select apvdt.before_problem_id
        from alfresco.alf_prop_value_duplicated_temp apvdt
        where
            aae.audit_user_id = apvdt.after_problem_id
    )
where
    exists (
        select 1
        from alfresco.alf_prop_value_duplicated_temp apvdt
        where
            aae.audit_user_id = apvdt.after_problem_id
    );

----------------------------------------------------------
-- DELETE DUPLICATES
----------------------------------------------------------

delete from alfresco.alf_prop_class
where
    id in (
        select after_problem_type_id
        from alfresco.alf_prop_class_duplicated_temp
    );

delete from alfresco.alf_audit_app
where
    id in (
        select after_problem_aa_id
        from alfresco.alf_audit_app_duplicated_temp
    );

delete from alfresco.alf_prop_value
where
    id in (
        select after_problem_id
        from alfresco.alf_prop_value_duplicated_temp
    );

delete from alfresco.alf_prop_string_value
where
    id in (
        select after_problem_sv_id
        from alfresco.alf_prop_string_value_duplicated_temp
    );

COMMIT;

----------------------------------------------------------
-- REMOVE TEMP TABLES
----------------------------------------------------------
DROP TABLE alf_prop_class_duplicated_temp;

DROP TABLE alf_prop_string_value_duplicated_temp;

DROP TABLE alf_prop_value_duplicated_temp;

DROP TABLE alf_prop_value_not_duplicated_temp;

DROP TABLE alf_prop_unique_ctx_map_values_temp;

DROP TABLE alf_prop_unique_ctx_duplicated_values_temp;

DROP TABLE alf_audit_app_duplicated_temp;


