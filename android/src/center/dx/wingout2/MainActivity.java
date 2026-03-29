package center.dx.wingout2;

import org.qtproject.qt.android.bindings.QtActivity;
import android.os.PowerManager;
import android.content.Context;
import android.util.Log;

public class MainActivity extends QtActivity {
    private static final String TAG = "WingOut2";
    private PowerManager.WakeLock wakeLock;
    private static WingOutDaemon daemon;
    private static Context appContext;
    private static volatile boolean stopDaemonOnClose = true;

    @Override
    public void onCreate(android.os.Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        appContext = getApplicationContext();

        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK, "WingOut2:WakeLockTag");
        acquireWakeLock();

        if (daemon == null) {
            daemon = new WingOutDaemon();
        }
    }

    @Override
    public void onDestroy() {
        // Wait briefly for qtMainLoopThread to finish processing the
        // ApplicationSuspended state change that onStop() triggered via
        // QtNative.setApplicationState(). Without this, super.onDestroy() calls
        // QtNative.terminateQt() which destroys Qt window objects while
        // qtMainLoopThread is still iterating them in applicationStateChanged
        // → use-after-free → SIGILL crash in libQt6Gui at setApplicationState.
        //
        // The race: onStop() posts ApplicationSuspended to qtMainLoopThread,
        // then onDestroy() runs immediately on the same (main) thread and calls
        // terminateQt() before qtMainLoopThread has processed the event.
        try {
            Thread.sleep(150);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        if (stopDaemonOnClose && daemon != null) {
            Log.i(TAG, "onDestroy: stopping daemon");
            daemon.stop();
            Log.i(TAG, "onDestroy: daemon stopped");
        } else {
            Log.i(TAG, "onDestroy: keeping daemon alive (stopDaemonOnClose="
                + stopDaemonOnClose + ")");
        }
        super.onDestroy();
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        WiFiHelper.onPermissionResult(this, requestCode, permissions, grantResults);
    }

    public void acquireWakeLock() {
        getWindow().addFlags(
            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (!wakeLock.isHeld()) {
            wakeLock.acquire();
        }
    }

    public void releaseWakeLock() {
        getWindow().clearFlags(
            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (wakeLock.isHeld()) {
            wakeLock.release();
        }
    }

    /**
     * Called from C++/Qt to start the embedded wingoutd daemon.
     * Returns the gRPC listen address (e.g. "127.0.0.1:3595") or empty string on failure.
     */
    public static String startDaemon(String streamdAddr, String ffstreamAddr) {
        Log.i(TAG, "startDaemon called, daemon=" + daemon + " appContext=" + appContext
            + " thread=" + Thread.currentThread().getName());
        if (daemon == null || appContext == null) {
            Log.e(TAG, "startDaemon called before onCreate");
            return "";
        }
        if (daemon.isRunning()) {
            String addr = daemon.getListenAddr();
            Log.i(TAG, "startDaemon: daemon already running at " + addr);
            return addr;
        }
        Log.i(TAG, "startDaemon: calling daemon.start()");
        String addr = daemon.start(appContext, streamdAddr, ffstreamAddr);
        Log.i(TAG, "startDaemon: daemon.start() returned: " + addr);
        return addr != null ? addr : "";
    }

    /**
     * Called from C++/Qt to configure whether the daemon is stopped when the Activity is destroyed.
     */
    public static void setStopDaemonOnClose(boolean stop) {
        Log.i(TAG, "setStopDaemonOnClose: " + stop);
        stopDaemonOnClose = stop;
    }

    /**
     * Called from C++/Qt to stop the embedded wingoutd daemon.
     */
    public static void stopDaemon() {
        if (daemon != null) {
            daemon.stop();
        }
    }

    /**
     * Called from C++/Qt to check if the daemon is running.
     */
    public static boolean isDaemonRunning() {
        return daemon != null && daemon.isRunning();
    }

    /**
     * Returns the daemon's listen address, or empty string if not running.
     */
    public static String getDaemonAddr() {
        if (daemon != null && daemon.isRunning()) {
            String addr = daemon.getListenAddr();
            return addr != null ? addr : "";
        }
        return "";
    }
}
