'use strict';

const { PATHS } = require('../src/utils/constants');

// The build installs exactly these files (overlay/common/etc/<brand>/ and
// scripts/common/install-os-pkgs.sh). The supervisor used to read paths the
// build never created, so on a device it always ran on defaults.
describe('constants paths match what the build installs', () => {
  it('reads its config from the overlay-provided supervisor-config.json', () => {
    expect(PATHS.CONFIG).toBe('/etc/kura/supervisor-config.json');
  });

  it('reads security settings from os-security hardening.json', () => {
    expect(PATHS.SECURITY_CONFIG).toBe('/etc/kura/security/hardening.json');
  });
});
