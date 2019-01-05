#!@SH_PATH

if [ "$1" == "--" ]; then
    shift
fi

# Use a temporary variable to prevent weird shell expansions.
ARGS="$@"

# Process the arguments.
for arg in ${ARGS}; do
    if [ "${arg}" == '-v' ]; then
        echo "fakefakeroot version @VERSION"
        exit 0
    fi
done

FAKEROOTKEY="@KEY" su -s "@SH_PATH" -c "${ARGS}"
exit "$?"
