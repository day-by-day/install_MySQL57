#!/bin/bash
#filename:install_MySQL57.sh

mysql_install_dir=/usr/local/mysql57
mysql_data_dir=/data/mysql/mysql3306
mysql57_ver=5.7.24


script_dir=$(dirname "`readlink -f $0`")

#linux版本
if [ -e "/usr/bin/yum" ]; then
  command -v lsb_release >/dev/null 2>&1 || { yum -y install redhat-lsb-core; clear; }
fi

command -v lsb_release >/dev/null 2>&1 ||  { echo " yum source failed! " ; exit 1; }

if [ -e /etc/redhat-release ]; then
  OS=CentOS
  CentOS_ver=$(lsb_release -sr | awk -F. '{print $1}')
else
  echo "Does not support this OS! "
  exit 1
fi

#环境监测、MySQL安装
yum clean all && yum makecache
# yum -y update
# yum install -y epel-release
yum install -y ntpdate curl lrzsz vim wget
yum -y install numactl* libaio*

#网络下载速度太慢
# src_url="https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-5.7.24-linux-glibc2.12-x86_64.tar.gz"
# wget --limit-rate=10M -4 --tries=6 -c --no-check-certificate ${src_url};

#手动上传MySQL二进制包
while :; do echo
  read -e -p "Please manually upload MySQL binary package to /opt directory. [y/n]: " upload_yn
  if [[ ! ${upload_yn} =~ ^[y,n]$ ]]; then
    echo "input error! Please only input 'y' or 'n'"
  elif [[ ${upload_yn} = 'n' ]]; then
    echo 'naughty!'
  else
    break
  fi
done

# Update time
ntpdate pool.ntp.org ;sleep 3;
[ ! -e "/var/spool/cron/root" -o -z "$(grep 'ntpdate' /var/spool/cron/root > /dev/null 2>&1)" ] && { echo "*/20 * * * * $(which ntpdate) pool.ntp.org > /dev/null 2>&1" >> /var/spool/cron/root;chmod 600 /var/spool/cron/root; }

# Check if user is root
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

#监测mysql是否已经安装
[ -d "${mysql_install_dir}/support-files" ] && { echo " MySQL already installed! "; exit 1; }
[ -d "${mysql_data_dir}" ] && { echo " instance already installed! "; exit 1; }


#防火墙是否关闭
while :; do echo
  read -e -p "Do you want to enable iptables? [y/n]: " iptables_yn
  if [[ ! ${iptables_yn} =~ ^[y,n]$ ]]; then
    echo "input error! Please only input 'y' or 'n'"
  else
    break
  fi
done

#如果需要关闭防火墙
if [ ${iptables_yn} = 'n' ];then
  if [ ${CentOS_ver} = 7 ];then
    systemctl stop firewalld.service && systemctl disable firewalld.service
    systemctl stop iptables.service >/dev/null 2>&1
    systemctl disable iptables.service >/dev/null 2>&1
  else
    service iptables stop
    chkconfig iptables off
  fi
fi

#关闭selinux
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
#关闭NetworkManager， #线上环境不需要图形化网络管理工具
if [ ${CentOS_ver} = 7 ];then
  systemctl stop NetworkManager.service >/dev/null 2>&1
  systemctl disable NetworkManager.service >/dev/null 2>&1
else
  service NetworkManager stop >/dev/null 2>&1
  chkconfig NetworkManager off >/dev/null 2>&1
fi

#卸载自带的mariadb、mariadb-libs
rpm -e --nodeps mariadb >/dev/null 2>&1
mariadb_libs=`rpm -qa | grep mariadb`
if [ $? = 0 ];then
  rpm -e --nodeps ${mariadb_libs}
fi

[ -d "${mysql_install_dir}/support-files" ] && { echo "MySQL already installed!"; db_option=Other; break; }


while :; do echo
  mkdir -pv /opt/mysql >/dev/null 2>&1
  if [ ! -z /opt/mysql-${mysql57_ver}-linux-glibc2.12-x86_64.tar.gz ];then
    #创建mysql用户
    id -u mysql >/dev/null 2>&1
    [ $? -ne 0 ] && groupadd mysql && useradd -s /sbin/nologin -g mysql -d ${mysql_install_dir} -NM mysql
    #MySQL软件放置 :
    tar zxvf /opt/mysql-${mysql57_ver}-linux-glibc2.12-x86_64.tar.gz -C /opt/mysql/
    #basedir： /usr/local/mysql
    ln -s /opt/mysql/mysql-${mysql57_ver}-linux-glibc2.12-x86_64 ${mysql_install_dir}

    #创建数据库相关目录：
    mkdir ${mysql_data_dir}/{data,logs,run,tmp,mysql-bin,relay-bin} -pv

    # my.cnf
    cat > ${mysql_data_dir}/my3306.cnf << EOF
