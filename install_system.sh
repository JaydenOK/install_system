#!/bin/bash

OutputMsg()
{
	echo "####################### ${1} #######################";
}

GetConf()
{
   echo `cat ${2} | grep ${1} | awk -F= '{print $2}'`
}

# $2可能有路径/,所以使用#为分隔符
ReplaceText()
{
	sed -i "s#$2#$3#" $1
}

##### 延时函数
DelayCountNum()
{
    seconds=$1
	echo "请等待..."
    while [ $seconds -gt 0 ];do
		echo -n ${seconds}
		sleep 1
		seconds=$(($seconds - 1))
		echo -ne "\r     \r"		# 清除本行文字
    done
}

# 增加用户和key
Add_Users()
{
	cd ${SCRIPT_DIR}
	/bin/mv -f /etc/sudoers /etc/sudoers.bak.${CDATE}
	/bin/cp -vf ${FILE_DIR}/sudoers /etc/
	chmod 440 /etc/sudoers
	for user_name in `ls ${KEY_DIR} | grep -v root | grep -v readme.txt | grep -v passwd.TXT`
	do
		if [[ "${user_name}" == "passwd.TXT" ]];then
			continue
		fi
		/usr/sbin/useradd -g wheel ${user_name}
		echo `cat ${KEY_DIR}/passwd.TXT | grep "${user_name}=" | awk -F= '{print $2}'` | passwd   --stdin   ${user_name}
		/usr/sbin/pwconv
		
		# ssh登录、连接其他服务器模块的文件: /root/.ssh/config;config文件指定了连接所需的参数 (用于连接其他服务器时免参数登录认证)
		# 增加用户公钥文件/home/用户名/.ssh/authorized_keys (用于连接此服务器时认证)
		
		/bin/mkdir -p /home/${user_name}/.ssh/
		/bin/cp -f ${KEY_DIR}/${user_name}/authorized_keys /home/${user_name}/.ssh/
		chown -R ${user_name}.wheel /home/${user_name}/.ssh/
		chmod 600 /home/${user_name}/.ssh/authorized_keys
		chmod 700 /home/${user_name}/.ssh/
	done
	# 修改root密码
	# echo `cat ${KEY_DIR}/root.txt ` | passwd   --stdin   root
	groupadd power && usermod -g power power
	cd ${SCRIPT_DIR}
}

# 安装系统所需包和工具，优化系统
Install_Package_Optimize()
{
	OutputMsg '安装系统所需包和工具，优化系统'
	cd ${SCRIPT_DIR}
	OutputMsg '修改yum源为CentOS6-Base-163.repo源'
	/bin/mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak.${CDATE}
	/bin/cp ${PACKAGE_DIR}/CentOS6-Base-163.repo /etc/yum.repos.d/CentOS-Base.repo
	/usr/bin/yum clean all
	/usr/bin/yum makecache

	OutputMsg '安装常用的依赖库'
	/usr/bin/yum -y update bash
	/usr/bin/yum -y install unzip
	
	# mysql 5.7依赖库 libaio numactl
	/usr/bin/yum -y install libaio numactl
	# 升级其它依赖库
	/usr/bin/yum -y update glibc-2.12-1.166.el6_7.7 glibc-common-2.12-1.166.el6_7.7 glibc-devel-2.12-1.166.el6_7.7 \
	glibc-headers-2.12-1.166.el6_7.7 glibc-static-2.12-1.166.el6_7.7 glibc-utils-2.12-1.166.el6_7.7 nscd-2.12-1.166.el6_7.7

	OutputMsg '升级本地其它rpm包（rsync，xinetd，lrzsz）'

	rpm -Uvh ${PACKAGE_DIR}/rsync-3.0.6-9.el6.x86_64.rpm
	rpm -Uvh ${PACKAGE_DIR}/xinetd-2.3.14-34.el6.x86_64.rpm
	# lrzszLinux服务器和window互传文件工具(sz,rz)
	rpm -Uvh ${PACKAGE_DIR}/lrzsz-0.12.20-27.1.el6.x86_64.rpm

	/sbin/service crond restart
	/sbin/chkconfig rsync on
	/sbin/service xinetd restart


	# 优化选项
	OutputMsg '优化配置选项'
	echo ""  >> /etc/rc.d/rc.local
	echo "/usr/sbin/setenforce 0" >> /etc/rc.d/rc.local

	cd ${SCRIPT_DIR}
}

# 关闭selinux,关闭iptables
Iptable_Off()
{
	OutputMsg '关闭selinux,关闭iptables'
	# 关闭selinux
	sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
	/usr/sbin/setenforce 0

	# 关闭iptables
	chkconfig iptables off
	service iptables stop
}

