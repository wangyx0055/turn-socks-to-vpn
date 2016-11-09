#!/bin/bash

#iptables -t nat -D POSTROUTING -p tcp -j SHADOWSOCKS
iptables -t nat -D OUTPUT -p icmp -j SHADOWSOCKS
iptables -t nat -D OUTPUT -p tcp -j SHADOWSOCKS
iptables -t nat -D PREROUTING -p icmp -j SHADOWSOCKS
iptables -t nat -D PREROUTING -p tcp -j SHADOWSOCKS
iptables -t nat -F SHADOWSOCKS
iptables -t nat -X SHADOWSOCKS
ipset destroy chnroute
