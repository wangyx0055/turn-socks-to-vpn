## 介绍
这里有两种方案，都可以实现全局智能分流。第一种方案的思路是使用 ipset 载入 chnroute 的 IP 列表并使用 iptables 实现带自动分流国内外流量的全局代理。为什么不用 PAC 呢？因为 PAC 这种东西只对浏览器有用。难道你在浏览器之外就不需要科学上网了吗？反正我是不信的……
<br \>
首先将本项目克隆到你的机器上，比如在/home/yang/目录下执行：
```bash
$ git clone https://github.com/yangchuansheng/turn-socks-to-vpn.git
```
## 方案一
### 安装相关软件（本教程为Archlinux平台）
* shadowsocks-libev
* ipset
```bash
$ pacman -S badvpn shadowsocks-libev ipset
```
### 配置shadowsocks-libev（略过）
假设shadowsocks配置文件为/etc/shadowsocks1.json
 
### 获取中国IP段
保存在cn_rules.conf中

### 修改启动和关闭脚本
```bash
$ vim ss-up.sh
```
```bash
#!/bin/bash

SOCKS_SERVER=$SERVER_IP # SOCKS 服务器的 IP 地址，改成你自己的服务器地址
# Setup the ipset
ipset -N chnroute hash:net maxelem 65536

for ip in $(cat '/home/yang/turn-socks-to-vpn/cn_rules.conf'); do
  ipset add chnroute $ip
done

# 在nat表中新增一个链，名叫：SHADOWSOCKS
iptables -t nat -N SHADOWSOCKS

# Allow connection to the server
iptables -t nat -A SHADOWSOCKS -d $SOCKS_SERVER -j RETURN

# Allow connection to reserved networks
iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 224.0.0.0/4 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 240.0.0.0/4 -j RETURN

# Allow connection to chinese IPs
iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set chnroute dst -j RETURN
iptables -t nat -A SHADOWSOCKS -p icmp -m set --match-set chnroute dst -j RETURN

# Redirect to Shadowsocks
# 把1081改成你的shadowsocks本地端口
iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-port 1081
iptables -t nat -A SHADOWSOCKS -p icmp -j REDIRECT --to-port 1081

# 将SHADOWSOCKS链中所有的规则追加到OUTPUT链中
iptables -t nat -A OUTPUT -p tcp -j SHADOWSOCKS
iptables -t nat -A OUTPUT -p icmp -j SHADOWSOCKS
```
&emsp;&emsp;这是在启动 shadowsocks 之前执行的脚本，用来设置 iptables 规则，对全局应用代理并将 chnroute 导入 ipset 来实现自动分流。注意要把服务器 IP 和本地端口相关的代码全部替换成你自己的。
&emsp;&emsp;这里就有一个坑了，就是在把 chnroute.txt 加入 ipset 的时候。因为 chnroute.txt 是一个 IP 段列表，而中国持有的 IP 数量上还是比较大的，所以如果使用 hash:ip 来导入的话会使内存溢出。我在第二次重新配置的时候就撞进了这个大坑……
&emsp;&emsp;但是你也不能尝试把整个列表导入 iptables。虽然导入 iptables 不会导致内存溢出，但是 iptables 是线性查表，即使你全部导入进去，也会因为低下的性能而抓狂。
<br \>
ss-down.sh是用来清除上述规则的脚本,不用作任何修改
<br \>
接着执行
```bash
$ chmod +x ss-up.sh
$ chmod +x ss-down.sh
```
### 配置ss-redir服务
首先，默认的 ss-local 并不能用来作为 iptables 流量转发的目标，因为它是 socks5 代理而非透明代理。我们至少要把 systemd 执行的程序改成 ss-redir。其次，上述两个脚本还不能自动执行，必须让 systemd 分别在启动 shadowsocks 之前和关闭之后将脚本执行，这样才能自动配置好 iptables 规则。
```bash
$ vim /usr/lib/systemd/system/shadowsocks-libev@.service
```
```bash
[Unit]
Description=Shadowsocks-Libev Client Service
After=network.target

[Service]
User=root
CapabilityBoundingSet=~CAP_SYS_ADMIN
ExecStart=
ExecStartPre=/home/yang/turn-socks-to-vpn/ss-up.sh
ExecStart=/usr/bin/ss-redir -u -c /etc/%i.json
ExecStopPost=/home/yang/turn-socks-to-vpn/ss-down.sh

[Install]
WantedBy=multi-user.target
```
然后启动服务
```bash
$ systemctl start shadowsocks-libev@shadowsocks1
```
开机自启
```bash
$ systemctl enable shadowsocks-libev@shadowsocks1
```
### 六、配置ss-tunnel服务，用来提供本地DNS解析
```bash
$ vim /usr/lib/systemd/system/shadowsocks-libev-tunnel@.service
```
```bash
[Unit]
Description=Shadowsocks-Libev Client Service Tunnel Mode
After=network.target

[Service]
Type=simple
User=nobody
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=/usr/bin/ss-tunnel -c /etc/%i.json -l 53 -L 8.8.8.8:53 -u

[Install]
WantedBy=multi-user.target
```
启动服务
```bash
$ systemctl start shadowsocks-libev-tunnel@shadowsocks1
```
开机自启
```bash
$ systemctl enable shadowsocks-libev-tunnel@shadowsocks1
```

