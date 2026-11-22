use super::*;

#[test]
fn names_round_trip_and_are_all_different() {
    for action in Action::ALL {
        assert_eq!(Action::parse(action.name()), Some(action));
    }
    let mut names: Vec<_> = Action::ALL.iter().map(|a| a.name()).collect();
    names.sort_unstable();
    names.dedup();
    assert_eq!(names.len(), Action::ALL.len());
    for other in ["", "Terminal", "rm -rf", "power "] {
        assert_eq!(Action::parse(other), None, "{other}");
    }
}

#[test]
fn only_looking_is_open_to_everyone() {
    let open: Vec<_> = Action::ALL.into_iter().filter(|a| !a.needs_admin()).collect();
    assert_eq!(
        open,
        [Action::Terminal, Action::Files, Action::ListContainers, Action::UpdateStatus, Action::ChangeOwnPassword]
    );
}

#[test]
fn arguments_refuse_what_they_do_not_know() {
    assert_eq!(serde_json::from_str::<PowerArgs>(r#"{"how":"restart"}"#).unwrap().how, PowerKind::Restart);
    assert_eq!(serde_json::from_str::<UpdateArgs>(r#"{"what":"install"}"#).unwrap().what, UpdateKind::Install);
    assert!(serde_json::from_str::<PowerArgs>(r#"{"how":"hibernate"}"#).is_err());
    assert!(serde_json::from_str::<PowerArgs>(r#"{"how":"restart","force":true}"#).is_err());
    assert!(serde_json::from_str::<UpdateArgs>(r#"{"what":"install; reboot"}"#).is_err());
    assert!(serde_json::from_str::<LogsArgs>(r#"{"id":"a"}"#).is_err());
}
