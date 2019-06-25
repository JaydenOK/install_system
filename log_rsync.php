<?php
//php单进程执行日志解析任务，自动清除上次执行异常锁（超时30min）

function check_lock_num()
{
    $strcmd = "ps aux|grep log_rsync_thread|grep " . GAME_NAME . "|wc -l";
    $ret = array();
    exec($strcmd, $ret);
    return $ret[0];
}

if (empty($module)) {
    exit;
}

$lockfile = SRC_DIR . 'log_rsync.lock';
if (is_file($lockfile)) {
    $strcmd = "ps aux|grep log_rsync.php|grep " . GAME_NAME . "|wc -l";
    exec($strcmd, $process_arr);
    print_r($process_arr);
    if ($process_arr[0] > 2) {
        //进程数少于等于2个为上次异常退出而没有清除互斥锁
        $locktime = strtotime(file_get_contents($lockfile));
        //避免异常后不再同步的情况
        if (time() - $locktime < 30 * 60) {
            exit('已经存在另一个同步进程log_rsync.lock');
        } else {
            //结束上一次的超时运行，并且退出
            unlink($lockfile);
            system("ps aux|grep log_rsync.php|grep " . GAME_NAME . "|awk '{print $2}'|xargs kill -9");
            exit;
        }
    }
}
file_put_contents($lockfile, date('Y-m-d H:i:s'));

//判断任务类型
$task_name = 'log_rsync_thread.php';
$allow_thread_num = 5;
//开始定时任务
foreach ($module as $module_name => $module_info) {
    while (check_lock_num() >= $allow_thread_num) {
        sleep(1);
    }
    usleep(100000);
    $strcmd = PHP_BIN_DIR . SRC_DIR . "log_rsync_thread.php {$module_name}  > /dev/null &";
    // echo $strcmd;
    exec($strcmd, $result);
}

unlink($lockfile);
?>
