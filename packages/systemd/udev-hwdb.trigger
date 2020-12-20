{
	"trigger": {
		"name": "udev-hwdb",
		"directories_exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/udev/hwdb.d/"
		],
		"command": "/usr/bin/systemd-hwdb update"
	}
}
