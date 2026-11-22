use super::*;

fn user(name: &str) -> Session {
    Session { user: SessionUser { name: name.into(), uid: 1000, admin: false }, ticket: "t".into() }
}

#[test]
fn ids_are_256_bit_hex_and_unique() {
    let a = new_session_id();
    assert_eq!(a.len(), 64);
    assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
    assert_ne!(a, new_session_id());
}

#[test]
fn touch_keeps_a_session_alive_until_idle_timeout() {
    let store = SessionStore::new();
    let t0 = Instant::now();
    let id = store.create(user("kura"), t0);
    let cases = [(Duration::from_secs(60), true), (IDLE_TIMEOUT - Duration::from_secs(1), true)];
    let mut now = t0;
    for (step, alive) in cases {
        now += step;
        assert_eq!(store.touch(&id, now).is_some(), alive);
    }
    assert!(store.keep_alive(&id, now));
    assert!(!store.keep_alive(&id, now + IDLE_TIMEOUT));
    assert!(store.is_empty(), "expired session is removed");
    assert!(store.touch("unknown", now).is_none());
}

#[test]
fn remove_ends_a_session() {
    let store = SessionStore::new();
    let now = Instant::now();
    let id = store.create(user("kura"), now);
    assert_eq!(store.remove(&id), Some(user("kura")));
    assert_eq!(store.remove("unknown"), None);
    assert!(store.touch(&id, now).is_none());
}

#[test]
fn the_store_is_bounded_and_drops_the_oldest() {
    let store = SessionStore::new();
    let t0 = Instant::now();
    let first = store.create(user("first"), t0);
    for i in 1..=MAX_SESSIONS {
        store.create(user("x"), t0 + Duration::from_secs(i as u64));
    }
    assert_eq!(store.len(), MAX_SESSIONS);
    assert!(store.touch(&first, t0 + Duration::from_secs(999)).is_none());
}

#[test]
fn create_prunes_expired_sessions() {
    let store = SessionStore::new();
    let t0 = Instant::now();
    store.create(user("old"), t0);
    store.create(user("new"), t0 + IDLE_TIMEOUT);
    assert_eq!(store.len(), 1);
}

#[test]
fn a_maximum_age_ends_a_session_however_busy() {
    let store = IdleStore::with_max_age(Duration::from_secs(3600));
    let t0 = Instant::now();
    let id = store.create(user("kura"), t0);
    assert!(store.keep_alive(&id, t0 + Duration::from_secs(3599)));
    assert!(!store.keep_alive(&id, t0 + Duration::from_secs(3600)), "used a second ago, and still too old");
    assert!(store.is_empty());
}

#[test]
fn sessions_can_be_ended_by_whose_they_are() {
    let store = SessionStore::new();
    let now = Instant::now();
    let (anna, bob, _bob2) =
        (store.create(user("anna"), now), store.create(user("bob"), now), store.create(user("bob"), now));
    assert_eq!(store.remove_where(|s| s.user.name == "bob"), 2);
    assert!(store.touch(&anna, now).is_some() && store.touch(&bob, now).is_none());
}

#[test]
fn one_owner_cannot_push_the_others_out() {
    let store = SessionStore::new();
    let t0 = Instant::now();
    let anna = store.create(user("anna"), t0);
    let is_bob = |s: &Session| s.user.name == "bob";
    let bobs: Vec<String> =
        (1..=5).map(|i| store.create_capped(user("bob"), t0 + Duration::from_secs(i), 3, is_bob)).collect();
    assert_eq!(store.len(), 4, "anna and bob's newest three");
    let later = t0 + Duration::from_secs(9);
    assert!(store.touch(&anna, later).is_some());
    assert_eq!(
        bobs.iter().map(|id| store.touch(id, later).is_some()).collect::<Vec<_>>(),
        [false, false, true, true, true]
    );
}
