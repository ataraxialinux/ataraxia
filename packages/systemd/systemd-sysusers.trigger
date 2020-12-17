{
	"trigger": {
		"name": "systemd-sysusers",
		"directories-exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/sysusers.d/"
		],
		"command": "/usr/bin/systemd-sysusers"
	}
}
