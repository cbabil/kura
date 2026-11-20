use super::*;

#[test]
fn five_failures_then_refused_until_the_window_passes() {
    let rl = RateLimiter::new();
    let t0 = Instant::now();
    let keys = login_keys("10.0.0.2", "kura");
    for i in 0..MAX_FAILURES {
        assert!(rl.begin(keys.clone(), t0 + Duration::from_secs(i as u64)).is_ok());
    }
    assert_eq!(rl.begin(keys.clone(), t0 + Duration::from_secs(10)).unwrap_err(), 50);
    assert!(rl.begin(keys.clone(), t0 + WINDOW).is_ok(), "oldest failure aged out");
}

#[test]
fn per_ip_and_per_user_limits_are_independent() {
    let rl = RateLimiter::new();
    let now = Instant::now();
    for i in 0..MAX_FAILURES {
        rl.begin(login_keys("10.0.0.2", &format!("u{i}")), now).unwrap();
    }
    assert!(rl.begin(login_keys("10.0.0.2", "other"), now).is_err(), "same IP");
    assert!(rl.begin(login_keys("10.0.0.3", "other"), now).is_ok(), "other IP");
    for i in 0..MAX_FAILURES {
        rl.begin(login_keys(&format!("10.1.0.{i}"), "anna"), now).unwrap();
    }
    assert!(rl.begin(login_keys("10.9.9.9", "anna"), now).is_err(), "same user");
}

#[test]
fn a_success_does_not_count() {
    let rl = RateLimiter::new();
    let now = Instant::now();
    let keys = login_keys("10.0.0.2", "kura");
    for _ in 0..MAX_FAILURES * 2 {
        let attempt = rl.begin(keys.clone(), now).unwrap();
        rl.succeeded(attempt);
    }
    assert!(rl.lock().is_empty());
    let a = rl.begin(keys.clone(), now).unwrap();
    rl.begin(keys.clone(), now).unwrap();
    rl.succeeded(a);
    assert_eq!(rl.lock()[&keys[0]].len(), 1);
}

#[test]
fn retry_after_is_at_least_one_second() {
    let rl = RateLimiter::new();
    let t0 = Instant::now();
    let keys = login_keys("ip", "u");
    for _ in 0..MAX_FAILURES {
        rl.begin(keys.clone(), t0).unwrap();
    }
    let wait = rl.begin(keys.clone(), t0 + WINDOW - Duration::from_millis(1)).unwrap_err();
    assert_eq!(wait, 1);
}

#[test]
fn ipv6_clients_are_keyed_by_their_64() {
    let cases = [
        ("192.168.1.5", "192.168.1.5"),
        ("::ffff:10.0.0.2", "10.0.0.2"),
        ("2001:db8:1:2:aaaa::1", "2001:db8:1:2::/64"),
        ("2001:db8:1:2:bbbb::9", "2001:db8:1:2::/64"),
        ("fe80::1", "fe80:0:0:0::/64"),
    ];
    for (ip, want) in cases {
        assert_eq!(ip_key(ip.parse().unwrap()), want);
    }
}

#[test]
fn a_table_full_of_live_keys_refuses_newcomers() {
    let rl = RateLimiter::new();
    let now = Instant::now();
    for i in 0..MAX_KEYS / 2 {
        rl.begin(login_keys(&i.to_string(), &i.to_string()), now).unwrap();
    }
    assert_eq!(rl.begin(login_keys("new", "new"), now).unwrap_err(), WINDOW.as_secs());
}

#[test]
fn stale_keys_are_dropped_past_the_cap() {
    let rl = RateLimiter::new();
    let t0 = Instant::now();
    for i in 0..MAX_KEYS / 2 {
        rl.begin(login_keys(&i.to_string(), &i.to_string()), t0).unwrap();
    }
    rl.begin(login_keys("new", "new"), t0 + WINDOW).unwrap();
    assert_eq!(rl.lock().len(), 2);
}
