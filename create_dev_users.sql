-- -------------------------------------------------------------------
--
-- Title: create_dev_users.sql
--
-- Description: 
-- This script creates:
--      - Tablespaces : "<APP_NAME>_DATA", "<APP_NAME>_IDX", "<APP_NAME>_LOBS"(optional)
--      - Users       : "<APP_NAME><OWNER_SUFFIX>","<APP_NAME>","<APP_NAME><SUPPORT_SUFFIX>"
--      - Roles       : "<APP_NAME>_RW", "<APP_NAME>_RO"
--      - Triggers    : "<APP_NAME>.AFTER_LOGON_TRG", "<APP_NAME><SUPPORT_SUFFIX>".AFTER_LOGON_TRG 
--      - Package:    : USER_GRANT in owner schema: To grant access rights to roles after object creation
--      - Synonym:    : GRANTTOROLES, which is a synonym for the USER_GRANT package (backward compatibility)
--
-- Usage: create_dev_users.sql [version]
-- Notes: 
--      - Run as SYSTEM (or other user with DBA role) or SYSDBA
--      - Note! If ATOMIKOS_ENABLE is Y, then run as SYSDBA
--      - Set variables in environment script (dev_users_env.sql) 
--
-- Author: Lasse Jenssen, lasse.jenssen@rightconsulting.no
-- Date:   22.Nov 2016
--
-- Version: 1.7
-- 
-- History
-- 01.feb 2013 - v1.0 - Lasse Jenssen      : Initial script (for testing)
-- 12.jan 2014 - v1.1 - Lasse Jenssen      : First official release
-- 24.apr 2014 - v1.2 - Lasse Jenssen      : Added Atomikos support
-- 21.may 2015 - v1.3 - Lasse Jenssen      : Support for Oracle versions ++
-- 12.aug 2015 - v1.4 - Sigmund Orjavik    : Support for PDB, 
--                                           Increased APP_NAME to varchar(25)
-- 13.aug 2015 - v1.5 - Lasse Jenssen      : Common file for variables
--                                           Refactored design of script
-- 03.sep 2016 - v1.6 - Sigmund Orjavik    : Support for BIGFILE tablespaces
--                                           Support for profiles
-- 15.sep 2016 - v1.7 - Sigmund Orjavik    : Support for encrypted tablespaces
-- -------------------------------------------------------------------

-- Environment Variables is set by the user in the DEV_USERS_ENV.SQL script
-- Argument: Oracle Version - for instance 11 or 12
@dev_users_env.sql &1         

WHENEVER SQLERROR EXIT SQL.SQLCODE
set serveroutput on size 1000000
set verify off
set feedback off
set lines 120

-- -------------------------------------------------------------------
-- Startup Message
-- -------------------------------------------------------------------
DECLARE
   l_cre_scr       boolean         := case when '&CREATE_SCRIPT'='N' then false else true end;
   
   procedure log(txt_i IN varchar2) as
   begin
     dbms_output.put_line('-- * '||rpad(txt_i,76,' ')||' * --');
   end;
BEGIN
   log(rpad('-',76,'-'));
   log(chr(8));

   if l_cre_scr then
      log('Script: Save as "create_app_users_env.sql" ');
      log(chr(8));
      log('Description:');
      log('  Script to generate an application environment in Oracle');
      log('Use:');
      log('  Run as SYSTEM (or SYSDBA if ATOMIKOS_ENABLE=Y)');
      log('----- Script start below ----------------------------------------------------');
   else
      log('Script: create_dev_users.sql');
      log(chr(8));
      log('Use:');
      log('  Run as SYSTEM (or SYSDBA if ATOMIKOS_ENABLE=Y)');
      log(chr(8));
      log('Description: This script is potensially creating');
      log('             users, roles, tablespaces and login triggers');
      log('             for an test or development environment.');
      log(chr(8));
      log('Author: Lasse Jenssen, CoE - Database mailto: lasse.jenssen@evry.com');
      log(chr(8));
      log('Note! Before running please set the required parameters ');
      log('      in environment script (dev_users_env.sql) .');
   end if;
   
   log(chr(8));
   log(rpad('-',76,'-'));
