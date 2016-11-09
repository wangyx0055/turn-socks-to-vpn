#!/bin/bash

# Setup the ipset
ipset -N chnroute hash:net maxelem 65536

for ip in $(cat '/home/yang/bin/路由表/cn_rules.conf'); do
  ipset add chnroute $ip
done

# Setup iptables
iptables -t nat -N SHADOWSOCKS

# 8381 是 ss 代理服务器的端口，即远程 shadowsocks 服务器提供服务的端口
iptables -t nat -A SHADOWSOCKS -p tcp --dport 8381 -j RETURN

# Allow connection to the server
iptables -t nat -A SHADOWSOCKS -d 103.214.195.99 -j RETURN

# Allow connection to reserved networks
iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 224.0.0.0/4 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 240.0.0.0/4 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 172.16.39.0/24 -j RETURN

# Allow connection to chinese IPs
iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set chnroute dst -j RETURN
iptables -t nat -A SHADOWSOCKS -p icmp -m set --match-set chnroute dst -j RETURN

# Redirect to Shadowsocks
iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-port 1081
iptables -t nat -A SHADOWSOCKS -p icmp -j REDIRECT --to-port 1081

# Redirect to SHADOWSOCKS
iptables -t nat -A OUTPUT -p tcp -j SHADOWSOCKS
iptables -t nat -A OUTPUT -p icmp -j SHADOWSOCKS
#iptables -t nat -A POSTROUTING -p tcp -j SHADOWSOCKS
