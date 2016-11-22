-- -------------------------------------------------------------------------------
--
-- Title: dev_users_env.sql
--
-- Description: 
-- This script set the environment variables for the scripts:
--      - create_dev_users.sql
--      - drop_dev_users.sql
--
-- Usage:
--      - This script is not run standalone, 
--        but called by the scripts listed above.
--
-- Author: Lasse Jenssen, lasse.jenssen@evry.com
-- Date:   13.Aug 2015
--
-- Version: 1.7
--
-- History
-- 13.aug 2015 - v1.0 - Lasse Jenssen      : Initial script (for testing)
-- 13.oct 2015 - v1.1 - Lasse Jenssen      : First official release
-- 22.nov 2016 - v1.7 - Lasse Jenssen      : Synchronized with version 1.7
-- -------------------------------------------------------------------------------

-- -------------------------------------------------------------------------------
-- Set the following parameters
-- -------------------------------------------------------------------------------

-- ORA_VERSION:      The Oracle version (default 12)
-- SWITCH_TO_PDB:    (Y/N) Controls if we should switch to the PBD "PBD_NAME"
-- PBD_NAME:         The name of the plugable database (only if version 12 and above)
-- CREATE_SCRIPT:    (Y/N) where 
--                       N - Everything is ran towards the database, 
--                       Y - Only script is created)
-- APP_NAME          The application name
-- SET_PROFILE       (Y/N) Y if we should assign a profile to the users
-- PROFILE_NAME      Name of the profile assigned to users
-- OWNER_GRANTS      Priveleges granted to data owner
-- TBS_AUTOEXTEND    (Y/N) Y if tbs should use AUTOEXTEND feature
-- TBS_OMF_USE       (Y/N) Y if Oracle Managed Files is to be used
--                   Note! Parameter DB_CREATE_FILE_DEST needs to be set
-- TBS_DIR           Path to files in tablespaces
-- TBS_ASM_USE       (Y/N) Y if ASM is to be used, else N
--                   Note! Will not work if TBS_OMF_USE set to "Y"
-- TBS_ASM_DGRP      Spesify name of disk group if ASM enabled
-- TBS_BIGFILE       (Y/N) Y if we should use BIGFILE. NB! BIGFILE TBS must be at least 10MB
-- TBS_ENCRYPT       (Y/N) Y if we should use encryption
-- TBS_ENCRYPT_TYPE  Encryption type
-- TBS_SIZE          Size for data tablespace
-- TBS_IDX_SIZE      Size for index tablespace
-- TBS_LOB_SIZE      Size for lob tablepace
--
-- ATOMIKOS_ENABLE   (Y/N) Y to enable XA (Atomikos), N to disable
--                   "Y" will grant necessary rights to read-write role to enable use of atomikos.
--
-- DEBUG             (Y/N) Y to enable debug(output statements to screen), N to disable.
-- 
-- Variables to control what do drop when running "drop_dev_users.sql"
-- DROP_USR          (Y/N) Y to drop users when running "drop_dev_users.sql"
-- DROP_ROL          (Y/N) Y to drop roles when running "drop_dev_users.sql"
-- DROP_TBS          (Y/N) Y to drop tablespaces when running "drop_dev_users.sql"
-- DROP_TRG          (Y/N) Y to drop triggers when running "drop_dev_users.sql"

DEFINE CREATE_SCRIPT=N

DEFINE APP_NAME="DEV"
DEFINE SET_PROFILE=N
DEFINE PROFILE_NAME="dummy"
DEFINE OWNER_GRANTS='create table, create view, create materialized view, create sequence, create procedure, create type, create trigger, create synonym, create database link'

DEFINE ORA_VERSION="&1"
DEFINE SWITCH_TO_PDB=Y
DEFINE PDB_NAME=ORCL

DEFINE TBS_AUTOEXTEND=Y
DEFINE TBS_OMF_USE=N
DEFINE TBS_DIR="/u01/app/oracle/oradata/orcl"
DEFINE TBS_ASM_USE=N
DEFINE TBS_ASM_DGRP="+disk_group"
DEFINE TBS_BIGFILE=N
DEFINE TBS_ENCRYPT=N
DEFINE TBS_ENCRYPT_TYPE="DEFAULT"
DEFINE TBS_SIZE="20M"
DEFINE TBS_IDX_SIZE="10M"
DEFINE TBS_LOB_SIZE="10M"

DEFINE DEBUG=N

DEFINE ATOMIKOS_ENABLE=N

DEFINE DROP_USR=Y
DEFINE DROP_ROL=Y
DEFINE DROP_TBS=Y
DEFINE DROP_TRG=Y

-- -------------------------------------------------------------------------------
-- ------ DO NOT EDIT BELOW THIS LINE --------------------------------------------
-- -------------------------------------------------------------------------------
-- OWNER_SUFFIX      Suffix for data owner name: <APP_NAME><OWNER_SUFFIX>
-- SUPPORT_SUFFIX    Suffix for support user:    <APP_NAME><SUPPORT_SUFFIX>
-- TRG_PREFIX        Prefix for login triggers 

DEFINE OWNER_SUFFIX=DATA
DEFINE SUPPORT_SUFFIX=SUPP
DEFINE TRG_PREFIX=TRG_
DEFINE TBS_DATA_SUFFIX=DATA
DEFINE TBS_LOB_SUFFIX=LOB
DEFINE TBS_IDX_SUFFIX=IDX
-- -------------------------------------------------------------------------------