### 配置系统 DNS 服务器设置
* 可参见 https://developers.google.com/speed/public-dns/docs/using 中 Changing your DNS servers settings 中 Linux 一节

* 图形界面以 GNOME 3 为例：

* 打开所有程序列表，并 -&gt; 设置 – 硬件分类 – 网络

* 如果要对当前的网络配置进行编辑 -&gt; 单击齿轮按钮

* 选中 IPv4

* DNS 栏目中，将自动拨向关闭

* 在服务器中填入 127.0.0.1 （或103.214.195.99:7300）并应用

* 选中 IPv6

* DNS 栏目中，将自动拨向关闭

* 在服务器中填入 ::1 并应用

* 请务必确保只填入这两个地址，填入其它地址可能会导致系统选择其它 DNS 服务器绕过程序的代理

* 重启网络连接

* 直接修改系统文件修改 DNS 服务器设置：

* 自动获取地址(DHCP)时：

* 以 root 权限进入 /etc/dhcp 或 /etc/dhcp3 目录（视乎 dhclient.conf 文件位置）

* 直接修改 dhclient.conf 文件，修改或添加 prepend domain-name-servers 一项即可

* 如果 prepend domain-name-servers 一项被 # 注释则需要把注释去掉以使配置生效，不需要添加新的条目

* dhclient.conf 文件可能存在多个 prepend domain-name-servers 项，是各个网络接口的配置项目，直接修改总的配置项目即可

* 使用 service network(/networking) restart 或 ifdown/ifup 或 ifconfig stop/start 重启网络服务/网络端口

* 非自动获取地址(DHCP)时：

* 以 root 权限进入 /etc 目录

* 直接修改 resolv.conf 文件里的 nameserver 即可

* 如果重启后配置被覆盖，则需要修改或新建 /etc/resolvconf/resolv.conf.d 文件，内容和 resolv.conf 一样

* 使用 service network(/networking) restart 或 ifdown/ifup 或 ifconfig stop/start 重启网络服务/网络端口

### 打开流量转发
```bash
$ cat /etc/sysctl.d/30-ipforward.conf
```

```ini
net.ipv4.ip_forward=1

net.ipv6.conf.all.forwarding = 1

net.ipv4.tcp_congestion_control=westwood

net.ipv4.tcp_syn_retries = 5

net.ipv4.tcp_synack_retries = 5
```
编辑完成后，执行以下命令使变动立即生效

     $ sysctl -p
 

方案一固然可以实现全局智能分流，可这里有一个问题，它并不能让连接到此电脑上的设备也实现智能分流，也就是说，它还不能当成一个翻墙路由器使用，下面我们介绍的方案二便可以解决这个问题。前面的步骤大致相似，到后面略有不同。

## 方案二

### 安装相关软件（本教程为Archlinux平台）
* badvpn
* pdnsd
* shadowsocks
```bash
$ pacman -S badvpn pdnsd shadowsocks
```
### 配置shadowsocks（略过）
假设shadowsocks配置文件为/etc/shadowsocks1.json
 
### 获取中国IP段
保存在cn_rules.conf中

### 修改iptables启动和关闭脚本
```bash
$ vim sstunnel-up.sh
```
```bash
#!/bin/bash
# 后面将会用ss-tunnel开启本地dns解析服务，所以将本地dns的udp请求转发到pdnsd的dns端口
# 至于为什么多此一举，而不直接将pdnsd的本地端口设置为53，是因为53端口已经被污染了，所以通过此方法来欺骗GFW
iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to 127.0.0.1:10053
```
<br \>
sstunnel-down.sh是用来清除上述规则的脚本
```bash
#!/bin/bash
iptables -t nat -F OUTPUT
```
### 配置pdnsd服务，用来提供本地DNS解析
将pdnsd.conf复制到/etc目录下，然后修改pdnsd.service

```bash
$ vim /usr/lib/systemd/system/pdnsd.service
```
```bash
[Unit]
Description=proxy name server
Wants=network-online.target
After=network-online.target

[Service]
ExecStartPre=/home/yang/turn-socks-to-vpn/sstunnel-up.sh
ExecStart=/usr/bin/pdnsd
ExecStopPost=/home/yang/turn-socks-to-vpn/sstunnel-down.sh

[Install]
WantedBy=multi-user.target
```
启动服务
```bash
$ systemctl start pdnsd
```
开机自启
```bash
$ systemctl enable pdnsd
```

### 配置系统 DNS 服务器设置
* 可参见 https://developers.google.com/speed/public-dns/docs/using 中 Changing your DNS servers settings 中 Linux 一节

* 图形界面以 GNOME 3 为例：

* 打开所有程序列表，并 -&gt; 设置 – 硬件分类 – 网络

* 如果要对当前的网络配置进行编辑 -&gt; 单击齿轮按钮