[client]
port  = 3306
socket  = ${mysql_data_dir}/run/mysql.sock

[mysql]
prompt="MySQL [\\d]> "
no-auto-rehash

[mysqld]
user  = mysql
port  = 3306
basedir = ${mysql_install_dir}
datadir = ${mysql_data_dir}/data
tmpdir = ${mysql_data_dir}/tmp
socket  = ${mysql_data_dir}/run/mysql.sock
pid-file = ${mysql_data_dir}/run/mysql.pid
character-set-server = utf8mb4
skip_name_resolve = 1

#replicate
server-id = 1
gtid_mode = on
enforce_gtid_consistency = 1
master_info_repository = TABLE
relay_log_info_repository = TABLE

#binlog
log-bin = ${mysql_data_dir}/mysql-bin/mysql-bin
binlog_format = row
sync_binlog = 1
binlog_cache_size = 4M
max_binlog_cache_size = 2G
max_binlog_size = 512M
expire_logs_days = 7
binlog_checksum = 1
log_slave_updates = ON

#slowlog && errorlog && relaylog
long_query_time = 0.1
slow_query_log = 1
slow_query_log_file = ${mysql_data_dir}/logs/slow.log
log_slow_admin_statements = 1
log_slow_slave_statements = 1
min_examined_row_limit = 100
log_queries_not_using_indexes =1
log_throttle_queries_not_using_indexes = 60
log-error = ${mysql_data_dir}/logs/error.log
relay_log_recovery = 1
relay-log-purge = 1
relay_log = ${mysql_data_dir}/relay-bin/relay-bin

#timeout
wait_timeout = 600
interactive_timeout = 600
lock_wait_timeout = 3600

#limit
open_files_limit = 65535
max_connections = 1000
max_connect_errors = 1000000
tmp_table_size = 32M
max_heap_table_size = 32M
back_log = 1024
thread_stack = 512K
max_allowed_packet = 32M

#buffer && cache
table_open_cache = 1024
table_definition_cache = 1024
table_open_cache_instances = 64
sort_buffer_size = 4M
join_buffer_size = 4M
thread_cache_size = 768
query_cache_size = 0
query_cache_type = 0
key_buffer_size = 32M
read_buffer_size = 8M
read_rnd_buffer_size = 4M
bulk_insert_buffer_size = 64M
myisam_sort_buffer_size = 128M

#myisam
external-locking = FALSE
myisam_max_sort_file_size = 10G
myisam_repair_threads = 1

transaction_isolation = REPEATABLE-READ
explicit_defaults_for_timestamp = 1
innodb_thread_concurrency = 0
innodb_sync_spin_loops = 100
innodb_spin_wait_delay = 30
#innodb_additional_mem_pool_size = 16M
innodb_buffer_pool_size = 1434M                 #单个实例的话，设置成服务器内存的百分之八十
innodb_buffer_pool_instances = 8
innodb_buffer_pool_load_at_startup = 1
innodb_buffer_pool_dump_at_shutdown = 1
innodb_data_file_path = ibdata1:1G:autoextend
innodb_flush_log_at_trx_commit = 1
innodb_log_buffer_size = 32M
innodb_log_file_size = 2G
innodb_log_files_in_group = 2
innodb_max_undo_log_size = 4G

# 根据您的服务器IOPS能力适当调整
# 一般配普通SSD盘的话，可以调整到 10000 - 20000
# 配置高端PCIe SSD卡的话，则可以调整的更高，比如 50000 - 80000
innodb_io_capacity = 4000
innodb_io_capacity_max = 8000
innodb_flush_neighbors = 0
innodb_write_io_threads = 8
innodb_read_io_threads = 8
innodb_purge_threads = 4
innodb_page_cleaners = 4
innodb_open_files = 65535
innodb_max_dirty_pages_pct = 50
innodb_flush_method = O_DIRECT
innodb_lru_scan_depth = 4000
innodb_checksums = 1
innodb_checksum_algorithm = crc32
#innodb_file_format = Barracuda
#innodb_file_format_max = Barracuda
innodb_lock_wait_timeout = 10
innodb_rollback_on_timeout = 1
innodb_print_all_deadlocks = 1
innodb_file_per_table = 1
innodb_online_alter_log_max_size = 4G
internal_tmp_disk_storage_engine = InnoDB
innodb_stats_on_metadata = 0

