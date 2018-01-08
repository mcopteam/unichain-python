#!/bin/bash

function usage(){
    echo -e "Usage: $0 \$1 \$2 \$3 \$4"
    echo -e "\t\t \$0 每秒发送的压力大小"
    echo -e "\t\t \$1 统计阶段前压力持续时间 s"
    echo -e "\t\t \$2 统计阶段  压力持续时间 s"
    echo -e "\t\t \$3 统计阶段后压力持续时间 s"
    return 0
}

[[ $# -lt 4 ]] && usage && exit 1

#============================命令参数识别区=====================================#
##压力大小,每秒发送的请求数
send_press=$1
##压力时间,统计阶段前的压力持续时间
send_before_range=$2
##压力时间,发送请求的持续时间
send_stat_range=$3
##压力时间,统计阶段后的压力持续时间
send_after_range=$4
#============================可配参数配置区=====================================#
##API host & port
send_host=192.168.0.249
send_port=38
send_method=POST
send_content_type=application/json
send_url=/uniledger/v1/transaction/createByPayload
##Rethinkdb connect host & port & dbname
rethinkdb_host=192.168.0.240
rethinkdb_port=28015
rethinkdb_db=bigchain

##集群node个数
chain_node_num=6

##数据统计周期 5s
stat_loop_range=5
stat_backlog_range=5

##生成的log路径&名称
##backlog消耗统计日志 
backlog_log="log/press_backlog.log"
##压力过程处理日志
send_log="log/press_process.log"
##性能结果分析日志
result_log="log/press_result.log"
#============================================================================#

mkdir -p log
rm -rf log/*.log 2>/dev/null
stat_loop_range_haomiao=$(($stat_loop_range * 1000))
send_total=$(($send_press * $send_stat_range))
############################################################################
echo -e "============press param info==================" > $result_log
echo -e "press cmd  : $0" >> $result_log
echo -e "press param:"  >> $result_log
echo -e "\t\t: send_host [$send_host]"  >> $result_log
echo -e "\t\t: send_port [$send_port]"  >> $result_log
echo -e "\t\t: send_press [$send_press]"  >> $result_log
echo -e "\t\t: send_beore_state [$send_before_range], send_request[$(($send_press * $send_before_range))]"  >> $result_log
echo -e "\t\t: send_stat_range [$send_stat_range], send_request[$(($send_press * $send_stat_range))]"  >> $result_log
echo -e "\t\t: send_after_range [$send_after_range], send_request[$(($send_press * $send_after_range))]"  >> $result_log
#############################################################################

## args: $1 press_begin_time all :second level
##       $2 press_end_time all :second level
function stat_backlog(){
    local s_begin_timestamp=$1
    local s_end_timestamp=$2
    local now_date=`date "+%Y-%m-%d %H:%M:%S"`
    local process_num=0
    local s_range=$(($s_end_timestamp - $s_begin_timestamp))    
    local s_loop=$(($s_range / $stat_backlog_range))
    for((i=0;i<=$s_loop;i++))
    do
        now_date=`date "+%Y-%m-%d %H:%M:%S"`
        process_num=`python3 stat_backlog.py`
        echo -e "[$now_date] backlog process:$process_num" >> $backlog_log
        sleep ${stat_backlog_range}s
    done
    
    return 0
}

## args: $1 send_state
##       $2 send_press
function send_req_write(){
    local s_state=$1
    local s_press=$2
    local now_date=`date "+%Y-%m-%d %H:%M:%S"`
    for((i=0;i<=$s_press;i++))
    do
        now_date=`date "+%Y-%m-%d %H:%M:%S"`
        echo "[$now_date]send $s_state a request..." >> $send_log
        curl -i -H "Content-Type:application/json" -X POST -d "{\"payload\":\"send request by curl\"}" -w %{http_code} http://$send_host:$send_port/uniledger/v1/transaction/createByPayload >> /dev/null 2>&1 &
    done
    return 0
}

## args: $1 s_state
##       $2 s_loop
##       $3 s_last_press
function send_req_write_for_loop(){
    local s_state=$1
    local s_loop=$2
    local s_last_press=$3
    for((i=1;i<=$s_loop;i++))
    do
        send_req_write $s_state 500 &
    done
    [[ $s_last_press -ne 0 ]] && send_req_write $s_state $s_last_press &
    return 0
}

## args: $1 send_press
function get_req_loop_info(){
    local s_press=$1
    local send_loop=$(($s_press / 500))
    local send_last_press=$(($s_press % 500))
    echo "${send_loop},${send_last_press}"
    return 0
}
## arge: $1 send_state_decription
##       $2 send_stat_range
function send_state(){
    local s_state=$1
    local s_range=$2
    local s_loop_info=`get_req_loop_info $send_press`
    local s_loop=`echo "$s_loop_info"|awk -F"," '{print $1}'`
    local s_last_press=`echo "$s_loop_info"|awk -F"," '{print $2}'`
    echo "[state:$s_state][`date "+%Y-%m-%d %H:%M:%S"`]send $s_state request begin........" >> $send_log
    local send_begin=`date "+%s"`
    local send_end=`date "+%s"`
    while [[ `echo "$send_end $send_begin"|awk '{if(($1-$2)<'$s_range')print 1;else print 0}'` -eq 1 ]];
    do
        ab -r -n $send_press -c 20 -t 1 -v 1 -T "$send_content_type" -p 'write_json.txt' 'http://'${send_host}':'${send_port}${send_url} >> $send_log 2>&1
        send_end=`date "+%s"`
        echo "[state:$s_state][`date "+%Y-%m-%d %H:%M:%S"`]send $s_state $send_press request..." >> $send_log
    done
    #ab -r -n $(($send_press * $s_range))  -c 56 -v 1 -T 'application/json' -p 'write_json.txt' 'http://${send_host}:${send_port}/uniledger/v1/transaction/createByPayload' > $press_requst 2>&1
    #while [[ `echo "$send_end $send_begin"|awk '{if(($1-$2)<'$s_range')print 1;else print 0}'` -eq 1 ]];
    #do
    #    ##每个发送请求只有500的容量，因此按500进行并行发送
    #    send_req_write_for_loop $s_state $s_loop $s_last_press
    #    sleep 1s
    #    send_end=`date "+%s"`
    #    echo "[state:$s_state][`date "+%Y-%m-%d %H:%M:%S"`]send $s_state $send_press request..." >> $send_log
    #done 
    echo "[state:$s_state][`date "+%Y-%m-%d %H:%M:%S"`]send $s_state request end........" >> $send_log
    return 0
}

function stat_press(){
    echo -e "===send before " >> $result_log
    cat $send_log 2>/dev/null | grep "send before a request" |awk -F"]" '{print $1}'|sed "s/\[//g"|sort|uniq -c >> $result_log
    echo -e "===send stat " >> $result_log
    cat $send_log 2>/dev/null | grep "send stat a request" |awk -F"]" '{print $1}'|sed "s/\[//g"|sort|uniq -c >> $result_log
    echo -e "===send after " >> $result_log
    cat $send_log 2>/dev/null | grep "send after a request" |awk -F"]" '{print $1}'|sed "s/\[//g"|sort|uniq -c >> $result_log
    return 0
}

function stat_data(){
    local stat_before_begin_time=`grep "send before request begin" $send_log 2>/dev/null|awk -F"]" '{print $2}'|sed "s/\[//g"`
    local stat_begin_time=`grep "send stat request begin" $send_log 2>/dev/null|awk -F"]" '{print $2}'|sed "s/\[//g"`
    local stat_end_time=`grep "send stat request end" $send_log 2>/dev/null|awk -F"]" '{print $2}'|sed "s/\[//g"`
    local stat_after_end_time=`grep "send after request end" $send_log 2>/dev/null|awk -F"]" '{print $2}'|sed "s/\[//g"`
    [[ -z $stat_begin_time || -z $stat_end_time ]] && echo "stat_data fail[stat_begin_time or stat_end_time not exists!!!]" && return 1
    local before_begin_timestamp=$[$(date -d "$stat_before_begin_time" +%s%N)/1000000]
    local begin_timestamp=$[$(date -d "$stat_begin_time" +%s%N)/1000000]
    local end_timestamp=$[$(date -d "$stat_end_time" +%s%N)/1000000]
    local after_end_timestamp=$[$(date -d "$stat_after_end_time" +%s%N)/1000000]

    echo -e "=======State Result: stat_range=============" >> $result_log
    echo -e "[stat result]stat_begin_time: $stat_begin_time, $begin_timestamp" >> $result_log
    echo -e "[stat result]stat_end_time  : $stat_end_time, $end_timestamp" >> $result_log
    local stat_timestamp_range=$(($end_timestamp - $begin_timestamp))
    stat_timestamp_range=$(($stat_timestamp_range / 1000))
    local stat_transaction_sum=`python3 stat_transactions.py $begin_timestamp  $end_timestamp`
    local stat_transaction_avg=$(($stat_transaction_sum / $stat_timestamp_range))
    echo -e "[stat result]stat_transaction_sum: $stat_transaction_sum" >> $result_log
    echo -e "[stat result]stat_timestamp_range: $stat_timestamp_range" >> $result_log
    echo -e "[stat result]TPS: $stat_transaction_avg" >> $result_log

    echo -e "=======State Result: before_range + stat_range=============" >> $result_log
    echo -e "[stat result]stat_begin_time: $stat_before_begin_time, $before_begin_timestamp" >> $result_log
    echo -e "[stat result]stat_end_time  : $stat_end_time, $end_timestamp" >> $result_log
    stat_timestamp_range=$(($end_timestamp - $before_begin_timestamp))
    stat_timestamp_range=$(($stat_timestamp_range / 1000))
    stat_transaction_sum=`python3 stat_transactions.py $before_begin_timestamp  $end_timestamp`
    stat_transaction_avg=$(($stat_transaction_sum / $stat_timestamp_range))
    echo -e "[stat result]stat_transaction_sum: $stat_transaction_sum" >> $result_log
    echo -e "[stat result]stat_timestamp_range: $stat_timestamp_range" >> $result_log
    echo -e "[stat result]TPS: $stat_transaction_avg" >> $result_log

    echo -e "=======State Result: before_range + stat_range + after_range=============" >> $result_log
    echo -e "[stat result]stat_begin_time: $stat_before_begin_time, $before_begin_timestamp" >> $result_log
    echo -e "[stat result]stat_end_time  : $stat_after_end_time, $after_end_timestamp" >> $result_log
    stat_timestamp_range=$(($after_end_timestamp - $before_begin_timestamp))
    stat_timestamp_range=$(($stat_timestamp_range / 1000))
    stat_transaction_sum=`python3 stat_transactions.py $before_begin_timestamp  $after_end_timestamp`
    stat_transaction_avg=$(($stat_transaction_sum / $stat_timestamp_range))
    echo -e "[stat result]stat_transaction_sum: $stat_transaction_sum" >> $result_log
    echo -e "[stat result]stat_timestamp_range: $stat_timestamp_range" >> $result_log
    echo -e "[stat result]TPS: $stat_transaction_avg" >> $result_log
    return 0
}

##统计压力过程中的实时通量情况
function stat_process_data(){
    local stat_before_begin_time=`grep "send before request begin" $send_log 2>/dev/null|awk -F"]" '{print $2}'|sed "s/\[//g"`
    #local stat_begin_time=`grep "send stat request begin" $send_log 2>/dev/null|awk -F"]" '{print $2}'|sed "s/\[//g"`
    #local stat_end_time=`grep "send stat request end" $send_log 2>/dev/null|awk -F"]" '{print $2}'|sed "s/\[//g"`
    local stat_after_end_time=`grep "send after request end" $send_log 2>/dev/null|awk -F"]" '{print $2}'|sed "s/\[//g"`
    #[[ -z $stat_begin_time || -z $stat_end_time ]] && echo "stat_data fail[stat_begin_time or stat_end_time not exists!!!]" && return 1
    local before_begin_timestamp=$[$(date -d "$stat_before_begin_time" +%s%N)/1000000]
    #local begin_timestamp=$[$(date -d "$stat_begin_time" +%s%N)/1000000]
    #local end_timestamp=$[$(date -d "$stat_end_time" +%s%N)/1000000]
    local after_end_timestamp=$[$(date -d "$stat_after_end_time" +%s%N)/1000000]

    echo -e "=======State Result: stat process data range=============" >> $result_log
    echo -e "[stat result]stat_begin_time: $stat_before_begin_time, $before_begin_timestamp" >> $result_log
    echo -e "[stat result]stat_end_time  : $stat_after_end_time, $after_end_timestamp" >> $result_log
    
    local stat_timestamp_range=$(($after_end_timestamp - $before_begin_timestamp))
    stat_timestamp_range=$(($stat_timestamp_range / 1000))
    local stat_transaction_sum=0
    local stat_transaction_avg=0
    after_end_timestamp=$((before_begin_timestamp + $stat_loop_range_haomiao))
    local stat_process_range=0
    local loop_range=$((stat_timestamp_range / $stat_loop_range))
    for ((i=1;i<=${loop_range};i++))
    do
        if [[ $i -ne 1 ]];then
            before_begin_timestamp=$after_end_timestamp
            after_end_timestamp=$(($after_end_timestamp + $stat_loop_range_haomiao))
        fi
    	stat_transaction_sum=`python3 stat_transactions.py $before_begin_timestamp  $after_end_timestamp`
        stat_process_range=$(($after_end_timestamp - $before_begin_timestamp))
        stat_process_range=$(($stat_process_range / 1000))
    	stat_transaction_avg=$(($stat_transaction_sum / $stat_process_range))
        #stat_process_time=`date -d "$stat_before_begin_time ${i} second" "+%Y-%m-%d %H:%M:%S"`
        #echo -e "[stat result][stat_date:$stat_process_time]Process TPS: $stat_transaction_avg" >> $result_log
        #stat_process_time=`date -d "$stat_after_end_time ${i} second" "+%Y-%m-%d %H:%M:%S"`
        second_detal=$(($stat_loop_range * ${i}))
        stat_process_time=`date -d "$stat_before_begin_time ${second_detal} second" "+%Y-%m-%d %H:%M:%S"`
        echo -e "[stat result][stat_date:$stat_process_time]Process TPS: $stat_transaction_avg" >> $result_log
    done
    return 0
}
##############################################################################
stat_backlog_begin_time=$[$(date "+%s%N")/1000000000]
stat_backlog_end_time=$[$(date "+%s%N")/1000000000 + $send_before_range + $send_stat_range + $send_after_range]
stat_backlog $stat_backlog_begin_time $stat_backlog_end_time & 

send_state "before" $send_before_range
send_state "stat" $send_stat_range
send_state "after" $send_after_range

wait
echo -e "\n======================================================" >> $result_log
echo -e "============backlog count stat==================" >> $result_log
echo -e "======================================================" >> $result_log
cat $backlog_log 2>/dev/null >> $result_log
echo -e "\n======================================================" >> $result_log
echo -e "============write request stat==================" >> $result_log
echo -e "======================================================" >> $result_log
#stat_press
./stat_request.sh $send_log
echo -e "\n======================================================" >> $result_log
echo -e "============process result stat=======================" >> $result_log
echo -e "======================================================" >> $result_log
stat_process_data
echo -e "\n======================================================" >> $result_log
echo -e "============final result stat=========================" >> $result_log
echo -e "======================================================" >> $result_log
stat_data

exit 0
