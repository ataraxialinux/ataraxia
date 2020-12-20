{
	"trigger": {
		"name": "systemd-binfmt",
		"directories_exist": [
			"/run/systemd"
		],
		"directory": [
			"usr/lib/binfmt.d/"
		],
		"command": "/usr/lib/systemd/systemd-binfmt"
	}
}
