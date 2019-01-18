#!/bin/bash
#filename:install_MySQL57.sh

#安装目录设置
port=3306
mysql57_ver=5.7.24
ver=`echo $mysql57_ver | awk -F'.' '{print $1$2}'`
mysql_install_dir=/usr/local/mysql${ver}
mysql_data_dir=/data/mysql/mysql${port}
ip_end=`/sbin/ifconfig -a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | tr -d "addrs:" | awk -F'.' '{print $4}'`


echo "Please manually upload MySQL${mysql57_ver} binary package to /opt directory. "

#环境监测、MySQL安装
yum clean all && yum makecache
yum -y update
yum -y install epel-release
yum install -y ntpdate curl lrzsz vim wget fish htop openssh
yum -y install numactl* libaio
yum -y groupinstall "Development tools"

#卸载自带的mariadb、mariadb-libs
rpm -e --nodeps mariadb >/dev/null 2>&1
mariadb_libs=`rpm -qa | grep mariadb`
if [ $? = 0 ];then
  rpm -e --nodeps ${mariadb_libs}
fi

#网络下载
src_url="https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-${mysql57_ver}-linux-glibc2.12-x86_64.tar.gz"
MD5="075dccd655e090ca999e2c8da3b67eb7"
# src_url_china="https://mirrors.ustc.edu.cn/mysql-ftp/Downloads/MySQL-5.7/mysql-5.7.24-linux-glibc2.12-x86_64.tar.gz"

# Check if user is root
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }
 
#监测mysql是否已经安装
[ -d "${mysql_install_dir}/support-files" ] && { echo " MySQL already installed! "; exit 1; }
[ -f "${mysql_data_dir}/data/auto.cnf" ] && { echo " instance already installed! "; exit 1; }


if [ ! -f /opt/mysql-${mysql57_ver}-linux-glibc2.12-x86_64.tar.gz ];then
  echo "开始下载"
  wget -P /opt/ --limit-rate=10M -4 --tries=6 -c --no-check-certificate ${src_url}
  if $? == 0;then
    echo "MySQL二进制包下载完成"
  else
    echo "MySQL二进制包下载失败，请检查"
    exit 0
  fi
else
  upload_md5=`md5sum /opt/mysql-${mysql57_ver}-linux-glibc2.12-x86_64.tar.gz | awk '{print $1}' `
  if ${MD5}=${upload_md5};then
    echo "MySQL二进制包已上传完成， 开始安装"
  else
    echo "MySQL二进制包md5值不一致， 请确认上传完成"
    exit 0
  fi
fi


mkdir -pv /opt/mysql >/dev/null 2>&1
tar -zxvf /opt/mysql-${mysql57_ver}-linux-glibc2.12-x86_64.tar.gz -C /opt/mysql/
ln -s /opt/mysql/mysql-${mysql57_ver}-linux-glibc2.12-x86_64 ${mysql_install_dir}
#创建数据库相关目录：
mkdir -pv ${mysql_data_dir}/{data,logs,run,tmp,mysql-bin,relay-bin} 

#创建mysql用户
id -u mysql >/dev/null 2>&1
[ $? -ne 0 ] && groupadd mysql && useradd -s /sbin/nologin -g mysql -d ${mysql_install_dir} -NM mysql

# my.cnf
cat > ${mysql_data_dir}/my3306.cnf << EOF
[client]
port  = ${port}
socket  = ${mysql_data_dir}/run/mysql.sock
[mysql]
prompt="MySQL [\\d]> "
no-auto-rehash
[mysqld]
user  = mysql
port  = ${port}
basedir = ${mysql_install_dir}
datadir = ${mysql_data_dir}/data
tmpdir = ${mysql_data_dir}/tmp
socket  = ${mysql_data_dir}/run/mysql.sock
pid-file = ${mysql_data_dir}/run/mysql.pid
character-set-server = utf8mb4
skip_name_resolve = 1

#replicate
server-id = ${ip_end}${port}
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

