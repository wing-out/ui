package center.dx.wingout2;

import android.content.Context;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import java.util.logging.Logger;

public class VibratorWrapper {
    private static final Logger logger = Logger.getLogger(VibratorWrapper.class.getName());

    public static void vibrate(Context context, long durationMs, int effect) {
        Vibrator vibrator;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibratorManager vm = (VibratorManager) context.getSystemService(
                Context.VIBRATOR_MANAGER_SERVICE);
            if (vm == null) {
                logger.warning("unable to find a VibratorManager");
                return;
            }
            vibrator = vm.getDefaultVibrator();
        } else {
            vibrator = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
        }

        if (vibrator == null) {
            logger.warning("unable to get vibrator");
            return;
        }
        if (!vibrator.hasVibrator()) {
            logger.warning("the device has no vibrator");
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs, effect));
        } else {
            vibrator.vibrate(durationMs);
        }
    }
}
