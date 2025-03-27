#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

##### 用户可配置区域 #####
PROG="/usr/bin/sing-box"
RES_DIR="/etc/sing-box"
CONF="$RES_DIR/config.json"
TPROXY_MARK=1
ADGUARD_MARK=2
NFT_TABLE="sing-box"
NFT_FILE="/etc/sing-box/singbox_nftables_tproxy_dns.nft"
TABLE_START_v4=100
TABLE_START_v6=106
##### 用户可配置区域 #####

MARK_ARRAY="$TPROXY_MARK $ADGUARD_MARK"

validate_config() {
    [ -x "$PROG" ] || {
        echo "Error: $PROG not executable"
        exit 1
    }
    [ -d "$RES_DIR" ] || {
        echo "Error: RES_DIR $RES_DIR not found"
        exit 1
    }
    [ -f "$CONF" ] || {
        echo "Error: Config $CONF not found"
        exit 1
    }
    [ -f "$NFT_FILE" ] || {
        echo "Error: NFT rules $NFT_FILE not found"
        exit 1
    }
}

start_service() {
    validate_config

    # 清理旧表（避免规则冲突）
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true

    # 启动主进程
    procd_open_instance
    procd_set_param command "$PROG" run -D "$RES_DIR" -c "$CONF"
    procd_set_param user root
    procd_set_param limits core="unlimited"
    procd_set_param limits nofile="1000000 1000000"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 3600 5 5
    procd_set_param reload_signal SIGHUP # 支持热重载
    procd_close_instance

    # 添加路由规则
    old_ifs="$IFS"
    IFS=' '
    for mark in $MARK_ARRAY; do
        v4_table=$((TABLE_START_v4 + (mark - TPROXY_MARK)))
        v6_table=$((TABLE_START_v6 + (mark - TPROXY_MARK)))

        # 清理旧规则
        ip rule del fwmark "$mark" table "$v4_table" 2>/dev/null || true
        ip -6 rule del fwmark "$mark" table "$v6_table" 2>/dev/null || true

        # 添加新规则
        ip rule add fwmark "$mark" table "$v4_table" prio 1000
        ip route add local 0.0.0.0/0 dev lo table "$v4_table"
        ip -6 rule add fwmark "$mark" table "$v6_table" prio 1000
        ip -6 route add local ::/0 dev lo table "$v6_table"
    done
    IFS="$old_ifs"

    # 加载NFT规则
    nft -f "$NFT_FILE" || {
        echo "Failed to load NFT rules"
        exit 1
    }
    echo "sing-box 启动成功！"
}

stop_service() {
    # 停止主进程
    service_stop "$PROG"

    # 清理路由规则
    old_ifs="$IFS"
    IFS=' '
    for mark in $MARK_ARRAY; do
        v4_table=$((TABLE_START_v4 + (mark - TPROXY_MARK)))
        v6_table=$((TABLE_START_v6 + (mark - TPROXY_MARK)))

        ip rule del fwmark "$mark" table "$v4_table" 2>/dev/null || true
        ip route del local 0.0.0.0/0 dev lo table "$v4_table" 2>/dev/null || true
        ip -6 rule del fwmark "$mark" table "$v6_table" 2>/dev/null || true
        ip -6 route del local ::/0 dev lo table "$v6_table" 2>/dev/null || true
    done
    IFS="$old_ifs"

    # 清理NFT表
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true
    echo "sing-box 已停止！"
}

reload_service() {
    # 通过SIGHUP热重载配置（无需重启进程）
    procd_send_signal "$PROG" SIGHUP
    echo "配置已重载！"
}
