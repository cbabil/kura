A fixed stand-in for /proc, /sys and /etc so `make dev` runs on a Mac,
which has no /proc. Numbers do not change, so CPU and network read 0.
The real readers are tested against the live system in CI.