# 安装mysql
Install_Mysql()
{
	cd ${SCRIPT_DIR}/

	OutputMsg '卸载系统旧版mysql'
	for old_rmp in `rpm -qa | grep mysql`;do rpm -e $old_rmp --nodeps;done;
	OutputMsg '卸载完成'

	OutputMsg "安装mysql到（$MysqlInstallDir）"
	cd ${PACKAGE_DIR}/
	# tar.gz名称
	targz_name='mysql-5.7.24-linux-glibc2.12-x86_64.tar.gz'
	###################################################################
	# 获取目录名
	package_name=`echo $targz_name | sed 's/.tar.gz//'`
	# 解压到安装目录/usr/local/mysql${MysqlPort}
	rm -rf $MysqlInstallDir
	tar -zxf $targz_name && mv -f $package_name/ $MysqlInstallDir

	# 拷贝、修改配置文件
	cp -f ${FILE_DIR}/my.cnf $TMP_DIR/$MyCnfFile

	ReplaceText $TMP_DIR/${MyCnfFile} "^port = .*" "port = ${MysqlPort}"
	ReplaceText $TMP_DIR/${MyCnfFile} "^socket = .*" "socket = /tmp/mysql${MysqlPort}\.sock"
	ReplaceText $TMP_DIR/${MyCnfFile} "^server-id = .*" "server-id = ${MysqlPort}"
	ReplaceText $TMP_DIR/${MyCnfFile} "^basedir = .*" "basedir = ${MysqlInstallDir}"
	ReplaceText $TMP_DIR/${MyCnfFile} "^datadir = .*" "datadir = ${MysqlInstallDir}/data"
	ReplaceText $TMP_DIR/${MyCnfFile} "^pid-file = .*" "pid-file = ${MysqlInstallDir}/data/mysql${MysqlPort}.pid"
	ReplaceText $TMP_DIR/${MyCnfFile} "^innodb_data_home_dir = .*" "innodb_data_home_dir = ${MysqlInstallDir}/data"
	ReplaceText $TMP_DIR/${MyCnfFile} "^innodb_log_group_home_dir = .*" "innodb_log_group_home_dir = ${MysqlInstallDir}/redolog"
	ReplaceText $TMP_DIR/${MyCnfFile} "^innodb_undo_directory = .*" "innodb_undo_directory = ${MysqlInstallDir}/undolog"

	cp -f $TMP_DIR/${MyCnfFile} /etc/ && chown mysql:mysql /etc/${MyCnfFile} && chmod 664 /etc/${MyCnfFile}

	chown -R mysql:mysql $MysqlInstallDir

	OutputMsg '增加mysql用户及mysql组'
	groupadd mysql && useradd -r -s /sbin/nologin -g mysql mysql -d /usr/local/mysql

	mkdir -p $MysqlInstallDir/data/ && rm -rf $MysqlInstallDir/data/*
	mkdir -p $MysqlInstallDir/redolog/ && mkdir -p $MysqlInstallDir/undolog/ && rm -rf $MysqlInstallDir/redolog/* && rm -rf $MysqlInstallDir/undolog/*

	# 修改目录文件权限
	chown -R mysql:mysql $MysqlInstallDir

	cp -f ${FILE_DIR}/mysql.server $TMP_DIR/${MysqldFile}

	#修改启动文件配置
	ReplaceText $TMP_DIR/${MysqldFile} "^basedir=.*" "basedir=${MysqlInstallDir}"
	ReplaceText $TMP_DIR/${MysqldFile} "^datadir=.*" "datadir=${MysqlInstallDir}/data"
	ReplaceText $TMP_DIR/${MysqldFile} "^mysqld_pid_file_path=.*" "mysqld_pid_file_path=${MysqlInstallDir}/data/mysql${MysqlPort}.pid"

	ReplaceText $TMP_DIR/${MysqldFile} "--defaults-file=\"/etc/my.cnf\"" "--defaults-file=\"/etc/${MyCnfFile}\""

	cp -f $TMP_DIR/${MysqldFile} /etc/init.d/ && chmod +x /etc/init.d/${MysqldFile}

	# 开始安装mysql
	OutputMsg '安装并初始化数据库'

	#初始化数据目录 : 这里我们使用 --initialize; 用--initialize-insecure 则生成的新实例密码为空
	$MysqlInstallDir/bin/mysqld --defaults-file=/etc/${MyCnfFile} --initialize --basedir=$MysqlInstallDir --datadir=$MysqlInstallDir/data/ --user=mysql --explicit_defaults_for_timestamp
	defaultPwd=`grep 'A temporary password' $MysqlInstallDir/data/error.log | awk -F"root@localhost: " '{ print $2}' `
	echo "默认登录密码为:${defaultPwd}" | tee -a $LOG_DIR/mysqlPwd.log

	# 复制当前端口登录mysql二进制文件
	cp -r ${FILE_DIR}/mysql $MysqlInstallDir/bin/${MysqlFile}

	###### 启动mysql实例
	OutputMsg "启动端口：${MysqlPort}的mysql实例..."
	/etc/init.d/${MysqldFile} start

	OutputMsg '修改root密码'
	# 用 bin/mysql修改root密码
	# $MysqlInstallDir/bin/mysqladmin  -u'root' -p'${defaultPwd}' password '${DB_PWD}' --socket=/tmp/mysql${MysqlPort}.sock --port=${MysqlPort}
	echo "ALTER user 'root'@'localhost' IDENTIFIED BY '${DB_PWD}';FLUSH PRIVILEGES;" | $MysqlInstallDir/bin/${MysqlFile} --connect-expired-password -uroot -p${defaultPwd} --socket /tmp/mysql${MysqlPort}.sock --port=${MysqlPort}
	# 增加mysql配置环境变量
	echo '' >> /etc/profile
	echo "export PATH=$MysqlInstallDir/bin:\$PATH" >> /etc/profile
	# 当前shell窗口生效，执行完初始化脚本需重启linux服务器
	source /etc/profile

	OutputMsg '添加此端口mysqld系统服务，开机启动'
	chkconfig --add ${MysqldFile}
	chkconfig --level 3 ${MysqldFile} on
	# 重启mysql
	/etc/init.d/${MysqldFile} restart

	rm -rf mysql/
	rm -rf $TMP_DIR/*
	cd ${SCRIPT_DIR}/
}

# 配置mysql
Configure_Mysql()
{
	OutputMsg '安装phpMyAdmin'
	cd ${PACKAGE_DIR}/
	phpMyAdminTargzFile='phpMyAdmin-4.8.4-all-languages.tar.gz'

	phpMyAdmin_dir=`echo $phpMyAdminTargzFile | sed 's/.tar.gz//'`

	tar -zxf $phpMyAdminTargzFile && mv $phpMyAdmin_dir/ phpmyadmin/

	OutputMsg '增加www用户及www组'
	# -g www组，-d 指定用户主目录
	test -d /var/www/html/ || mkdir -p /var/www/html/
	chown -R www:www /var/www/html/
	groupadd www && useradd -r -s /sbin/nologin -g www www -d /var/www/html/
	OutputMsg '复制安装phpmyadmin'
	/bin/cp -rf phpmyadmin/ /var/www/html/ && chown -R www:www /var/www/html/phpmyadmin/

	cp -r ${FILE_DIR}/config.sample.inc.php /var/www/html/phpmyadmin/config.inc.php && chown www:www /var/www/html/phpmyadmin/config.inc.php && chmod 755 /var/www/html/phpmyadmin/config.inc.php
	#### 增加phpmyadmin端口配置
	sed -i "s/\$i = 0\;/\$i = 0\;\n \
	\$i++;\n \
	\/\/################ New Server  ################ \n \
	\$cfg['Servers'][\$i]['auth_type'] = 'cookie';\n \
	\$cfg['Servers'][\$i]['host'] = '127.0.0.1';\n \
	\$cfg['Servers'][\$i]['compress'] = false;\n \
	\$cfg['Servers'][\$i]['AllowNoPassword'] = false;\n \
	\$cfg['Servers'][\$i]['port'] = '$MysqlPort';\n/" /var/www/html/phpmyadmin/config.inc.php

	rm -rf phpmyadmin/

	# 授权访问数据库
	####################### 添加此端口mysqld系统服务，开机启动 #####################\
	# --connect-expired-password mysql5.7安全模式安装需加
	echo "GRANT ALL ON *.* TO 'root'@'localhost' IDENTIFIED BY '${DB_PWD}';" | $MysqlInstallDir/bin/${MysqlFile} --connect-expired-password -uroot -p${DB_PWD} -S /tmp/mysql${MysqlPort}.sock
	echo "GRANT ALL ON *.* TO 'root'@'127.0.0.1' IDENTIFIED BY '${DB_PWD}';" | $MysqlInstallDir/bin/${MysqlFile} --connect-expired-password -uroot -p${DB_PWD} -S /tmp/mysql${MysqlPort}.sock
	echo "CREATE USER '${custom_user}'@'127.0.0.1' IDENTIFIED BY '${custom_user_password}';" | $MysqlInstallDir/bin/${MysqlFile} --connect-expired-password -uroot -p${DB_PWD} -S /tmp/mysql${MysqlPort}.sock
	echo "GRANT SELECT ON *.* TO '${custom_user}'@'127.0.0.1' IDENTIFIED BY '${custom_user_password}';" | $MysqlInstallDir/bin/${MysqlFile} --connect-expired-password -uroot -p${DB_PWD} -S /tmp/mysql${MysqlPort}.sock
	echo "USE mysql;DELETE FROM user WHERE authentication_string='' OR host = '%';FLUSH PRIVILEGES;exit;" | $MysqlInstallDir/bin/${MysqlFile} --connect-expired-password -uroot -p${DB_PWD} -S /tmp/mysql${MysqlPort}.sock

	/etc/init.d/${MysqldFile} restart
	cd ${SCRIPT_DIR}
}

# 安装web环境,php nginx
# 执行：echo '' > logs/install_system.log && ./install_system.sh | tee -a logs/install_system.log
Install_Web()
{
	OutputMsg '安装web环境(php,nginx等)'
	cd ${SCRIPT_DIR}
	test -d /var/www/html/ || mkdir -p /var/www/html/
	chown -R www:www /var/www/html/
	test -d /usr/local/php || mkdir -p /usr/local/php
	rm -rf /usr/local/php/* && chown -R www:www /usr/local/php

	# 进入packages目录
	cd ${PACKAGE_DIR}/
	OutputMsg '安装php依赖包'
	##### devel 包主要是供开发用，至少包括以下2个东西:1. 头文件,2. 链接库；如果你安装基于 glib 开发的程序，只需要安装 glib 包就行了。但是如果你要编译使用了glib的源代码，则需要安装 glib-devel。
	########## 一般安装curl-devel已包含安装curl的包了，所以有先安装curl包，也没关系
	yum install -y zlib-devel autoconf libjpeg libjpeg-devel libpng libpng-devel freetype freetype-devel \
	libpng libpng-devel libxml2 libxml2-devel glibc glibc-devel glib2 glib2-devel bzip2 bzip2-devel \
	curl curl-devel gdbm-devel db4-devel libXpm-devel libX11-devel gd-devel gmp-devel readline-devel \
	libxslt-devel openssl-devel expat-devel
	
	OutputMsg '安装nginx 依赖包,gcc-c++编译器'
	yum -y install make zlib zlib-devel gcc-c++ libtool openssl openssl-devel
	
	## with-mcrypt所需库
	# yum install -y php-mcrypt epel-release libmcrypt-devel 
	# 指定路径/usr/local/libmcrypt
	OutputMsg '安装 libmcrypt 库'
	tar -zxf libmcrypt-2.5.8.tar.gz
	cd libmcrypt-2.5.8
	./configure
	make && make install
	
	# 链接libmcrypt解压的ldconfig
	# ldconfig是一个动态链接库管理命令，其目的为了让动态链接库为系统所共享
	ldconfig
	cd libltdl/
	./configure --enable-ltdl-install
	make && make install
	# 删除解压文件
	cd ../../ && /bin/rm -rf libmcrypt-2.5.8/

	OutputMsg '安装 mhash 库'
	tar -zxf mhash-0.9.9.tar.gz
	cd mhash-0.9.9/
	./configure
	make && make install
	cd ../
	/bin/rm -rf mhash-0.9.9/

	## 安装mcrypt
	tar -zxf mcrypt-2.6.8.tar.gz
	cd mcrypt-2.6.8
	./configure
	make && make install
	cd ../
	/bin/rm -rf mcrypt-2.6.8/
	
	# 安装libiconv(指定路径，安装PHP时也要指定路径)
	tar -zxf libiconv-1.13.1.tar.gz
	cd libiconv-1.13.1/
	./configure --prefix=/usr/local/libiconv
	make && make install
	cd ../
	/bin/rm -rf libiconv-1.13.1/

	# 安装libevent；使用libevent进行多线程socket编程
	tar -zxf libevent-1.4.9-stable.tar.gz
	cd libevent-1.4.9-stable/
	./configure
	make && make install

	echo '/usr/local/lib/' > /etc/ld.so.conf.d/libevent.conf
	ldconfig
	cd ../
	rm -rf libevent-1.4.9-stable/

	OutputMsg '安装 php5.6.40'
	tar -zxf php-5.6.40.tar.gz
	cd php-5.6.40/
	# CHOST="x86_64-pc-linux-gnu" CFLAGS="-march=nocona -O2 -pipe" CXXFLAGS="-march=nocona -O2 -pipe"

	# CFLAGS:C语言编译器参数;CXXFLAGS:C++语言编译器参数;LDFLAGS:链接器参数
	# 如果Makefile中定义了 CFLAGS ，那么则会使用Makefile中的这个变量，如果没有定义则使用系统环境变量的值

	# LNMP环境中的nginx是不支持php的，需要通过fastcgi插件来处理有关php的请求。而php需要php-fpm这个组件提供该功能。
	# 在php5.3.3以前的版本php-fpm是以一个补丁包的形式存在的，而php5.3.3以后只需在编译安装时使用--enable-fpm加载该模块即可，无需另行安装。
	# --prefix 安装目录；--with-config-file-path即读取的php.ini配置文件所在
	# --with-pdo-mysql 指向mysql：base_dir=/usr/local/mysql
	./configure \
	--prefix=/usr/local/php \
	--with-config-file-path=/etc \
	--with-mysql=${WithMysql} \
	--with-mysqli=${WithMysql}/bin/mysql_config \
	--with-pdo-mysql=${WithMysql} \
	--enable-fpm \
	--enable-soap \
	--with-libxml-dir \
	--with-openssl \
	--with-mcrypt \
	--with-mhash \
	--with-pcre-regex \
	--with-zlib \
	--enable-bcmath \
	--with-iconv=/usr/local/libiconv \
	--with-bz2 \
	--enable-calendar \
	--with-curl \
	--with-cdb \
	--enable-dom \
	--enable-exif \
	--enable-fileinfo \
	--enable-filter \
	--with-pcre-dir \
	--enable-ftp \
	--with-gd \
	--with-openssl-dir \
	--with-jpeg-dir \
	--with-png-dir \
	--with-zlib-dir \
	--with-freetype-dir \
	--enable-gd-native-ttf \
	--enable-gd-jis-conv \
	--with-gettext \
	--with-gmp \
	--with-mhash \
	--enable-json \
	--enable-mbstring \
	--disable-mbregex \
	--disable-mbregex-backtrack \
	--with-libmbfl \
	--with-onig \
	--enable-pdo \
	--with-pdo-mysql \
	--with-zlib-dir \
	--with-readline \
	--enable-session \
	--enable-shmop \
	--enable-simplexml \
	--enable-sockets \
	--enable-sysvmsg \
	--enable-sysvsem \
	--enable-sysvshm \
	--enable-wddx \
	--with-libxml-dir \
	--with-xsl \
	--enable-zip \
	--enable-mysqlnd-compression-support \
	--with-pear

	make && make install && cd ../

	# 安装mysqli扩展
	# cd /usr/local/php/ext/mysqli
	# /usr/local/php/bin/phpize
	# ./configure --with-php-config=/usr/local/php/bin/php-config --with-mysqli=/usr/bin/mysql_config

	OutputMsg '安装PDO_MYSQL'
	tar -zxf PDO_MYSQL-1.0.2.tgz
	cd PDO_MYSQL-1.0.2/
	/usr/local/php/bin/phpize
	./configure \
	--with-php-config=/usr/local/php/bin/php-config  \
	--with-pdo-mysql=${WithMysql}
	make && make install
	cd ../ && rm -rf PDO_MYSQL-1.0.2/


	# 复制 lighttpd 中的spawn-fcgi 程序到PHP目录下使用
	# 先使用安装的配置文件
	# 后边复制方式
	mv /usr/local/php/etc/php-fpm.conf /usr/local/php/etc/php-fpm.conf.bak.${CDATE}
	cp -rvf ${FILE_DIR}/php-fpm.conf  /usr/local/php/etc/

	# 修改fastcgi端口
	ReplaceText /usr/local/php/etc/php-fpm.conf "^listen =.*" "listen = 127.0.0.1:8888"

	# 添加 php-fpm 为系统服务 (php-fpm为引导启动脚本，非默认二进制文件)
	cp -rvf ${FILE_DIR}/php-fpm /etc/init.d/
	chmod 755 /etc/init.d/php-fpm
	/sbin/chkconfig --add php-fpm
	/sbin/chkconfig php-fpm on && /sbin/chkconfig --list | grep php-fpm

	# 备份旧的 php 程序，并将新安装的执行程序与之链接
	if [ -f /usr/bin/php ] ; then
		mv /usr/bin/php  /usr/bin/php_old
		ln -s /usr/local/php/bin/php /usr/bin/php
	fi

	# 对应目录 --with-config-file-path=/etc
	cp -rvf php-5.6.40/php.ini-development /etc/php.ini
	cp -rvf ${FILE_DIR}/php.ini /etc/php.ini
	# 修改php.ini参数
	ReplaceText /etc/php.ini ".*date\.timezone =.*" "date.timezone = PRC"
	################ 安装nginx ##########################

	OutputMsg '安装Nginx 1.14所需的pcre库'
	cd ${PACKAGE_DIR}
	tar -zxf pcre-8.12.tar.gz
	cd pcre-8.12/
	./configure
	make && make install
	cd ../
	rm -rf pcre-8.12/


	## 安装Nginx ,安装完测试：/etc/init.d/nginx -t
	## 为优化性能，可以安装 google 的 tcmalloc，这个之前在装mysql时，已经安装过了
	## 所以我们编译 Nginx 时，加上参数 --with-google_perftools_module
	## 然后在启动nginx前需要设置环境变量 export LD_PRELOAD=/usr/local/lib/libtcmalloc.so
	## 加上 -O2 参数也能优化一些性能
	##
	## 默认的Nginx编译选项里居然是用 debug模式的(-g参数)，在 auto/cc/gcc 文件最底下，去掉那个 -g 参数
	## 就是将  CFLAGS="$CFLAGS -g"  修改为   CFLAGS="$CFLAGS"   或者直接删除这一行
	## 如果安装pcre有指定目录则加上目录--with-pcre=/usr/local/pcre
	test -d /usr/local/nginx || mkdir -p /usr/local/nginx
	rm -rf /usr/local/nginx/* && chown -R www:www /usr/local/nginx/
	tar -zxf nginx-1.14.2.tar.gz
	cd nginx-1.14.2/
	./configure --user=www --group=www \
	--prefix=/usr/local/nginx \
	--with-http_stub_status_module \
	--with-http_ssl_module \
	--with-pcre \
	--with-stream
	make && make install
	cd ../ && rm -rf nginx-1.14.2/


	cd ${SCRIPT_DIR}
	test -d /usr/local/nginx/conf/vhost/ || mkdir -p /usr/local/nginx/conf/vhost/

	cp -rvf ${FILE_DIR}/nginx.conf /usr/local/nginx/conf/
	cp -rvf ${FILE_DIR}/example.conf /usr/local/nginx/conf/vhost/${SERVER_IP}.conf
	
	### 复制phpinfo.php文件
	cp -rvf ${FILE_DIR}/phpinfo.php /usr/local/nginx/html/phpinfo.php
	chown www:www /usr/local/nginx/html/phpinfo.php && chmod 755 /usr/local/nginx/html/phpinfo.php
	
	# 修改nginx.conf : fastcgi端口8888
	ReplaceText /usr/local/nginx/conf/nginx.conf ".*fastcgi_pass.*" "\t\t fastcgi_pass \t 127.0.0.1:8888;"
	# 修改 vhost : fastcgi端口8888
	ReplaceText /usr/local/nginx/conf/vhost/${SERVER_IP}.conf ".*fastcgi_pass.*" "\t\t fastcgi_pass \t 127.0.0.1:8888;"

	ReplaceText /usr/local/nginx/conf/vhost/${SERVER_IP}.conf ".*server_name.*" "		server_name		${SERVER_IP};"
	ReplaceText /usr/local/nginx/conf/vhost/${SERVER_IP}.conf ".*root.*" "		root		/usr/local/nginx/html;"
	# 复制引导启动脚本（非二进制文件）
	cp -rvf ${FILE_DIR}/nginx /etc/init.d/

	chmod 755 /etc/init.d/nginx
	/sbin/chkconfig --add nginx
	/sbin/chkconfig nginx on && /sbin/chkconfig --list | grep nginx
	cp -rvf ${FILE_DIR}/fcgi.conf /usr/local/nginx/conf/
	cd ${SCRIPT_DIR}
}


# 安装Redis和phpredis扩展,最新5.0(2019)
Install_Redis()
{
	# 安装Redis
	test -d /usr/local/redis/ || mkdir -p /usr/local/redis/
	test -f /etc/redis.conf && /bin/mv /etc/redis.conf  /ect/redis.conf.bak.`date '+%Y-%m-%d-%H-%M-%-S'`

	cd ${PACKAGE_DIR}
	tar  -zxf redis-5.0.3.tar.gz
	cd redis-5.0.3
	make
	cd src
	make install PREFIX=/usr/local/redis

	cp -rvf ${FILE_DIR}/redis.conf  /etc/redis.conf

	ReplaceText  /etc/redis.conf  "^protected-mode .*" "protected-mode no"
	ReplaceText  /etc/redis.conf  "^daemonize .*" "daemonize yes"
	ReplaceText  /etc/redis.conf  "^pidfile .*" "pidfile /var/run/redis.pid"
	ReplaceText  /etc/redis.conf  "^dir .*" "dir /usr/local/redis/"
	ReplaceText  /etc/redis.conf  "^port .*" "port ${REDIS_PORT}"

	# 复制启动脚本
	cp -rvf ${FILE_DIR}/redis  /etc/init.d/redis
	ReplaceText /etc/init.d/redis  "^RedisServer=.*" "RedisServer=/usr/local/redis/bin/redis-server"
	ReplaceText /etc/init.d/redis "^RedisConf=.*" "RedisConf=/etc/redis.conf"

	chmod a+x /etc/init.d/redis
	OutputMsg '设置redis开机启动： /etc/init.d/redis start >> /etc/rc.d/rc.local'
	echo "/etc/init.d/redis start"  >> /etc/rc.d/rc.local
	OutputMsg '启动redis ...'
	/etc/init.d/redis start
	rm -rf ${PACKAGE_DIR}/redis-5.0.3


	OutputMsg '安装 phpredis 扩展'
	# 安装 phpredis 扩展(redis-4.2.0.tgz为:PHP Version: PHP 5.3.0 or newer)
	cd ${PACKAGE_DIR}
	tar -zxf redis-4.2.0.tgz
	cd redis-4.2.0
	/usr/local/php/bin/phpize
	./configure --with-php-config=/usr/local/php/bin/php-config
	make && make install

	OutputMsg '开启php.ini的redis扩展'
	cp /etc/php.ini /etc/php.ini.bak.`date '+%Y-%m-%d-%H-%M-%-S'`
	ReplaceText /etc/php.ini  ".*extension = redis.so" "extension = /usr/local/php/lib/php/extensions/no-debug-non-zts-20131226/redis.so"
	rm -rf ${PACKAGE_DIR}/redis-4.2.0
	OutputMsg '重启fastcgi'
	/etc/init.d/php-fpm restart
	cd ${SCRIPT_DIR}
}

# 创建log_srv目录
Create_Dir_Log()
{
	test -d /data/import/ || mkdir -p /data/import/
	test -d /data/import_script/ || mkdir -p /data/import_script/
	test -d /data/log/ || mkdir -p /data/log/
	test -d /data/log_bak || mkdir -p /data/log_bak/
	test -d /data/key/ || mkdir -p /data/key/
	test -d /data/log_import/ || mkdir -p /data/log_import/
	cp -rf ${FILE_DIR}/db_config.php /data/import_script/
	cp -rf ${FILE_DIR}/log_rsync_conf.php /data/import_script/
	cp -rf ${FILE_DIR}/auto_backmysql /bin/
	cp -rf ${FILE_DIR}/auto_crond /bin/
	cp -rf ${FILE_DIR}/auto_managertool_backmysql /bin/
	cp -rf ${FILE_DIR}/auto_managertool_crond /bin/
	cp -rf ${FILE_DIR}/auto_managertoolall_backmysql /bin/
	cp -rf ${FILE_DIR}/auto_https_crond /bin/
	cp -rf ${SCRIPT_DIR}/keys/shangqu/shangqu_rsa /data/key/
	/bin/chmod 600 /data/key/shangqu_rsa
	/bin/chmod 755 /bin/auto_backmysql
	/bin/chmod 755 /bin/auto_crond
	/bin/chmod 755 /bin/auto_managertool_backmysql
	/bin/chmod 755 /bin/auto_managertoolall_backmysql
	/bin/chmod 755 /bin/auto_managertool_crond
	/bin/chmod 755 /bin/auto_https_crond
	#清除日志备份
	command1_0="0 5 \* \* \*  /usr/bin/find /data/log_bak -name \*.txt -ctime +30 | xargs rm -f > /dev/null"
	command1_1="\*/1 3,7,17 \* \* \*  /bin/auto_backmysql 2> /dev/null"
	command1_2="\*/1 \* \* \* \*  /bin/auto_crond 2> /dev/null"
	command1_3="5 6,16 \* \* \*  /bin/auto_managertool_backmysql 2> /dev/null"
	command1_4="\*/1 \* \* \* \*  /bin/auto_managertool_crond 2> /dev/null"
	command1_5="50 3 \* \* \* /bin/auto_managertoolall_backmysql 2> /dev/null"

	command2_0=`cat /var/spool/cron/root|grep "${command1_0}"|head -1`
	command2_1=`cat /var/spool/cron/root|grep "${command1_1}"|head -1`
	command2_2=`cat /var/spool/cron/root|grep "${command1_2}"|head -1`
	command2_3=`cat /var/spool/cron/root|grep "${command1_3}"|head -1`
	command2_4=`cat /var/spool/cron/root|grep "${command1_4}"|head -1`
	command2_5=`cat /var/spool/cron/root|grep "${command1_5}"|head -1`
	if [[ "${command2_0}" == "" ]];then
		echo "0 5 * * *  /usr/bin/find /data/log_bak -name *.txt -ctime +30 | xargs rm -f > /dev/null" >> /var/spool/cron/root
	fi
	if [[ "${command2_1}" == "" ]];then
		echo "*/1 3,7,17 * * *  /bin/auto_backmysql 2> /dev/null" >> /var/spool/cron/root
	fi
	if [[ "${command2_2}" == "" ]];then
		echo "*/1 * * * *  /bin/auto_crond 2> /dev/null" >> /var/spool/cron/root
	fi
	if [[ "${command2_3}" == "" ]];then
		echo "5 6,16 * * *  /bin/auto_managertool_backmysql 2> /dev/null" >> /var/spool/cron/root
	fi
	if [[ "${command2_4}" == "" ]];then
		echo "*/1 * * * *  /bin/auto_managertool_crond 2> /dev/null" >> /var/spool/cron/root
	fi
	if [[ "${command2_5}" == "" ]];then
		echo "50 3 * * * /bin/auto_managertoolall_backmysql 2> /dev/null" >> /var/spool/cron/root
	fi
	crontab /var/spool/cron/root
}

