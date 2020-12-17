{
	"trigger": {
		"name": "udev-rules",
		"directories-exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/udev/rules.d/"
		],
		"command": "/usr/bin/udevadm control --reload"
	}
}
