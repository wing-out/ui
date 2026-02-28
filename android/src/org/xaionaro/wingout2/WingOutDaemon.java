package org.xaionaro.wingout2;

import android.content.Context;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;

/**
 * Manages the wingoutd Go daemon lifecycle.
 * The daemon binary is packaged as libwingoutd.so in the APK's native libs,
 * which Android automatically extracts to nativeLibraryDir.
 */
public class WingOutDaemon {
    private static final String TAG = "WingOutDaemon";
    private static final String BINARY_NAME = "libwingoutd.so";
    private static final String DEFAULT_LISTEN = "127.0.0.1:3595";

    private Process process;
    private String listenAddr;

    /**
     * Starts the wingoutd daemon.
     *
     * @param context    Android context (for locating native library dir)
     * @param streamdAddr  Remote StreamD address (may be empty)
     * @param ffstreamAddr Remote FFStream address (may be empty)
     * @return the gRPC listen address (e.g. "127.0.0.1:3595")
     */
    public synchronized String start(Context context, String streamdAddr, String ffstreamAddr) {
        if (process != null) {
            return listenAddr;
        }

        File binary = new File(context.getApplicationInfo().nativeLibraryDir, BINARY_NAME);
        if (!binary.exists()) {
            Log.e(TAG, "wingoutd binary not found at: " + binary.getAbsolutePath());
            return null;
        }
        if (!binary.canExecute()) {
            Log.e(TAG, "wingoutd binary not executable: " + binary.getAbsolutePath());
            return null;
        }

        try {
            ProcessBuilder pb = new ProcessBuilder();
            pb.command(binary.getAbsolutePath(),
                "-mode", "embedded",
                "-listen", DEFAULT_LISTEN);

            if (streamdAddr != null && !streamdAddr.isEmpty()) {
                pb.command().add("-streamd-addr");
                pb.command().add(streamdAddr);
            }
            if (ffstreamAddr != null && !ffstreamAddr.isEmpty()) {
                pb.command().add("-ffstream-addr");
                pb.command().add(ffstreamAddr);
            }

            pb.redirectErrorStream(false);
            process = pb.start();

            // Read the handshake line from stdout (JSON with grpc_addr)
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()));
            String handshake = reader.readLine();
            if (handshake != null && handshake.contains("grpc_addr")) {
                // Parse grpc_addr from JSON: {"grpc_addr":"[::]:3595","version":"2.0.0"}
                int idx = handshake.indexOf("grpc_addr");
                int start = handshake.indexOf(":", idx) + 2; // skip ":"
                int end = handshake.indexOf("\"", start);
                String addr = handshake.substring(start, end);
                // Convert [::]:3595 to 127.0.0.1:3595 for local connection
                if (addr.startsWith("[::]:") || addr.startsWith("0.0.0.0:")) {
                    addr = "127.0.0.1:" + addr.substring(addr.lastIndexOf(":") + 1);
                }
                listenAddr = addr;
                Log.i(TAG, "wingoutd started, listening at: " + listenAddr);
            } else {
                listenAddr = DEFAULT_LISTEN;
                Log.w(TAG, "No handshake received, assuming default: " + DEFAULT_LISTEN);
            }

            // Log stderr in background
            new Thread(() -> {
                try {
                    BufferedReader errReader = new BufferedReader(
                        new InputStreamReader(process.getErrorStream()));
                    String line;
                    while ((line = errReader.readLine()) != null) {
                        Log.w(TAG, "wingoutd stderr: " + line);
                    }
                } catch (Exception e) {
                    Log.w(TAG, "Error reading wingoutd stderr", e);
                }
            }, "wingoutd-stderr").start();

            return listenAddr;
        } catch (Exception e) {
            Log.e(TAG, "Failed to start wingoutd", e);
            process = null;
            return null;
        }
    }

    /**
     * Stops the wingoutd daemon.
     */
    public synchronized void stop() {
        if (process != null) {
            process.destroy();
            try {
                process.waitFor();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            process = null;
            listenAddr = null;
            Log.i(TAG, "wingoutd stopped");
        }
    }

    /**
     * Returns the daemon's gRPC listen address, or null if not running.
     */
    public synchronized String getListenAddr() {
        return listenAddr;
    }

    /**
     * Returns true if the daemon process is running.
     */
    public synchronized boolean isRunning() {
        if (process == null) return false;
        try {
            process.exitValue();
            // Process has exited
            process = null;
            listenAddr = null;
            return false;
        } catch (IllegalThreadStateException e) {
            // Process is still running
            return true;
        }
    }
}
