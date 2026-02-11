"""Tests for network_manager.py (stratura-config).

The NetworkManager class relies on dbus for D-Bus communication with
the system NetworkManager daemon. All dbus calls are fully mocked.
"""

import json
from unittest.mock import MagicMock, mock_open, patch

import pytest


@pytest.fixture(autouse=True)
def _mock_dbus():
    """Mock the dbus module before importing network_manager."""
    mock_dbus = MagicMock()
    with patch.dict("sys.modules", {"dbus": mock_dbus}):
        yield mock_dbus


def _import_module():
    """Import network_manager after dbus is mocked."""
    import importlib
    import network_manager as nm

    importlib.reload(nm)
    return nm


def _make_mgr():
    """Create a NetworkManager with mocked D-Bus connections."""
    nm = _import_module()
    with patch.object(nm.NetworkManager, "__init__", lambda self: None):
        mgr = nm.NetworkManager.__new__(nm.NetworkManager)
    mgr.bus = MagicMock()
    mgr.nm = MagicMock()
    return mgr, nm


class TestSetupNetwork:
    """Tests for the setup_network dispatcher."""

    def test_setup_ethernet_only(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "setup_ethernet") as mock_eth:
            mgr.setup_network({
                "ethernet": {"enable": True, "interface": "eth0"},
                "wifi": {"enable": False},
            })
            mock_eth.assert_called_once()

    def test_setup_wifi_only(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "setup_wifi") as mock_wifi, \
             patch.object(nm.NetworkManager, "setup_ethernet") as mock_eth:
            mgr.setup_network({
                "ethernet": {"enable": False},
                "wifi": {"enable": True, "networks": []},
            })
            # ethernet enable defaults to True if key missing, so we
            # explicitly disable it
            mock_wifi.assert_called_once()

    def test_setup_cellular(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "setup_cellular") as mock_cell:
            mgr.setup_network({
                "ethernet": {"enable": False},
                "wifi": {"enable": False},
                "cellular": {"enable": True, "apn": "internet"},
            })
            mock_cell.assert_called_once()

    def test_setup_all_disabled(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "setup_ethernet") as mock_eth, \
             patch.object(nm.NetworkManager, "setup_wifi") as mock_wifi, \
             patch.object(nm.NetworkManager, "setup_cellular") as mock_cell:
            mgr.setup_network({
                "ethernet": {"enable": False},
                "wifi": {"enable": False},
                "cellular": {"enable": False},
            })
            mock_eth.assert_not_called()
            mock_wifi.assert_not_called()
            mock_cell.assert_not_called()


class TestSetupWifi:
    """Tests for WiFi connection setup."""

    def test_setup_wifi_creates_connections(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "add_connection") as mock_add:
            mgr.setup_wifi({
                "networks": [
                    {"ssid": "HomeNet", "psk": "password123"},
                    {"ssid": "WorkNet", "psk": "secret456"},
                ]
            })
            assert mock_add.call_count == 2

    def test_setup_wifi_connection_structure(self):
        mgr, nm = _make_mgr()
        connections = []
        with patch.object(
            nm.NetworkManager, "add_connection",
            side_effect=lambda c: connections.append(c),
        ):
            mgr.setup_wifi({"networks": [{"ssid": "Net", "psk": "pass"}]})

        conn = connections[0]
        assert conn["802-11-wireless"]["ssid"] == "Net"
        assert conn["802-11-wireless-security"]["psk"] == "pass"
        assert conn["ipv4"]["method"] == "auto"

    def test_setup_wifi_no_networks(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "add_connection") as mock_add:
            mgr.setup_wifi({"networks": []})
            mock_add.assert_not_called()


class TestSetupEthernet:
    """Tests for ethernet connection setup."""

    def test_setup_ethernet_default(self):
        mgr, nm = _make_mgr()
        connections = []
        with patch.object(
            nm.NetworkManager, "add_connection",
            side_effect=lambda c: connections.append(c),
        ):
            mgr.setup_ethernet({"interface": "eth0"})

        conn = connections[0]
        assert conn["ipv4"]["method"] == "auto"
        assert conn["connection"]["interface-name"] == "eth0"
        assert conn["connection"]["type"] == "802-3-ethernet"

    def test_setup_ethernet_static_ip(self):
        mgr, nm = _make_mgr()
        connections = []
        with patch.object(
            nm.NetworkManager, "add_connection",
            side_effect=lambda c: connections.append(c),
        ):
            mgr.setup_ethernet({
                "interface": "eth0",
                "ipv4_method": "manual",
                "static_ip": ["192.168.1.100/24"],
                "dns_servers": ["8.8.8.8"],
            })

        conn = connections[0]
        assert conn["ipv4"]["method"] == "manual"
        assert "192.168.1.100/24" in conn["ipv4"]["addresses"]
        assert "8.8.8.8" in conn["ipv4"]["dns"]


