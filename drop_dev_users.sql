-- -------------------------------------------------------------------
--
-- Title: drop_dev_users.sql
--
-- Description: 
-- This script drops:
--      - Tablespaces "<APP_NAME>_DATA", "<APP_NAME>_IDX"
--      - Users "<APP_NAME><OWNER_SUFFIX>","<APP_NAME>","<APP_NAME><SUPPORT_SUFFIX>"
--      - Roles "<APP_NAME>_RW", "<APP_NAME>_RO"
--      - Triggers "<APP_NAME>.AFTER_LOGON_TRG", "<APP_NAME><SUPPORT_SUFFIX>".AFTER_LOGON_TRG
--
-- Usage:
--      - Run as SYSTEM (or other user with DBA role) or SYSDBA
--      - Setting ORA_VERSION to 12 will make it switch into the PBD named "PBD_NAME"
--
-- Notes:
--      - Set variables in environment script (dev_users_env.sql) 
-- 
-- Author: Lasse Jenssen, lasse.jenssen@evry.com
-- Date:  20 Nov 2013
--
-- Version: 1.7
--
-- History
-- 01.feb 2013 - v1.0 - Lasse Jenssen    : Initial script (for testing)
-- 12.jan 2014 - v1.1 - Lasse Jenssen    : First official release
-- 24.apr 2014 - v1.2 - Lasse Jenssen    : Added Atomikos support
-- 21.may 2015 - v1.3 - Lasse Jenssen    : Support for Oracle versions ++
-- 12.aug 2015 - v1.4 - Sigmund Orjavik  : Support for PDB, 
--                                         Increased APP_NAME to varchar(25)
-- 13.aug 2015 - v1.5 - Lasse Jenssen    : Common file for variables
--                                         Refactored design of script
-- 22.nov 2016 - v1.7 - Lasse Jenssen    : Syncked with v1.7
-- -------------------------------------------------------------------

-- Environment Variables is set by the user in the DEV_USERS_ENV.SQL script
@dev_users_env.sql &1

set serveroutput on
set verify off
set feedback off
set lines 120

-- -------------------------------------------------------------------
-- Startup Message
-- -------------------------------------------------------------------
DECLARE
   procedure log(txt_i IN varchar2) as
   begin
     dbms_output.put_line('* '||rpad(txt_i,76,' ')||' *');
   end;
BEGIN
   log(rpad('-',76,'-'));
   log(chr(8));
   log('Script: drop_dev_users.sql');
   log(chr(8));
   log('Description: This script is potensially dropping');
   log('             users, roles, tablespaces and login trigger.');
   log(chr(8));
   log('Author: Lasse Jenssen, CoE - Database mailto: lasse.jenssen@evry.com');
   log(chr(8));
   log('Note! Before running please set the required parameters ');
   log('      in environment script (dev_users_env.sql) .');
   log(chr(8));
   log(rpad('-',76,'-'));
END;
/

prompt 
-- NOTE! Unomment the PAUSE below for an interactive script
-- pause Press Enter to Continue ... (CNTR + C ENTER to abourt)

-- -------------------------------------------------------------------
-- Warning Message: Script is running (Please wait ...)
-- -------------------------------------------------------------------
DECLARE
   g_cre_scr       boolean         := case when '&CREATE_SCRIPT'='N' then false else true end;
   procedure log(txt_i IN varchar2) as
   begin
     dbms_output.put_line('* '||rpad(txt_i,76,' ')||' *');
   end;
BEGIN
   if not g_cre_scr then
      log(rpad('-',76,'-'));
      log(chr(8));
      log('Warning! Script is running (please wait ...)');
      log(chr(8));
      log(rpad('-',76,'-'));
   end if;
END;
/

-- -------------------------------------------------------------------
-- If plugable set Container(if SWITCH_TO_PDB=Y)
-- -------------------------------------------------------------------
DECLARE
   l_switch_to_pdb char(1)          := '&SWITCH_TO_PDB';
   l_ora_version   number           := &ORA_VERSION;
   l_pdb_name      varchar2(50)     := '&PDB_NAME';