# 复制rsyncd配置文件,添加自启动
Copy_Rsyncd_Conf()
{
	if [[ ! -f /etc/rsyncd.conf ]];then
		/bin/cp -rvf ${FILE_DIR}/rsyncd.conf /etc/
		/bin/cp -rvf ${FILE_DIR}/rsyncd.password /etc/
		/bin/cp -rvf ${FILE_DIR}/rsyncd.password_client /etc/
		chmod 644 /etc/rsyncd.conf
		chmod 600 /etc/rsyncd.password
		chmod 600 /etc/rsyncd.password_client
		# rsync 模块示例 rsyncd_log.conf.add  追加到 /etc/rsyncd.conf
		# if [[ "`grep "\[logsrv_script\]" /etc/rsyncd.conf`" == "" ]];then
		       # /bin/cp -vf /etc/rsyncd.conf /etc/rsyncd.conf.`date +"%Y-%m-%d-%H-%M-%S"`.bak
		       # /bin/cp -rvf ${FILE_DIR}/rsyncd_log.conf.add /etc/
	               # echo "" >> /etc/rsyncd.conf
		       # echo "########## logsrv_script ##########" >> /etc/rsyncd.conf
		       # cat /etc/rsyncd_log.conf.add >> /etc/rsyncd.conf
		       # echo "======在 rsyncd.conf 新增 logsrv_script 配置模块======"
		       # cat /etc/rsyncd_log.conf.add
		       # echo "========================================================================"
		# else
		       # echo "在 rsyncd.conf 已经增加了 logsrv_script 配置模块!!!"
		# fi
	fi
}

