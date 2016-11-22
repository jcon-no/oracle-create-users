# Oracle: Create Users Script

Scripts for creating and droping a user framework:
1. create_dev_users.sql : Creating user framework 
2. drop_dev_users.sql   : Droping user framework
3. dev_users_env.sql    : Setting values for variables

## 1. Script: create_dev_users.sql
 
This scripts will create development users and roles.

By setting an APP_NAME in the dev_users_env.sql script, the scripts makes the following:

- Tablespaces : "<APP_NAME>_DATA", "<APP_NAME>_IDX", "<APP_NAME>_LOBS"(optional)
- Users       : "<APP_NAME><OWNER_SUFFIX>","<APP_NAME>","<APP_NAME><SUPPORT_SUFFIX>"
- Roles       : "<APP_NAME>_RW", "<APP_NAME>_RO"
- Triggers    : "<APP_NAME>.AFTER_LOGON_TRG", "<APP_NAME><SUPPORT_SUFFIX>".AFTER_LOGON_TRG
- Package:    : USER_GRANT in owner schema: To grant access rights to roles after object creation
- Synonym:    : GRANTTOROLES, which is a synonym for the USER_GRANT package (backward compatibility)

## 2. Script: drop_dev_users.sql

This scrip clean up the users framework, dependant of the following settings in the dev_users_env.sql script:
```
DEFINE DROP_USR=Y
DEFINE DROP_ROL=Y
DEFINE DROP_TBS=Y
DEFINE DROP_TRG=Y
```

## 3. Script: dev_users_env.sql

This script is called by the create_dev_users.sql and drop_dev_users.sql scripts, and sets important values for the user framework creation.
This is the only file that needs to be edited by the user.
