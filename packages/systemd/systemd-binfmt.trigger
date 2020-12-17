{
	"trigger": {
		"name": "systemd-binfmt",
		"directories-exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/binfmt.d/"
		],
		"command": "/usr/lib/systemd/systemd-binfmt"
	}
}