# 复制mysql数据异地备份rsync配置模块
Copy_mysql_bk_Conf()
{
	if [[ "`grep "\[mysql_bk\]" /etc/rsyncd.conf`" == "" ]];then
		   /bin/cp -vf /etc/rsyncd.conf /etc/rsyncd.conf.`date +"%Y-%m-%d-%H-%M-%S"`.bak
		   /bin/cp -rvf ${FILE_DIR}/rsyncd_mysqlbk.conf.add /etc/
			   echo "" >> /etc/rsyncd.conf
		   echo "########## mysql_bk ##########" >> /etc/rsyncd.conf
		   cat /etc/rsyncd_mysqlbk.conf.add >> /etc/rsyncd.conf
		   echo "======在 rsyncd.conf 新增 mysql_bk 配置模块======"
		   cat /etc/rsyncd_mysqlbk.conf.add
		   echo "========================================================================"
	else
		   echo "在 rsyncd.conf 已经增加了 mysql_bk 配置模块!!!"
	fi
}

# 添加phpmyadmin服务
Add_PhpMyAdmin_Host()
{
	OutputMsg '添加phpmyadmin服务'
	phpmyadmin=$SERVER_IP.com
	/bin/cp -vf /usr/local/nginx/conf/vhost/$SERVER_IP.conf /usr/local/nginx/conf/vhost/${phpmyadmin}.conf
	ReplaceText /usr/local/nginx/conf/vhost/${phpmyadmin}.conf ".*server_name.*" "\t server_name \t ${phpmyadmin};"
	ReplaceText /usr/local/nginx/conf/vhost/${phpmyadmin}.conf ".*root.*" "\t root \t /var/www/html/phpmyadmin;"
	/etc/init.d/nginx reload
}

