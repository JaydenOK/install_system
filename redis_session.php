<?php
/**
 * php+redis-负载均衡-保持多台web业务服务器会话一致
 * 架构 ： 主+备+web1+web2+web3(auth-redis会话服务器)
 * 192.168.227.141：nginx + keepalived   master
 * 192.168.227.142：nginx + keepalived   backup
 * 192.168.227.143：nginx (web)
 * 192.168.227.144：nginx (web)
 * 192.168.227.145：auth (做会话服务器 : 此处测试用 192.168.227.142 充当会话服务器 )
 */

//全局变量保存
$_ENV = array(
    //redis对象
    'cache' => null,
    //配置
    'conf'  => array(
        'host'         => '192.168.227.142',
        'port'         => '60312',
        'password'     => 'nF2eZ830OkIgTFmTUmiu',
        'lifetime'     => 1200,     //20分钟失效
        'session_name' => 'SESSIONID',
    ),
);

class SessionHandle
{
    protected static $prefix = 'sess_';

    public static function open()
    {
        session_write_close();
        ini_set('session.auto_start', 0);
        //清理概率 = gc_probability/gc_divisor
        ini_set('session.gc_probability', 1);
        ini_set('session.gc_divisor', 50);
        ini_set('session.name', $_ENV['conf']['session_name']);
        ini_set('session.use_cookies', 1);
        //if (true) {
        ////客户端禁用cookie时，启用url传值，html页面上的链接会基于url传递SESSIONID
        //    ini_set('session.use_trans_sid', 1);
        //    ini_set('session.use_only_cookies', 0);
        //}
        ini_set('session.gc_maxlifetime', $_ENV['conf']['lifetime']);
        ini_set('session.cookie_lifetime', $_ENV['conf']['lifetime']);
        try {
            $_ENV['cache'] = new Redis();
            $_ENV['cache']->connect($_ENV['conf']['host'], $_ENV['conf']['port']);
            $_ENV['cache']->auth($_ENV['conf']['password']);
        } catch (\Exception $e) {
            if (0 == strncasecmp("Can't connect to", $e->getMessage(), strlen("Can't connect to"))) {
                exit('connect redis fail:' . $_SERVER['HTTP_HOST']);
            }
        }
        return true;
    }

    public static function read($id)
    {
        return $_ENV['cache']->get(self::$prefix . $id);
    }

    public static function write($id, $data)
    {
        return $_ENV['cache']->set(self::$prefix . $id, $data, $_ENV['conf']['lifetime']);
    }

    public static function close()
    {
        $_ENV['cache']->close();
        unset($_ENV['cache'], $_ENV['conf']);
        return TRUE;
    }

    public static function destroy($id)
    {
        return $_ENV['cache']->delete(self::$prefix . $id);
    }

    public static function gc()
    {
        return true;
    }

}


//用户自定义session处理机制。php.ini 配置：session.save_handler = user
session_set_save_handler('SessionHandle::open', 'SessionHandle::close', 'SessionHandle::read', 'SessionHandle::write', 'SessionHandle::destroy', 'SessionHandle::gc');
$session_name = $_ENV['conf']['session_name'];
$_ENV[$session_name] = (isset($_COOKIE[$session_name])) ? trim($_COOKIE[$session_name]) : session_id();
if ($_ENV[$session_name] !== '') {
    //客户端有发送session_id时，将其设置为此次会话id，没有则生成新的
    session_id($_ENV[$session_name]);
}
session_start();

$_SESSION['user'] = 'john';

echo "被访问的主机:", $_SERVER['SERVER_ADDR'], '<br>';
echo "<br><br>请求参数:<br>";
print_r($_REQUEST);
echo "<br><br>SESSION:<br>";
print_r($_SESSION);
echo "<br><br>ENV:<br>";
print_r($_ENV);
echo "<br><br>COOKIE:<br>";
print_r($_COOKIE);

echo '<br><br>', '<a href="?a=11">下一页</a>';






###################################################
/*
//查看redi当前保存的session信息文件:redis.php
<?php

//全局变量保存
$_ENV = array(
    //redis对象
    'cache' => null,
    //配置
    'conf'  => array(
        'host'         => '192.168.227.142',
        'port'         => '60312',
        'password'     => 'nF2eZ830OkIgTFmTUmiu',
        'lifetime'     => 1200,     //20分钟失效
        'session_name' => 'SESSIONID',
    ),
);


try {
    $_ENV['cache'] = new Redis();
    $_ENV['cache']->connect($_ENV['conf']['host'], $_ENV['conf']['port']);
    $_ENV['cache']->auth($_ENV['conf']['password']);
} catch (\Exception $e) {
    if (0 == strncasecmp("Can't connect to", $e->getMessage(), strlen("Can't connect to"))) {
        exit('connect redis fail:' . $_SERVER['HTTP_HOST']);
    }
}


echo '当前redis保存信息：<br>';

$keys = $_ENV['cache']->keys('*');
foreach ($keys as $key) {
    $str = $_ENV['cache']->get($key);
    echo "键：{$key} ;值：{$str}", '<br>';
}



*/