BEGIN
   if l_ora_version >=12 and l_switch_to_pdb='Y' then
      execute immediate 'alter session set container=' || l_pdb_name ;
      dbms_output.put_line('Successfully set container(PBD) to ' || l_pdb_name );
      dbms_output.put_line(chr(10));
   end if;
EXCEPTION 
   when others then
      raise_application_error(-20001, 'ERROR: Failed to set container(PBD) to ' || l_pdb_name);
END;
/

-- Need to be reset because of possible login into PLUGABLE database
set serveroutput on size 1000000
set verify off
set feedback off
set lines 120

DECLARE -- MAIN 
   -- Defining EXCEPTIONS
   app_name_error EXCEPTION;
   pdb_ora_version_error EXCEPTION;
   illegal_user_error EXCEPTION;
   illegal_user_xa_error EXCEPTION;

   -- "Global" variables from "dev_users_env.sql"
   g_cre_scr       boolean         := case when '&CREATE_SCRIPT'='N' then false else true end;

   g_app_name      varchar2(200)   := '&APP_NAME';
   g_own_suff      varchar2(10)    := '&OWNER_SUFFIX';
   g_sup_suff      varchar2(10)    := '&SUPPORT_SUFFIX';
   g_owner         varchar2(30)    := g_app_name || g_own_suff;
   g_support       varchar2(30)    := g_app_name || g_sup_suff;

   g_ro_role       varchar2(30)    := g_app_name || '_RO';
   g_rw_role       varchar2(30)    := g_app_name || '_RW';

   g_ora_version   number          := &ORA_VERSION;
   g_switch_to_pdb char(1)         := '&SWITCH_TO_PDB';
   g_pdb_name      varchar2(50)    := '&PDB_NAME';

   g_own_grnt      varchar2(1000)  := '&OWNER_GRANTS';

   g_tbs           varchar2(30)    := g_app_name || '_' || '&TBS_DATA_SUFFIX';
   g_tbs_idx       varchar2(30)    := g_app_name || '_' || '&TBS_IDX_SUFFIX';
   g_tbs_lob       varchar2(30)    := g_app_name || '_' || '&TBS_LOB_SUFFIX';
   g_tbs_size      varchar2(10)    := '&TBS_SIZE';
   g_tbs_idx_size  varchar2(10)    := '&TBS_IDX_SIZE';
   g_tbs_lob_size  varchar2(10)    := '&TBS_LOB_SIZE';
   
   g_tbs_auto_use  char(1)         := '&TBS_AUTOEXTEND';
   g_tbs_omf_use   char(1)         := '&TBS_OMF_USE';
   g_tbs_asm_use   char(1)         := '&TBS_ASM_USE';
   g_tbs_asm_dgrp  varchar2(30)    := '&TBS_ASM_DGRP';
   g_tbs_dir       varchar2(100)   := '&TBS_DIR';

   g_trg_pref      varchar2(10)    := '&TRG_PREFIX';

   g_debug         boolean         := case when '&DEBUG'='Y' then true else false end;

   g_xa_enable     boolean         := case when '&ATOMIKOS_ENABLE'='N' then false else true end;

   -- Other variables used in script
   g_grant_pkg     varchar2(30)    :='USER_GRANT';

   -- Only for this file (drop_dev_users.sql)
   g_drop_users    boolean         := case when '&DROP_USR'='Y' then true else false end;
   g_drop_roles    boolean         := case when '&DROP_ROL'='Y' then true else false end;
   g_drop_tbs      boolean         := case when '&DROP_TBS'='Y' then true else false end;
   g_drop_trg      boolean         := case when '&DROP_TRG'='Y' then true else false end;
   
   procedure log(txt_i varchar2) as
      l_txt varchar2(200);
   begin
      l_txt:=txt_i;
      -- If generating script, make log text to a comment
      if g_cre_scr then
         l_txt:='-- ' || l_txt;
      end if;
      dbms_output.put_line(l_txt);
   end;

   procedure log_sql(txt_i varchar2) as
   begin
      dbms_output.put_line(txt_i||';');
   end;

   procedure debug(txt_i varchar2) as
   begin
      if g_debug then
         dbms_output.put_line('DEBUG: ' || txt_i);
      end if;
   end;
   
   procedure log_exception(txt_i varchar2) as
      p_header varchar2(100):= 'Scripted terminated because of ...';
      p_contact varchar2(50):= 'If help needed contact lasse.jenssen@evry.com';
      p_width number        := 76;
      p_text varchar2(1000);
   begin
      p_text := 'EXCEPTION: ' || txt_i;
      dbms_output.put_line('-- * '||rpad('',p_width,'-')||' * --');
      dbms_output.put_line('-- * '||rpad(p_header,p_width,' ')||' * --');
      dbms_output.put_line('-- * '||rpad(p_text,p_width,' ')||' * --');
      dbms_output.put_line('-- * '||rpad(p_contact,p_width,' ')||' * --');
      dbms_output.put_line('-- * '||rpad('',p_width,'-')||' * --');
   end;
   
   procedure log_env(name_i varchar2, txt_i varchar2) as
      p_width number        := 20;
   begin
      dbms_output.put_line(rpad(name_i,p_width,' ')|| ' : ' || txt_i);
   end;

   procedure print_settings as
   begin
      log('*** --------------------------------------------- ***');
      log('*** ENVIRONMENT SETTINGS:                         ***');
      log('*** --------------------------------------------- ***');
      log_env('Data Owner',              g_owner);
      log_env('Application User',        g_app_name);
      log_env('Support User',            g_support);
      log_env('Oracle Version',          g_ora_version);
      log_env('Grant Package',           g_grant_pkg);
      log_env('Read-Only Role',          g_ro_role);
      log_env('Read-Write Role',         g_rw_role);
      log_env('Atomikos Enabled',        case when g_xa_enable then 'TRUE' else 'FALSE' end);
      if g_tbs_asm_use='N' then
         log_env('Tablespace Directory', g_tbs_dir);
      else
         log_env('ASM Disk Group',       g_tbs_dir);
      end if;
      if g_switch_to_pdb='Y' then
         log_env('Plugable Name',        g_pdb_name);
      end if;
      log('*** --------------------------------------------- ***');
   end;

   procedure drop_user(user_i varchar2) as
      l_cnt number;
      l_sql varchar2(100);
   begin
      l_sql := 'DROP USER ' || user_i || ' CASCADE';

      if g_cre_scr then
         log_sql(l_sql);
      else
         select count(*) into l_cnt from dba_users where username = upper(user_i);

         if l_cnt>0 then
            begin
               execute immediate 'drop user ' || user_i || ' cascade';
               log('User '||user_i||' dropped');
            exception when others then
               log('ERROR: Dropping '|| user_i ||' failed: ' || SQLERRM);
            end;
         else
            log('User '|| user_i ||' does not exist.'); 
         end if;
      end if;
   end;

   procedure drop_role(role_i varchar2) as
      l_cnt number;
      l_sql varchar2(100);
   begin
      l_sql := 'DROP ROLE ' || role_i;
      
      if g_cre_scr then
         log_sql(l_sql);
      else 
         select count(*) into l_cnt from dba_roles where role = upper(role_i);

         if l_cnt>0 then
            begin
               execute immediate 'drop role ' || role_i;
               log('Role '|| role_i ||' dropped.');
            exception when others then
               log('ERROR: Dropping '|| role_i ||' failed: ' || SQLERRM);
            end;
         else
            log('Role '|| role_i ||' does not exist.');
         end if;
      end if;
   end;

   procedure drop_tablespace (tbs_i varchar2) as
      l_cnt number;
      l_sql varchar2(100);
   begin
      l_sql:= 'DROP TABLESPACE ' || tbs_i || ' INCLUDING CONTENTS AND DATAFILES';

      if g_cre_scr then
         log_sql(l_sql);
      else
         select count(*) into l_cnt from dba_tablespaces where tablespace_name = upper(tbs_i);

         if l_cnt>0 then
            begin
               execute immediate l_sql;
               log('Tablespace '|| tbs_i ||' dropped');
            exception when others then
               log('ERROR: Dropping '|| tbs_i ||' failed: ' || SQLERRM);
            end;      
         else
            log('Tablespace '|| tbs_i ||' does not exist.');
         end if;
      end if;
   end;

   procedure drop_trigger(trigger_i IN varchar2) as
      l_cnt number;
      l_sql varchar2(100);
   begin
      l_sql:= 'DROP TRIGGER ' || trigger_i;

      if g_cre_scr then
         log_sql(l_sql);
      else
         select count(*) into l_cnt from dba_triggers where trigger_name = upper(trigger_i);

         if l_cnt>0 then
            begin
               execute immediate l_sql;
               log('Trigger '|| trigger_i ||' dropped');
            exception when others then
               log('ERROR: Dropping trigger '|| trigger_i ||' failed: ' || SQLERRM);
            end;
         else
            log('Trigger '|| trigger_i ||' does not exist(Possibly dropped with user).');
         end if;
      end if;
   end;
   