# 安装mysql的IBDB引擎
Install_IBDB()
{
	cd ${SCRIPT_DIR}
	cd ${PACKAGE_DIR}/
	# 安装 boost
	tar -jxf boost_1_42_0.tar.bz2
	cd boost_1_42_0
	./bootstrap.sh --prefix=/usr/local/boost
	./bjam install --without-python
	export BOOST_ROOT=/usr/local/boost
	echo "/usr/local/boost/lib" > /etc/ld.so.conf.d/boost-x86_64.conf
	ldconfig
	cd ../
	rm -rf boost_1_42_0

	# 安装infobright
	groupadd mysql
	/usr/sbin/useradd -g mysql mysql -s /sbin/nologin

	tar -zxf infobright-4.0.7-0-src-ice.tar.gz
	cd infobright-4.0.7
	make EDITION=community release
	make EDITION=community install-release
	cp -f src/build/pkgmt/my-ib.cnf /etc/
	/usr/local/infobright/bin/mysql_install_db --defaults-file=/etc/my-ib.cnf --user=mysql &
	cd ../ && rm -rf infobright-4.0.7
	cd /usr/local/infobright
	chown -R root  .
	chown -R mysql var cache
	chgrp -R mysql .
	cp -f share/mysql/mysql.server /etc/init.d/mysqld-ib
	sed -i 's/^conf=.*/conf=\/etc\/my-ib\.cnf/g'	/etc/init.d/mysqld-ib
	sed -i 's/^user=.*/user=mysql/g'	/etc/init.d/mysqld-ib
	cp -rf ${FILE_DIR}/ib_manager.sh	/usr/local/infobright
	chmod 755 /usr/local/infobright/ib_manager.sh
#	/sbin/service mysqld-ib restart
#	/sbin/chkconfig --add mysqld-ib
	/sbin/chkconfig mysqld-ib stop
	cd ${SCRIPT_DIR}
}

