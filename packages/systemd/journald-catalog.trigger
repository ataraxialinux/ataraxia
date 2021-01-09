{
	"trigger": {
		"name": "journald-catalog",
		"directories_exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/systemd/catalog/"
		],
		"command": "/usr/bin/journalctl --update-catalog"
	}
}
