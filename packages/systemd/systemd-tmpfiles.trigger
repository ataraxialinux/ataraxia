{
	"trigger": {
		"name": "systemd-tmpfiles",
		"directories_exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/tmpfiles.d/"
		],
		"command": "/usr/bin/systemd-tmpfiles --create"
	}
}
