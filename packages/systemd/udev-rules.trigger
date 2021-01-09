{
	"trigger": {
		"name": "udev-rules",
		"directories_exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/udev/rules.d/"
		],
		"command": "/usr/bin/udevadm control --reload"
	}
}