# 调整SSHD端口，配置文件sshd_config设置端口 ：Port 62919
Change_SSH()
{
	cd ${SCRIPT_DIR}
	/bin/mv -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.${CDATE}
	/bin/cp -vf ${FILE_DIR}/sshd_config /etc/ssh/
	chmod 600 /etc/ssh/sshd_config
	/sbin/service sshd restart
	cd ${SCRIPT_DIR}
}

# 调整xinetd参数
Change_Xinetd()
{
	cd ${SCRIPT_DIR}
	/bin/mv -f /etc/xinetd.conf /etc/xinetd.conf.bak.${CDATE}
	/bin/mv -f /etc/xinetd.d/rsync /etc/xinetd.d/rsync.bak.${CDATE}
	/bin/cp -vf ${FILE_DIR}/xinetd.conf /etc/xinetd.conf
	/bin/cp -rvf ${FILE_DIR}/rsync /etc/xinetd.d/rsync
	chmod 600 /etc/xinetd.conf
	chmod 644 /etc/xinetd.d/rsync
	/sbin/service xinetd restart
	cd ${SCRIPT_DIR}
}

# 修改rsync端口
Change_Rsync_Port()
{
	sed -i "s/^rsync.*873\//rsync		${RSYNC_PORT}\//g" /etc/services
	sed -i "s/^ssh.*22\//ssh		${SSH_PORT}\//g" /etc/services
	/sbin/service xinetd reload
}

# 在线安装ZABBIX客户端
Install_Zabbix_Online()
{
	##################  安装zabbix_client ###################
	/usr/sbin/groupadd zabbix
	/usr/sbin/useradd -g zabbix zabbix -s /sbin/nologin

	#创建目录以及修改权限
	test -d /etc/zabbix/zabbix_agentd.d || mkdir -p /etc/zabbix/zabbix_agentd.d
	test -d /var/log/zabbix/ || mkdir -p /var/log/zabbix/
	test -d /var/run/zabbix/ || mkdir -p /var/run/zabbix/
	test -d /etc/zabbix/ || mkdir -p /etc/zabbix/
	chown -R root.root /etc/zabbix/
	chown -R zabbix.zabbix /var/log/zabbix/
	chown -R zabbix.zabbix /var/run/zabbix/
	#在线安装
	#安装zabbix源、aliyu nYUM源
	curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-6.repo
	curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-6-cloud.repo
	rpm -ivh http://repo.zabbix.com/zabbix/3.0/rhel/6/x86_64/zabbix-release-3.0-1.el6.noarch.rpm


	cp -rf zabbix_agentd.conf /etc/zabbix/
	cp -rf zabbix-agent /etc/init.d/zabbix-agent
	chmod +x /etc/init.d/zabbix-agent
	chkconfig --add zabbix-agent   #添加开机启动
	chkconfig zabbix-agent off
	/etc/init.d/zabbix-agent stop

	cd ${SCRIPT_DIR}
}

