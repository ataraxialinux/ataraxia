{
	"trigger": {
		"name": "systemd-tmpfiles",
		"directories-exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/tmpfiles.d/"
		],
		"command": "/usr/bin/systemd-tmpfiles --create"
	}
}
