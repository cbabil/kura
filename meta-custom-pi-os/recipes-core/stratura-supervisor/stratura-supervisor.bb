SUMMARY = "straturaOS Supervisor"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://supervisor.service \
    file://supervisor-healthcheck \
    file://supervisor \
    file://supervisor-config.json \
"

inherit systemd

SYSTEMD_SERVICE_${PN} = "supervisor.service"

RDEPENDS_${PN} += "python3-docker python3-requests python3-json"

do_install() {
    # Install supervisor binary and healthcheck
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/supervisor ${D}${bindir}/stratura-supervisor
    install -m 0755 ${WORKDIR}/supervisor-healthcheck ${D}${bindir}/stratura-supervisor-healthcheck

    # Install config
    install -d ${D}${sysconfdir}/stratura-supervisor
    install -m 0644 ${WORKDIR}/supervisor-config.json ${D}${sysconfdir}/stratura-supervisor/config.json

    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/supervisor.service ${D}${systemd_system_unitdir}

    # Create state directory
    install -d ${D}/var/lib/stratura-supervisor
} 