#升级gcc6.1
Upgrade_Gcc()
{
	cd ${SCRIPT_DIR}
	cd ${PACKAGE_DIR}/

	#安装依赖库
	yum install -y texinfo-tex flex zip libgcc.i686 glibc-devel.i686

	#安装gcc
	tar zxf gcc-6.1.0.tar.gz
	cd gcc-6.1.0/
	./contrib/download_prerequisites   
	mkdir gcc-build-6.1.0
	cd gcc-build-6.1.0
	../configure -enable-checking=release -enable-languages=c,c++ -disable-multilib
	yum -y groupinstall "Development Tools"
	make && make install

	#找到 gcc 6.1.0 最新的库文件
	NEWEST_GCC_LIB_FILE=`find ../ -name "libstdc++.so*" |grep 'stage1-x86_64-pc-linux-gnu/libstdc++-v3/src/.libs/libstdc++.so.6.0.22'`
	/bin/cp $NEWEST_GCC_LIB_FILE /usr/lib64
	cd /usr/lib64
	/bin/rm libstdc++.so.6
	ln -s libstdc++.so.6.0.22 libstdc++.so.6
	#---------到此时，电脑上有两个版本的gcc，位置不一样（/usr/bin/gcc /usr/local/bin/gcc）----------#
	/bin/mv /usr/bin/gcc /usr/bin/gcc4.4.7
	ln -s /usr/local/bin/gcc /usr/bin/gcc

	/bin/mv /usr/bin/g++ /usr/bin/g++4.4.7
	ln -s /usr/local/bin/g++ /usr/bin/g++

	mv /usr/bin/c++ /usr/bin/c++4.4.7
	ln -s /usr/local/bin/c++ /usr/bin/c++

	#显示当前gcc版本
	echo "当前gcc版本："
	gcc -v
	echo "当前g++版本："
	g++ -v

	echo "-----------------注意：升级完gcc要重启服务器（reboot）---------------------"
	cd ${SCRIPT_DIR}
}

# 升级gcc到4.8.5版本
Upgrade_Gcc_4_8_5()
{
	cd ${SCRIPT_DIR}
	cd ${PACKAGE_DIR}/

	#安装依赖库
	yum install -y texinfo-tex flex zip libgcc.i686 glibc-devel.i686

	#安装gcc
	tar zxf gcc-4.8.5.tar.gz
	cd gcc-4.8.5/
	./contrib/download_prerequisites
	mkdir gcc-build-4.8.5
	cd gcc-build-4.8.5
	../configure -enable-checking=release -enable-languages=c,c++ -disable-multilib
	yum -y groupinstall "Development Tools"
	make && make install

	#找到 gcc 4.8.5 最新的库文件
	NEWEST_GCC_LIB_FILE=`find ../ -name "libstdc++.so*" | grep 'stage1-x86_64-unknown-linux-gnu/libstdc++-v3/src/.libs/libstdc++.so.6.0.19'`
	/bin/cp $NEWEST_GCC_LIB_FILE /usr/lib64
	cd /usr/lib64
	/bin/rm libstdc++.so.6
	ln -s libstdc++.so.6.0.19 libstdc++.so.6
	#---------此时有两个版本的gcc，位置不一样（/usr/bin/gcc /usr/local/bin/gcc）----------#
	/bin/mv /usr/bin/gcc /usr/bin/gcc4.4.7
	ln -s /usr/local/bin/gcc /usr/bin/gcc

	/bin/mv /usr/bin/g++ /usr/bin/g++4.4.7
	ln -s /usr/local/bin/g++ /usr/bin/g++

	mv /usr/bin/c++ /usr/bin/c++4.4.7
	ln -s /usr/local/bin/c++ /usr/bin/c++

	#显示当前gcc版本
	echo "当前gcc版本："
	gcc -v
	echo "当前g++版本："
	g++ -v

	echo "-----------------注意：升级完gcc要重启服务器（reboot）---------------------"
	cd ${SCRIPT_DIR}
}

# 输出检测信息
Check_Config()
{
	cdate=`date +'%Y年%m月%d日%H时%M分%S秒'`
	echo "==============================================="
	echo "网卡信息: "
	echo $DEVICE
	# /sbin/ethtool -i ${IF_name}
	echo "==============================================="
	echo "查看定时任务:"
	/usr/bin/crontab -l
	/bin/ls -l /bin/
	echo "==============================================="
	echo "服务器时间:${cdate}"
	/sbin/hwclock --systohc
	echo "==============================================="
	echo "系统时间写入硬件时钟"
	/sbin/hwclock -w

	echo "==============================================="
	echo "Mysql启动信息"
	/sbin/service ${MysqldFile} restart
	echo "==============================================="
#	echo "Mysql启动信息(infobright)"
#	/sbin/service mysqld-ib restart
	echo "==============================================="
	echo "nginx & php & redis启动信息"
	/sbin/service nginx restart
	/sbin/service php-fpm restart
	/sbin/service redis restart
	echo "==============================================="
	echo "磁盘信息:"
	/bin/df -lh
	echo "==============================================="
	echo "定时任务检查"
	/usr/bin/crontab -l
	/bin/ls -l|grep auto
	echo "==============================================="

	echo "服务器时区"
	/bin/date -R
	echo "数据库时间"
	echo "show variables like '%time_zone%';" | $MysqlInstallDir/bin/${MysqlFile} --connect-expired-password -uroot -p${DB_PWD} -S /tmp/mysql${MysqlPort}.sock
    echo "==============================================="
	echo "磁盘信息:"
	/bin/df -lh
	echo "==============================================="
	echo "查看数据库用户权限"
	echo "select user,host from mysql.user;" | $MysqlInstallDir/bin/${MysqlFile} --connect-expired-password -uroot -p${DB_PWD} -S /tmp/mysql${MysqlPort}.sock
	echo "==============================================="
	echo "ntp禁止开机启动"
	/sbin/chkconfig --list|grep ntp
	ps aux|grep ntp
	echo "==============================================="
}

