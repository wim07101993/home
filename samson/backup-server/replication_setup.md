1. Install postgres in the primary and standby server as usual. This requires only configure, make and make install.
2. Create the initial database cluster in the primary server as usual, using initdb.
3. Create a user named replication with REPLICATION privileges.
   ```sql
   CREATE ROLE replication WITH REPLICATION PASSWORD 'password' LOGIN;
   ```
4. Set up connections and authentication on the primary so that the standby server can successfully connect to the replication pseudo-database on the primary.
   ```bash
   $EDITOR postgresql.conf
   
   listen_addresses = '192.168.0.10'
   ```
   ```bash
   $EDITOR pg_hba.conf
   
   # The standby server must connect with a user that has replication privileges.
   # TYPE  DATABASE        USER            ADDRESS                 METHOD
   host  replication     replication     192.168.0.20/32         md5
   ```
5. Set up the streaming replication related parameters on the primary server.
   ```bash
   $EDITOR postgresql.conf

   # To enable read-only queries on a standby server, wal_level must be set to
   # "hot_standby". But you can choose "archive" if you never connect to the
   # server in standby mode.
   wal_level = hot_standby
   
   # Set the maximum number of concurrent connections from the standby servers.
   max_wal_senders = 5
   
   # To prevent the primary server from removing the WAL segments required for
   # the standby server before shipping them, set the minimum number of segments
   # retained in the pg_xlog directory. At least wal_keep_segments should be
   # larger than the number of segments generated between the beginning of
   # online-backup and the startup of streaming replication. If you enable WAL
   # archiving to an archive directory accessible from the standby, this may
   # not be necessary.
   wal_keep_segments = 32
   
   # Enable WAL archiving on the primary to an archive directory accessible from
   # the standby. If wal_keep_segments is a high enough number to retain the WAL
   # segments required for the standby server, this is not necessary.
   archive_mode    = on
   archive_command = 'cp %p /path_to/archive/%f'
   ```
6. Start postgres on the primary server.
7. Make a base backup by copying the primary server's data directory to the standby server.

   7.1. Do it with pg_(start|stop)_backup and rsync on the primary
   ```
   psql -c "SELECT pg_start_backup('label', true)"
   rsync -ac ${PGDATA}/ standby:/srv/pgsql/standby/ --exclude postmaster.pid
   psql -c "SELECT pg_stop_backup()"
   ```
   7.2. Do it with pg_basebackup on the standby
   In version 9.1+, pg_basebackup can do the dirty work of fetching the entire data directory of your PostgreSQL installation from the primary and placing it onto the standby server.

The prerequisite is that you make sure the standby's data directory is empty.

Make sure to remove any tablespace directories as well. You can find those directories with:

$ psql -c '\db'
If you keep your postgresql.conf and other config files in PGDATA, you need a backup of postgresql.conf, to restore after pg_basebackup.

After you've cleared all the directories, you can use the following command to directly stream the data from the primary onto your standby server. Run it as the database superuser, typically 'postgres', to make sure the permissions are preserved (use su, sudo or whatever other tool to make sure you're not root).

$ pg_basebackup -h 192.168.0.10 -D /srv/pgsql/standby -P -U replication --xlog-method=stream
In version 9.3+, you can also add the -R option so it creates a minimal recovery command file for step 9 below.

If you backed up postgresql.conf, now restore it.

8. Set up replication-related parameters, connections and authentication in the standby server like the primary, so that the standby might work as a primary after failover.
9. Enable read-only queries on the standby server. But if wal_level is archive on the primary, leave hot_standby unchanged (i.e., off).
   $ $EDITOR postgresql.conf

hot_standby = on
10. Create a recovery command file in the standby server; the following parameters are required for streaming replication.
    $ $EDITOR recovery.conf
# Note that recovery.conf must be in the $PGDATA directory, even if the
# main postgresql.conf file is located elsewhere.

# Specifies whether to start the server as a standby. In streaming replication,
# this parameter must to be set to on.
standby_mode          = 'on'

# Specifies a connection string which is used for the standby server to connect
# with the primary.
primary_conninfo      = 'host=192.168.0.10 port=5432 user=replication password=password'

# Specifies a trigger file whose presence should cause streaming replication to
# end (i.e., failover).
trigger_file = '/path_to/trigger'

# Specifies a command to load archive segments from the WAL archive. If
# wal_keep_segments is a high enough number to retain the WAL segments
# required for the standby server, this may not be necessary. But
# a large workload can cause segments to be recycled before the standby
# is fully synchronized, requiring you to start again from a new base backup.
restore_command = 'cp /path_to/archive/%f "%p"'
11. Start postgres in the standby server. It will start streaming replication.
12. You can calculate the replication lag by comparing the current WAL write location on the primary with the last WAL location received/replayed by the standby. They can be retrieved using pg_current_xlog_location on the primary and the pg_last_xlog_receive_location/pg_last_xlog_replay_location on the standby, respectively.
    $ psql -c "SELECT pg_current_xlog_location()" -h192.168.0.10 (primary host)
    pg_current_xlog_location
--------------------------
0/2000000
(1 row)

$ psql -c "select pg_last_xlog_receive_location()" -h192.168.0.20 (standby host)
pg_last_xlog_receive_location
-------------------------------
0/2000000
(1 row)

$ psql -c "select pg_last_xlog_replay_location()" -h192.168.0.20 (standby host)
pg_last_xlog_replay_location
------------------------------
0/2000000
(1 row)
13. You can also check the progress of streaming replication by using ps command.
# The displayed LSNs indicate the byte position that the standby server has
# written up to in the xlogs.
[primary] $ ps -ef | grep sender
postgres  6879  6831  0 10:31 ?        00:00:00 postgres: wal sender process postgres 127.0.0.1(44663) streaming 0/2000000

[standby] $ ps -ef | grep receiver
postgres  6878  6872  1 10:31 ?        00:00:01 postgres: wal receiver process   streaming 0/2000000
How to do failover
Create the trigger file in the standby after the primary fails.
How to stop the primary or the standby server
Shut down it as usual (pg_ctl stop).
How to restart streaming replication after failover
Repeat the operations from 6th; making a fresh backup, some configurations and starting the original primary as the standby. The primary server doesn't need to be stopped during these operations.
How to restart streaming replication after the standby fails
Restart postgres in the standby server after eliminating the cause of failure.
How to disconnect the standby from the primary
Create the trigger file in the standby while the primary is running. Then the standby would be brought up.
How to re-synchronize the stand-alone standby after isolation
Shut down the standby as usual. And repeat the operations from 6th.
If you have more than one standby, promoting one will break the other(s). Update their recovery.conf settings to point to the new master, set recovery_target_timeline to 'latest', scp/rsync the pg_xlog directory, and restart the standby.