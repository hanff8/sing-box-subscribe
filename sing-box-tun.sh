#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

##### 用户可配置区域 #####
PROG="/usr/bin/sing-box"
RES_DIR="/etc/sing-box"
CONF="$RES_DIR/config.json"
##### 用户可配置区域 #####

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
}

start_service() {
    validate_config
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

    echo "sing-box 启动成功！"
}

stop_service() {
    # 停止主进程
    service_stop "$PROG"
    echo "sing-box 已停止！"
}

reload_service() {
    # 通过SIGHUP热重载配置（无需重启进程）
    procd_send_signal "$PROG" SIGHUP
    echo "配置已重载！"
}