innodb_status_file = 1
# 注意: 开启 innodb_status_output & innodb_status_output_locks 后, 可能会导致log-error文件增长较快
innodb_status_output = 0
innodb_status_output_locks = 0

#performance_schema
performance_schema = 1
performance_schema_instrument = '%=on'

#innodb monitor
innodb_monitor_enable="module_innodb"
innodb_monitor_enable="module_server"
innodb_monitor_enable="module_dml"
innodb_monitor_enable="module_ddl"
innodb_monitor_enable="module_trx"
innodb_monitor_enable="module_os"
innodb_monitor_enable="module_purge"
innodb_monitor_enable="module_log"
innodb_monitor_enable="module_lock"
innodb_monitor_enable="module_buffer"
innodb_monitor_enable="module_index"
innodb_monitor_enable="module_ibuf_system"
innodb_monitor_enable="module_buffer_page"
innodb_monitor_enable="module_adaptive_hash"

[mysqldump]
quick
max_allowed_packet = 32M
EOF

    #更改权限
    chown -R mysql:mysql ${mysql_data_dir}
    chown -R mysql:mysql ${mysql_install_dir}
    [ -d "/etc/mysql" ] && /bin/mv /etc/mysql{,_bk}

    # chmod 600 ${mysql_data_dir}/my3306.cnf
    #初始化
    ${mysql_install_dir}/bin/mysqld --defaults-file=${mysql_data_dir}/my3306.cnf --initialize-insecure --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}/data

    echo "export PATH=${mysql_install_dir}/bin:\$PATH" >> /etc/profile  && source /etc/profile

    #第一次启动MySQL
    ${mysql_install_dir}/bin/mysqld --defaults-file=${mysql_data_dir}/my3306.cnf &
    sleep 5

    #mysql修改初始密码
    # PASSWD=$(grep 'password is' /data/mysql/mysql3306/data/error.log  | awk '{print $NF}')
    # mysql -uroot -p"$PASSWD" --connect-expired-password -e "alter user user() identified by '${dbrootpwd}';"
    ${mysql_install_dir}/bin/mysql -S ${mysql_data_dir}/run/mysql.sock -e "grant all privileges on *.* to root@'127.0.0.1' identified by 'P@ssw0rd' with grant option;"
    ${mysql_install_dir}/bin/mysql -S ${mysql_data_dir}/run/mysql.sock -e "grant all privileges on *.* to root@'localhost' identified by 'P@ssw0rd' with grant option;"
    ${mysql_install_dir}/bin/mysql -S ${mysql_data_dir}/run/mysql.sock -uroot -p'P@ssw0rd' -e "reset master;"
    [ -e "${mysql_install_dir}/my.cnf" ] && rm -f ${mysql_install_dir}/my.cnf
    rm -rf /etc/ld.so.conf.d/{mysql,mariadb,percona,alisql}*.conf
    echo "${mysql_install_dir}/lib" > /etc/ld.so.conf.d/mysql.conf && ldconfig


    #创建 MySQL 启动脚本
    /bin/cp ${mysql_install_dir}/support-files/mysql.server /etc/init.d/mysqld
    sed -i "s@^basedir=.*@basedir=${mysql_install_dir}@" /etc/init.d/mysqld
    sed -i "s@^datadir=.*@datadir=${mysql_data_dir}@" /etc/init.d/mysqld
    chmod +x /etc/init.d/mysqld
    source /etc/profile

    if [ -d "${mysql_install_dir}/support-files" ]; then
      echo "MySQL installed successfully!"
    fi
    break
  else
    read -e -p "Please confirm whether you have uploaded MySQL binary package to /opt directory [y/n]:" confirm_yn
    if [[ ! ${confirm_yn} =~ ^[y,n]$ ]]; then
      echo "input error! Please only input 'y' or 'n'"
    else
      if [ "${confirm_yn}" == 'y' ];then
        continue
      else
        echo "exit!"; exit 1
      fi
    fi
  fi

done

