
package center.dx.wingout;

import org.qtproject.qt.android.bindings.QtActivity;
import android.os.PowerManager;
import android.content.Context;

public class MainActivity extends QtActivity {
    private PowerManager.WakeLock wakeLock;

    @Override
  	public void onCreate(android.os.Bundle savedInstanceState) {
  		super.onCreate(savedInstanceState);
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK, "WingOut:WakeLockTag");
  		this.acquireWakeLock();
  	}

    public void acquireWakeLock() {
        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (!wakeLock.isHeld()) {
            wakeLock.acquire();
        }
    }

    public void releaseWakeLock() {
        getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (wakeLock.isHeld()) {
            wakeLock.release();
        }
    }
}