BEGIN -- MAIN
   -- -------------------------------------------------------------------
   -- Sanity Check of Variables and Users
   -- -------------------------------------------------------------------
   
   -- Check that APP_NAME is 1-25 characters (and objects no more than 30)
   -- Note! Because of TABLESPACE naming APP_NAME || '_DATA' 
   --       the max characters for APP_NAME is 25
   if length(g_app_name)>25 then
      raise app_name_error;
   end if;

   -- If SWITCH_TO_PDB=Y the ORA_VERSION must be 12 or above
   -- if g_switch_to_pdb='Y' and g_ora_version<12 then
   --    raise pdb_ora_version_error;
   -- end if;
 
   -- Check if script ran as appropriate user rights
   -- Generally needs to be ran as SYSTEM
   if (USER not in ('SYS','SYSTEM')) then
      raise illegal_user_error;
   end if;
      
   -- If ATOMIKOS_ENABLE=Y then need to be ran as SYSDBA
   if (g_xa_enable AND USER!='SYS') then
      raise illegal_user_xa_error;
   end if;

   -- -------------------------------------------------------------------
   -- Print Settings (if CREATE_SCRIPT=N)
   -- -------------------------------------------------------------------
   if not g_cre_scr then
      print_settings;
   end if;

   log('*** --------------------------------------------- ***');
   log('***      Dropping USERS (waiting)                 ***');
   log('*** --------------------------------------------- ***');

   if g_drop_users then
      drop_user(g_owner);
      drop_user(g_support);
      drop_user(g_app_name);
   else
      log('Users not configured to be dropped.');
   end if;

   log('*** --------------------------------------------- ***');
   log('***      Dropping ROLES                           ***');
   log('*** --------------------------------------------- ***');

   if g_drop_roles then
      drop_role(g_ro_role);
      drop_role(g_rw_role);
   else
      log('Roles not configured to be dropped.');
   end if;

   log('*** --------------------------------------------- ***');
   log('***      Dropping Tablespaces (waiting)           ***');
   log('*** --------------------------------------------- ***');

   if g_drop_tbs then
      drop_tablespace(g_tbs);
      drop_tablespace(g_tbs_idx);
      drop_tablespace(g_tbs_lob);
   else
      log('Tablespaces not configured to be dropped.');
   end if;

   log('*** --------------------------------------------- ***');
   log('***      Dropping Triggers                        ***');
   log('*** --------------------------------------------- ***');

   if g_drop_users then
      log('Triggers dropped with users.');
   elsif g_drop_trg then
      drop_trigger(g_trg_pref||g_app_name);
      drop_trigger(substr(g_trg_pref||g_app_name||g_sup_suff,1,30));
   else
      log('Triggers not configured to be dropped.');
   end if;

EXCEPTION -- MAIN
   when app_name_error then
      log_exception('Configuration Error: APP_NAME must be 1-25 characters');
   when pdb_ora_version_error then 
      log_exception('Config Error: When PBD in use (SWITCH_TO_PDB=Y) then ORA_VERSION must 12 or above.');
   when illegal_user_error then
      log_exception('Script must be ran as SYSTEM or SYSDBA');
   when illegal_user_xa_error then     
      log_exception('Enabling Atomikos has to be ran as SYSDBA');  
END; -- MAIN
/
