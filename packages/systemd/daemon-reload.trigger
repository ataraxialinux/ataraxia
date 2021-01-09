{
	"trigger": {
		"name": "daemon-reload",
		"directories_exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/systemd/system/"
		],
		"command": "/usr/bin/systemctl daemon-reload"
	}
}