# keepalived实现双机热备
# keepalived的作用是检测后端TCP服务的状态，如果有一台提供TCP服务的后端节点死机，或者工作出现故障，
# keepalived会及时检测到，并将有故障的节点从系统中剔除，当提供TCP服务的节点恢复并且正常提供服务后keepalived会自动将TCP服务的节点加入到集群中。
# 这些工作都是keepalived自动完成，不需要人工干涉，需要人工做的只是修复发生故障的服务器
Install_Keepalived()
{
	# 安装后配置路径为/etc/keepalived/keepalived.conf
	yum install -y keepalived
}

# 安装java运行环境JDK
Install_Java()
{
	cd ${SCRIPT_DIR}
	OutputMsg '检查是否已安装java（需手动卸载）'
	rpm -qa | grep java
	
	cd ${PACKAGE_DIR}
	mkdir -p /usr/local/java
	
	tar -zxvf jdk-8u202-linux-x64.tar.gz -C /usr/local/java
	
	OutputMsg '增加java环境变量'
	JAVA_HOME=/usr/local/java/jdk1.8.0_202
	JRE_HOME=/usr/local/java/jdk1.8.0_202/jre
	echo "
export JAVA_HOME=${JAVA_HOME}
export JRE_HOME=${JRE_HOME}
export CLASSPATH=.:\$JAVA_HOME/lib/dt.jar:\$JAVA_HOME/lib/tools.jar:\$JRE_HOME/lib:\$CLASSPATH
export PATH=\$JAVA_HOME/bin:\$PATH" >> /etc/profile
	# vi ~/.bash_profile   另外可配置普通用户java环境变量
	source /etc/profile
	OutputMsg 'java安装完成，版本信息:'
	java -version
	cd ${SCRIPT_DIR}
}

# 安装数据库集群中间件Mycat（读写分离）
Install_Mycat()
{
	cd ${SCRIPT_DIR}
	cd ${PACKAGE_DIR}
	OutputMsg 'Mycat安装目录为/usr/local/mycat'
	# jdk 版本必须是 1.7 及以上版本
	rm -rf /usr/local/mycat
	tar -zxvf Mycat-server-1.6.6.1-release-20181031195535-linux.tar.gz  -C /usr/local/
	
	# 修改java路径
	# vi /usr/local/mycat/conf/wrapper.conf 
	# Java Application
	# wrapper.java.command=/usr/local/java/jdk1.8.0_202/bin/java
	cd ${SCRIPT_DIR}
}

############################  开始初始化系统 (CentOS6.x: 6.5,6.8,6.9,6.10已成功)  #######################################
############### 切换到 /install_system/目录下执行脚本(初始化约15分钟)   ##############
# sudo su
# chmod -R 777 ./*
# 执行：echo '' > logs/install_system.log && ./install_system.sh | tee -a logs/install_system.log


## 定义初始化脚本目录名称（绝对路径）
SCRIPT_DIR=$(cd `dirname $0`; pwd)
KEY_DIR=${SCRIPT_DIR}/keys
FILE_DIR=${SCRIPT_DIR}/files
PACKAGE_DIR=${SCRIPT_DIR}/packages
LOG_DIR=${SCRIPT_DIR}/logs
TMP_DIR=${SCRIPT_DIR}/tmp

start_install=`date +"%s"`
CDATE=`date '+%Y-%m-%d-%H-%M-%-S'`

## 获取服务器ip
SERVER_IP=$(/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:")
DEVICE=`cat /etc/sysconfig/network-scripts/ifcfg-eth*`

OutputMsg "服务器IP:${SERVER_IP}"

## 配置mysql数据库root密码
DB_PWD='RootG8YCqMQXu83John'
DB_ALLOW_IP='127.0.0.1'

# 只有查询权限的用户
custom_user="nobody"
custom_user_password="nobodyFjL6zXu7z9T"

######################################## 安装MySQL配置 ################################################
#
# 定义默认端口: MysqlDefaultPort,不带后缀的端口实例，启动 /etc/init.d/mysql start；
# MysqlDefaultPort='4580' (默认端口)
# MysqlPort='4580'  (实际设置端口)
# 如果 MysqlPort=MysqlDefaultPort,则安装不加后缀的/etc/init.d/mysql start；启动程序，
# 否则安装启动需加端口 如 /etc/init.d/mysql${MysqlPort} start 的实例,安装目录 /usr/local/mysql${MysqlPort}/
#
#######################################################################################################

MysqlDefaultPort='4580'
MysqlPort='4580'
MysqlInstallDir=/usr/local/mysql
MyCnfFile=my.cnf
MysqldFile=mysqld
MysqlFile=mysql
# php 指向路径
WithMysql=/usr/local/mysql

# 不是默认端口，调整路径及名称
if [[ "${MysqlPort}" != "${MysqlDefaultPort}" ]];then
	MysqlInstallDir=/usr/local/mysql${MysqlPort}
	MyCnfFile=my${MysqlPort}.cnf
	MysqldFile=mysqld${MysqlPort}
	MysqlFile=mysql${MysqlPort}
	WithMysql=/usr/local/mysql${MysqlPort}
fi

# 调整rsync，ssh端口，配置redis端口
RSYNC_PORT='786'
SSH_PORT='22'
REDIS_PORT='5632'

OutputMsg '开始安装系统'

##增加Linux用户账号
Add_Users

#安装依赖库
Install_Package_Optimize

#关闭防火墙
Iptable_Off

#安装MySQL
Install_Mysql

## 配置mysql
Configure_Mysql

# 安装web环境（lnmp）
Install_Web

# 增加phpmyadmin虚拟主机访问
Add_PhpMyAdmin_Host

## 安装redis服务
Install_Redis

# 安装java运行环境
Install_Java

###################################################### 其它非必须步骤
## infobright数据库（引擎ENGINE=BRIGHTHOUSE）
# Install_IBDB

## 创建自动处理定时任务（ crontab /var/spool/cron/root ）
# Create_Dir_Log

# 异地备份rsync配置模块
# Copy_mysql_bk_Conf
######################################################

#### 复制rsync用户power密码认证等文件（用于跨服务器传输文件）
Copy_Rsyncd_Conf

#### keepalived 实现双机热备
# Install_Keepalived

## 修改xinetd
Change_Xinetd

## 修改ssh端口
Change_SSH

## 修改rsync端口
Change_Rsync_Port

## 最后检查系统初始化结果信息
Check_Config

## zabbix客户端安装
# Install_Zabbix_Online

end_install=`date +"%s"`
minute=$(( (${end_install} - ${start_install})/60 ))
second=$(( (${end_install} - ${start_install})%60 ))
echo "执行时间：${minute}分${second}秒"
exit

# 执行：echo '' > logs/install_system.log && ./install_system.sh | tee -a logs/install_system.log
# 安装前后命令行执行mysql语句
# echo "show master status;" | /usr/local/mysql/bin/mysql --connect-expired-password -uroot -pRootG8YCqMQXu83John -S /tmp/mysql4580.sock
