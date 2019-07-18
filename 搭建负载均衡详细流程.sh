###############################################################################################################################
###############################  nginx实现请求的负载均衡 + keepalived实现nginx的高可用 成功实例 ###############################
###############################################################################################################################

192.168.227.141：nginx + keepalived   master
192.168.227.142：nginx + keepalived   backup
192.168.227.143：nginx (web)
192.168.227.144：nginx (web)
192.168.227.145：auth (做会话服务器 : 此处测试用192.168.227.142充当会话服务器 )
虚拟ip(VIP):192.168.227.140，对外提供服务的ip，也可称作浮动ip
******** 4、VIP也称浮动ip，是公网ip，与域名进行映射，对外提供服务； 其他ip一般而言都是内网ip， 外部是直接访问不了的 ************************

)))))
#141 及 142 机器配置： 
### server 模块前增加 upstream ( 在nginx.conf配置)
###  添加web主机列表，真实应用服务器都放在这
upstream web_nginx_pool
{
   #server nginx地址:端口号 weight表示权值，权值越大，被分配的几率越大;
   server 192.168.227.143:80 weight=4 max_fails=2 fail_timeout=30s;
   server 192.168.227.144:80 weight=4 max_fails=2 fail_timeout=30s;
}

# server 模块增加反向代理到上述web主机名,如下
server
{
	listen       80;
	server_name        192.168.227.142;
	index index.html index.htm index.php;
	root    /usr/local/nginx/html;
	charset utf-8;
	location ~.*\.(css|js|swf|jpg|gif|png|jpep|jpg|mp3|xx|xmlbak|xml)$ {
		expires       720h;
	}
	access_log off;

	# 默认请求设置
	location / {
		proxy_pass http://web_nginx_pool;    # 转向web_nginx处理
	}
	# 所有的php页面均由web_nginx处理 （需设置转向相关头部信息：Host，X-Real-IP）
	location ~ \.php$ {
		proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
		proxy_pass http://web_nginx_pool;   # 转向web_nginx处理
	}

}

2)))))
keepalived实现nginx高可用(HA)
# 安装keepalived ： 	yum install -y openssl openssl-devel keepalived
# 安装后配置路径为 /etc/keepalived/keepalived.conf
# 写入如下配置到 master（227.141）机器
# VRRP双方节点都启动以后，要实现状态转换的，刚开始启动的时候，初始状态都是BACKUP，而后向其它节点发送通告，以及自己的优先级信息，谁的优先级高，就转换为MASTER，否则就还是BACKUP，这时候服务就在状态为MASTER的节点上启动，为用户提供服务，如果，该节点挂掉了，则转换为BACKUP，优先级降低，另一个节点转换为MASTER，优先级上升，服务就在此节点启动，VIP,VMAC都会被转移到这个节点上，为用户提供服务，

# 全局定义块
global_defs {
    notification_email {
        603480498@qq.com
    }
    notification_email_from jcai12321@gmail.com
    smtp_server smtp.hysec.com
    smtp_connection_timeout 30
    router_id nginx_master        # 设置nginx master的id，在一个网络应该是唯一的
}

vrrp_script chk_http_port {
    script "/usr/local/nginx/conf/check_nginx_pid.sh"    # 最后手动执行下此脚本，以确保此脚本能够正常执行
    interval 2                          #（检测脚本执行的间隔，单位是秒）
    weight 2
}

vrrp_instance VI_1 {
    state MASTER            # 指定keepalived的角色，MASTER为主，BACKUP为备
    interface eth0            # 当前进行vrrp通讯的网络接口卡(当前centos的网卡)
    virtual_router_id 66        # 虚拟路由编号，主从要一直
    priority 100            # 优先级，数值越大，获取处理请求的优先级越高
    advert_int 1            # 检查间隔，默认为1s(vrrp组播周期秒数)
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    track_script {
		chk_http_port            #（调用检测脚本）
    }
    virtual_ipaddress {
        192.168.227.140            # 定义虚拟ip(VIP)，可多设，每行一个,是公网ip，与域名进行映射，对外提供服务
    }
}

