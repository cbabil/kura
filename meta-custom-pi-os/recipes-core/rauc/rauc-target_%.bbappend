PACKAGECONFIG_append = " service json"

do_install_append() {
    install -d ${D}${sysconfdir}/rauc
    install -m 0644 ${WORKDIR}/system.conf ${D}${sysconfdir}/rauc/
    
    # Create data partition mount point
    install -d ${D}${localstatedir}/straturaOS-data
}

SYSTEMD_SERVICE_${PN} += "rauc.service" 