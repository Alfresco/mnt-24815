# MNT-24815: Critical Data Integrity Fix for Alfresco 23.3.0 and 23.4.0

## Overview

This repository addresses a critical bug identified in Alfresco versions 23.3.0 and 23.4.0, which impacts Audit, Quick Links, and Alfresco Governance Services (AGS). The issue affects the CRC calculation, leading to data inconsistencies and the inability to view previous audit logs or quick links.

## Reproduction Steps

To replicate the issue:

1. **Install**: Set up ACS 23.2.1 (or an earlier version) with AGS.
2. **Create Data**: Establish quick links, an AGS site, generate records, and perform edits.
3. **Verify**: Ensure accessibility to the quick links and records' audit logs.
4. **Upgrade**: Move to version 23.3.0, 23.3.1, or 23.4.0.
5. **Observe**: Notice the inability to view quick links or previous audit logs. Additionally, the file plan becomes DoD compliant.
6. **Database Check**: In the database, observe that `alf_prop_class` contains duplicate classes (one in lowercase and the other in mixed case).

## Resolution Steps

To rectify the issue:

1. **Backup Your Database**: Before making any changes, create a full backup of your database to ensure you can restore it if needed.

2. **Upgrade Alfresco**: Install a corrected version (23.3.3 or 23.4.1).

3. **Shutdown Services**: After upgrading, stop all services connected to the database, including Alfresco.

4. **Execute the Fix Script**:  
   - Depending on your DBMS, run the corresponding SQL script located in the `dbscripts` folder.  
   - Ensure the script completes successfully without errors.

5. **Verify the Fix**:  
   - Check that the affected functionalities (Quick Links, Audit Logs, AGS) are restored.  
   - Manually inspect the database to confirm the expected changes.

6. **Final Validation**:  
   - Test all relevant functionalities to ensure the issue is resolved.  
   - Only archive the backup once you have confirmed everything is working as expected.

*Note: Detailed SQL scripts are available in the `dbscripts` directory of this repository.*

## Contribution and Support

We actively encourage community involvement. If you encounter issues or have suggestions, please open an issue in this repository. Contributions are welcome via pull requests (PRs).

## Helpful Links

- [MNT-24815 Jira Issue](https://hyland.atlassian.net/browse/MNT-24815)
- [Caused by MNT-24137](https://hyland.atlassian.net/browse/MNT-24137)
- [Initial Detection Issue](https://hyland.atlassian.net/browse/MNT-24756)

*For a comprehensive understanding of the bug and its implications, please refer to the [official announcement](https://connect.hyland.com/t5/alfresco-blog/critical-bug-in-alfresco-community-23-3-0-and-23-4-0/ba-p/486952).* 