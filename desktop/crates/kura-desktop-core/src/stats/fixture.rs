//! A fake root with `/proc`, `/sys` and `/etc` files for reader tests
//! (the `fixtures` feature shares it with other crates' tests).

use crate::root::SysRoot;

/// A temporary tree; removed when dropped.
pub struct Fixture {
    pub dir: tempfile::TempDir,
}

pub const STAT: &str = "cpu  1000 0 500 8000 500 0 0 0 0 0\n\
cpu0 500 0 250 4000 250 0 0 0 0 0\ncpu1 500 0 250 4000 250 0 0 0 0 0\n\
intr 1\nctxt 100\nbtime 1700000000\nprocesses 10\nprocs_running 1\nprocs_blocked 0\n";

pub const MEMINFO: &str = "MemTotal:       16000000 kB\nMemFree:         8000000 kB\n\
MemAvailable:   12000000 kB\nBuffers:          500000 kB\nCached:          1500000 kB\n\
SwapCached:            0 kB\nActive:          1 kB\nInactive:        1 kB\nSwapTotal: 0 kB\n\
SwapFree: 0 kB\nDirty: 0 kB\nWriteback: 0 kB\nAnonPages: 1 kB\nMapped: 1 kB\nShmem: 1 kB\n\
SReclaimable:     200000 kB\nSlab: 300000 kB\nCommitLimit: 1 kB\nCommitted_AS: 1 kB\n\
VmallocTotal: 1 kB\nVmallocUsed: 1 kB\nVmallocChunk: 1 kB\nPageTables: 1 kB\nKernelStack: 1 kB\n\
Bounce: 0 kB\nNFS_Unstable: 0 kB\nWritebackTmp: 0 kB\nSUnreclaim: 1 kB\n";

pub const NET_DEV: &str = "Inter-|   Receive                                                |  Transmit\n \
face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n    \
lo: 9999 1 0 0 0 0 0 0 9999 1 0 0 0 0 0 0\n  \
eth0: 1000 10 0 0 0 0 0 0 500 5 0 0 0 0 0 0\n\
veth12: 777 1 0 0 0 0 0 0 777 1 0 0 0 0 0 0\n";

pub const MOUNTINFO: &str = "\
22 1 259:2 / / rw,relatime shared:1 - ext4 /dev/nvme0n1p2 rw\n\
23 22 0:5 / /proc rw - proc proc rw\n\
24 22 0:30 / /run rw - tmpfs tmpfs rw\n\
25 22 259:3 / /srv rw - btrfs /dev/nvme0n1p3 rw\n\
26 22 259:3 /@home /home rw - btrfs /dev/nvme0n1p3 rw\n\
27 22 259:3 /@home /mnt/again rw - btrfs /dev/nvme0n1p3 rw\n\
28 22 0:40 / /var/lib/docker/overlay2/x/merged rw - overlay overlay rw\n";

impl Fixture {
    /// A tree with every source the collector reads.
    pub fn full() -> Self {
        let f = Self { dir: tempfile::tempdir().unwrap() };
        f.write("proc/stat", STAT);
        f.write("proc/meminfo", MEMINFO);
        f.write("proc/net/dev", NET_DEV);
        f.write("proc/self/mountinfo", MOUNTINFO);
        f.write("proc/uptime", "273600.52 1000.00\n");
        f.write("proc/sys/kernel/hostname", "kura-nuc\n");
        f.write("proc/sys/kernel/osrelease", "6.12.48-amd64\n");
        f.write("proc/sys/kernel/arch", "x86_64\n");
        f.write("etc/os-release", "NAME=\"Kura\"\nPRETTY_NAME=\"Kura 0.6.0\"\n");
        f.write("etc/passwd", "root:x:0:0::/root:/bin/sh\nkura:x:1000:1000::/home/kura:/bin/sh\n");
        f.write("etc/group", "sudo:x:27:kura\n");
        f.write("sys/class/thermal/thermal_zone0/temp", "47500\n");
        f.write("sys/class/hwmon/hwmon0/temp1_input", "51250\n");
        f.write("sys/class/hwmon/hwmon0/temp2_input", "bogus\n");
        f.proc(1, "systemd", 0, 100, 10, 12000);
        f.proc(812, "dockerd", 0, 3000, 2000, 96000);
        f.proc(902, "kura-desktopd", 1000, 50, 50, 28000);
        f.proc(2, "kthreadd", 0, 0, 0, 0);
        f.write("proc/2/status", "Name:\tkthreadd\nUid:\t0\t0\t0\t0\n");
        f
    }

    /// The tree as a root.
    pub fn root(&self) -> SysRoot {
        SysRoot::new(self.dir.path())
    }

    /// Writes a file at a path relative to the tree.
    pub fn write(&self, rel: &str, body: &str) {
        let path = self.dir.path().join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, body).unwrap();
    }

    /// A process with `utime`/`stime` ticks and `rss_kb` resident memory.
    pub fn proc(&self, pid: i32, name: &str, uid: u32, utime: u64, stime: u64, rss_kb: u64) {
        let stat = format!(
            "{pid} ({name}) S 1 {pid} {pid} 0 -1 4194560 100 0 0 0 {utime} {stime} 0 0 20 0 1 0 100 1000000 {} 18446744073709551615 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0\n",
            rss_kb / 4
        );
        let status =
            format!("Name:\t{name}\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\nGid:\t0\t0\t0\t0\nVmRSS:\t{rss_kb} kB\n");
        self.write(&format!("proc/{pid}/stat"), &stat);
        self.write(&format!("proc/{pid}/status"), &status);
    }
}
