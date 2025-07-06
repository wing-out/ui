#!/system/bin/sh
ASAN_OPTIONS=log_to_syslog=true,allow_addr2line=true,print_cmdline=true,halt_on_error=0,verbosity=2,debug=true,symbolize=1,abort_on_error=0
if [ -f /data/user/0/center.dx.wingout/files/asan.suppressions ]; then
    ASAN_OPTIONS="$ASAN_OPTIONS",suppressions=/data/user/0/center.dx.wingout/files/asan.suppressions
fi
echo "ASAN_OPTIONS=$ASAN_OPTIONS"
export ASAN_OPTIONS
exec "$@"
