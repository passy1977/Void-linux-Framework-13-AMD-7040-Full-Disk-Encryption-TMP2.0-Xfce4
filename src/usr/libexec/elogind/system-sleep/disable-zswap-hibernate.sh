#!/bin/sh
case "$1/$2" in
  pre/hibernate|pre/hybrid-sleep)
    logger "disable-zswap-hibernate: DISABLING zswap before hibernate"
    echo 0 > /sys/module/zswap/parameters/enabled
    ;;
  post/hibernate|post/hybrid-sleep)
    logger "disable-zswap-hibernate: RE-ENABLING zswap after hibernate"
    echo 1 > /sys/module/zswap/parameters/enabled
    ;;
esac