chmod 600 ${mysql_data_dir}/my3306.cnf
#初始化
${mysql_install_dir}/bin/mysqld --defaults-file=${mysql_data_dir}/my3306.cnf --initialize-insecure --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}/data

echo "export PATH=\$PATH:${mysql_install_dir}/bin" >> /etc/profile
echo 'PS1="\[\e[37;40m\][\[\e[32;40m\]\u\[\e[37;40m\]@\h \[\e[35;40m\]\W\[\e[0m\]]\\$ \[\e[33;40m\]"' >> /etc/profile
source /etc/profile

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
# /bin/cp ${mysql_install_dir}/support-files/mysql.server /etc/init.d/mysqld
# sed -i "s@^basedir=.*@basedir=${mysql_install_dir}@" /etc/init.d/mysqld
# sed -i "s@^datadir=.*@datadir=${mysql_data_dir}@" /etc/init.d/mysqld
# chmod +x /etc/init.d/mysqld
# source /etc/profile

# if [ -d "${mysql_install_dir}/support-files" ]; then
#   echo "MySQL installed successfully!"
# fi

#========================================================================================



#关闭防火墙
service iptables stop >/dev/null 2>&1 && chkconfig iptables off >/dev/null 2>&1
systemctl stop firewalld.service >/dev/null 2>&1 && systemctl disable firewalld.service >/dev/null 2>&1
systemctl stop iptables.service >/dev/null 2>&1
systemctl disable iptables.service >/dev/null 2>&1

#关闭NetworkManager， #线上环境不需要图形化网络管理工具
systemctl stop NetworkManager.service >/dev/null 2>&1 && systemctl disable NetworkManager.service >/dev/null 2>&1
service NetworkManager stop >/dev/null 2>&1 && chkconfig NetworkManager off >/dev/null 2>&1

#关闭selinux
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
echo "selinux is disable"

# Update time
ntpdate pool.ntp.org ;sleep 3;
[ ! -e "/var/spool/cron/root" -o -z "$(grep 'ntpdate' /var/spool/cron/root > /dev/null 2>&1)" ] && { echo "*/20 * * * * $(which ntpdate) pool.ntp.org > /dev/null 2>&1" >> /var/spool/cron/root;chmod 600 /var/spool/cron/root; }

# Set timezone  
rm -rf /etc/localtime  
ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime  

#安装python3，pip3，mycli
yum -y install zlib-devel bzip2-devel openssl-devel ncurses-devel sqlite-devel readline-devel tk-devel gcc make libffi-devel epel-release python-pip wget
cd /usr/local/src
wget https://www.python.org/ftp/python/3.7.0/Python-3.7.0.tgz
tar -xf Python-3.7.0.tgz
cd /usr/local/src/Python-3.7.0
./configure --prefix=/usr/local/python3 --with-ssl
make && make install
ln -s /usr/local/python3/bin/python3 /usr/bin/python3
ln -s /usr/local/python3/bin/pip3 /usr/bin/pip3
pip3 install --upgrade pip

/usr/bin/pip3 install mycli
ln -s /usr/local/python3/bin/mycli /usr/local/bin/
echo "mycli install finish"


# /etc/security/limits.conf
echo "ulimit -SHn 102400" >> /etc/rc.local
cat >> /etc/security/limits.conf << EOF
 *           soft   nofile       102400
 *           hard   nofile       102400
 *           soft   nproc        102400
 *           hard   nproc        102400
EOF

# /etc/sysctl.conf  
sed -i 's/net.ipv4.tcp_syncookies.*$/net.ipv4.tcp_syncookies = 1/g' /etc/sysctl.conf  
cat >> /etc/sysctl.conf << EOF
vm.swappiness = 5
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
net.ipv4.tcp_max_syn_backlog = 819200
net.core.netdev_max_backlog = 400000
net.core.somaxconn = 40960
fs.file-max=102400 
net.ipv4.tcp_tw_reuse = 1  
net.ipv4.tcp_tw_recycle = 1  
net.ipv4.ip_local_port_range = 1024 65000
EOF
/sbin/sysctl -p
echo "sysctl set OK!!"
