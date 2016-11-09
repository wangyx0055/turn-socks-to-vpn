#!/bin/bash

iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to 127.0.0.1:10053
