#!/bin/bash
#git clone代码、启动容器进行编译

set -e

# 安装日志
install_log=/var/log/doris_build.log
tm=$(date +'%Y%m%d %T')

# 日志颜色
COLOR_G="\x1b[0;32m"  # green
RESET="\x1b[0m"

function info(){
    echo -e "${COLOR_G}[$tm] [Info] ${1}${RESET}"
}

function run_cmd(){
  sh -c "$1 | $(tee -a "$install_log")"
}

function run_function(){
  $1 | tee -a "$install_log"
}


function get_ip()
{
    first=18
    last=30
    docker network prune
    for ((subnet=$first; subnet<=$last; subnet++))
    do
        ping 172.$subnet.0.2 -c 1 || ip_subnet=$subnet;break
    done
    info $ip_subnet
}

function get_port()
{
    IP=127.0.0.1
    first_port=40000
    last_port=40100
    for ((port=$first_port; port<=$last_port; port++))
    do
        (echo >/dev/tcp/$IP/$port)> /dev/null 2>&1 && echo $port open || echo "$port closed" && port_free+=($port)
    done
    info ${port_free[@]}
}

http_port=8030
rpc_port=9020
query_port=9030
edit_log_port=9010

be_port=9060
webserver_port=8040
heartbeat_service_port=9050
brpc_port=8060


#########################获取doris代码#####################################
function build_doris()
{
  #分支名
  branch=$1
  cd /opt/incubator-doris/
  git checkout origin/$branch
  git fetch | tee -a "$install_log"
  git rebase origin/$branch | tee -a "$install_log"
  git status | tee -a "$install_log"
  time=`date +%y%m%d%H%M%y`
  cp -rf /opt/incubator-doris /opt/doris_$time

  docker run -td --privileged -v /home/leaf/.m2:/root/.m2 -v /opt/doris_$time:/root/doris_$time/ apache/incubator-doris:build-env-for-0.15.0 /bin/sh -c "bash /root/doris_$time/build.sh >> /root/build.log 2>&1"
  rm -rf /opt/doris_install_*.conf
  echo "time=$time" >> /opt/doris_install_$time.conf

}
#########################安装doris#####################################

