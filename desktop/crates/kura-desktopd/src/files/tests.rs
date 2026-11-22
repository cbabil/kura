use super::*;

/// A link whose agent never answers, and the agent's end of the socket.
async fn silent() -> (FilesLink, std::os::unix::net::UnixStream) {
    let (ours, theirs) = std::os::unix::net::UnixStream::pair().unwrap();
    ours.set_nonblocking(true).unwrap();
    let link = FilesLink {
        home: "/home/x".into(),
        stream: tokio::sync::Mutex::new(UnixStream::from_std(ours).unwrap()),
        broken: AtomicBool::new(false),
        used: Mutex::new(Instant::now()),
    };
    (link, theirs)
}

#[tokio::test]
async fn a_request_given_up_half_way_breaks_the_link_for_good() {
    let (link, _agent) = silent().await;
    assert!(link.usable(Instant::now()));
    // The browser goes away while the agent is still working.
    let gone = tokio::time::timeout(Duration::from_millis(50), link.ask(&Request::ListTrash, None)).await;
    assert!(gone.is_err(), "still waiting when it was dropped");
    assert!(!link.usable(Instant::now()));
    // The reply to that request must never answer the next one.
    let next = link.ask(&Request::Hello, None).await;
    assert_eq!(next.unwrap_err().kind(), io::ErrorKind::BrokenPipe);
}

#[tokio::test]
async fn a_busy_agent_is_not_waited_for_by_what_is_asked_again_anyway() {
    let (link, _agent) = silent().await;
    let link = Arc::new(link);
    let copying = tokio::spawn({
        let link = link.clone();
        async move { link.ask(&Request::EmptyTrash, None).await }
    });
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert!(matches!(link.ask_if_free(&Request::ListTrash).await, Ok(None)));
    copying.abort();
}

#[tokio::test]
async fn an_agent_that_does_not_say_hello_is_not_a_link() {
    let (_ours, theirs) = std::os::unix::net::UnixStream::pair().unwrap();
    tokio::time::pause();
    let opening = tokio::spawn(FilesLink::open(theirs.into()));
    tokio::time::advance(HELLO_TIMEOUT + Duration::from_secs(1)).await;
    assert_eq!(opening.await.unwrap().err().map(|e| e.kind()), Some(io::ErrorKind::TimedOut));
}
