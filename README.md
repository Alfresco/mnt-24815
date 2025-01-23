# MNT-24815

This repo will contain all fixes necessary to revert the data changes caused by deploying ACS/AGS 23.3.0, 23.3.1 or 23.4.0

## Step-by-Step guide

### How to reproduce

- Install ACS 23.2.1 (or earlier version) with AGS
- Create quicklinks, AGS site, create some records and edit
- Verify you are able to view the quicklinks and the records audit logs
- Upgrade to 23.3.0, 23.3.1 or 23.4.0
- You are now longer able to view the quicklinks or the previous audit logs. Aditionally your fileplan is now DOD compliant.
- In the database you will see that alf_prop_class now contains duplicate classes (one in lowercase and the other in mixed case)

### How to fix
- Install a corrected version (23.3.3 or 23.4.1)
- After the upgrade to a fixed version, stop all services connected to the DB, including alfresco
- Depending on your DBMS, run the corresponding SQL Script in folder dbscripts
- Start alfresco and run job Prop Tables Cleaner

//TODO

## Helpful links

- [MNT-24815 Jira Issue](https://hyland.atlassian.net/browse/MNT-24815)
- [Caused by MNT-24137](https://hyland.atlassian.net/browse/MNT-24137)
- [Jira Issue where it was first detected](https://hyland.atlassian.net/browse/MNT-24756)