# 写入如下配置到backup（227.142）机器
global_defs {
    notification_email {
        603480498@qq.com
    }
    notification_email_from jcai12321@gmail.com
    smtp_server smtp.hysec.com
    smtp_connection_timeout 30
    router_id nginx_backup        # 设置nginx backup的id，在一个网络应该是唯一的
}

vrrp_script chk_http_port {
    script "/usr/local/nginx/conf/check_nginx_pid.sh"    #最后手动执行下此脚本，以确保此脚本能够正常执行
    interval 2                          #（检测脚本执行的间隔，单位是秒）
    weight 2
}

vrrp_instance VI_1 {
    state BACKUP            # 指定keepalived的角色，MASTER为主，BACKUP为备
    interface eth0            # 当前进行vrrp通讯的网络接口卡(当前centos的网卡)
    virtual_router_id 66        # 虚拟路由编号，主从要一直
    priority 99            # 优先级，数值越大，获取处理请求的优先级越高
    advert_int 1            # 检查间隔，默认为1s(vrrp组播周期秒数)
    authentication {
        auth_type PASS		#VRRP认证方式，主备必须一致
        auth_pass 1111		#(密码)  应该为随机的字符串
    }
    track_script {
		chk_http_port            #（调用检测脚本）
    }
    virtual_ipaddress {
        192.168.227.140            # 定义虚拟ip(VIP)，可多设，每行一个,是公网ip，与域名进行映射，对外提供服务
    }
}

########################## check_nginx_pid.sh 内容 ############################
#!/bin/bash

A=`ps -C nginx --no-header |wc -l`  # 查看nginx进程（正常为2）
if [ $A -eq 0 ];then
    /etc/init.d/nginx restart                # 重启nginx (安装方式不同命令不同)
    if [ `ps -C nginx --no-header |wc -l` -eq 0 ];then    # nginx重启失败
        exit 1
    else
        exit 0
    fi
else
    exit 0
fi
########################## check_nginx_pid.sh 内容 ############################

# 启动keepalived
service keepalived start
# 停止
service keepalived stop
# 重启keepalived
service keepalived restart


# 查看keepalived日志
tail /var/log/messages

# 查看定义虚拟ip(VIP)状态码
ip a
如下有vip定义虚拟ip：192.168.227.140 则此服务器为当前启用状态
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    link/ether 00:0c:29:61:89:78 brd ff:ff:ff:ff:ff:ff
    inet 192.168.227.142/24 brd 192.168.227.255 scope global eth0
    inet 192.168.227.140/32 scope global eth0
    inet6 fe80::20c:29ff:fe61:8978/64 scope link
       valid_lft forever preferred_lft forever

有如下信息 : VIP 信息
inet 192.168.227.140/32 scope global eth0

查看进程:ps aux|grep keepalived


3、请求走向
访问虚拟IP(VIP)，keepalived将请求映射到本地nginx，nginx将请求转发至tomcat，例如：http://192.168.0.200/myWeb/，被映射成http://192.168.0.221/myWeb/，
端口是80，而221上nginx的端口正好是80；映射到nginx上后，nginx再进行请求的转发。
VIP总会在keepalived服务器中的某一台上，也只会在其中的某一台上；VIP绑定的服务器上的nginx就是master，当VIP所在的服务器宕机了，keepalived会将VIP转移
到backup上，并将backup提升为master。
4、VIP也称浮动ip，是公网ip，与域名进行映射，对外提供服务； 其他ip一般而言都是内网ip， 外部是直接访问不了的

))))))))))))

143,144  配置对应站点主机：www.lvs-keepalived.com
server
{
        listen       80;
        server_name     www.lvs-keepalived.com;
        index index.html index.htm index.php;
        root            /var/www/html/www.lvs-keepalived.com;
        charset utf-8;
        location ~.*\.(css|js|swf|jpg|gif|png|jpep|jpg|mp3|xx|xmlbak|xml)$ {
                expires       720h;
        }

        access_log off;

        location ~ .*\.php$ {
                include fastcgi.conf;
                 fastcgi_pass    127.0.0.1:8888;
                fastcgi_index index.php;
                expires off;
                access_log off;
        }
}


加上/var/www/html/www.lvs-keepalived.com/t.php测试文件;


######### 电脑host加上   192.168.227.140    www.lvs-keepalived.com
####    访问:  http://www.lvs-keepalived.com/t.php  查看结果，看到不同机器的结果