* 选中 IPv4

* DNS 栏目中，将自动拨向关闭

* 在服务器中填入 127.0.0.1 （或103.214.195.99:7300）并应用

* 选中 IPv6

* DNS 栏目中，将自动拨向关闭

* 在服务器中填入 ::1 并应用

* 请务必确保只填入这两个地址，填入其它地址可能会导致系统选择其它 DNS 服务器绕过程序的代理

* 重启网络连接

* 直接修改系统文件修改 DNS 服务器设置：

* 自动获取地址(DHCP)时：

* 以 root 权限进入 /etc/dhcp 或 /etc/dhcp3 目录（视乎 dhclient.conf 文件位置）

* 直接修改 dhclient.conf 文件，修改或添加 prepend domain-name-servers 一项即可

* 如果 prepend domain-name-servers 一项被 # 注释则需要把注释去掉以使配置生效，不需要添加新的条目

* dhclient.conf 文件可能存在多个 prepend domain-name-servers 项，是各个网络接口的配置项目，直接修改总的配置项目即可

* 使用 service network(/networking) restart 或 ifdown/ifup 或 ifconfig stop/start 重启网络服务/网络端口

* 非自动获取地址(DHCP)时：

* 以 root 权限进入 /etc 目录

* 直接修改 resolv.conf 文件里的 nameserver 即可

* 如果重启后配置被覆盖，则需要修改或新建 /etc/resolvconf/resolv.conf.d 文件，内容和 resolv.conf 一样

* 使用 service network(/networking) restart 或 ifdown/ifup 或 ifconfig stop/start 重启网络服务/网络端口

### 修改路由表启动和终止脚本
将socksfwd复制到/usr/local/bin目录下,然后修改相关参数
```bash
$ vim /usr/local/bin/socksfwd
```

```bash
#!/bin/bash
SOCKS_SERVER=$SERVER_IP # SOCKS 服务器的 IP 地址
SOCKS_PORT=1081 # 本地SOCKS 服务器的端口
GATEWAY_IP=172.16.68.254 # 家用网关（路由器）的 IP 地址
TUN_NETWORK_DEV=tun0 # 选一个不冲突的 tun 设备号
TUN_NETWORK_PREFIX=10.0.0 # 选一个不冲突的内网 IP 段的前缀


start_fwd() {
ip tuntap del dev "$TUN_NETWORK_DEV" mode tun
# 添加虚拟网卡
ip tuntap add dev "$TUN_NETWORK_DEV" mode tun
# 给虚拟网卡绑定IP地址
ip addr add "$TUN_NETWORK_PREFIX.1/24" dev "$TUN_NETWORK_DEV"
# 启动虚拟网卡
ip link set "$TUN_NETWORK_DEV" up
ip route del default via "$GATEWAY_IP"
ip route add "$SOCKS_SERVER" via "$GATEWAY_IP"
# 特殊ip段走家用网关（路由器）的 IP 地址（如局域网联机）
# ip route add "172.16.39.0/24" via "$GATEWAY_IP"
# 国内网段走家用网关（路由器）的 IP 地址
for i in $(cat /home/yang/turn-socks-to-vpn/cn_rules.conf)
do
ip route add "$i" via "$GATEWAY_IP"
done
# 将默认网关设为虚拟网卡的IP地址
ip route add 0.0.0.0/1 via "$TUN_NETWORK_PREFIX.1"
ip route add 128.0.0.0/1 via "$TUN_NETWORK_PREFIX.1"
# 将socks5转为vpn
badvpn-tun2socks --tundev "$TUN_NETWORK_DEV" --netif-ipaddr "$TUN_NETWORK_PREFIX.2" --netif-netmask 255.255.255.0 --socks-server-addr "127.0.0.1:$SOCKS_PORT"
TUN2SOCKS_PID="$!"
}


stop_fwd() {
ip route del 128.0.0.0/1 via "$TUN_NETWORK_PREFIX.1"
ip route del 0.0.0.0/1 via "$TUN_NETWORK_PREFIX.1"
for i in $(cat /home/yang/bin/路由表/cn_rules.conf)
do
ip route del "$i" via "$GATEWAY_IP"
done
ip route del "172.16.39.0/24" via "$GATEWAY_IP"
ip route del "$SOCKS_SERVER" via "$GATEWAY_IP"
ip route add default via "$GATEWAY_IP"
ip link set "$TUN_NETWORK_DEV" down
ip addr del "$TUN_NETWORK_PREFIX.1/24" dev "$TUN_NETWORK_DEV"
ip tuntap del dev "$TUN_NETWORK_DEV" mode tun
}



start_fwd
trap stop_fwd INT TERM
wait "$TUN2SOCKS_PID"
```
<br \>
将socksfwd.service复制到/usr/lib/systemd/system/目录下，然后启动服务

```bash
$ systemctl start socksfwd
```

开机自启
```bash
$ systemctl enable socksfwd
```

### 打开流量转发
将30-ipforward.conf复制到/etc/sysctl.d/目录下，然后执行以下命令使变动立即生效
```bash
$ sysctl -p
``` 