END;
/

prompt 
-- NOTE! Unomment the PAUSE below for an interactive script
-- pause Press Enter to Continue ... (CNTR + C ENTER to abort)

-- -------------------------------------------------------------------
-- If pluggable set Container(if SWITCH_TO_PDB=Y)
-- -------------------------------------------------------------------
DECLARE
   l_switch_to_pdb char(1)          := '&SWITCH_TO_PDB';
   l_ora_version   number           := &ORA_VERSION;
   l_pdb_name      varchar2(50)     := '&PDB_NAME';
BEGIN
   if l_ora_version>=12 and l_switch_to_pdb='Y' then
      execute immediate 'alter session set container=' || l_pdb_name ;
      dbms_output.put_line('Successfully set container(PDB) to ' || l_pdb_name );
      dbms_output.put_line(chr(10));
   end if;
EXCEPTION 
   when others then
      raise_application_error(-20001, 'ERROR: Failed to set container(PDB) to ' || l_pdb_name);
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
   g_set_profile   char(1)         := '&SET_PROFILE';
   g_profile_name  varchar2(30)    := '&PROFILE_NAME';
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
   g_tbs_bigfile   char(1)         := '&TBS_BIGFILE';
   g_tbs_encrypt   char(1)         := '&TBS_ENCRYPT';
   g_tbs_encrypt_type varchar2(30) := '&TBS_ENCRYPT_TYPE';
   g_tbs_dir       varchar2(100)   := '&TBS_DIR';

   g_trg_pref      varchar2(10)    := '&TRG_PREFIX';

   g_debug         boolean         := case when '&DEBUG'='Y' then true else false end;

   g_xa_enable     boolean         := case when '&ATOMIKOS_ENABLE'='N' then false else true end;

   -- Other variables used in script
   g_grant_pkg     varchar2(30)    :='USER_GRANT';
   
   procedure log(txt_i varchar2) as
   begin
      dbms_output.put_line(txt_i);
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

   procedure create_tbs(tbs_i varchar2, tbs_size_i varchar2) as
      l_filename varchar2(100);
      l_sql varchar2(1000);
      l_cnt number;
   begin
      l_filename := case when g_tbs_asm_use='Y' then g_tbs_asm_dgrp  
                         else g_tbs_dir || '/' || tbs_i || '01.dbf'
                    end;
      l_sql := 'CREATE ' || 
                    case when g_tbs_bigfile='Y' then 'BIGFILE ' else '' end ||'TABLESPACE ' || tbs_i || ' datafile ' ||
                    case when g_tbs_omf_use!='Y' then '''' || l_filename || '''' else '' end || ' SIZE ' || tbs_size_i ||
                    case when g_tbs_auto_use='Y' then ' autoextend on maxsize unlimited' else '' end ||
                    case when g_tbs_encrypt='Y' then ' encryption '|| g_tbs_encrypt_type ||' storage(encrypt)' else '' end;
      if g_cre_scr then
         log(l_sql || ';');
      else
         debug('CREATE TABLESPACE:');
         debug(l_sql || ';');
         select count(*) into l_cnt from dba_tablespaces where upper(tablespace_name)=upper(tbs_i);
         if l_cnt=0 then
            begin
               execute immediate l_sql;
               log('Creating tablespace ' || tbs_i ||' succeeded.');
            exception when others then
               log('ERROR: Creating tablespace ' || tbs_i ||' failed.');
            end;
         else
            log('Tablespace ' || tbs_i || ' exists.');
         end if;
      end if;
   end;

   procedure create_role(role_i varchar2) as
      l_sql varchar2(1000);
      l_cnt number;
   begin
      l_sql    := 'CREATE ROLE ' || role_i;

      if g_cre_scr then
         log(l_sql || ';');
      else
         debug('CREATE ROLE:');
         debug(l_sql || ';');
         select count(*) into l_cnt from dba_roles where upper(role)=upper(role_i);
         if l_cnt=0 then
            begin
               execute immediate l_sql;
               log('Creating role ' || role_i ||' succeeded.');
            exception when others then
               log('ERROR: Creating role ' || role_i ||' failed:' || SQLERRM);
            end;
         else
            log('Warning: The role '|| upper(role_i) || ' already exists.');
         end if;
      end if;
   end;
   
   procedure grant_role(grant_i varchar2, object_i varchar2, role_i varchar2) as
      l_sql varchar2(1000);
   begin
      l_sql    := 'GRANT ' || grant_i || ' ON ' || object_i || ' TO ' || role_i;
      if g_cre_scr then
         log(l_sql || ';');
      else
         debug('GRANT ROLE:');
         debug(l_sql || ';');
         begin
            execute immediate l_sql;
            log('Granting '|| grant_i || ' on ' || object_i || ' to ' || role_i || ' succeeded');
         exception when others then
            log('ERROR: Granting ' || grant_i || ' on ' || object_i || ' to ' || role_i || ' failed:' || SQLERRM);
         end;
      end if;
   end;

   procedure grant_role_to_user(role_i IN dba_roles.role%type, user_i IN varchar2) as
      l_sql varchar2(1000):= 'Not set';
   begin
      l_sql := 'GRANT ' || role_i || ' TO ' || user_i;
      
      if g_cre_scr then
         log(l_sql || ';');
      else
         debug('GRANT ROLE TO USER:');
         debug(l_sql || ';');
         execute immediate l_sql;
         log('User ' || user_i || ' granted ' || role_i || ' successfully.');
      end if;
   exception when others then
      log('ERROR: Granting role ' || role_i || ' to ' || user_i || ' failed:' || SQLERRM); 
   end;

   procedure create_user(user_i IN varchar2, owner_i IN boolean default false) as
      l_sql_usr       varchar2(2000);
      l_sql_grnt      varchar2(1000);
      l_sql_grnt_own  varchar2(1000);
      p_cnt           number;
   begin
      l_sql_usr   := 'CREATE USER ' || user_i ||' IDENTIFIED BY ' || lower(g_app_name) || 
                        ' DEFAULT TABLESPACE ' || g_tbs || ' TEMPORARY TABLESPACE temp ' ||
                        case when owner_i=false then '' 
                             else ' QUOTA UNLIMITED ON '|| g_tbs || ' QUOTA UNLIMITED ON ' || g_tbs_idx || ' QUOTA UNLIMITED ON ' || g_tbs_lob
                        end ||
                        case when g_set_profile='Y' then ' PROFILE ' || g_profile_name else '' end;
      l_sql_grnt     := 'GRANT create session TO '|| user_i;
      l_sql_grnt_own := 'GRANT ' || g_own_grnt || ' TO ' || user_i; 

      if g_cre_scr then
         log(l_sql_usr || ';');
         log(l_sql_grnt || ';');
         if owner_i then 
            log(l_sql_grnt_own || ';');
         end if;
      else
         select count(*) into p_cnt from dba_users where username=user_i;
         if p_cnt=0 then
            begin
               debug('CREATE USER '|| user_i||':');
               debug(l_sql_usr || ';');
               execute immediate l_sql_usr;
               log('User ' || user_i || ' created successfully.');
            exception when others then
               log('ERROR: Creating user ' || user_i || ' failed:' || SQLERRM);
            end;
            begin
               debug('Grant CREATE SESSION to ' || user_i ||':');
               debug(l_sql_grnt || ';');
               execute immediate l_sql_grnt;
               log('User ' || user_i || ' granted CREATE SESSION successfully');
            exception when others then
               log('ERROR: Granting create session to ' || user_i || ' failed:' || SQLERRM);
            end;

            if owner_i then
               begin
                  debug('Grant OWNER grants to ' || user_i ||':');
                  debug(l_sql_grnt_own || ';');
                  execute immediate l_sql_grnt_own;
                  log('User ' || user_i || ' granted owner rights successfully.');
               exception when others then
                  log('ERROR: Granting owner rights to ' || user_i || ' failed:' || SQLERRM);
               end;
            end if;
         else
            log('User ' || user_i || ' allready exist!');
         end if;
      end if;
   end;

   procedure create_logon_trigger(user_i IN varchar2) as
      l_sql varchar2(2000):= 'Not set';
      p_name varchar2(30);
   begin
      p_name := substr(g_trg_pref || user_i,1,30);
      l_sql := 'CREATE OR REPLACE TRIGGER ' || p_name ||  chr(10) ||
               '   AFTER LOGON ON '|| user_i || '.SCHEMA' || chr(10) ||  
               'BEGIN ' || chr(10) ||
               '   EXECUTE IMMEDIATE ''ALTER SESSION SET current_schema=' || g_owner || '''; ' || chr(10) ||
               'END;';
      if g_cre_scr then
         log(l_sql);
         log('/');
      else
         begin
            execute immediate l_sql;
            log('Trigger ' || p_name || ' created successfully.'); 
         exception when others then
            log('ERROR: Creating logon trigger for ' || user_i || ' failed: ' || SQLERRM);
         end;
      end if; 
   end;

   procedure set_db_create_file_dest as
      l_sql varchar2(1000);
   begin
      l_sql :='ALTER SYSTEM SET DB_CREATE_FILE_DEST="'|| g_tbs_dir ||'" scope=both' ;

      debug('ALTER SYSTEM:');
      debug(l_sql || ';');
      execute immediate l_sql;
      log('Successfully set parameter DB_CREATE_FILE_DEST to ' || g_tbs_dir);
      log(chr(10));
   exception 
      when others then
         log('ERROR: Failed to set parameter DB_CREATE_FILE_DEST.');
   end set_db_create_file_dest;

   procedure create_grant_pkg as
      l_sql_big varchar2(4000);
   begin
      l_sql_big := 'CREATE OR REPLACE PACKAGE ' || g_owner || '.' || g_grant_pkg || ' AS ' || chr(10) ||
                '    APP_NAME       CONSTANT  varchar2(' || length(g_app_name) ||') := ''' || g_app_name || ''';' || chr(10) ||
                '    SUPP_USR       CONSTANT  varchar2(' || length(g_support)  ||') := ''' || g_support  || ''';' || chr(10) ||
                '    DATA_USR       CONSTANT  varchar2(' || length(g_owner)    ||') := ''' || g_owner    || ''';' || chr(10) ||
                '    ROLE_NAME_RW   CONSTANT  varchar2(' || length(g_rw_role)  ||') := ''' || g_rw_role  || ''';' || chr(10) ||
                '    ROLE_NAME_RO   CONSTANT  varchar2(' || length(g_ro_role)  ||') := ''' || g_ro_role  || ''';' || chr(10) || chr(10) ||
                '    procedure grantToRoles;' || chr(10) ||
                'END;';
      if g_cre_scr then
         log(l_sql_big);
         log('/');
      else
         begin
            execute immediate l_sql_big;
            log('Package ' || g_grant_pkg || ' created successfully.'); 
         exception when others then
            log('ERROR: Creating package ' || g_grant_pkg || ' failed: ' || SQLERRM);
         end;
      end if;
   end;

   procedure create_grant_pkg_body as
      l_sql_big varchar2(32000);
   begin
      l_sql_big := 'CREATE OR REPLACE PACKAGE BODY ' || g_owner || '.' || g_grant_pkg || ' AS ' || chr(10) ||
                '    PROCEDURE log(txt_i IN varchar2) AS' || chr(10) ||
                '    BEGIN' || chr(10) ||
                '       dbms_output.put_line(txt_i);' || chr(10) ||
                '    END;' || chr(10) || chr(10) ||
                '    PROCEDURE grant_to_roles(obj_name_i IN varchar2, obj_type_i IN varchar2) AS ' || chr(10) ||
                '       l_sql varchar2(200);' || chr(10) ||
                '    BEGIN' || chr(10) ||
                '       -- Grant to RW role' || chr(10) ||
                '       l_sql := ''GRANT '' || case obj_type_i when ''TABLE''     then ''SELECT, INSERT, UPDATE, DELETE''' || chr(10) ||
                '                                            when ''VIEW''      then ''SELECT''' || chr(10) ||
                '                                            when ''SEQUENCE''  then ''SELECT''' || chr(10) ||
                '                                                             else ''EXECUTE'' end || ' || chr(10) ||
                '                        '' ON '' || obj_name_i || '' TO '' || ROLE_NAME_RW; ' || chr(10) ||
                '       begin' || chr(10) ||      
                '          execute immediate l_sql;' || chr(10) ||
                '          log(''Grant towards '' || obj_name_i || '' to '' || ROLE_NAME_RW || '' completed successfully.'');' || chr(10) || 
                '       exception when others then' || chr(10) ||
                '          log(''ERROR: Grant towards'' || obj_name_i || '' to '' || ROLE_NAME_RW || '' failed: '' || SQLERRM);' || chr(10) ||
                '       end;' || chr(10) || chr(10) ||
                '       -- Grant to RO role if table or view' || chr(10) ||
                '       if obj_type_i in (''TABLE'',''VIEW'') then ' || chr(10) ||
                '          l_sql := ''GRANT SELECT ON '' || obj_name_i || '' TO '' || ROLE_NAME_RO; '|| chr(10) ||
                '          begin' || chr(10) ||
                '             execute immediate l_sql;' || chr(10) ||
                '             log(''Grant towards '' || obj_name_i || '' to '' || ROLE_NAME_RO || '' completed successfully.'');' || chr(10) ||
                '          exception when others then' || chr(10) ||
                '             log(''ERROR: Grant towards'' || obj_name_i || '' to '' || ROLE_NAME_RO || '' failed: '' || SQLERRM);' || chr(10) ||
                '          end;' || chr(10) ||
                '       end if;' || chr(10) ||
                '    END;' || chr(10) || chr(10) ||
                '    PROCEDURE grantToRoles is' || chr(10) ||
                '    BEGIN ' || chr(10) ||
                '       dbms_output.enable(1000000);' || chr(10) ||
                '       FOR rec IN ( SELECT object_name,  object_type  FROM user_objects' || chr(10) ||
                '                    WHERE object_type IN (''TABLE'',''PACKAGE'',''PROCEDURE'',''FUNCTION'',''SEQUENCE'',''VIEW'',''TYPE'')' || chr(10) ||
                '                      AND NOT (object_type like ''%PACKAGE%'' and object_name=''' || g_grant_pkg ||'''))' || chr(10) ||
                '       LOOP' || chr(10) ||
                '          BEGIN' || chr(10) ||
                '             grant_to_roles(rec.object_name, rec.object_type);' || chr(10) ||
                '          EXCEPTION WHEN others THEN' || chr(10) ||
                '             dbms_output.   put_line(''Bad object_name=''  || rec.object_name);' || chr(10) ||
                '          END;' || chr(10) ||
                '       END LOOP;' || chr(10) ||
                '    END;' || chr(10) ||
                'END;';

      if g_cre_scr then
         log(l_sql_big);
         log('/');
      else
         begin
            execute immediate l_sql_big;
            log('Package body ' || g_grant_pkg || ' created successfully.'); 
         exception when others then
            log('ERROR: Creating package body' || g_grant_pkg || ' failed: ' || SQLERRM);
         end;
      end if;
   end;

   procedure create_grant_pkg_synonym as
      l_sql varchar2(200);
   begin
      l_sql := 'CREATE OR REPLACE SYNONYM ' || g_owner || '.GRANTTOROLES FOR ' || g_owner || '.' || g_grant_pkg;
      if g_cre_scr then
         log(l_sql);
         log('/');
      else
         begin
            execute immediate l_sql;
            log('Synonym for ' || g_grant_pkg || ' created successfully.'); 
         exception when others then
            log('ERROR: Creating synonym for ' || g_grant_pkg || ' failed: ' || SQLERRM);
         end;
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
   if g_switch_to_pdb='Y' and g_ora_version<12 then
      raise pdb_ora_version_error;
   end if;
 
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

   -- -------------------------------------------------------------------
   -- If TBS_OMF_USE=Y and TBS_ASM_USE=N set DB_CREATE_FILE_DEST
   -- -------------------------------------------------------------------
   if g_tbs_omf_use='Y' and g_tbs_asm_use='N' then
      set_db_create_file_dest;
   end if;
   
   -- -------------------------------------------------------------------
   -- Creating Tablespaces
   -- -------------------------------------------------------------------
   log('*** --------------------------------------------- ***');
   log('***      Creating TABLESPACES ... (waiting)       ***');
   log('*** --------------------------------------------- ***');
   
   create_tbs(g_tbs,      g_tbs_size);
   create_tbs(g_tbs_idx,  g_tbs_idx_size);
   create_tbs(g_tbs_lob,  g_tbs_lob_size);

   -- -------------------------------------------------------------------
   -- Creating ROLES and give GRANTS
   -- -------------------------------------------------------------------
   log('*** --------------------------------------------- ***');
   log('***      Creating ROLES and give GRANTS           ***');
   log('*** --------------------------------------------- ***');

   create_role(g_ro_role);
   create_role(g_rw_role);

   grant_role('SELECT', 'sys.dba_pending_transactions', g_rw_role);
   grant_role('SELECT', 'sys.pending_trans$',           g_rw_role);
   grant_role('SELECT', 'sys.dba_2pc_pending',          g_rw_role);
   
   if g_ora_version>=11 then
      grant_role('EXECUTE','sys.dbms_xa',               g_rw_role);
   else
      grant_role('EXECUTE','sys.dbms_system',           g_rw_role);
   end if;

   -- -------------------------------------------------------------------
   -- Creating Users
   -- -------------------------------------------------------------------
   log('*** --------------------------------------------- ***');
   log('***     Creating users ... (waiting)              ***');
   log('*** --------------------------------------------- ***');
   
   create_user(g_app_name,false);
   create_user(g_owner,true);
   create_user(g_support,false);

   grant_role_to_user(g_rw_role, g_app_name);
   grant_role_to_user(g_ro_role, g_support);

   -- -------------------------------------------------------------------
   -- Creating Triggers
   -- -------------------------------------------------------------------
   log('*** --------------------------------------------- ***');
   log('***     Creating triggers ...                     ***');
   log('*** --------------------------------------------- ***');

   create_logon_trigger(g_app_name);
   create_logon_trigger(g_support);

   -- -------------------------------------------------------------------
   -- Creating GRANT package ...
   -- -------------------------------------------------------------------
   log('*** --------------------------------------------- ***');
   log('***     Creating GRANT package ...                ***');
   log('*** --------------------------------------------- ***');

   create_grant_pkg;
   create_grant_pkg_body;
   create_grant_pkg_synonym; -- For backward compatibility

EXCEPTION -- MAIN
   when app_name_error then
      log_exception('Configuration Error: APP_NAME must be 1-25 characters');
   when pdb_ora_version_error then 
      log_exception('Config Error: When PDB in use (SWITCH_TO_PDB=Y) then ORA_VERSION must 12 or above.');
   when illegal_user_error then
      log_exception('Script must be ran as SYSTEM or SYSDBA');
   when illegal_user_xa_error then     
      log_exception('Enabling Atomikos has to be ran as SYSDBA');  
END; -- MAIN
/