Keepalived日志
默认日志存放在系统日志: /var/log/messages
 
141 服务器停掉：
查看142备用机日志信息
[root@localhost conf]# tail /var/log/messages
Jul 18 09:11:08 localhost Keepalived_vrrp[3422]: VRRP_Instance(VI_1) Transition to MASTER STATE
Jul 18 09:11:09 localhost Keepalived_vrrp[3422]: VRRP_Instance(VI_1) Entering MASTER STATE
Jul 18 09:11:09 localhost Keepalived_vrrp[3422]: VRRP_Instance(VI_1) setting protocol VIPs.
Jul 18 09:11:10 localhost Keepalived_vrrp[3422]: VRRP_Instance(VI_1) Sending gratuitous ARPs on eth0 for 192.168.227.140
Jul 18 09:11:10 localhost Keepalived_healthcheckers[3421]: Netlink reflector reports IP 192.168.227.140 added
Jul 18 09:11:15 localhost Keepalived_vrrp[3422]: VRRP_Instance(VI_1) Sending gratuitous ARPs on eth0 for 192.168.227.140
[root@localhost conf]# 
[root@localhost conf]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN 
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    link/ether 00:0c:29:61:89:78 brd ff:ff:ff:ff:ff:ff
    inet 192.168.227.142/24 brd 192.168.227.255 scope global eth0
    inet 192.168.227.140/32 scope global eth0
    inet6 fe80::20c:29ff:fe61:8978/64 scope link 
       valid_lft forever preferred_lft forever
[root@localhost conf]# 
##  Netlink reflector reports IP 192.168.227.140 added
##  inet 192.168.227.140/32 scope global eth0   可以看到142已经接管的访问的VIP，站点访问依然正常

))))))))
再停掉143web1机器，可以看到144-nginx日志有短暂upstream访问延迟的日志，3秒后访问又恢复正常
[root@localhost conf]# less /usr/local/nginx/logs/error.log 
2019/07/18 09:16:22 [error] 9431#0: *40 connect() failed (113: No route to host) while connecting to upstream, client: 192.168.227.1, server: localhost, request: "GET /redis_session.php?a=1 HTTP/1.1", upstream: "http://192.168.227.143:80/redis_session.php?a=1", host: "www.lvs-keepalived.com"




######### 主从热备+负载均衡（LVS + keepalived）测试域名  ##########
### 公网ip访问，与域名映射
192.168.227.140     www.lvs-keepalived.com
### 主
192.168.227.141     www.lvs-keepalived1.com
### 备用
192.168.227.142     www.lvs-keepalived2.com

))))))))))))))))))

解决负载均衡导致session不一致问题
192.168.227.142 （正式应独立开一台:内存大点）做 redis 服务器 

143,144配置php session保存类型，服务器

2）如果将session.save_handler修改为redis，即表示将php的session信息存放到redis里（前提是安装了php的phpredis扩展），然后在session.save_path处
配置redis的connect 地址。如下：

session.save_handler = redis 
session.save_path = "tcp://127.0.0.1:6379"

########################################### 142 redis机器远程连接设置
0,设置连接端口
port 60312

1、将 bind 127.0.0.1 ::1 这一行注释掉。
这里的bind指的是只有指定的网段才能远程访问这个redis。  注释掉后，就没有这个限制了。
或者bind 自己所在的网段

band localhost   只能本机访问,局域网内计算机不能访问。
bind  局域网IP    只能局域网内IP的机器访问, 本地localhost都无法访问。
######### 绑定
bind 0.0.0.0 即可 (所有主机访问)

2、将 protected-mode 要设置成 no   （默认是设置成yes的， 防止了远程访问，在redis3.2.3版本后）
 
#将protected-mode模式修改为no
protected-mode no

3、设置远程连接密码
取消注释 requirepass foobared
将 foobared 改成任意密码，用于验证登录
默认是没有密码的就可以访问的，我们这里最好设置一个密码

#设置需要密码才能访问,password修改为你自己的密码
requirepass nF2eZ830OkIgTFmTUmiu

#修改这个为yes,以守护进程的方式运行，就是关闭了远程连接窗口，redis依然运行
daemonize yes


4、重启 reids
/etc/init.d/redis restart
