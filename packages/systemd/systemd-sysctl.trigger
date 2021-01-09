{
	"trigger": {
		"name": "systemd-sysctl",
		"directories_exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/sysctl.d/"
		],
		"command": "/usr/lib/systemd/systemd-sysctl"
	}
}
