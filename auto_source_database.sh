#!/bin/bash

# 自动删除旧表，入库脚本
# 注意在数据库所在服ip执行[dbHost='127.0.0.1'],数据库不存在时会提示创建数据库
# ./auto_source_database.sh [解压后的目录名] [数据库名-可省略]

basePath=$(cd "$(dirname "$0")";pwd)
dbUser='root'
dbPass='11111111'
dbHost='127.0.0.1'
dbPort='9999'

# 标准输入确认是否继续执行，$1 提示信息
function shell_confirm()
{
    if [[ -n $1 ]]; then echo $1; fi
    while true ;do
        read -p "请输入[y/n]【继续|终止】:" input;
        case $input in
            y|Y)
                echo "继续执行"
                break;
            ;;
            n|N)
                echo "已终止"
                exit;
            ;;
            *)
                ## 其它
            ;;
        esac
    done
}

if [[ -n $1  ]]; then
    backupsPath=$1
	if [[ -n $2 ]]; then
		dbName=$2
	else
		game=`echo $1|awk -F_ '{print $1}'`
		plat=`echo $1|awk -F_ '{print $2}'`
		server=`echo $1|awk -F_ '{print $3}'`
		db=`echo $1|awk -F_ '{print $4}'`
		if [[ "${server}" == "manager"  ]]; then
			dbName=${game}_${plat}_${server}
		else
			dbName=${game}_${plat}_${server}_${db}
		fi
	fi
    # 判断是否存在数据库
    dbFlag=`echo "SHOW DATABASES;" | mysql -h${dbHost} -P${dbPort} -u${dbUser} -p${dbPass}|grep $dbName`
    if [[ -z $dbFlag ]];then
        shell_confirm "数据库 ${dbName} 不存在，是否创建?"
        mysql -h${dbHost} -P${dbPort} -u${dbUser} -p${dbPass} -e "CREATE DATABASE IF NOT EXISTS ${dbName} DEFAULT CHARSET utf8 COLLATE utf8_general_ci;"
    fi
    # 查找已存在的表
    tableList=`echo "SHOW TABLES;" | mysql -h${dbHost} -P${dbPort} -u${dbUser} -p${dbPass} -D${dbName}|grep -v "Tables_in_"`
    if [[ -d ${basePath}/${backupsPath} ]]; then
	    opFlag=0
        for sqlFile in `find  ${basePath}/${backupsPath} -name "*.sql"`; do
            echo $sqlFile;
            opFlag=1
            # 去掉sql后缀及路径
            tbName=`echo ${sqlFile}|awk -F. '{print $1}'`
            tbName=`echo ${tbName}|sed  "s#${basePath}\/${backupsPath}[\/]*##g"`
            if [[ $tableList =~ ${tbName} ]];then
                mysql -h${dbHost} -P${dbPort} -u${dbUser} -p${dbPass} -f $dbName -e "DROP TABLE ${tbName}"
                echo "已删除表:${tbName}"
            fi
            mysql -h${dbHost} -P${dbPort} -u${dbUser} -p${dbPass} -f $dbName -e "source ${sqlFile}"
            if [[ $? = 0 ]];then
                echo "已导入:${tbName}"
            else
                echo "导入失败:${tbName}"
            fi
        done
		if [[ $opFlag == 0 ]];then
			echo '没有对应的SQL文件'
		else
			echo '入库已完成'
		fi
    else
        echo "待入库的sql文件夹不存在:${basePath}/${backupsPath}"
        exit
    fi
else
    echo "# $1 sql文件夹名称"
    echo "# $2 数据库名称"
    exit
fi
