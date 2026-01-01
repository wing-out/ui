package center.dx.wingout;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.MacAddress;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.net.wifi.WifiNetworkSpecifier;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

public final class WiFi {

    private static final String TAG = "WiFi";

    // For connectToAP() multi-request
    private static final AtomicInteger NEXT_ID = new AtomicInteger(1);
    private static final Map<Integer, ConnectivityManager.NetworkCallback> callbacks =
            new ConcurrentHashMap<>();
    private static final Map<Integer, Network> networks =
            new ConcurrentHashMap<>();

    private static WifiManager.LocalOnlyHotspotReservation localOnlyHotspotReservation = null;

    // For tracking current WiFi AP via NetworkCallback (FLAG_INCLUDE_LOCATION_INFO)
    private static final Object currentWiFiLock = new Object();
    private static WifiInfo currentWiFiInfo = null;
    private static boolean currentWiFiCallbackRegistered = false;
    private static ConnectivityManager.NetworkCallback currentWiFiCallback = null;

    private WiFi() {}

    // --------------------------------------------------------------------
    // 0) Permission/log helper
    // --------------------------------------------------------------------
    private static void logLocationPermissions(Context context) {
        try {
            boolean hasFine =
                    context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)
                            == PackageManager.PERMISSION_GRANTED;
            boolean hasNearby =
                    context.checkSelfPermission(android.Manifest.permission.NEARBY_WIFI_DEVICES)
                            == PackageManager.PERMISSION_GRANTED;
            Log.i(TAG, "WiFi perms: FINE=" + hasFine + " NEARBY_WIFI_DEVICES=" + hasNearby);
        } catch (Throwable t) {
            Log.w(TAG, "Cannot check permissions", t);
        }
    }

    public static void requestNearbyDevicesPermission(Context context) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                if (context.checkSelfPermission(android.Manifest.permission.NEARBY_WIFI_DEVICES)
                        != PackageManager.PERMISSION_GRANTED) {
                    if (context instanceof android.app.Activity) {
                        Log.i(TAG, "Requesting NEARBY_WIFI_DEVICES permission");
                        ((android.app.Activity) context).requestPermissions(
                                new String[]{android.Manifest.permission.NEARBY_WIFI_DEVICES},
                                1001);
                    }
                }
            }
        } catch (Throwable t) {
            Log.e(TAG, "Failed to request NEARBY_WIFI_DEVICES permission", t);
        }
    }

    // --------------------------------------------------------------------
    // 1) Scan: startScan + getScanResultsJson
    // --------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    public static void startScan(Context context) {
        try {
            WifiManager wifiManager =
                    (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifiManager == null) {
                Log.w(TAG, "WifiManager is null in startScan()");
                return;
            }
            wifiManager.startScan();
        } catch (Exception e) {
            Log.w(TAG, "startScan() failed or throttled", e);
        }
    }

    @SuppressLint("MissingPermission")
    public static String getScanResultsJSON(Context context) {
        try {
            WifiManager wifiManager =
                    (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifiManager == null) {
                Log.w(TAG, "WifiManager is null in getScanResultsJSON()");
                return "[]";
            }

            List<ScanResult> results = wifiManager.getScanResults();
            JSONArray arr = new JSONArray();

            for (ScanResult r : results) {
                JSONObject o = new JSONObject();
                o.put("ssid", r.SSID);
                o.put("bssid", r.BSSID);
                o.put("level", r.level);         // dBm
                o.put("frequency", r.frequency); // MHz
                arr.put(o);
            }

            return arr.toString();
        } catch (Exception e) {
            Log.e(TAG, "getScanResultsJson failed", e);
            return "[]";
        }
    }

    // --------------------------------------------------------------------
    // 2) Connect to AP (multi-request, returns requestId)
    // --------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    public static int connectToAP(Context context,
                                  String ssid,
                                  String bssid,
                                  String security,
                                  String password) {
        if (ssid == null || ssid.isEmpty()) {
            Log.w(TAG, "connectToAP: empty SSID");
            return -1;
        }

        try {
            WifiNetworkSpecifier.Builder builder = new WifiNetworkSpecifier.Builder()
                    .setSsid(ssid);

            if (bssid != null && !bssid.isEmpty()) {
                builder.setBssid(MacAddress.fromString(bssid));
            }

            // Security handling (modern types)
            String sec = security != null ? security.trim() : "";
            sec = sec.toUpperCase(Locale.ROOT);

            boolean needsPassword = false;
            boolean usedSecurityFlag = false;

            switch (sec) {
                case "":
                case "OPEN":
                    // Open AP, no passphrase
                    if (password != null && !password.isEmpty()) {
                        Log.w(TAG, "Security OPEN but password is non-empty; ignoring password.");
                    }
                    break;

                case "WPA3":
                case "WPA3_PSK":
                case "SAE":
                    needsPassword = true;
                    if (password == null || password.isEmpty()) {
                        Log.w(TAG, "WPA3 requires non-empty password");
                        return -1;
                    }
                    builder.setWpa3Passphrase(password);
                    usedSecurityFlag = true;
                    break;

                case "WPA2":
                case "WPA2_PSK":
                    needsPassword = true;
                    if (password == null || password.isEmpty()) {
                        Log.w(TAG, "WPA2 requires non-empty password");
                        return -1;
                    }
                    builder.setWpa2Passphrase(password);
                    usedSecurityFlag = true;
                    break;

                case "WPA2_WPA3":
                case "WPA2_WPA3_PSK":
                    needsPassword = true;
                    if (password == null || password.isEmpty()) {
                        Log.w(TAG, "WPA2_WPA3 requires non-empty password");
                        return -1;
                    }
                    // Builder only allows one; prefer WPA3.
                    builder.setWpa3Passphrase(password);
                    usedSecurityFlag = true;
                    break;

                default:
                    Log.w(TAG, "Unknown security type '" + security
                            + "', assuming WPA2-PSK");
                    needsPassword = true;
                    if (password == null || password.isEmpty()) {
                        Log.w(TAG, "Assumed WPA2-PSK requires non-empty password");
                        return -1;
                    }
                    builder.setWpa2Passphrase(password);
                    usedSecurityFlag = true;
                    break;
            }

            if (!usedSecurityFlag && needsPassword) {
                Log.w(TAG, "Security handling inconsistent for '" + security + "'");
                return -1;
            }

            WifiNetworkSpecifier specifier = builder.build();

            NetworkRequest request = new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .setNetworkSpecifier(specifier)
                    .build();

            ConnectivityManager cm = (ConnectivityManager)
                    context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) {
                Log.w(TAG, "ConnectivityManager is null");
                return -1;
            }

            final int id = NEXT_ID.getAndIncrement();

            ConnectivityManager.NetworkCallback callback =
                    new ConnectivityManager.NetworkCallback() {

                        @Override
                        public void onAvailable(Network network) {
                            Log.i(TAG, "WiFi network available for ID=" + id + ": " + network);
                            networks.put(id, network);
                            cm.bindProcessToNetwork(network); // last available wins
                        }

                        @Override
                        public void onLost(Network network) {
                            Log.i(TAG, "WiFi network LOST for ID=" + id + ": " + network);
                            networks.remove(id);
                            callbacks.remove(id);

                            Network bound = cm.getBoundNetworkForProcess();
                            if (bound != null && bound.equals(network)) {
                                cm.bindProcessToNetwork(null);
                            }
                        }

                        @Override
                        public void onUnavailable() {
                            Log.w(TAG, "WiFi network UNAVAILABLE for ID=" + id);
                            callbacks.remove(id);
                        }
                    };

            callbacks.put(id, callback);
            cm.requestNetwork(request, callback);

            Log.i(TAG, "Requested WiFi network for ID=" + id
                    + " SSID=" + ssid + " BSSID=" + bssid + " security=" + sec);

            return id;

        } catch (Exception e) {
            Log.e(TAG, "connectToAP failed", e);
            return -1;
        }
    }

    // --------------------------------------------------------------------
    // 3) Disconnect requests
    // --------------------------------------------------------------------

    public static void disconnectRequestedAP(Context context, int requestId) {
        ConnectivityManager cm = (ConnectivityManager)
                context.getSystemService(Context.CONNECTIVITY_SERVICE);

        Network net = networks.remove(requestId);
        ConnectivityManager.NetworkCallback cb = callbacks.remove(requestId);

        if (cm != null && cb != null) {
            try {
                cm.unregisterNetworkCallback(cb);
            } catch (Exception e) {
                Log.w(TAG, "unregisterNetworkCallback failed for ID=" + requestId, e);
            }
        }

        if (cm != null && net != null) {
            Network bound = cm.getBoundNetworkForProcess();
            if (bound != null && bound.equals(net)) {
                cm.bindProcessToNetwork(null);
            }
        }

        Log.i(TAG, "disconnectRequestedAP done for ID=" + requestId);
    }

    public static void disconnectAllRequestedAPs(Context context) {
        Integer[] ids = callbacks.keySet().toArray(new Integer[0]);
        for (int id : ids) {
            disconnectRequestedAP(context, id);
        }
    }

    // --------------------------------------------------------------------
    // 4) Current WiFi AP info via NetworkCallback + FLAG_INCLUDE_LOCATION_INFO
    // --------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private static void ensureCurrentWiFiMonitor(Context context) {
        if (currentWiFiCallbackRegistered) {
            return;
        }

        ConnectivityManager cm = (ConnectivityManager)
                context.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm == null) {
            Log.w(TAG, "ConnectivityManager is null in ensureCurrentWiFiMonitor()");
            return;
        }

        logLocationPermissions(context);

        NetworkRequest request = new NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build();

        currentWiFiCallback =
                new ConnectivityManager.NetworkCallback(
                        ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO) {

                    @Override
                    public void onCapabilitiesChanged(Network network,
                                                      NetworkCapabilities caps) {
                        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                            return;
                        }
                        Object ti = caps.getTransportInfo();
                        if (ti instanceof WifiInfo) {
                            WifiInfo wi = (WifiInfo) ti;
                            synchronized (currentWiFiLock) {
                                currentWiFiInfo = wi;
                            }
                        }
                    }

                    @Override
                    public void onLost(Network network) {
                        synchronized (currentWiFiLock) {
                            currentWiFiInfo = null;
                        }
                    }
                };

        cm.registerNetworkCallback(request, currentWiFiCallback);
        currentWiFiCallbackRegistered = true;
        Log.i(TAG, "Registered current WiFi monitor callback");
    }

    @SuppressLint("MissingPermission")
    public static String getCurrentConnectionJSON(Context context) {
        try {
            ensureCurrentWiFiMonitor(context);

            WifiInfo wi;
            synchronized (currentWiFiLock) {
                wi = currentWiFiInfo;
            }

            if (wi == null) {
                Log.i(TAG, "getCurrentConnectionJSON: no WifiInfo yet (no WiFi AP or callback not fired)");
                return "{}";
            }

            String ssid  = wi.getSSID();
            String bssid = wi.getBSSID();
            int rssi     = wi.getRssi();   // dBm

            if ("<unknown ssid>".equals(ssid)) {
                Log.w(TAG, "SSID is <unknown ssid> – likely redacted or no WiFi AP");
            }
            if ("02:00:00:00:00:00".equals(bssid)) {
                Log.w(TAG, "BSSID is 02:00:00:00:00:00 – likely redacted or no WiFi AP");
            }

            // Strip quotes around SSID if present
            if (ssid != null && ssid.length() >= 2
                    && ssid.startsWith("\"") && ssid.endsWith("\"")) {
                ssid = ssid.substring(1, ssid.length() - 1);
            }

            JSONObject o = new JSONObject();
            o.put("ssid",  ssid  != null ? ssid  : "");
            o.put("bssid", bssid != null ? bssid : "");
            o.put("rssi",  rssi);

            return o.toString();

        } catch (Exception e) {
            Log.e(TAG, "getCurrentConnectionJson failed", e);
            return "{}";
        }
    }

    @SuppressLint("MissingPermission")
    public static String getHotspotConfigurationJSON(Context context) {
        try {
            WifiManager wifiManager = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifiManager == null) return "{}";

            String ssid = null;
            String psk = null;

            if (android.os.Build.VERSION.SDK_INT >= 30) { // Build.VERSION_CODES.R
                try {
                    // Use reflection to avoid compile-time dependency on newer SDK if not available
                    java.lang.reflect.Method getSoftApConfigurationMethod = wifiManager.getClass().getMethod("getSoftApConfiguration");
                    Object config = getSoftApConfigurationMethod.invoke(wifiManager);
                    if (config != null) {
                        ssid = (String) config.getClass().getMethod("getSsid").invoke(config);
                        psk = (String) config.getClass().getMethod("getPassphrase").invoke(config);
                    }
                } catch (Throwable t) {
                    Log.w(TAG, "Failed to get hotspot config via getSoftApConfiguration: " + t.getMessage());
                }
            }

            if (ssid == null || psk == null) {
                // Deprecated way for older Android or if above failed
                try {
                    java.lang.reflect.Method method = wifiManager.getClass().getDeclaredMethod("getWifiApConfiguration");
                    method.setAccessible(true);
                    Object config = method.invoke(wifiManager);
                    if (config != null) {
                        java.lang.reflect.Field ssidField = config.getClass().getDeclaredField("SSID");
                        java.lang.reflect.Field pskField = config.getClass().getDeclaredField("preSharedKey");
                        if (ssid == null) ssid = (String) ssidField.get(config);
                        if (psk == null) psk = (String) pskField.get(config);
                    }
                } catch (Throwable t) {
                    Log.w(TAG, "Failed to get hotspot config via getWifiApConfiguration: " + t.getMessage());
                }
            }

            // Fallback to Settings.Secure/System (some OEMs use these)
            if (ssid == null) {
                try {
                    ssid = android.provider.Settings.Secure.getString(context.getContentResolver(), "wifi_ap_ssid");
                } catch (Throwable ignored) {}
            }
            if (psk == null) {
                try {
                    psk = android.provider.Settings.Secure.getString(context.getContentResolver(), "wifi_ap_passwd");
                } catch (Throwable ignored) {}
            }
            if (ssid == null) {
                try {
                    ssid = android.provider.Settings.System.getString(context.getContentResolver(), "wifi_ap_ssid");
                } catch (Throwable ignored) {}
            }
            if (psk == null) {
                try {
                    psk = android.provider.Settings.System.getString(context.getContentResolver(), "wifi_ap_passwd");
                } catch (Throwable ignored) {}
            }

            // Fallback to SharedPreferences (Workaround #2)
            android.content.SharedPreferences prefs = context.getSharedPreferences("hotspot_prefs", Context.MODE_PRIVATE);
            if (ssid == null || ssid.isEmpty()) {
                ssid = prefs.getString("ssid", null);
            }
            if (psk == null || psk.isEmpty()) {
                psk = prefs.getString("psk", null);
            }

            // Clean up SSID (strip quotes)
            if (ssid != null && ssid.length() >= 2 && ssid.startsWith("\"") && ssid.endsWith("\"")) {
                ssid = ssid.substring(1, ssid.length() - 1);
            }

            JSONObject o = new JSONObject();
            o.put("ssid", ssid != null ? ssid : "");
            o.put("psk", psk != null ? psk : "");
            return o.toString();
        } catch (Exception e) {
            Log.e(TAG, "getHotspotConfigurationJSON failed", e);
            return "{}";
        }
    }

    public static void saveHotspotConfiguration(Context context, String ssid, String psk) {
        try {
            android.content.SharedPreferences prefs = context.getSharedPreferences("hotspot_prefs", Context.MODE_PRIVATE);
            prefs.edit().putString("ssid", ssid).putString("psk", psk).apply();
            Log.i(TAG, "Saved hotspot configuration to SharedPreferences");
        } catch (Exception e) {
            Log.e(TAG, "saveHotspotConfiguration failed", e);
        }
    }

    public static void setHotspotEnabled(Context context, boolean enabled) {
        try {
            WifiManager wifiManager = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifiManager == null) return;

            // Try to find the hidden setWifiApEnabled method
            java.lang.reflect.Method method = null;
            try {
                method = wifiManager.getClass().getMethod("setWifiApEnabled", android.net.wifi.WifiConfiguration.class, boolean.class);
            } catch (NoSuchMethodException e) {
                try {
                    method = wifiManager.getClass().getDeclaredMethod("setWifiApEnabled", android.net.wifi.WifiConfiguration.class, boolean.class);
                    method.setAccessible(true);
                } catch (NoSuchMethodException e2) {
                    Log.w(TAG, "setWifiApEnabled method not found even via reflection");
                }
            }

            if (method != null) {
                method.invoke(wifiManager, null, enabled);
            } else {
                // Fallback: try to open the hotspot settings page if we can't do it programmatically
                Log.i(TAG, "Opening hotspot settings as fallback");
                android.content.Intent intent = new android.content.Intent(android.provider.Settings.ACTION_WIRELESS_SETTINGS);
                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(intent);
            }
        } catch (Exception e) {
            Log.e(TAG, "setHotspotEnabled failed", e);
        }
    }

    public static boolean isLocalHotspotEnabled(Context context) {
        return localOnlyHotspotReservation != null;
    }

    public static void setLocalHotspotEnabled(Context context, boolean enabled) {
        try {
            WifiManager wifiManager = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifiManager == null) return;

            if (android.os.Build.VERSION.SDK_INT >= 26) { // Oreo+
                if (enabled) {
                    if (localOnlyHotspotReservation != null) return;
                    wifiManager.startLocalOnlyHotspot(new WifiManager.LocalOnlyHotspotCallback() {
                        @Override
                        public void onStarted(WifiManager.LocalOnlyHotspotReservation reservation) {
                            super.onStarted(reservation);
                            localOnlyHotspotReservation = reservation;
                            Log.i(TAG, "Local-only hotspot started");
                        }

                        @Override
                        public void onStopped() {
                            super.onStopped();
                            localOnlyHotspotReservation = null;
                            Log.i(TAG, "Local-only hotspot stopped");
                        }

                        @Override
                        public void onFailed(int reason) {
                            super.onFailed(reason);
                            localOnlyHotspotReservation = null;
                            Log.e(TAG, "Local-only hotspot failed: " + reason);
                        }
                    }, null);
                } else {
                    if (localOnlyHotspotReservation != null) {
                        localOnlyHotspotReservation.close();
                        localOnlyHotspotReservation = null;
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "setLocalHotspotEnabled failed", e);
        }
    }

    public static boolean isHotspotEnabled(Context context) {
        try {
            WifiManager wifiManager = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifiManager == null) return false;
            java.lang.reflect.Method method = wifiManager.getClass().getDeclaredMethod("getWifiApState");
            method.setAccessible(true);
            int state = (Integer) method.invoke(wifiManager);
            return state == 13 || state == 12; // 13 is ENABLED, 12 is ENABLING
        } catch (Exception e) {
            return false;
        }
    }

    public static String getLocalOnlyHotspotInfoJSON() {
        try {
            if (localOnlyHotspotReservation == null) return "{}";
            android.net.wifi.SoftApConfiguration config = localOnlyHotspotReservation.getSoftApConfiguration();
            JSONObject o = new JSONObject();
            o.put("ssid", config.getSsid());
            o.put("psk", config.getPassphrase());
            return o.toString();
        } catch (Exception e) {
            Log.e(TAG, "getLocalOnlyHotspotInfoJSON failed", e);
            return "{}";
        }
    }
}