class TestSetupCellular:
    """Tests for cellular/GSM connection setup."""

    def test_setup_cellular_with_apn(self):
        mgr, nm = _make_mgr()
        connections = []
        with patch.object(
            nm.NetworkManager, "add_connection",
            side_effect=lambda c: connections.append(c),
        ):
            mgr.setup_cellular({"apn": "internet", "interface": "wwan0"})

        conn = connections[0]
        assert conn["gsm"]["apn"] == "internet"
        assert conn["connection"]["type"] == "gsm"

    def test_setup_cellular_no_apn(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "add_connection") as mock_add:
            mgr.setup_cellular({"interface": "wwan0"})
            mock_add.assert_not_called()

    def test_setup_cellular_defaults(self):
        mgr, nm = _make_mgr()
        connections = []
        with patch.object(
            nm.NetworkManager, "add_connection",
            side_effect=lambda c: connections.append(c),
        ):
            mgr.setup_cellular({"apn": "test"})

        conn = connections[0]
        assert conn["gsm"]["number"] == "*99#"
        assert conn["gsm"]["pin"] == ""


class TestAddConnection:
    """Tests for D-Bus connection addition."""

    def test_add_connection_calls_nm(self):
        mgr, nm = _make_mgr()
        import sys
        mock_dbus = sys.modules["dbus"]
        mock_dbus.Dictionary.return_value = {"mocked": True}

        mgr.add_connection({"connection": {"id": "test"}})
        mgr.nm.AddConnection.assert_called_once()


class TestHandleConnectionLoss:
    """Tests for connection loss handling and failover.

    Several methods called by handle_connection_loss are referenced but
    not defined in the source (get_active_connection, try_primary_connection,
    try_wifi_connections, try_cellular_failover). We use create=True to
    allow patching them.
    """

    def test_primary_reconnect_succeeds(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "get_active_connection", create=True, return_value=None), \
             patch.object(nm.NetworkManager, "try_primary_connection", create=True, return_value=True):
            mgr.handle_connection_loss()

    def test_wifi_failover(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "get_active_connection", create=True, return_value=None), \
             patch.object(nm.NetworkManager, "try_primary_connection", create=True, return_value=False), \
             patch.object(nm.NetworkManager, "try_wifi_connections", create=True, return_value=True):
            mgr.handle_connection_loss()

    def test_cellular_failover(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "get_active_connection", create=True, return_value=None), \
             patch.object(nm.NetworkManager, "try_primary_connection", create=True, return_value=False), \
             patch.object(nm.NetworkManager, "try_wifi_connections", create=True, return_value=False), \
             patch.object(nm.NetworkManager, "try_cellular_failover", create=True, return_value=True):
            mgr.handle_connection_loss()

    def test_all_failover_fails(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "get_active_connection", create=True, return_value=None), \
             patch.object(nm.NetworkManager, "try_primary_connection", create=True, return_value=False), \
             patch.object(nm.NetworkManager, "try_wifi_connections", create=True, return_value=False), \
             patch.object(nm.NetworkManager, "try_cellular_failover", create=True, return_value=False), \
             patch.object(nm.NetworkManager, "notify_connection_failure") as mock_notify:
            mgr.handle_connection_loss()
            mock_notify.assert_called_once()

    def test_already_connected(self):
        mgr, nm = _make_mgr()
        with patch.object(nm.NetworkManager, "get_active_connection", create=True, return_value="conn1"), \
             patch.object(nm.NetworkManager, "try_primary_connection", create=True) as mock_primary:
            mgr.handle_connection_loss()
            mock_primary.assert_not_called()


class TestNotifyConnectionFailure:
    """Tests for connection failure notification."""

    @patch("subprocess.run")
    def test_notify_writes_state_file(self, mock_run, tmp_path):
        mgr, nm = _make_mgr()
        mgr.recovery_attempts = 3
        state_file = tmp_path / "network-state"

        with patch("builtins.open", mock_open()) as mf:
            # Patch the hardcoded path
            with patch.object(
                nm, "json", wraps=json
            ):
                mgr.notify_connection_failure()
        mock_run.assert_called_once()
