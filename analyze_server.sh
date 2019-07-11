#!/bin/bash
[[ -z $1 ]] && echo "使用: ${0} [game_name] " && exit
game=$1
now=`date +"%s"`

declare -A total_arr
declare -A merge_arr
declare -A online_arr
declare -A unopen_arr

function array_key_exists()
{
        search=$1
        arr=$2
        for key in ${!arr[*]}
        do
        if [ "$search" = "$key" ];then
                        return 0
        fi
        done
        return 1
}

function output_arr ()
{
	arr=$1
	for key in ${!arr[@]}
	do
			echo "平台：${key} ，数量 :"
			echo ${arr[$key]}
	done
}

for plat_cname in `ls /$game|grep -v lost+found`;do
        # 初始化数组
        ret=`array_key_exists $plat_cname $total_arr`
        if [[ ! $ret ]] ;then
                total_arr[$plat_cname]=0
                merge_arr[$plat_cname]=0
                online_arr[$plat_cname]=0
                unopen_arr[$plat_cname]=0
        fi
        # 统计平台总服数
        total=`ls /$game/$plat_cname|grep -v managertool|grep -v mobileclient_res|wc -l`
        total_arr[$plat_cname]=$total

        # 统计合服数
        for server_id in `ls /$game/$plat_cname|grep -v managertool|grep -v mobileclient_res`;do
                commonconfig_file="/${game}/${plat_cname}/${server_id}/out/config/serverconfig/commonconfig.xml"
                if [[ -f $commonconfig_file ]] ;then
                        ServerStartTimeS=`cat $commonconfig_file | grep  ServerStartTimeS | sed 's#.*<ServerStartTimeS>\(.*\)<\/ServerStartTimeS>.*#\1#g'`
                        if [[ $ServerStartTimeS -gt $now ]];then
                                # 未开服
                                let unopen_arr[$plat_cname]++
                                else
                                # 已运行
                                let online_arr[$plat_cname]++
                        fi
                else
                        let merge_arr[$plat_cname]++
                fi
        done
done

function dump()
{
        declare -A a
        a=$1
        echo ${a[@]}
        echo ${!a[@]}
}

echo -e "\n所有服信息：\n"
for key in ${!total_arr[@]}
do
		echo "${key} : ${total_arr[$key]}"
done

echo -e "\n已合服信息：\n"
for key in ${!merge_arr[@]}
do
		echo "${key} : ${merge_arr[$key]}"
done

echo -e "\n正在运行服信息：\n"
for key in ${!online_arr[@]}
do
		echo "${key} : ${online_arr[$key]}"
done

echo -e "\n未开服信息：\n"
for key in ${!unopen_arr[@]}
do
		echo "${key} : ${unopen_arr[$key]}"
done
