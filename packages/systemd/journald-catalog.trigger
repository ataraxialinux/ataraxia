{
	"trigger": {
		"name": "journald-catalog",
		"directories-exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/systemd/catalog/"
		],
		"command": "/usr/bin/journalctl --update-catalog"
	}
}