# cat > ./doris_install_$time.conf << EOF
# Fe_ips=172.$ip_subnet.0.2,172.$ip_subnet.0.3,172.$ip_subnet.0.4
# Be_ips=172.$ip_subnet.0.2,172.$ip_subnet.0.3,172.$ip_subnet.0.4
# EOF
function install_doris()
{
source /opt/doris_install_*.conf
docker rm $(docker ps -qf status=exited) >> $install_log 2>&1
mkdir -p /opt/doris_$time/doris_1_$time
mkdir -p /opt/doris_$time/doris_2_$time
mkdir -p /opt/doris_$time/doris_3_$time

[ ! -d /opt/doris_$time/doris_1_$time ] && cp -rf /opt/doris_$time/output/* /opt/doris_$time/doris_1_$time
[ ! -d /opt/doris_$time/doris_2_$time ] && cp -rf /opt/doris_$time/output/* /opt/doris_$time/doris_2_$time
[ ! -d /opt/doris_$time/doris_3_$time ] && cp -rf /opt/doris_$time/output/* /opt/doris_$time/doris_3_$time

get_port
get_ip

cat > ./doris_install_$time.yml << EOF
version: "3.0"

services:
  mysql:
    container_name: doris_mysql_$time
    image: daocloud.io/yjmyzz/mysql-osx:latest
    volumes:
      - /opt/doris_$time/mysql/db:/var/lib/mysql
    ports:
      - ${port_free[0]}:3306
    expose:
      - 9030    
    environment:
      - MYSQL_ROOT_PASSWORD=123
    networks:
      extnetwork:
        ipv4_address: 172.$ip_subnet.0.5      
    command: 
        - bash
        - -c
        - |
            yum -y install passwd openssl openssh-server
            echo "123" | passwd --stdin root
            ssh-keygen -q -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N ''
            ssh-keygen -q -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ''
            ssh-keygen -t dsa -f /etc/ssh/ssh_host_ed25519_key -N ''
            sed -i "s/#UsePrivilegeSeparation.*/UsePrivilegeSeparation no/g" /etc/ssh/sshd_config
            sed -i "s/UsePAM.*/UsePAM no/g" /etc/ssh/sshd_config
            /usr/sbin/sshd -D
            tail -f /dev/null

  doris1:
    container_name: doris1_$time
    image: apache/incubator-doris:build-env-for-0.15.0
    restart: always
    tty: true
    volumes:
      - /opt/doris_$time/doris_1_$time:/opt/doris_$time/doris_1_$time
    ports:
      - ${port_free[1]}:8030
      - ${port_free[2]}:9020
      - ${port_free[3]}:9030
      - ${port_free[4]}:9010
      - ${port_free[5]}:9060
      - ${port_free[6]}:8040
      - ${port_free[7]}:9050
      - ${port_free[8]}:8060
    networks:
      extnetwork:
        ipv4_address: 172.$ip_subnet.0.2
    command: 
        - bash
        - -c
        - |
            yum -y install passwd openssl openssh-server
            echo "123" | passwd --stdin root
            ssh-keygen -q -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N ''
            ssh-keygen -q -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ''
            ssh-keygen -t dsa -f /etc/ssh/ssh_host_ed25519_key -N ''
            sed -i "s/#UsePrivilegeSeparation.*/UsePrivilegeSeparation no/g" /etc/ssh/sshd_config
            sed -i "s/UsePAM.*/UsePAM no/g" /etc/ssh/sshd_config
            /usr/sbin/sshd -D
            tail -f /dev/null

  doris2:
    container_name: doris2_$time
    image: apache/incubator-doris:build-env-for-0.15.0
    restart: always
    tty: true   
    volumes:
      - /opt/doris_$time/doris_2_$time:/opt/doris_$time/doris_2_$time
    ports:
      - ${port_free[9]}:8030
      - ${port_free[10]}:9020
      - ${port_free[11]}:9030
      - ${port_free[12]}:9010
      - ${port_free[13]}:9060
      - ${port_free[14]}:8040
      - ${port_free[15]}:9050
      - ${port_free[16]}:8060
    networks:
      extnetwork:
        ipv4_address: 172.$ip_subnet.0.3
    command: 
        - bash
        - -c
        - |
            yum -y install passwd openssl openssh-server
            echo "123" | passwd --stdin root
            ssh-keygen -q -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N ''
            ssh-keygen -q -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ''
            ssh-keygen -t dsa -f /etc/ssh/ssh_host_ed25519_key -N ''
            sed -i "s/#UsePrivilegeSeparation.*/UsePrivilegeSeparation no/g" /etc/ssh/sshd_config
            sed -i "s/UsePAM.*/UsePAM no/g" /etc/ssh/sshd_config
            /usr/sbin/sshd -D
            tail -f /dev/null

  doris3:
    container_name: doris3_$time
    image: apache/incubator-doris:build-env-for-0.15.0
    restart: always
    tty: true    
    volumes:
      - /opt/doris_$time/doris_3_$time:/opt/doris_$time/doris_3_$time
    ports:
      - ${port_free[17]}:8030
      - ${port_free[18]}:9020
      - ${port_free[19]}:9030
      - ${port_free[20]}:9010
      - ${port_free[21]}:9060
      - ${port_free[22]}:8040
      - ${port_free[23]}:9050
      - ${port_free[24]}:8060
    networks:
      extnetwork:
        ipv4_address: 172.$ip_subnet.0.4
    command: 
        - bash
        - -c
        - |
            yum -y install passwd openssl openssh-server
            echo "123" | passwd --stdin root
            ssh-keygen -q -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N ''
            ssh-keygen -q -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ''
            ssh-keygen -t dsa -f /etc/ssh/ssh_host_ed25519_key -N ''
            sed -i "s/#UsePrivilegeSeparation.*/UsePrivilegeSeparation no/g" /etc/ssh/sshd_config
            sed -i "s/UsePAM.*/UsePAM no/g" /etc/ssh/sshd_config
            /usr/sbin/sshd -D
            tail -f /dev/null
            ssh-keygen -t rsa -f ~/.ssh/id_rsa -P '' && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

networks:
  extnetwork:
    ipam:
      config:
      - subnet: 172.$ip_subnet.0.0/16
        gateway: 172.$ip_subnet.0.1
EOF
# 容器启动
docker-compose -f doris_install_$time.yml up -d>> $install_log 2>&1
ssh-keygen -R 172.$ip_subnet.0.2
ssh-keygen -R 172.$ip_subnet.0.3
ssh-keygen -R 172.$ip_subnet.0.4
#ssh免密
# cat > /root/.ssh/authorized_keys << EOF 
# ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDglj1sXqi+APxy5msK7x2+jtcFkOuDI71pg9TvxHtKXmaVg8BSQxri1d6SQaz8ct69bnvjfemG+lk4dDaOwggDPxAg/QiMWhcnkrUBvFAsbFh6tgE5Wx2W/gEFiLcWNJb/2v+DRyEm5htUS2ow14VcuUPBBHmMu9CWw8+t1vVTGfEUI+2OS5BRsnsba6MzPYGTvxjoKW7i/Oc5RqWpYXJDSwD2Z3QC7Nv7c8Rb/KbfTWzMEO2V6V9infLVX5MrKGW1PwEZjU8GLP8F5VexoEhfILYyuhMb2CSzNctmrlxc8hszdT0GAMezwUPKmTbH3oihYRfgTepeim7t7HN9joRB root@localhost.localdomain
# EOF
# #ssh-keygen -t rsa -f ~/.ssh/id_rsa -P '' && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
cat > /opt/host_ip_$time.txt << EOF
172.$ip_subnet.0.2 root 123
172.$ip_subnet.0.3 root 123
172.$ip_subnet.0.4 root 123
EOF

# 密钥对不存在则创建密钥
if [ ! -f /root/.ssh/id_rsa.pub ];then
expect << EOF
  spawn ssh-keygen -t rsa
  expect {
          "*to save the key" {send "\n";exp_continue}
          "*(y/n)" {send "y\r";exp_continue}
          "Enter passphrase" {send "\n";exp_continue}
          "Enter same passphrase" {send "\n";exp_continue}
  }
EOF
fi

#bash /opt/ssh_auto.sh >> $install_log 2>&1
for ((i=0; i<=60; i++))
do
  #statements
  SSHD_PORT=22
  if (echo >/dev/tcp/172.$ip_subnet.0.2/$SSHD_PORT)> /dev/null 2>&1 && (echo >/dev/tcp/172.$ip_subnet.0.3/$SSHD_PORT)> /dev/null 2>&1 && (echo >/dev/tcp/172.$ip_subnet.0.4/$SSHD_PORT)> /dev/null 2>&1; then
    info "sshd服务启动"
    break
  fi
  sleep 3
  info "等待sshd服务启动"
done

while read line;do
      ip=`echo $line | cut -d " " -f1`             # 提取文件中的ip
      user_name=`echo $line | cut -d " " -f2`      # 提取文件中的用户名
      pass_word=`echo $line | cut -d " " -f3`      # 提取文件中的密码
expect <<EOF
      spawn ssh-copy-id -i /root/.ssh/id_rsa.pub $user_name@$ip
      expect {
              "yes/no" { send "yes\n";exp_continue}
              "password" { send "$pass_word\n"}
      }
      expect eof
EOF

done < /opt/host_ip_$time.txt      # 读取存储ip的文件

# 配置ansible
echo "[allnode_$time]" >> /etc/ansible/hosts
echo "172.$ip_subnet.0.2" >> /etc/ansible/hosts
echo "172.$ip_subnet.0.3" >> /etc/ansible/hosts
echo "172.$ip_subnet.0.4" >> /etc/ansible/hosts
#设置环境变量
ansible 172.$ip_subnet.0.2 -m shell -a "echo 'export JAVA_HOME=/usr/lib/jvm/java-11' >> .bashrc" >> $install_log 2>&1
ansible 172.$ip_subnet.0.3 -m shell -a "echo 'export JAVA_HOME=/usr/lib/jvm/java-11' >> .bashrc" >> $install_log 2>&1
ansible 172.$ip_subnet.0.4 -m shell -a "echo 'export JAVA_HOME=/usr/lib/jvm/java-11' >> .bashrc" >> $install_log 2>&1
#修改配置文件
ansible 172.$ip_subnet.0.2 -m shell -a "sed 's/4096/2048/g' /opt/doris_$time/doris_1_$time/fe/conf/fe.conf" >> $install_log 2>&1
ansible 172.$ip_subnet.0.3 -m shell -a "sed 's/4096/2048/g' /opt/doris_$time/doris_2_$time/fe/conf/fe.conf" >> $install_log 2>&1
ansible 172.$ip_subnet.0.4 -m shell -a "sed 's/4096/2048/g' /opt/doris_$time/doris_3_$time/fe/conf/fe.conf" >> $install_log 2>&1
#启动fe_master
ansible 172.$ip_subnet.0.2 -m shell -a "bash /opt/doris_$time/doris_1_$time/fe/bin/start_fe.sh --daemon" >> $install_log 2>&1
#fe_master是否启动成功
for ((i=0; i<=60; i++))
do
  #statements
  if ansible 172.$ip_subnet.0.2 -m shell -a "curl -s 'http://127.0.0.1:8030/api/bootstrap'" > /dev/null 2>&1; then
    info "fe_master启动成功"
    break
  fi
  sleep 3
  info "等待fe_master启动成功"
done


#组建Doris集群
mysql -h172.$ip_subnet.0.2 -P9030 -e "ALTER SYSTEM ADD FOLLOWER '172.$ip_subnet.0.3:9010';" >> $install_log 2>&1
mysql -h172.$ip_subnet.0.2 -P9030 -e "ALTER SYSTEM ADD FOLLOWER '172.$ip_subnet.0.4:9010';" >> $install_log 2>&1
mysql -h172.$ip_subnet.0.2 -P9030 -e "ALTER SYSTEM ADD BACKEND '172.$ip_subnet.0.2:9050';" >> $install_log 2>&1
mysql -h172.$ip_subnet.0.2 -P9030 -e "ALTER SYSTEM ADD BACKEND '172.$ip_subnet.0.3:9050';" >> $install_log 2>&1
mysql -h172.$ip_subnet.0.2 -P9030 -e "ALTER SYSTEM ADD BACKEND '172.$ip_subnet.0.4:9050';" >> $install_log 2>&1
#启动fe_follow
ansible 172.$ip_subnet.0.3 -m shell -a "bash /opt/doris_$time/doris_2_$time/fe/bin/start_fe.sh --helper 172.$ip_subnet.0.2:9010 --daemon" >> $install_log 2>&1
ansible 172.$ip_subnet.0.4 -m shell -a "bash /opt/doris_$time/doris_3_$time/fe/bin/start_fe.sh --helper 172.$ip_subnet.0.2:9010 --daemon" >> $install_log 2>&1
#启动be
ansible 172.$ip_subnet.0.2 -m shell -a "bash /opt/doris_$time/doris_1_$time/be/bin/start_be.sh --daemon" >> $install_log 2>&1
ansible 172.$ip_subnet.0.3 -m shell -a "bash /opt/doris_$time/doris_2_$time/be/bin/start_be.sh --daemon" >> $install_log 2>&1
ansible 172.$ip_subnet.0.4 -m shell -a "bash /opt/doris_$time/doris_3_$time/be/bin/start_be.sh --daemon" >> $install_log 2>&1
info "doris集群安装成功"
}


#################################卸载Doris###################################################

function uninstall_doris()
{
  source /opt/doris_install_*.conf
  docker rm $(docker ps -qf name=doris*)
  rm -rf doris_$time*

}


case $1 in
    build)
        build_doris $2
        ;;
    install)
        install_doris
        ;;
    uninstall)
        uninstall_doris
        ;;
    *)
        echo "error"
esac



